# Periodic Batch Auction

The defining architectural choice of Promovolve is that auctions run **ahead of time**, not per-request. When a page is classified — on demand, triggered by its first visitor via the ad tag — the system runs a full multi-phase auction and caches results in DData for instant serve-time lookups.

## Auction Pipeline

```
┌─────────────────────────┐
│ Page Classification     │  LLM-based (Gemini/OpenAI/Anthropic)
│                         │  → IAB categories + confidence scores
└────────┬────────────────┘
         ▼
┌─────────────────────────┐
│ Category Ranking        │  TaxonomyRankerEntity per (category, site)
│                         │  → Thompson-sampled weights, 7-day half-life
└────────┬────────────────┘
         ▼
┌─────────────────────────┐
│ Bid Collection          │  CategoryBidderEntity (5 virtual shards)
│                         │  → CampaignDistributor (8 workers)
│                         │  → CampaignEntity bid responses
└────────┬────────────────┘
         ▼
┌─────────────────────────┐
│ Candidate Shortlisting  │  Fair selection: 1 per campaign, fill remainder
│                         │  → Top K per slot (default K=3)
└────────┬────────────────┘
         ▼
┌─────────────────────────┐
│ ServeIndex Caching      │  DData WriteLocal, 120-minute TTL
│                         │  → Replicated to all API nodes via gossip
└─────────────────────────┘
```

## Periodic Re-Auction

After the initial classification, the system runs **periodic re-auctions** every 5 minutes (`promovolve.auction.reauction-interval`) for recent content within the 48-hour freshness window. Additionally, event-driven re-auctions trigger on campaign/advertiser state changes (approve, pause, budget events) on a 1-second debounce.

## Classification Freshness Window

Only pages classified within the last **48 hours** participate in auctions. Every 5 minutes, AuctioneerEntity runs cleanup to remove classifications older than 48 hours.

## Key Configuration

| Parameter | Value | Env Var |
|-----------|-------|---------|
| Re-auction interval | 5 minutes | `REAUCTION_INTERVAL` |
| Classification freshness | 48 hours (default) | — |
| ServeIndex TTL | 120 minutes | — |
| Taxonomy ask timeout | 800ms | — |
