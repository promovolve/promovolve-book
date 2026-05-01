# Fair Candidate Selection

The serve-time selection pipeline applies multiple filters before Thompson Sampling runs, ensuring only eligible candidates are considered.

## Complete Selection Pipeline

From the AdServer source code, the exact order of operations:

```
1. Lookup ServeView from DData
   Key: "siteId|slotId"
   → Vector[CandidateView]

2. Content Recency Filter
   Keep if: (now - classifiedAtMs) ≤ contentRecencyWindowMs (48h)

3. Frequency Cap Check (if userId provided AND any caps exist)
   → Group candidates by advertiserId
   → Query AdvertiserEntity for user impression counts (100ms timeout)
   → Filter: keep if impressions < frequencyCap
   → Fail open on timeout (include all)

4. Rate Tracking (synchronous)
   → TrafficObserver.recordRequest(nowMs)
   → Update EMA-smoothed request rate (1s window, α=0.3)
   → BEFORE any async operations

5. Pacing Gate (BEFORE Thompson Sampling)
   → Fetch CachedSpendInfo for all participating campaigns
   → Compute aggregate PacingContext
   → PacingStrategy.throttleProbability(ctx) → [0.0, 0.99]
   → if random() < throttleProb: return NoCandidates (204)
   → Pacing gates VOLUME, not CHOICE

6. Thompson Sampling Selection
   → Cold start strategy selection (full cold / warmup / partial / standard)
   → Score: sampledCTR × CPM^α
   → Select argmax

7. Budget Reservation
   → CampaignEntity.Reserve(spend estimate)
   → AdvertiserEntity.GetBudgetStatus()
   → On failure: loop to next-best Thompson score candidate
   → All exhausted: return NoCandidates
```

## Why Pacing Before Thompson Sampling?

If pacing ran after TS:
- TS picks a creative → pacing throttles → **wasted exploration** (we learned nothing)
- TS would consistently select a high-CTR creative that gets throttled, biasing future selection

With pacing before TS:
- Throttle decision is independent of creative choice
- When a request passes the gate, TS explores the full eligible set
- Every Thompson Sampling decision contributes useful data

## Campaign Mix Change Detection

When the set of participating campaigns changes between requests:

```scala
if lastCampaignSet.nonEmpty && currentCampaignSet != lastCampaignSet:
    log campaign mix changed (added/removed)
    pacingStrategy.reset()  // Don't let PI compensate for mix changes
```

This prevents the PI controller from making corrections based on stale campaign data.

## Orphaned Creative Preservation

When new auction results arrive, creatives from the previous auction that aren't in the new set are preserved as "orphaned":

```scala
orphanedCreatives = existingCandidates.filterNot(c =>
    newAuctionCreativeIds.contains(c.creativeId)
)
mergedCandidates = (newCandidates ++ orphanedCreatives).distinctBy(_.creativeId)
```

This ensures multi-campaign diversity survives across auction cycles and approval status is preserved.
