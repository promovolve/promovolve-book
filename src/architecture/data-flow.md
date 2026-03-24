# Data Flow: Crawl vs Serve

Promovolve separates its workload into two distinct phases with fundamentally different performance characteristics.

## Crawl Phase (Write Path)

The crawl phase runs on a configurable schedule (default: Quartz cron `"0 0 2 * * ?"` — 2am daily) and is the "heavy" computation path. Crawl configuration per site includes `maxDepth` (default: 2) and `concurrency` (default: 5), running on a dedicated `crawler-dispatcher` with 4 fixed threads.

```
External Crawler (4-thread pool)
     │
     ▼
Page Classification (LLM-based: Gemini/OpenAI/Anthropic)
     │  → categories + confidence scores
     ▼
AuctioneerEntity (sharded by siteId)
     │
     ├── TaxonomyRankerEntity queries (800ms timeout)
     │   → Thompson-sampled weights with half-life decay (7 days)
     │   → site-blend threshold: 20.0, min impressions: 100
     │
     ├── CategoryBidderEntity fan-out (5 virtual shards)
     │   → CampaignDistributor (8 workers)
     │     → CampaignEntity bid responses
     │       → bidCpm = max(maxCpm × bidMultiplier, floorCpm)
     │
     └── Candidate shortlisting → ServeIndex (DData, WriteLocal)
           → 120-minute TTL
```

## Serve Phase (Read Path)

The serve phase handles every ad request and must be extremely fast.

```
User Request (page load)
     │
     ▼
API Node (HTTP, port 8080)
     │
     ├── Lookup ServeIndex[siteId|slotId] from local DData
     │     → Vector[CandidateView]
     │
     ├── Content Recency Filter
     │     → classifiedAtMs within 48h window
     │
     ├── Frequency Cap Check (100ms timeout, fail-open)
     │     → query AdvertiserEntity per user
     │
     ├── Rate Tracking (synchronous EMA, 1s window, α=0.3)
     │
     ├── Pacing Gate (PI control, before Thompson Sampling)
     │     → aggregate budget from CachedSpendInfo
     │     → throttle probability [0.0, 0.99]
     │     → Bernoulli: if random() < throttle → skip (204)
     │
     ├── Thompson Sampling Selection
     │     → sample Beta(clicks+1, non_clicks+1) per candidate
     │     → score = sampledCTR × log(1 + CPM)
     │     → argmax
     │
     └── Budget Reservation
           → CampaignEntity.Reserve + AdvertiserEntity.GetBudgetStatus
           → On failure: try next-best by Thompson score
           → All exhausted: NoCandidates (204)
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
