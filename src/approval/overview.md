# Publisher Creative Approval

In traditional ad tech, publishers have no say over what appears on their site. The exchange picks a winner, and the publisher's ad server renders it — sight unseen. If an inappropriate ad slips through, the publisher's only recourse is to file a complaint after the fact.

Promovolve inverts this. **Every creative must be approved by the publisher before it can be shown to readers.** This isn't a bolt-on compliance feature — it's a core design constraint that shapes the auction system, the multi-candidate architecture, and the serving pipeline.

## Why Approval Matters

Magazine advertising always had publisher approval. An editor at a cooking magazine would review every ad before it ran — no gambling ads next to a recipe, no competitor ads next to a feature article. The publisher's editorial judgment was part of the product.

Promovolve restores this for the web. A publisher running a Japanese travel blog can:
- Approve a ryokan ad that complements their Kyoto temple article
- Reject a fast-food chain ad that doesn't fit their editorial voice
- Block entire ad product categories (gambling, alcohol) site-wide
- Revoke a previously approved creative if their standards change

This is also why Promovolve uses multi-candidate auctions. If the system only picked one winner and the publisher rejected it, the slot would be empty. With multiple candidates queued, rejecting one simply promotes the next.

## The Approval Lifecycle

A creative goes through distinct states as it moves through the system:

```
Auction Result
     │
     ▼
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Pending   │────►│  Approved   │────►│   Serving   │
│  (in queue) │     │ (in index)  │     │ (to users)  │
└─────────────┘     └─────────────┘     └─────────────┘
     │                    │
     ▼                    ▼
┌─────────────┐     ┌─────────────┐
│  Rejected   │     │   Revoked   │
│ (blocked)   │     │ (removed)   │
└─────────────┘     └─────────────┘
```

### 1. Auction produces candidates

The AuctioneerEntity shortlists multiple candidates per ad slot and sends them to the AdServer. Each candidate carries a `preApproved` flag — but the AdServer doesn't trust it blindly.

### 2. AdServer determines actual approval status

Instead of relying on the `preApproved` flag (which comes from a probabilistic Cuckoo filter and can have false positives), the AdServer queries the ServeIndex to see which creatives are *actually* serving:

```
existingCreativeIds =
    creatives in this slot's ServeIndex
  + creatives approved at any other slot on this site (inverted index)
  + creatives loaded from DB on startup (persisted approvals)
```

This three-source merge means:
- A creative approved at one slot is recognized site-wide
- Approvals survive process restarts (loaded from PostgreSQL)
- Re-auctions don't re-queue already-approved creatives

### 3. Partition: approved vs pending

The AdServer partitions candidates into two groups:

```
approved = candidates whose creativeId is in existingCreativeIds
pending  = everything else
```

**Approved creatives** go straight to the ServeIndex — they're already trusted. The AdServer fetches their category scores from the TaxonomyRankerEntity, builds `CandidateView` objects with CDN asset URLs and dimensions, and writes them to DData. They can be served immediately.

**Pending creatives** are queued in the `PendingSelectionStore` (PostgreSQL) for the publisher to review. They cannot be served until approved.

### 4. Blocklist filtering

Before any of this happens, candidates are filtered against two blocklists:

- **Domain blocklist**: Publishers can block specific landing domains. A creative linking to a competitor's site is filtered out before it ever reaches the pending queue.
- **Ad product category blocklist**: Publishers can block entire product categories (e.g., gambling, alcohol, firearms). Distributed via DData, this filter runs at auction time.

Blocked creatives are silently dropped — they never appear in the publisher's approval queue.

## The Pending Queue

The pending queue is the publisher's inbox for new creatives. It's persisted in PostgreSQL (table: `pending_selection`) so it survives restarts.

### Data model

Each pending entry is a `Selection` — an ordered list of candidates for a specific (publisher, URL, slot) combination:

```
Selection
  publisherId: String
  url:         String
  slotId:      String
  ordered:     Vector[Candidate]   — ranked by CPM
  idx:         Int                 — index of current candidate being reviewed
  state:       Pending
  expiresAt:   Instant             — TTL-based expiration
```

The `idx` pointer tracks which candidate the publisher is currently reviewing. When a creative is rejected, the pointer advances to the next candidate.

### Key operations

| Operation | What happens |
|-----------|-------------|
| `upsertPending` | Write/overwrite a pending selection for a slot |
| `getPending` | Fetch current pending for a slot |
| `pendingQueue` | List all pending items for a publisher (for the dashboard) |
| `removeCreativeFromPending` | Remove a specific creative after approval, keep the rest |
| `rejectAndPromote` | Reject current candidate, advance to next in queue |
| `purgeExpired` | Clean up expired selections (TTL-based) |
| `flagCreative` | Quarantine a creative with a reason (for later review) |
| `unflagCreative` | Return a quarantined creative to the pending queue |

### Budget exhaustion cleanup

When a campaign or advertiser runs out of budget, their creatives are removed from the pending queue — there's no point asking the publisher to review an ad that can't pay:

| Event | Cleanup |
|-------|---------|
| Campaign budget exhausted | `removeByCampaignId` — remove all pending creatives for this campaign |
| Advertiser budget exhausted | `removeByAdvertiserId` — remove all pending creatives for this advertiser |
| Creative paused | `removeCreativeFromAll` — remove from all pending slots |
| Landing domain blocked | `removeByLandingDomain` — remove all creatives with this domain |
| Ad product category blocked | `removeByAdProductCategory` — remove all creatives in this category |

## The Three Publisher Actions

### Approve

The publisher reviews a pending creative and approves it:

1. Validate the creative ID matches the current candidate in the queue
2. Fetch category scores from TaxonomyRankerEntity
3. Build a `CandidateView` with CDN asset URL, dimensions, and metadata
4. Append to ServeIndex via DData — the creative is now live
5. Persist approval to PostgreSQL (`insertApproved`) — survives restarts
6. Update AdvertiserEntity with `ApprovalStatus.Approved`
7. Remove from pending queue
8. Broadcast SSE event: `approved`

The creative begins serving to readers on the next page load.

### Reject

The publisher reviews a pending creative and rejects it:

1. Update AdvertiserEntity with `ApprovalStatus.Rejected` — recorded in a Bloom filter so the creative won't be re-submitted in future auctions for this site
2. Remove from ServeIndex (if it was somehow there)
3. Call `rejectAndPromote` to advance the queue to the next candidate
4. If the queue is exhausted (no more candidates), trigger a re-auction so other campaigns can fill the slot
5. Broadcast SSE event: `rejected`

Rejection is permanent for this site — the Bloom filter prevents the same creative from appearing in future pending queues.

### Revoke

The publisher changes their mind about a previously approved creative:

1. Remove from ServeIndex — the creative stops serving immediately
2. Clear from both approved and rejected filters in AdvertiserEntity
3. Broadcast SSE event: `revoked`

Unlike rejection, revocation is reversible — the creative can be re-queued for approval later (e.g., after the advertiser updates it).

### Bulk approve

For publishers who trust an advertiser or want to quickly clear their queue:

```
POST /v1/publishers/{publisherId}/sites/{siteId}/creatives/bulk-approve
```

Approves all pending creatives for a slot in one operation. Each creative goes through the same approval flow (ServeIndex update, DB persistence, AdvertiserEntity notification). A single SSE event (`bulk-approved`) is broadcast with the count.

## Real-Time Notifications (SSE)

Publishers don't have to poll for new creatives. Promovolve streams events in real time via Server-Sent Events:

```
GET /v1/publishers/{publisherId}/sites/{siteId}/events
```

### Event types

| Event | When | Payload |
|-------|------|---------|
| `pending-updated` | New creatives queued for review | siteId, url, slotId, count, topCreativeId |
| `approved` | Creative approved and now serving | siteId, url, slotId, creativeId |
| `rejected` | Creative rejected | siteId, url, slotId, creativeId |
| `bulk-approved` | Multiple creatives approved at once | siteId, url, slotId, approvedCount |
| `revoked` | Approval revoked, creative removed from serving | siteId, creativeId |
| `creative-status-changed` | Creative paused or reactivated by advertiser | creativeId, campaignId, status |
| `campaign-status-changed` | Campaign status changed | campaignId, status |
| heartbeat | Keep-alive ping | (empty, every 30 seconds) |

### Architecture

The `PendingEventHub` actor manages SSE subscribers grouped by site:

```
PendingEventHub
  └── subscribers: Map[siteId → Set[ActorRef[PendingEvent]]]
```

- Site-specific events (pending, approved, rejected) go to subscribers for that site
- Cross-site events (creative-status-changed, campaign-status-changed) broadcast to all subscribers
- Subscribers auto-unsubscribe when the SSE stream terminates
- Stale subscribers are cleaned up via actor death-watch

## Pre-Approved: The Auction Tiebreaker

When the AuctioneerEntity sorts candidates, pre-approved creatives get a tiebreaker advantage:

```
sort key = (-CPM, if preApproved then 0 else 1)
```

At equal CPM, a pre-approved creative ranks higher than an unapproved one. This has two effects:

1. **Faster time-to-serve**: Pre-approved creatives skip the pending queue and go straight to the ServeIndex, so they start earning impressions sooner
2. **Re-auction stability**: When a re-auction runs, already-approved creatives maintain their position rather than being displaced by new, unapproved ones that would sit in the queue

## How Approval Enables Multi-Candidate Auctions

The approval workflow is the reason Promovolve uses multi-candidate auctions in the first place. Consider the alternative:

**Single-winner auction without approval**: The exchange picks one winner. It starts serving immediately. The publisher sees an ad for online gambling on their children's education blog. Damage done.

**Single-winner auction with approval**: The exchange picks one winner. The publisher rejects it. The slot is empty until the next auction. Readers see no ad. Revenue is zero.

**Multi-candidate auction with approval**: The auction shortlists three candidates. The publisher rejects the first one. The second candidate is already queued and ready. The slot is never empty. Revenue continues. The publisher maintains editorial control.

This is the design that makes approval practical at scale — without it, publisher approval would mean empty slots and lost revenue every time a creative is rejected.

## Approval Persistence

Approvals are stored in two places for different purposes:

| Storage | Purpose | Survives restart? |
|---------|---------|-------------------|
| ServeIndex (DData) | Fast serve-time lookups | No (ephemeral, rebuilt from auctions) |
| PostgreSQL (`approved_creatives`) | Approval state of record | Yes |
| `keysByCreative` (in-memory inverted index) | Site-wide approval recognition | No (rebuilt from ServeIndex on startup) |
| `persistedApprovedIds` (loaded from DB) | Bootstrap approvals on startup | Yes (loaded from PostgreSQL) |

On startup, the AdServer loads `persistedApprovedIds` from PostgreSQL. When a re-auction runs, creatives in this set are recognized as already approved and skip the pending queue — the publisher doesn't have to re-approve creatives they already reviewed.