# Entityの階層構造とCluster Role

## Entityの関連図

```
Advertiser (sharded by advertiserId)
  ├── Budget: dailyBudget, spendToday, lastResetEpochDay
  ├── Creatives: Map[CreativeId, Creative]
  ├── Site blocklist: Set[SiteId]
  └── Campaigns: Set[CampaignId]
        └── Campaign (sharded by advertiserId|campaignId)
              ├── Budget: dailyBudget, spendToday, maxCpm
              ├── RL Agent: BidOptimizationAgent (DQN snapshot)
              ├── Creative assignments: Set[CreativeId]
              ├── Spend buffer: 500ms / 20 events batching
              ├── Idempotency: BloomFilter (50K entries, 0.01% FPP)
              └── Categories: Set[CategoryId]

Publisher
  └── Site (sharded by siteId)
        ├── Config: domain, seedUrl, cronSchedule, maxDepth
        ├── PacingConfig: dayDuration, traffic shapes, warmupMode
        ├── Ad product blocklist: Set[AdProductCategoryId]
        └── Slots: List[AdSlotConfig(slotId, width, height)]

AuctioneerEntity (sharded by siteId)
  ├── Page classifications: Map[URL, Classification]
  ├── Participating campaigns: Map[CampaignId, Set[URL]]
  ├── TaxonomyRankerEntity (sharded by category|siteId)
  │     └── Thompson Sampling weights, half-life decay
  └── CategoryBidderEntity (sharded by category|siteId|shard)
        └── Virtual sharding: hash(siteId) % 5

CampaignDirectory (ClusterSingleton)
  └── 60-second reconciliation cycle
```

## Sharding戦略

各entityタイプは、そのアクセスパターンに最適化された異なるshard keyを使用します:

| Entity | Shard Key | Shards | 根拠 |
|--------|-----------|--------|-----------|
| AuctioneerEntity | `siteId` | 100 | サイト内の全ページが一括でオークションされる |
| CategoryBidderEntity | `category\|siteId\|shard` | 100 × 5 virtual | 人気カテゴリ内の負荷を分散する |
| TaxonomyRankerEntity | `category\|siteId` | 100 | bidderと同じ場所に配置し低レイテンシを実現 |
| CampaignEntity | `advertiserId\|campaignId` | 100 | 独立したライフサイクル、キャンペーンごとのRL状態 |
| AdvertiserEntity | `advertiserId` | 100 | 広告主ごとの予算とフリークエンシーキャップ |
| CampaignDistributor | N/A | 8 workers | `hash(categoryId) % 8`でルーティング |

## Entityのライフサイクル

### CampaignEntity
- **Statusの列挙型**: `Active`、`Paused`
- **Active**: 入札リクエストに応答し、RL agentが15分ごとにmultiplierを調整
- **Paused**: 応答を停止し、クリエイティブがServeIndexから削除される
- **予算消化済み**: 入札を停止するが、クリエイティブはServeIndexに**残る**（予算は毎日リセットされる）
- **日次リセットガード**: `lastRolledEpochDay`により同一暦日での二重ロールを防止
- **Passivation**: 5分間の非アクティブ後

### CampaignEntityの支出記録
支出パスは正確性を重視して設計されています:
1. **バッファリング**: 500msタイマー、または20イベントのバッチ（先に発火した方が優先）
2. **冪等性**: 50Kエントリの Bloom filter (0.01% FPP) + 50KのScaffeine cache (5分TTL)
3. **At-least-once**: 保留中のレポートはexponential backoffでリトライ（100ms → 5s、最大5回）
4. **Persist-then-publish**: `SpendUpdate`イベントの発行前に状態を保存

### AuctioneerEntity
- サイトのページが最初にクロールされた時点で**アクティブ化**
- 直近のオークションに参加したキャンペーンを**追跡**（ターゲットを絞った再オークション用）
- **定期的な再オークション**: 5分ごと（`promovolve.auction.reauction-interval`）
- **クリーンアップ**: 5分ごとに48時間以上経過した分類情報を削除
- 5分間の非アクティブ後に**passivation**

### AdvertiserEntity
- **追跡対象**: キャンペーンのSet、クリエイティブのMap、日次予算/支出
- **Flush IDの重複排除**: 直近1000件の処理済みflush IDを保持（`MaxProcessedFlushIds`）
- **日次リセット**: `lastResetEpochDay`と現在のepoch dayの比較に基づく
