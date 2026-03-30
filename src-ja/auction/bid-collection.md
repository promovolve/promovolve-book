# Phase 3: Bid Collection

選択された各カテゴリに対して、システムはすべてのアクティブなキャンペーンにファンアウトし、入札を収集します。これはオークションの中で最も分散的なフェーズです。

## エンドツーエンドのマッチング: Ad Productからページコンテンツまで

Bid Collectionを理解するために、広告主の商品とパブリッシャーのページを結ぶ全体の流れを見てみましょう。ここではジムキャンペーンを具体例として示します。

**キャンペーンのセットアップ（一度だけ実行）:**

1. 広告主がキャンペーンを作成し、Ad Productを選択: **"Gyms and Health Clubs"** (IAB Ad Product 1512)
2. `ContentToAdProductMapping.getContentForAdProduct("1512")` がIABマッピングを参照
3. 1512に直接のマッピングがない → 親の **1510** (Fitness Activities) に遡る
4. 1510がコンテンツカテゴリ **{225, 227}** (Fitness and Exercise, Running and Jogging) にマッピングされる
5. キャンペーンが `categories = Set(225, 227)` を保存 — これがこのキャンペーンが入札するコンテンツタイプとなる
6. CampaignDirectory がカテゴリ225と227の下にキャンペーンを登録
7. カテゴリ225と227の CategoryBidderEntity がこのキャンペーンの存在を認識する

**ページクロール（ページごとに実行）:**

8. SiteEntity がすべてのアクティブなキャンペーンから **デマンドカテゴリ** を収集 → `{225, 227}`
9. `buildTaxonomyCandidates` がこれらを子孫カテゴリで展開 → `{226, 227}` (Participant Sports, Running and Jogging)
10. これが Gemini に送信される **候補リスト** となる — LLMはアクティブなキャンペーンがターゲットしているカテゴリのみを参照する
11. Gemini がそれらのカテゴリのみを使用してページテキストを分類
12. 十分な信頼度で225または227が返された場合、AuctioneerEntity が CategoryBidderEntity に入札リクエストをファンアウト
13. CategoryBidderEntity がジムキャンペーンにルーティング
14. キャンペーンが入札 → 候補が作成 → パブリッシャーの承認待ちキューに入る

**主要な設計判断:**

- LLMプロンプトは **デマンドカテゴリに制約される** — アクティブなキャンペーンが存在するカテゴリにのみ分類を行います。これによりトークンを節約し、誰も広告を出していないコンテンツの分類を回避します。
- ハルシネーションによるカテゴリID（LLMが候補リストにないIDを返した場合）は **フィルタリングされる** — 有効なマッチのみがオークションを生成します。
- 広告主はコンテンツカテゴリを一切見ることがありません。広告主は自分の商品を選択するだけで、IABマッピングが残りを処理します。

## CategoryBidderEntity

各 `(category, siteId)` ペアは、負荷を分散するために **5つの仮想シャード** を使用します。シャードは `hash(siteId) % 5` で選択されるため、実際のエンティティキーは `category|siteId|shardIndex` となります。

## CampaignDistributor

各 CategoryBidderEntity 内で、`CampaignDistributor` が **8つのワーカーアクター** を使用して個別キャンペーンへのファンアウトを管理します。ルーティングは `hash(categoryId) % 8` で行われます。

## Bid Request → Response

各 `CampaignEntity` はリクエストを評価し、適格なクリエイティブを返します。Bid CPM は以下のように計算されます:

```scala
bidCpm = max(maxCpm × bidMultiplier, floorCpm)
```

各パラメータの意味:
- `maxCpm`: キャンペーンに設定された最大CPM（デフォルト: $5.00）
- `bidMultiplier`: RLエージェントの現在のマルチプライヤー。`[minMultiplier, maxMultiplier]` の範囲にクランプされる
- `floorCpm`: システムのフロアプライス（デフォルト: $0.50）

RLエージェントは、マルチプライヤーが低い場合でも入札がフロアプライスを下回らないことを保証します。

## 適格性フィルター（キャンペーン側）

以下のいずれかのチェックに失敗した場合、CampaignEntity はレスポンスを返しません:

1. **カテゴリ不一致**: ページカテゴリがキャンペーンの `categories` セットに含まれていない — これが主要なフィルターです。キャンペーンのカテゴリは、Ad Product Taxonomy 2.0 IDから `ContentToAdProductMapping` を介して導出され、Content Taxonomy 2.1 IDのセットにマッピングされます。マッチングは **完全一致** です: `state.categories.contains(pageCategory)`
2. **カテゴリブロックリスト**: カテゴリがキャンペーンの `categoryBlocklist` に含まれている（明示的な除外）
3. **ステータス一時停止**: キャンペーンの `status != Active`
4. **予算枯渇**: `dailyBudget - (spendToday + bufferedSpend) <= 0`
5. **日付チェック**: `lastResetInstant` 以降にカレンダー日が変わった場合、予算はリセット済みとして扱われる（リセットは遅延実行される）
6. **サイトブロックリスト**: パブリッシャーのサイトが広告主の `siteBlacklist` に登録されている
7. **サイズ不一致**: キャンペーンの `allowedSizes` のいずれもスロットの `AdSlotConfig(width, height)` に適合しない

## 集約ルール

CategoryBidderEntity はレスポンスを以下のように集約します:

1. **CPM閾値**: 最高CPMの **上位20%** 以内の候補のみが保持される: `cpm ≥ maxCpm × (1.0 - 0.20)`
2. **キャンペーン上限**: カテゴリごとに最大 **50キャンペーン** (`maxCampaignsPerCategory`)、CPM降順でランク付け
3. **キャンペーンあたり1クリエイティブ**: キャンペーンに複数の適格なクリエイティブがある場合、最高CPMのクリエイティブが選ばれる

## レスポンス構造

各適格なクリエイティブは `Candidate` にラップされます:

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
