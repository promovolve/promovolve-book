# フェーズ4: 候補ショートリスト

これは、Promovolveが従来のオークションと決定的に異なるフェーズです。単一の勝者を選ぶのではなく、配信時の探索のためにスロットごとに**Top-K候補のショートリスト**を作成し、キャンペーンごとの多様性を保証する公平な選択アルゴリズムを使用します。

## 公平な候補選択アルゴリズム

ショートリストアルゴリズムは、いずれかのキャンペーンが2つ目のスロットを得る前に、各キャンペーンが確実に代表されることを保証します:

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

### このアルゴリズムを採用する理由

これにより、3つのキャンペーンがそれぞれ1つのクリエイティブを持つ場合、3スロット構成ですべてのキャンペーンが確実に代表されます。1つの高CPMキャンペーンが3スロットすべてを占有することはありません。キャンペーンがスロット数より少ない場合にのみ、あるキャンペーンがショートリスト内で複数のクリエイティブを持つことになります。

## キャンペーン参加トラッキング

AuctioneerEntityは以下を管理します:

```
participatingCampaigns: Map[CampaignId, Set[URL]]
```

これにより**ターゲット再オークション**が可能になります: キャンペーンの状態が変わった際に、システムはどのページが影響を受けるかを正確に把握できます。

## CandidateView構造

ショートリストされた各候補は`CandidateView`として格納されます:

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

注意: インプレッションとクリックの統計は、`CandidateView`自体には格納されず、AdServerレベルの`CreativeStats`で**個別に**追跡されます。これにより、統計がオークションサイクルを超えて蓄積されます。

## 標準広告サイズ

PromovolveはIAB標準サイズをサポートしており、`AdSize`不透明型`(Int, Int)`として定義されています:

| 名称 | サイズ |
|------|------|
| Medium Rectangle | 300 × 250 |
| Leaderboard | 728 × 90 |
| Wide Skyscraper | 160 × 600 |
| Mobile Banner | 320 × 50 |
| Billboard | 970 × 250 |
| Half Page | 300 × 600 |
| Large Mobile Rectangle | 320 × 100 |

画像アセットにはIAB LEAN Ad制限が適用されます: 最大ファイルサイズ**50 KiB**（`promovolve.image-limits.max-file-size`、`IMAGE_MAX_FILE_SIZE`で設定可能）。
