# フェーズ3: 入札収集

選択された各カテゴリに対して、システムはすべてのアクティブなキャンペーンにファンアウトし、入札を収集する。これはオークションの中で最も分散化されたフェーズである。

## CategoryBidderEntity

各`(category, siteId)`ペアは負荷を分散するために**5つの仮想シャード**を使用する。シャードは`hash(siteId) % 5`で選択されるため、実際のエンティティキーは`category|siteId|shardIndex`となる。

## CampaignDistributor

各CategoryBidderEntity内で、`CampaignDistributor`は**8つのワーカーアクター**を使用して個々のキャンペーンへのファンアウトを管理し、`hash(categoryId) % 8`でルーティングする。

## 入札リクエストからレスポンスへ

各CampaignEntityはリクエストを評価し、適格なクリエイティブで応答する。入札CPMは以下のように計算される:

```scala
bidCpm = max(maxCpm × bidMultiplier, floorCpm)
```

各項目の意味:
- `maxCpm`: キャンペーンに設定された最大CPM（デフォルト: $5.00）
- `bidMultiplier`: RLエージェントの現在の乗数。`[minMultiplier, maxMultiplier]`にクランプされる
- `floorCpm`: システムのフロア価格（デフォルト: $0.50）

RLエージェントは、乗数が低い場合でも入札がフロア価格を下回らないことを保証する。

## 適格性フィルター（キャンペーン側）

以下のチェックのいずれかに失敗した場合、CampaignEntityは応答しない:

1. **カテゴリ不一致**: ページのカテゴリがキャンペーンの`categories`セットに含まれていない — これが主要なフィルターである。キャンペーンのカテゴリはAd Product Taxonomy 2.0のIDから`ContentToAdProductMapping`を通じて導出され、Content Taxonomy 2.1のIDセットにマッピングされる。マッチングは**厳密**: `state.categories.contains(pageCategory)`
2. **カテゴリがブロックリストに該当**: カテゴリがキャンペーンの`categoryBlocklist`に含まれている（明示的な除外）
3. **ステータスが一時停止**: キャンペーンの`status != Active`
4. **予算枯渇**: `dailyBudget - (spendToday + bufferedSpend) <= 0`
5. **日付を考慮したチェック**: `lastResetInstant`以降にカレンダー日が変わった場合、予算はリセットされたものとして扱われる（遅延リセット）
6. **サイトがブロックリストに該当**: パブリッシャーのサイトが広告主の`siteBlacklist`に含まれている
7. **適合するサイズがない**: キャンペーンの`allowedSizes`のいずれもスロットの`AdSlotConfig(width, height)`に合致しない

## 集約ルール

CategoryBidderEntityはレスポンスを集約する:

1. **CPM閾値**: 最高CPMの**上位20%**以内の候補のみが残される: `cpm ≥ maxCpm × (1.0 - 0.20)`
2. **キャンペーン上限**: カテゴリあたり最大**50キャンペーン**（`maxCampaignsPerCategory`）、CPMの降順でランク付け
3. **キャンペーンあたり1クリエイティブ**: キャンペーンに複数の適格なクリエイティブがある場合、最高CPMのクリエイティブが選ばれる

## レスポンス構造

適格な各クリエイティブは`Candidate`としてラップされる:

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
