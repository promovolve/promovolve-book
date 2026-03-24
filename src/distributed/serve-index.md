# ServeIndex & DData

The ServeIndex is Promovolve's distributed in-memory cache storing auction results for instant serve-time lookups, built on Pekko Distributed Data (DData).

## Why DData?

Every API node must serve ads without network round-trips:

| Alternative | Problem |
|-------------|---------|
| Database (PostgreSQL) | 1-10ms per query |
| Remote cache (Redis) | ~0.5ms network hop |
| Sharded in-memory | Requires request routing |
| DData | Local replica on every node, gossip replication |

## Data Model

```
ServeIndex
  └── Bucket[0..31]  (32 buckets, power-of-2)
        └── LWWMap[String, ServeView]
              Key:   "siteId|slotId"
              Value: ServeView
```

### ServeView

```scala
case class ServeView(
  candidates: Vector[CandidateView],
  version: Long,       // e.g., auction timestamp
  expiresAtMs: Long    // epoch millis; for TTL sweep
) extends CborSerializable
```

### CandidateView

```scala
case class CandidateView(
  creativeId: CreativeId,
  campaignId: CampaignId,
  advertiserId: AdvertiserId,
  assetUrl: CDNPath,          // URI to CDN-hosted asset
  mime: MimeType,             // imageJpeg, imagePng, imageGif, imageWebp, videoMp4
  width: Int,
  height: Int,
  category: CategoryId,
  cpm: CPM,
  classifiedAtMs: Long,       // when page content was classified
  categoryScore: Double = 0.5, // classifierConfidence × rankerWeight
  frequencyCap: Option[Int] = None,
  adProductCategory: Option[AdProductCategoryId] = None,
  landingDomain: String = ""
) extends CborSerializable
```

## DData Configuration (from application.conf)

| Setting | Value |
|---------|-------|
| Gossip interval | 2s |
| Notify subscribers | 500ms |
| Max delta elements | 500 |
| Durable keys | `shard-*`, `exhausted-campaigns` |
| Durable store | LMDB (100 MiB, 200ms write-behind) |
| Pruning interval | 120s |

Note: ServeIndex entries are **not** in the durable keys list — they are ephemeral and rebuilt from auctions on restart. Only shard metadata and exhausted-campaign flags are LMDB-durable.
