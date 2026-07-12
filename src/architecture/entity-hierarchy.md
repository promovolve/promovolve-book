# Entity Hierarchy & Cluster Roles

## Entity Relationship Map

```
Advertiser (sharded by advertiserId)
  ├── Budget: dailyBudget, spendToday, lastResetEpochDay
  ├── Creatives: Map[CreativeId, Creative]
  ├── Site blocklist: Set[SiteId]
  └── Campaigns: Set[CampaignId]
        └── Campaign (sharded by advertiserId|campaignId)
              ├── Budget: dailyBudget, spendToday, maxCpm
              ├── Creative assignments: Set[CreativeId]
              ├── Spend buffer: 500ms / 20 events batching
              ├── Idempotency: BloomFilter (50K entries, 0.01% FPP)
              └── Categories: Set[CategoryId]

Publisher
  └── Site (sharded by siteId)
        ├── Config: domain (+ seedUrl, cronSchedule, maxDepth — inert crawl-era vestiges)
        ├── Page classifications: Map[URL, ClassificationEntry] (durable copy)
        ├── PacingConfig: dayDuration, traffic shapes, warmupMode
        ├── Ad product blocklist: Set[AdProductCategoryId]
        └── Slots: List[AdSlotConfig(slotId, width, height)]

AuctioneerEntity (sharded by siteId)
  ├── lastPage: Map[URL, (categories, slots, classifiedAt)] (in-memory cache)
  ├── Participating campaigns: Map[CampaignId, Set[URL]]
  ├── TaxonomyRankerEntity (sharded by category|siteId)
  │     └── Thompson Sampling weights, half-life decay
  └── CategoryBidderEntity (sharded by category|siteId|shard)
        └── Virtual sharding: hash(siteId) % 5

CampaignDirectory (ClusterSingleton)
  ├── Reverse index: CategoryId → Map[CampaignId, AdvertiserId]
  ├── Routes updates via CampaignDistributor (8 workers)
  │     └── Fan-out to CategoryBidderEntity shards
  └── 60-second reconciliation cycle
```

## Sharding Strategy

Each entity type uses a different shard key optimized for its access pattern:

| Entity | Shard Key | Shards | Rationale |
|--------|-----------|--------|-----------|
| AuctioneerEntity | `siteId` | 100 | All pages on a site auction together |
| CategoryBidderEntity | `category\|siteId\|shard` | 100 × 5 virtual | Distributes load within popular categories |
| TaxonomyRankerEntity | `category\|siteId` | 100 | Co-located with bidder for low-latency |
| CampaignEntity | `advertiserId\|campaignId` | 100 | Independent lifecycle, per-campaign budget and pacing state |
| AdvertiserEntity | `advertiserId` | 100 | Budget and frequency caps per advertiser |
| CampaignDistributor | N/A | 8 workers | Routes by `hash(categoryId) % 8` |

## Entity Lifecycle

### CampaignEntity
- **Status enum**: `Active`, `Paused`
- **Active**: Responds to bid requests with the campaign's CPM (no bid optimizer — quality-adjusted second-price clearing handles price discovery)
- **Paused**: Stops responding, creatives removed from ServeIndex
- **Budget exhausted**: Stops bidding, creatives **remain** in ServeIndex (budget resets daily)
- **Day reset guard**: `lastRolledEpochDay` prevents double-roll on same calendar day
- **Passivation**: After 5 minutes of inactivity

### CampaignEntity Spend Recording
The spend path is carefully designed for correctness:
1. **Buffered**: 500ms timer OR batch of 20 events (whichever fires first)
2. **Idempotency**: 50K-entry Bloom filter (0.01% FPP) + 50K Scaffeine cache (5min TTL)
3. **At-least-once**: Pending reports retry with exponential backoff (100ms → 5s, max 5 attempts)
4. **Persist-then-publish**: State saved before `SpendUpdate` event published

### AuctioneerEntity
- **Activated** on the first classify/serve of a site's page
- **Holds** an in-memory `lastPage` cache of classifications — the durable copy lives in `SiteEntity.pageClassifications`, reseeded at boot via `RestoreClassifications` and recovered per-URL on a `Reevaluate` miss
- **Tracks** which campaigns participated in recent auctions (for targeted re-auction)
- **Periodic re-auction**: Every 5 minutes (`promovolve.auction.reauction-interval`)
- **Cleanup**: Removes classifications older than 48 hours every 5 minutes
- **Passivates** after 5 minutes of inactivity

### AdvertiserEntity
- **Tracks**: Set of campaigns, Map of creatives, daily budget/spend
- **Flush ID dedup**: Maintains last 1000 processed flush IDs (`MaxProcessedFlushIds`)
- **Day reset**: Based on `lastResetEpochDay` comparison with current epoch day
