# Phase 3: Bid Collection

For each selected category, the system fans out to all active campaigns and collects bids. This is the most distributed phase of the auction.

## CategoryBidderEntity

Each `(category, siteId)` pair uses **5 virtual shards** to distribute load. The shard is selected by `hash(siteId) % 5`, so the actual entity key is `category|siteId|shardIndex`.

## CampaignDistributor

Within each CategoryBidderEntity, a `CampaignDistributor` manages fan-out to individual campaigns using **8 worker actors**, routed by `hash(categoryId) % 8`.

## Bid Request → Response

Each `CampaignEntity` evaluates the request and responds with eligible creatives. The bid CPM is computed as:

```scala
bidCpm = max(maxCpm × bidMultiplier, floorCpm)
```

Where:
- `maxCpm`: The campaign's configured maximum CPM (default: $5.00)
- `bidMultiplier`: The RL agent's current multiplier, clamped to `[minMultiplier, maxMultiplier]`
- `floorCpm`: The system floor price (default: $0.50)

The RL agent ensures the bid never falls below floor even with a low multiplier.

## Eligibility Filters (Campaign-Side)

A CampaignEntity will not respond if any of these checks fail:

1. **Category mismatch**: The page category is not in the campaign's `categories` set — this is the primary filter. The campaign's categories are derived from its Ad Product Taxonomy 2.0 ID via `ContentToAdProductMapping`, which maps to a set of Content Taxonomy 2.1 IDs. Matching is **exact**: `state.categories.contains(pageCategory)`
2. **Category blocklisted**: The category is in the campaign's `categoryBlocklist` (explicit exclusions)
3. **Status paused**: Campaign `status != Active`
4. **Budget exhausted**: `dailyBudget - (spendToday + bufferedSpend) <= 0`
5. **Day-aware check**: If the calendar day changed since `lastResetInstant`, the budget is treated as fresh (reset happens lazily)
6. **Site blocklisted**: Publisher's site is on the advertiser's `siteBlacklist`
7. **No matching sizes**: None of the campaign's `allowedSizes` fit the slot's `AdSlotConfig(width, height)`

## Aggregation Rules

The CategoryBidderEntity aggregates responses:

1. **CPM threshold**: Only candidates within **top 20%** of the highest CPM are kept: `cpm ≥ maxCpm × (1.0 - 0.20)`
2. **Campaign cap**: Maximum **50 campaigns** per category (`maxCampaignsPerCategory`), ranked by CPM descending
3. **One creative per campaign**: The highest-CPM creative wins if a campaign has multiple eligible creatives

## Response Structure

Each eligible creative is wrapped in a `Candidate`:

```scala
Candidate(
  creativeId: CreativeId,
  campaignId: CampaignId,
  advertiserId: AdvertiserId,
  cpm: CPM,                              // bidCpm from above
  category: CategoryId,
  creativeHash: String,
  landingDomain: String,
  preApproved: Boolean,
  frequencyCap: Option[Int],
  adProductCategory: Option[AdProductCategoryId]
)
```
