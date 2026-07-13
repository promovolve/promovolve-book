# The Periodic Auction

Real-time bidding runs an auction per impression and gives each one a few
milliseconds. Promovolve inverts this: auctions run *ahead of* impressions —
when a page is classified, on a periodic tick, and when the world changes —
and their results are cached. Serving then reads the cache. The auction can
afford to be thoughtful because nobody is waiting on it.

## What an auction produces

For each page and slot, the site's `AuctioneerEntity` assembles a **candidate
pool**, not a winner:

1. **Demand lookup.** The page's categories (with ancestor expansion) are
   resolved against `CategoryBidderEntity` actors — the registry of which
   campaigns bid on which categories. A CPM threshold keeps only competitive
   bids.
2. **Bid collection.** Each eligible campaign's entity is asked for its
   creatives and current bid. Campaigns apply their own filters here — a
   site allowlist, if the advertiser restricted where they appear.
3. **Ordering, no cap.** Candidates are deduplicated by creative, sorted by
   CPM (publisher-approved creatives win ties), and reordered so each
   campaign's best creative comes first. **The full pool is kept** — no
   top-N cut. Serve-time selection needs losers to learn from; an auction
   that discards them would silently disable exploration.
4. **Caching.** The pool is written to the ServeIndex — a replicated,
   locally-readable cache described in [The Cluster](./cluster.md) — with a
   TTL.

Campaigns whose creatives the publisher hasn't approved yet still bid: that
is how a creative *reaches* the approval queue. But pending demand cannot
serve and is invisible to floor optimization — an unapproved bid must not
teach the market anything.

## When auctions run

- **On classification** — a page's first auction follows its first
  classification within moments.
- **On a timer** — every site re-evaluates its fresh pages periodically
  (the deployment runs a 5-minute interval; the code default is 30). The
  timer is a backstop; the event-driven paths below do most of the work.
- **On events, debounced** — campaign created, paused, or re-targeted;
  creative approved, rejected, or flagged; bids changed; floors moved. Each
  triggers re-evaluation of the affected pages on a one-second debounce.
- **On boot** — a restarted auctioneer is re-taught its classifications by
  the site entity and immediately kicks a re-auction, so a cluster restart
  converges without waiting for the timer.

## Budget exhaustion is not removal

When a campaign exhausts its daily budget, its ServeIndex entries are *not*
deleted — deletion would also discard the publisher-approval status attached
to them, forcing every creative back through the approval queue at midnight.
Instead the entries' TTL is refreshed past the day rollover and the serve
path simply refuses to select over-budget campaigns. At rollover the budget
resets and the creatives resume instantly.

The same principle governs every eviction decision in the system: **removal
events are deliberate and scoped** (an advertiser suspended, a campaign
leaving a site takes its reader pins with it), while **temporary conditions
mark rather than delete**. Most historical serving bugs traced back to
violations of exactly this rule.
