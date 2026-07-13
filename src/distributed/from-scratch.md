# Distributed State from Scratch

When a user loads a page, Promovolve needs to find the right ad in under a millisecond. Why not just query a database?

This chapter explains why Promovolve uses replicated in-memory state instead of a database, how it keeps multiple copies in sync without a leader, and why "eventually consistent" is not just acceptable but actually the right choice for ad serving.

## The Latency Problem

A PostgreSQL query takes 1-5 milliseconds on a fast local connection. That sounds fast. But the ad serving path runs on every page load, for every ad slot, for every user. At 1,000 requests per second with 3 ad slots each, that's 3,000 database queries per second — each adding latency to the user's page load.

Worse, database latency has a long tail. The median might be 2ms, but the 99th percentile might be 20ms. One slow query blocks the response. Under load, connection pool contention adds more. For a publisher who cares about page performance, every millisecond of ad serving latency is a tax on their readers.

Promovolve's target: **serve an ad in under 1 millisecond**. No database can deliver that consistently under load. The data needs to be in memory, on the same machine that handles the request.

## The Obvious Solution (and Why It Doesn't Work)

"Just put it in a local cache." Load the auction results into a `HashMap` on each API node. Reads are nanoseconds. Problem solved.

Not quite. Promovolve runs as a cluster of multiple nodes (for reliability and throughput). If node A runs an auction and updates its local cache, nodes B and C don't know about it. A user whose request lands on node B gets stale data — or no data at all.

You need the data replicated across all nodes. The question is: how?

## Option 1: Leader-Based Replication

The traditional approach: one node is the "leader" (or "primary"). All writes go through the leader. The leader replicates to followers.

```
Write → Leader → Follower 1
                → Follower 2
                → Follower 3
```

This is how PostgreSQL replication, Redis Sentinel, and most databases work. It provides **strong consistency** — all nodes see the same data after each write.

The problems:
- **The leader is a bottleneck.** All writes go through one node. If that node is slow or down, writes stall.
- **Leader failure requires election.** Detecting a dead leader, electing a new one, and catching up takes seconds. During that time, writes fail.
- **Network partitions are ugly.** If the leader can't reach some followers, it must choose: keep accepting writes (risking divergence) or stop accepting writes (sacrificing availability).

For a database backing a billing system, these trade-offs are worth it. For an ad serving cache that refreshes every 5 minutes, they're overkill.

## Option 2: Replicate Without a Leader

What if every node can write, and writes automatically propagate to all other nodes?

```
Node A writes → gossip → Node B receives
Node B writes → gossip → Node A receives
```

No leader. No election. No single point of failure. Every node accepts writes locally (fast) and syncs with others in the background (eventually).

The problem: what happens when two nodes write different values for the same key at the same time? With a leader, this can't happen — all writes go through one place. Without a leader, you need a way to resolve conflicts automatically.

## CRDTs: Data Structures That Merge Themselves

A **CRDT** (Conflict-free Replicated Data Type) is a data structure designed so that concurrent writes can always be merged without conflict. The merge is deterministic — no matter what order updates arrive, all nodes converge to the same result.

The simplest example: a **counter**. Instead of storing "count = 5", each node stores "my contribution is X":

```
Node A: my_count = 3
Node B: my_count = 2
Merge: total = 3 + 2 = 5
```

Both nodes increment their own counter. The merge just sums them. No conflict possible.

Promovolve uses a more sophisticated CRDT: **LWWMap** (Last-Writer-Wins Map). It's a key-value map where each entry has a timestamp. When two nodes write different values for the same key, the one with the later timestamp wins:

```
Node A writes: key="ad-slot-1" → creative_X at t=1000
Node B writes: key="ad-slot-1" → creative_Y at t=1003
Merge: creative_Y wins (later timestamp)
```

This is simple and predictable. The "conflict resolution" is just "most recent write wins" — the same semantics as overwriting a variable.

## How Promovolve Uses DData

Pekko's **Distributed Data (DData)** implements CRDTs with a gossip protocol. Every few seconds, each node shares its data changes with random peers. Changes propagate through the cluster like gossip in a social network — eventually reaching every node.

Promovolve's **ServeIndex** stores the auction results that the serve path needs:

```
DData map: "serve-views-site-123-7"        ← bucket lives in the MAP name
Entry key: "site-123|slot-banner-top"
Value: creative candidates
  "creative-abc" → ServeView(assetUrl, cpm, ctr_stats, expires_at, ...)
  "creative-def" → ServeView(...)
```

When the `AuctioneerEntity` completes an auction, it writes results to DData with `WriteLocal` — the write completes immediately on the local node. Within 2 seconds (the gossip interval), other nodes receive the update.

When the serve path needs to select an ad, it reads from the local DData replica — a local in-memory lookup, no network hop.

## Why "Eventually Consistent" Is Fine Here

"Eventually consistent" sounds scary. What if a user gets stale data?

For ad serving, consider what "stale" means in practice:

**A creative was updated 2 seconds ago but this node hasn't received the gossip yet.** The user sees the previous creative. Is this a problem? No — the creative was valid 2 seconds ago. It's still a legitimate ad with a valid tracking URL. The user has no way to notice the difference.

**A campaign ran out of budget but the serve node still shows its creative.** The pacing gate and budget reservation catch this. Even if the ServeIndex has a stale entry, the budget check (which queries the CampaignEntity directly) will reject the serve and fall back to the next candidate. The stale cache entry is harmless.

**An auction ran and produced new candidates, but this node still has the old ones.** The old candidates are at most 5 minutes stale (the re-auction interval). They were valid winners of the previous auction. Serving them for 2 more seconds until gossip arrives is fine.

The key insight: **the serve path is approximate by design**. Thompson Sampling adds randomness. Pacing throttles probabilistically. Click-through rates are estimates. Adding 2 seconds of gossip delay to a system that already operates on statistical estimates doesn't meaningfully degrade the outcome.

Strong consistency would give you a guarantee you don't need, at a cost (leader bottleneck, cross-node coordination latency) that directly hurts the thing you do need: speed.

## Bucketing: Keeping CRDTs Small

One problem with LWWMap: if you put thousands of entries in a single map, every gossip cycle transmits the entire delta (all changes since last sync). With frequent updates across many creatives, deltas grow large.

Promovolve splits each namespace into **32 buckets** by hashing the
composite `"site|slot"` key:

```
bucket = rotateLeft(("site-123|slot-banner").hashCode, 13) & 31
map    = "serve-views-site-123-" + bucket   // entry key stays "site|slot"
```

Each bucket is a separate LWWMap. An auction that updates 10 creatives touches maybe 8-10 buckets, not all 32. Gossip only transmits the buckets that changed. This keeps delta sizes small and gossip efficient.

Why 32? It's a balance. More buckets means smaller deltas but more DData keys to manage. Fewer means larger deltas but simpler bookkeeping. 32 works well for the typical case of dozens to hundreds of creatives per site.

## Write Consistency: Fast Writes, Safe Deletes

Not all writes are equal. Promovolve uses different consistency levels depending on the operation:

**Writes (Put, Append, Update CPM): `WriteLocal`**

The write succeeds immediately on the local node. Gossip propagates it. If the local node crashes before gossip, the write is lost — but the next auction (within 5 minutes) will repopulate it.

This is the right trade-off for the hot path. Auction results are ephemeral and refreshed frequently. Speed matters more than durability.

**Whole-key takedowns (`Remove`): `WriteMajority`**

Removing a slot's entry outright should be seen by all nodes quickly — you don't want a taken-down ad to keep serving because one node missed the delete. `WriteMajority` waits for acknowledgment from a majority of nodes (e.g., 2 out of 3) before confirming. (The finer-grained removals — a single campaign or creative pruned out of a key — ride `WriteLocal` like other updates: they rewrite the entry's candidate list, and gossip carries the new version.)

If `WriteMajority` times out (800ms), Promovolve retries up to 5 times with 200ms backoff. Removing an ad that shouldn't serve is more important than speed.

## What About Node Restarts?

DData is in-memory. If a node restarts, its local replica is empty. What happens?

**In a multi-node cluster**: The restarted node receives the full state from other nodes via DData's anti-entropy protocol. Within one gossip cycle (2 seconds), it has a complete replica.

**In a single-node cluster (development)**: The data is gone. The next `PeriodicReauction` timer (within 5 minutes) re-runs auctions and repopulates the ServeIndex. During the gap, the serve path returns `NoContent` (HTTP 204) — the ad slot is empty. Not ideal, but bounded.

The ServeIndex is also on the LMDB durable-keys list (`serve-views-*`,
alongside the `shard-*` sharding metadata), so even a full-cluster
restart comes back with the last written index instead of an empty one.
Durability is write-behind (batched to disk every 200ms off the hot
path), so reads stay in-memory and sub-millisecond; the periodic
re-auction remains the backstop that refreshes anything the write-behind
missed.

## The Full Picture

```
Auction completes
  → AuctioneerEntity writes to ServeIndex (WriteLocal, ~0ms)
  → Gossip propagates to all nodes (~2 seconds)
  → Every node has candidates in local memory

User loads page
  → API node reads local ServeIndex replica (~0.1ms)
  → Pacing gate + Thompson Sampling (~0.1ms)
  → Ad response sent (<1ms total)
```

No database in the serve path. No network hop for reads. No leader to bottleneck. No election to delay. The system trades strong consistency (which it doesn't need) for speed (which it does).

## From Theory to Code

| Concept | File | Key method |
|---------|------|-----------|
| ServeIndex DData actor | `ServeIndexDData.scala` | `Put`, `Append`, `Remove` commands |
| Bucketed LWWMap keys | `ServeIndexDData.scala` | `mapKey(pub, bucket)` |
| WriteLocal vs WriteMajority | `ServeIndexDData.scala` | `Replicator.WriteLocal`, `Replicator.WriteMajority` |
| TTL sweep (expire stale entries) | `ServeIndexDData.scala` | `Sweep` command |
| Gossip and replication config | `application.conf` | `pekko.cluster.distributed-data` |
| DData adapter in serve path | `AdServer.scala` | `ServeIndexDData` lookup |

The next chapters cover the bucketed LWWMap design, TTL expiration, and write consistency levels in detail.
