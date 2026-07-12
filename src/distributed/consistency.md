# Write Consistency Levels

DData supports different consistency levels. Promovolve uses different levels depending on operation criticality.

## Consistency Choices (from ServeIndexDData.scala)

| Operation | Consistency | Timeout | Retries | Rationale |
|-----------|-------------|---------|---------|-----------|
| **Put** (full replacement) | `WriteLocal` | — | — | Speed; next auction refreshes |
| **Append** (single candidate) | `WriteLocal` | — | — | Speed; dedup prevents issues |
| **CPM update** | `WriteLocal` | — | — | Best-effort price refresh |
| **FilterByCreativeIds** | `WriteLocal` | — | — | Batch cleanup |
| **Remove** (takedown) | `WriteMajority` | 800ms | 5 (200ms backoff) | Must be durable |
| **RemoveCampaignFromKey** | `WriteMajority` | 800ms | 5 | Must be durable |
| **RemoveCreativeFromKey** | `WriteMajority` | 800ms | 5 | Must be durable |
| **RemoveBySite** | `WriteMajority` | 800ms | 5 | Must be durable |

## Why WriteLocal for Puts?

Auction results are written frequently and losing one write is not catastrophic:
- The next re-auction cycle produces fresh results
- Gossip replicates to other nodes within seconds (2s gossip interval)
- Stale data is caught by the TTL sweep

## Why WriteMajority for Removes?

Removes must be durable. If a remove only reaches one node and that node crashes:
- The entry reappears on restart from other nodes' copies
- A "zombie" creative that was supposed to be taken down continues serving
- This is a compliance/safety concern (paused campaigns, suspended advertisers)

WriteMajority ensures the remove is acknowledged by a majority of nodes before returning.

### Retry Strategy

```
MaxRemoveRetries = 5
InitialRetryBackoff = 200.millis
```

If WriteMajority times out (800ms), the remove is retried with exponential backoff. After 5 failures, the removal is logged and will be caught by the next TTL sweep.

## Eventual Consistency Window

WriteLocal operations have a brief window (typically <2s, matching gossip interval) where different API nodes see different ServeIndex contents. This means:
- Two concurrent requests to different nodes might get different creatives
- A just-written entry might not be visible everywhere immediately

These are acceptable because:
1. Thompson Sampling already introduces per-request randomness
2. The 15-minute RL window averages over many decisions
3. Budget and pause checks at serve time catch any "shouldn't serve" cases
