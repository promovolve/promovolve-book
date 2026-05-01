# Data Flow: Crawl vs Serve

Promovolve separates its workload into two distinct phases with fundamentally different performance characteristics.

## Crawl Phase (Write Path)

The crawl phase runs on a configurable schedule (default: Quartz cron `"0 0 2 * * ?"` — 2am daily) and is the "heavy" computation path. Crawl configuration per site includes `maxDepth` (default: 2) and `concurrency` (default: 5), running on a dedicated `crawler-dispatcher` with 4 fixed threads.

```mermaid
graph TD
    Crawler["External Crawler<br/>(4-thread pool)"] --> Classification["Page Classification<br/>(LLM: Gemini/OpenAI/Anthropic)<br/>categories + confidence scores"]
    Classification --> Auctioneer["AuctioneerEntity<br/>(sharded by siteId)"]
    Auctioneer --> Taxonomy["TaxonomyRankerEntity<br/>(800ms timeout)<br/>Thompson-sampled weights, 7-day half-life<br/>site-blend threshold: 20.0, min imps: 100"]
    Auctioneer --> CatBid["CategoryBidderEntity fan-out<br/>(5 virtual shards)"]
    CatBid --> CampDist["CampaignDistributor (8 workers)"]
    CampDist --> CampResp["CampaignEntity bid responses<br/>bidCpm = max(maxCpm × multiplier, floor)"]
    Auctioneer --> ServeIndex["Candidate shortlisting → ServeIndex<br/>(DData, WriteLocal, 120-min TTL)"]
```

## Serve Phase (Read Path)

The serve phase handles every ad request and must be extremely fast.

```mermaid
graph TD
    User["User Request (page load)"] --> API["API Node (HTTP, port 8080)"]
    API --> Lookup["Lookup ServeIndex from local DData<br/>Key: siteId|slotId → Vector of CandidateView"]
    Lookup --> Recency["Content Recency Filter<br/>classifiedAtMs within 48h window"]
    Recency --> FreqCap["Frequency Cap Check<br/>(100ms timeout, fail-open)<br/>query AdvertiserEntity per user"]
    FreqCap --> Rate["Rate Tracking<br/>(synchronous EMA, 1s window, α=0.3)"]
    Rate --> Pacing["Pacing Gate (PI control)<br/>aggregate budget from CachedSpendInfo<br/>throttle probability 0.0–0.99"]
    Pacing -->|"random() < throttle"| Skip["Skip (204)"]
    Pacing -->|pass| TS["Thompson Sampling Selection<br/>sample Beta(clicks+1, non_clicks+1)<br/>score = sampledCTR × CPM^α<br/>argmax"]
    TS --> Budget["Budget Reservation<br/>CampaignEntity.Reserve +<br/>AdvertiserEntity.GetBudgetStatus"]
    Budget -->|failure| Next["Try next-best by Thompson score"]
    Budget -->|success| Serve["Serve ad"]
    Next -->|all exhausted| NoCandidates["NoCandidates (204)"]
```

## Why Two Phases?

| Concern | Crawl Phase | Serve Phase |
|---------|-------------|-------------|
| Latency | Seconds OK | Must be < 1ms |
| Computation | Full auction, LLM classification | Cache lookup + Beta sampling |
| Fan-out | Many entities | Zero (local DData) |
| Failure mode | Retry on next crawl | Serve cached candidates |
| Scaling | Add entity nodes | Add API nodes |
| Dispatcher | `crawler-dispatcher` (4 threads) | Default Pekko dispatcher |

This separation means:
1. **Auction complexity doesn't affect serve latency** — LLM classification and multi-entity fan-out happen in the background
2. **Serve capacity scales independently** — adding API nodes increases request throughput without affecting auction load
3. **Temporary failures are invisible to users** — cached candidates remain in ServeIndex until their 120-minute TTL expires
