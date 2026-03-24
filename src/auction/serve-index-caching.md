# Phase 5: ServeIndex Caching

The final auction phase stores shortlisted candidates in the distributed in-memory cache (ServeIndex) for instant retrieval at serve time.

## ServeIndex Write

After shortlisting, AuctioneerEntity writes the candidate set to ServeIndex:

```
Key:   siteId|slotId
Value: ServeView(
         candidates: Vector[CandidateView],
         version: Long,       // auction timestamp
         expiresAtMs: Long     // currentTimeMillis + TTL
       )
```

### Write Semantics

| Operation | Consistency | Use Case |
|-----------|-------------|----------|
| **Put** (full replacement) | `WriteLocal` | Fresh auction results |
| **Append** (single candidate) | `WriteLocal` + dedup by `creativeId` | Adding orphaned creative |
| **Remove** | `WriteMajority(800ms)` + retry (max 5, backoff 200ms) | Creative/campaign takedown |
| **CPM update** | `WriteLocal` | Best-effort CPM refresh |
| **FilterByCreativeIds** | `WriteLocal` | Keep only valid creatives |

### TTL

Each entry has a default TTL of **120 minutes**. On budget exhaustion events, TTL is refreshed to `dayDurationSeconds × 1.1 × 1000ms` to ensure entries survive until the next daily budget reset.

### Replication

ServeIndex uses Pekko DData with gossip-based replication:
- Gossip interval: 2 seconds
- Notify subscribers: 500ms
- Max delta elements: 500 per gossip round

Every API node gets a complete local copy within seconds of a write.

### Bucketing

Entries are partitioned into **32 buckets** (power-of-2) by hash of the key. Each bucket is an independent `LWWMap[String, ServeView]`. This keeps CRDT delta sizes small — an update to one bucket doesn't generate deltas for entries in other buckets.

### Removal Operations

ServeIndex supports granular removal:
- `RemoveCampaignFromKey`: Remove all candidates from a specific campaign across slots
- `RemoveCreativeFromKey`: Remove a specific creative across all slots
- `RemoveBySite`: Batch removal for all slots on a site

All removals use `WriteMajority` with retries for durability.
