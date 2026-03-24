# TTL Sweep & Expiration

ServeIndex entries have a time-to-live to prevent stale ads from serving indefinitely.

## TTL Assignment

When writing auction results:

```
expiresAtMs = System.currentTimeMillis() + ttlDurationMs
```

Default TTL: **120 minutes**. Under normal operation, the next auction refreshes the entry before TTL expires.

### Budget Exhaustion TTL Refresh

On `CampaignBudgetExhausted` or `AdvertiserBudgetExhausted`:

```
expiresAtMs = System.currentTimeMillis() + (dayDurationSeconds × 1.1 × 1000)
```

The 1.1x factor ensures the entry survives until well past the next daily budget reset.

## Periodic Sweep

From `ServeIndexDData.scala`:

```
SweepInterval = 2.minutes
MaxKeysRemovePerRun = 500
```

Every 2 minutes, each node scans all 32 buckets:

```
for each bucket:
    entries = bucket.entries
    expired = entries.filter(e => now > e.expiresAtMs)
    remove up to 500 expired entries from this bucket
```

### Bounded Removals

The 500-per-bucket limit prevents a large batch of expirations from overwhelming DData:
- 32 buckets × 500 = up to 16,000 entries per sweep
- In practice, expirations are spread across time, so batches are smaller

## Why Not Instant Expiration?

| Approach | Problem |
|----------|---------|
| Instant expiry | Clock skew between nodes → entries flicker |
| Individual removes | Many small deltas → gossip overhead |
| Batched sweep | Predictable load, clock-skew tolerant |

The 2-minute sweep interval means an expired entry might serve for up to 2 extra minutes. This is acceptable — the pacing gate and budget checks provide additional safety at serve time.
