# Bucketed LWWMap Design

The ServeIndex partitions entries into **32 buckets** to keep CRDT delta sizes small.

## Why Buckets?

A single `LWWMap` containing all entries would produce large deltas on any change. Bucketing partitions the keyspace:

```
bucket = rotateLeft(key.hashCode, 13) & 31   // key = "siteId|slotId"
```

Each bucket is an independent `LWWMap`. An update to bucket 7 only produces a delta for bucket 7.

## LWWMap (Last-Writer-Wins Map)

Conflicts are resolved by timestamp — the value with the higher timestamp wins. This is safe because:
1. Auction results are timestamped by the auction itself
2. Newer auctions should always override older ones
3. Concurrent auctions for the same slot are impossible (AuctioneerEntity is sharded by siteId)

## Bucket Count: Why 32?

- **Too few** (4): ~25% of entries per bucket → large deltas
- **Too many** (1024): CRDT management overhead outweighs savings
- **32**: With 10,000 entries, ~312 per bucket. Balanced.

## Per-Publisher Namespace

The composite key `"siteId|slotId"` naturally partitions entries by publisher. Slots from different sites land in different buckets (usually) due to hash distribution.

## DData Gossip Impact

With 32 buckets and max-delta-elements of 500:
- Each gossip round can propagate up to 500 changes across all buckets
- A single auction updating 10 slots affects at most 10 buckets
- Other buckets' gossip is unaffected
