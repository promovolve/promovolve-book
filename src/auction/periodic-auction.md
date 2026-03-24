# Periodic Batch Auction

The defining architectural choice of Promovolve is that auctions run **ahead of time**, not per-request. When content is crawled (default schedule: 2am daily via Quartz cron), the system runs a full multi-phase auction and caches results in DData for instant serve-time lookups.

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

Between crawl cycles, the system runs **periodic re-auctions** every 5 minutes (`promovolve.auction.reauction-interval`) for recent content within the 48-hour recency window. Additionally, event-driven re-auctions trigger on campaign/advertiser state changes.

## Content Recency Window

Only pages classified within the last **48 hours** participate in auctions. Every 5 minutes, AuctioneerEntity runs cleanup to remove classifications older than 48 hours.

## Key Configuration

| Parameter | Value | Env Var |
|-----------|-------|---------|
| Re-auction interval | 5 minutes | `REAUCTION_INTERVAL` |
| Content recency | 48 hours | — |
| Crawl cron schedule | `"0 0 2 * * ?"` | Per-site config |
| Crawl max depth | 2 | Per-site config |
| Crawl concurrency | 5 | Per-site config |
| ServeIndex TTL | 120 minutes | — |
| Taxonomy ask timeout | 800ms | — |
