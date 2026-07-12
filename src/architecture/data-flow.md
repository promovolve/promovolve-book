# Data Flow: Classify vs Serve

Promovolve separates its workload into two distinct phases with fundamentally different performance characteristics.

## Classify Phase (Write Path)

The classify phase is traffic-driven, not scheduled — there is no crawler and no cron. When a page's first visitor arrives and the serve misses, the ad tag itself extracts the live page's text and slot geometry in the browser and POSTs it to `/v1/classify-page`. The endpoint replies `202 Accepted` immediately and hands the payload to the SiteEntity, which single-flights classification per URL (concurrent visitors don't trigger duplicate LLM calls). This is the "heavy" computation path, and it never blocks a serve.

Freshness is governed by a token: every serve response carries `reclassifyInMs`, computed from the publisher's content-recency window (default 48 hours, publisher-configurable). Fresh pages don't re-classify on every serve; only when the window lapses does the ad tag send text again.

```mermaid
graph TD
    AdTag["Ad Tag (browser)<br/>first visitor: extract page text + slot geometry"] --> ClassifyEP["POST /v1/classify-page<br/>(202 Accepted, fire-and-forget)"]
    ClassifyEP --> Site["SiteEntity<br/>(single-flight per URL)"]
    Site --> Classification["Page Classification<br/>(LLM: Gemini/OpenAI/Anthropic)<br/>IAB Content Taxonomy 3.0<br/>categories + confidence scores<br/>persisted with classifiedAt"]
    Classification --> Auctioneer["AuctioneerEntity<br/>(sharded by siteId)"]
    Auctioneer --> Taxonomy["TaxonomyRankerEntity<br/>(800ms timeout)<br/>Thompson-sampled weights, 7-day half-life<br/>site-blend threshold: 20.0, min imps: 100"]
    Auctioneer --> CatBid["CategoryBidderEntity fan-out<br/>(5 virtual shards)"]
    CatBid --> CampDist["CampaignDistributor (8 workers)"]
    CampDist --> CampResp["CampaignEntity bid responses<br/>bidCpm = max(maxCpm × multiplier, floor)"]
    Auctioneer --> ServeIndex["Candidate shortlisting → ServeIndex<br/>(DData, WriteLocal, 120-min TTL)"]
```

The durable copy of classifications lives in `SiteEntity.pageClassifications`; the AuctioneerEntity keeps an in-memory `lastPage` map (categories, slots, `classifiedAt`) for re-auctions, reseeded at boot via `RestoreClassifications` and recovered per-URL when a `Reevaluate` misses. Beyond the first classification, the auction re-runs event-driven (campaign approve/pause, budget changes — on a 1-second debounce) with a periodic backstop.

A page nobody visits never classifies — and has no impressions to sell, so no work is wasted.

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

| Concern | Classify Phase | Serve Phase |
|---------|----------------|-------------|
| Latency | Seconds OK | Must be < 1ms |
| Computation | Full auction, LLM classification | Cache lookup + Beta sampling |
| Fan-out | Many entities | Zero (local DData) |
| Failure mode | Next visitor re-triggers (single-flight releases) | Serve cached candidates |
| Scaling | Add entity nodes | Add API nodes |
| Trigger | First visitor / freshness token lapse | Every ad request |

This separation means:
1. **Auction complexity doesn't affect serve latency** — LLM classification and multi-entity fan-out happen in the background
2. **Serve capacity scales independently** — adding API nodes increases request throughput without affecting auction load
3. **Temporary failures are invisible to users** — cached candidates remain in ServeIndex until their 120-minute TTL expires
