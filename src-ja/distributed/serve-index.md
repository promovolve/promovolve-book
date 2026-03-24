# ServeIndex & DData

ServeIndexは、Pekko Distributed Data (DData)上に構築された、オークション結果を即座に配信時ルックアップするためのPromovolveの分散インメモリキャッシュです。

## なぜDDataなのか？

すべてのAPIノードは、ネットワークラウンドトリップなしに広告を配信する必要があります：

| 代替手段 | 問題点 |
|-------------|---------|
| Database (PostgreSQL) | クエリあたり1-10ms |
| Remote cache (Redis) | ネットワークホップ約0.5ms |
| Sharded in-memory | リクエストルーティングが必要 |
| DData | すべてのノードにローカルレプリカ、gossipレプリケーション |

## データモデル

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

## DData設定（application.confより）

| 設定 | 値 |
|---------|-------|
| Gossip interval | 2s |
| Notify subscribers | 500ms |
| Max delta elements | 500 |
| Durable keys | `shard-*`, `exhausted-campaigns` |
| Durable store | LMDB (100 MiB, 200ms write-behind) |
| Pruning interval | 120s |

注意：ServeIndexのエントリはdurable keysリストに含まれて**いません** — これらは一時的であり、再起動時にオークションから再構築されます。LMDBで永続化されるのは、shardのメタデータとexhausted-campaignフラグのみです。
