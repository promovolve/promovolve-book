# Auction Timing: Periodic vs Realtime

The most fundamental difference between Promovolve and traditional ad tech is **when** the auction runs.

## Traditional: Per-Request Auctions

```
t=0ms    User loads page
t=5ms    SSP sends bid request to exchange
t=10ms   Exchange broadcasts to DSPs
t=80ms   DSPs respond with bids
t=85ms   Exchange picks winner
t=90ms   Ad creative URL returned
t=200ms  Ad renders on page
```

**Advantages**: Fresh bidding, competitive price discovery
**Disadvantages**: 50-200ms latency, auction QPS = page QPS, failure = empty slot

## Promovolve: Periodic Batch Auctions

```
Crawl time (background, 2am daily + 5-min re-auctions):
  t=0s     Crawler classifies page (LLM)
  t=1s     AuctioneerEntity starts auction
  t=3s     Bids collected (800ms timeout for taxonomy)
  t=4s     Candidates cached in DData

Serve time (user-facing):
  t=0.0ms  User loads page
  t=0.1ms  Local DData lookup
  t=0.2ms  Pacing gate + Thompson Sampling
  t=0.3ms  Ad response sent
```

**Advantages**: Sub-ms serving, bounded compute, graceful failure, exploration
**Disadvantages**: Stale bids (up to 5 min between re-auctions), no user-level signals

## When Periodic Wins

1. **Content is the signal, not the user**: Promovolve targets content categories via LLM classification. Content changes slowly, so periodic auctions suffice.
2. **Single publisher control**: No cross-publisher price discovery needed.
3. **Serve latency matters**: Adding 100ms per ad slot is unacceptable for performance-conscious publishers.
4. **Exploration has value**: The publisher wants to learn which creatives engage users, not just which advertiser pays most.

## The Refresh Cycle

Promovolve's re-auction interval (5 minutes) is a middle ground:
- Fresh enough to react to campaign budget changes
- Infrequent enough to avoid overwhelming entity actors
- Candidates in DData with 120-minute TTL survive multiple re-auction cycles
