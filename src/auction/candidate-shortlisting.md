# Phase 4: Candidate Shortlisting

This is the critical phase where Promovolve diverges from traditional auctions. Instead of selecting a single winner, it creates a **shortlist of top-K candidates** per slot for serve-time exploration, using a fair selection algorithm that guarantees per-campaign diversity.

## Fair Candidate Selection Algorithm

The shortlisting algorithm ensures each campaign gets representation before any campaign gets a second slot:

```
1. Collect all CampaignBidResponses across all categories
2. Group by campaign → pick best creative per campaign (by CPM)
3. If #campaigns ≥ #slots:
     Take top campaigns by CPM, one creative each
4. Else (fewer campaigns than slots):
     Each campaign gets 1 slot (guaranteed representation)
     Fill remaining slots with next-best creatives from existing campaigns
5. Record participating campaigns → Map[CampaignId, Set[URL]]
```

### Why This Algorithm?

This ensures that 3 campaigns with 1 creative each will all be represented in a 3-slot configuration, rather than having one high-CPM campaign fill all 3 slots. Only when there are fewer campaigns than slots does any campaign get multiple creatives in the shortlist.

## Campaign Participation Tracking

AuctioneerEntity maintains:

```
participatingCampaigns: Map[CampaignId, Set[URL]]
```

This enables **targeted re-auction**: when a campaign's state changes, the system knows exactly which pages are affected.

## CandidateView Structure

Each shortlisted candidate is stored as a `CandidateView`:

```scala
CandidateView(
  creativeId: CreativeId,
  campaignId: CampaignId,
  advertiserId: AdvertiserId,
  assetUrl: CDNPath,         // URI to CDN-hosted creative asset
  mime: MimeType,            // imageJpeg, imagePng, imageGif, imageWebp, videoMp4
  width: Int,
  height: Int,
  category: CategoryId,
  cpm: CPM,
  classifiedAtMs: Long,      // when the page content was classified
  categoryScore: Double,     // classifierConfidence × rankerWeight (default 0.5)
  frequencyCap: Option[Int],
  adProductCategory: Option[AdProductCategoryId],
  landingDomain: String
)
```

Note: impression and click statistics are tracked **separately** in `CreativeStats` at the AdServer level, not stored in the `CandidateView` itself. This allows stats to accumulate across auction cycles.

## Standard Ad Sizes

Promovolve supports IAB standard sizes defined as `AdSize` opaque type `(Int, Int)`:

| Name | Size |
|------|------|
| Medium Rectangle | 300 × 250 |
| Leaderboard | 728 × 90 |
| Wide Skyscraper | 160 × 600 |
| Mobile Banner | 320 × 50 |
| Billboard | 970 × 250 |
| Half Page | 300 × 600 |
| Large Mobile Rectangle | 320 × 100 |

Image assets are subject to the IAB LEAN Ad limit: max file size **50 KiB** (`promovolve.image-limits.max-file-size`, configurable via `IMAGE_MAX_FILE_SIZE`).
