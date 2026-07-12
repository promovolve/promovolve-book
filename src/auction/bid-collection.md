# Phase 3: Bid Collection

For each selected category, the system fans out to all active campaigns and collects bids. This is the most distributed phase of the auction.

## End-to-End Matching: From Ad Product to Page Content

To understand bid collection, it helps to see the full chain that connects an advertiser's product to a publisher's page. Here's a concrete example with a gym campaign:

**Campaign setup (happens once):**

1. Advertiser creates a campaign for their gym. The ad product category (**"Gyms and Health Clubs"**, IAB Ad Product 1512) is still declared — but it only feeds publisher blocklists, not matching
2. Target content categories are an explicit declaration in **IAB Content Taxonomy 3.0**: Gemini analyzes the campaign's landing page and suggests a set — say **{225, 227}** (Fitness and Exercise, Running and Jogging) — which the advertiser can edit
3. Campaign stores `categories = Set(225, 227)` — these are the content types this campaign will bid on
4. CampaignDirectory registers the campaign under categories 225 and 227
5. CategoryBidderEntity for categories 225 and 227 now knows this campaign exists

**On-demand classification (happens per page):**

6. A page's first visitor arrives; the ad tag extracts the live page's text and POSTs it to `/v1/classify-page`, which hands it to SiteEntity → Gemini
7. Gemini sees the **full Content Taxonomy 3.0** and returns whatever genuinely matches the page (possibly nothing); if it returns nothing, the site's known **demand categories** seed a broad low-confidence fallback pool so the auction isn't starved
8. If the page classifies into 225 or 227 with sufficient confidence, AuctioneerEntity fans out bid requests to CategoryBidderEntity — demand intersection happens here, at the fan-out
9. CategoryBidderEntity routes to the gym campaign
10. Campaign bids → candidate created → queued for publisher approval

**Key design decisions:**

- The classifier is **honest**: it sees the full taxonomy and reports what the page is actually about. Demand intersection happens downstream at the auction fan-out, not by constraining the prompt.
- Hallucinated category IDs (where the LLM returns an ID not in the taxonomy) are **filtered out** — only valid matches produce auctions.
- Both sides speak Content Taxonomy 3.0 IDs directly. There is no content↔ad-product mapping layer — the advertiser's target categories come from Gemini's read of their own landing page, refined by hand if they wish.

## CategoryBidderEntity

Each `(category, siteId)` pair uses **5 virtual shards** to distribute load. The shard is selected by `hash(siteId) % 5`, so the actual entity key is `category|siteId|shardIndex`.

## CampaignDistributor

Within each CategoryBidderEntity, a `CampaignDistributor` manages fan-out to individual campaigns using **8 worker actors**, routed by `hash(categoryId) % 8`.

## Bid Request → Response

Each `CampaignEntity` evaluates the request and responds with eligible creatives. The bid CPM is simply the advertiser's max CPM:

```scala
bidCpm = max(maxCpm, floorCpm)
```

Where:
- `maxCpm`: The campaign's configured maximum CPM
- `floorCpm`: The publisher's floor price (auto-optimized by the floor CPM agent)

The advertiser bids their true value. There's no bid shading or multiplier — the quality-adjusted pricing at serve time ensures they only pay what's needed to win, not their full bid.

## Eligibility Filters (Campaign-Side)

A CampaignEntity will not respond if any of these checks fail:

1. **Category mismatch**: The page category is not in the campaign's `categories` set — this is the primary filter. The campaign's categories are its declared Content Taxonomy 3.0 target set (Gemini-suggested from the landing page, advertiser-editable). Matching is **exact**: `state.categories.contains(pageCategory)`
2. **Category blocklisted**: The category is in the campaign's `categoryBlocklist` (explicit exclusions)
3. **Status paused**: Campaign `status != Active`
4. **Budget exhausted**: `dailyBudget - (spendToday + bufferedSpend) <= 0`
5. **Day-aware check**: If the calendar day changed since `lastResetInstant`, the budget is treated as fresh (reset happens lazily)
6. **Site blocklisted**: Publisher's site is on the advertiser's `siteBlacklist`
7. **No matching sizes**: None of the campaign's `allowedSizes` fit the slot's `AdSlotConfig(width, height)`

## Aggregation Rules

The CategoryBidderEntity aggregates responses:

1. **CPM threshold**: Only candidates within **top 80%** of the highest CPM are kept: `cpm ≥ maxCpm × (1.0 - 0.80)`. This is deliberately wide — quality-adjusted pricing at serve time handles differentiation among competitive bids.
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
