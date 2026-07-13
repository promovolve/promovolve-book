# The Cluster

Everything so far — classification, auctions, selection, pacing, floors — is
stateful, per-site work. The architecture question is where that state
lives. Promovolve's answer: in **actors**, one per real-world thing, each
the single writer of its own state.

## Entities

The system runs on Apache Pekko cluster sharding. Each entity is an actor,
addressed by ID, living on exactly one node at a time; the shard coordinator
places and moves them as nodes join and leave.

| Entity | One per | Owns |
|---|---|---|
| `SiteEntity` | site | verification, slots, classifications |
| `AdServer` | site | serving, pacing, creative stats, floors |
| `AuctioneerEntity` | site | auctions, page cache, approval queue feed |
| `CampaignEntity` | campaign | bids, creatives, budget |
| `AdvertiserEntity` | advertiser | campaigns, approvals, daily budget |
| `CategoryBidderEntity` | category × shard | demand registry |

A site's entire serving path — pacing state, Thompson windows, floor sweeps
— is a single actor processing one message at a time. That is a design
position, not an accident: **no locks, no cache-coherence protocol, no
read-modify-write races**, because there is nothing concurrent to race
with. The trade is a throughput ceiling per site — one actor's mailbox — and
the position holds because a single actor comfortably absorbs a site doing
millions of impressions a day. Sites that ever exceed one actor's capacity
are a scaling problem the design would meet with sharding *within* the site,
not by making the state stateless.

Nodes carry roles — `api` (HTTP), `entity` (sharded actors), `singleton`
(cluster-wide directories), and `crawler`, which despite its historical name
now exists to host the landing-page analysis workers. Blocking work
(Playwright, LLM calls, JDBC) runs on dedicated dispatchers so an entity
under load cannot starve the serving path.

## The ServeIndex: replicated reads, single-writer writes

Serving reads must not cross the network. The candidate pools live in the
**ServeIndex**, built on Pekko Distributed Data (CRDTs): every node holds a
full replica, so a serve-time lookup is a local map read. Entries are
spread across 32 named maps by a hash of `site|slot` — replication works
map-by-map, and one giant map would re-gossip everything on every change.

Consistency is asymmetric on purpose. Writes acknowledge locally
(`WriteLocal`) and gossip outward — auction results becoming visible on
other nodes tens of milliseconds late is harmless. The exception is
whole-key removal, which uses majority writes with retries: a *removal*
that loses a gossip race resurrects deleted candidates, and (worse) removal
tombstones are the one place where divergent replicas can disagree
destructively. Fast paths are eventually consistent; destructive paths pay
for certainty.

Replicas are durable — DData persists designated keys to a local LMDB store
— so a restarting node recovers its cache from disk instead of re-gossiping
the world. Combined with the boot-time classification replay (the site
entity re-teaches a fresh auctioneer, idempotently), a full cluster restart
self-heals in about a minute: the "post-restart dark window" during which
slots briefly serve empty, then refill on their own.

## Rules learned the hard way

Cross-node messages are Jackson-CBOR-serialized by marker trait, and the
discipline is strict because failures are silent: a reply payload missing
the marker simply vanishes at the network boundary. Bare tuples and other
unregistered shapes are banned from cross-node protocols. Durable state
evolves by field aliasing, never by renaming persisted fields outright.
And any state a future needs must be delivered back to the actor as a
message — completing a Future inline against actor state is the
concurrency bug the whole architecture exists to prevent.

The platform around the core — dashboards, approval queues, billing, member
management — is a separate Go service rendering server-side templates (no
SPA framework), talking to the core over HTTP and to Postgres for
projections and the ledger. Authentication is passkey-only. But every
serving decision described in this book happens inside the actors.
