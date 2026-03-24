# 再オークションとイベントトリガー

クロールサイクルの間、システムは定期的およびイベント駆動型の再オークションを通じてServeIndexを最新に保ちます。

## 定期再オークション

AuctioneerEntityは48時間のコンテンツ鮮度ウィンドウ内のすべてのページに対して、**5分ごと**（`promovolve.auction.reauction-interval`、環境変数: `REAUCTION_INTERVAL`）に完全な再オークションを実行します。

## イベント駆動型再オークション

### キャンペーンレベルのイベント（ターゲット型）

これらは、影響を受けるキャンペーンが参加しているページのみ（`participatingCampaigns`マップを使用）に対して再オークションをトリガーします:

| イベント | ServeIndexアクション | 再オークション範囲 |
|-------|-------------------|-----------------|
| `CampaignBudgetExhausted` | TTLの更新（エントリを保持） | 参加ページ |
| `CampaignBudgetReset` | TTLの更新 | 参加ページ |
| `CampaignPaused` | ServeIndexから**削除** | 参加ページ |
| `CampaignAdProductChanged` | ServeIndexから**削除** | 参加ページ |
| `CpmUpdated` | ServeIndex内のCPMを更新 | 参加ページ |
| `CreativeStatusChanged(isActive=false)` | **クリエイティブを削除** | 参加ページ |

### 広告主レベルのイベント（サイト全体）

これらは広告主配下のすべてのキャンペーンに影響します:

| イベント | ServeIndexアクション | 再オークション範囲 |
|-------|-------------------|-----------------|
| `AdvertiserBudgetExhausted` | TTLの更新（エントリを保持） | サイト上のすべての最近のページ |
| `AdvertiserBudgetReset` | TTLの更新 | サイト上のすべての最近のページ |
| `AdvertiserSuspended` | ServeIndexから**削除** | サイト上のすべての最近のページ |

## 予算枯渇: 削除せず保持する

キャンペーンまたは広告主の予算が枯渇した場合、クリエイティブはServeIndexから**削除されません**。代わりに:

1. **TTLが更新**され、`dayDurationSeconds × 1.1 × 1000ms`に設定される（次の予算リセットまで延長）
2. 配信時の**ペーシングゲート**が配信前に予算をチェックする
3. 予算が枯渇している場合、その候補はスキップされ、Thompson Samplingが別の候補を選択する
4. 予算がリセットされると（翌日）、再オークションなしでクリエイティブの配信が再開される

**理由:** 予算枯渇は一時的であり、予算は毎日リセットされます。エントリの削除と再挿入は以下の問題を引き起こします:
- 不要なDDataのチャーン（WriteMajorityによる削除はコストが高い）
- クリエイティブの承認ステータスの喪失
- エントリを復元するための完全な再オークションの必要性

## 恒久的な削除

ServeIndexからの実際の削除が必要なイベントは以下のみです:
- クリエイティブの一時停止/無効化
- キャンペーンの一時停止
- キャンペーンの広告商品カテゴリの変更（パブリッシャーのブロックリストに違反する可能性）
- 広告主の停止

これらは`WriteMajority`の一貫性を使用し、最大5回のリトライと200msの初期バックオフで実行されます。

## コンテンツクリーンアップ

5分ごとに、AuctioneerEntityは内部の`Map[URL, Classification]`から48時間より古い分類を削除し、古くなったコンテンツが自然にエージアウトするようにします。

## 公開イベント

再オークションと予算イベントは、エンティティ間の連携のためにドメインイベント（`CborSerializable`を拡張）として公開されます:

- `SpendUpdate`: CampaignEntityから約500msまたは20イベントごとに公開され、`dailyBudget`、`todaySpend`、`dayStart`を含む
- `PendingCreativesQueued`: パブリッシャー承認ワークフロー用のSSE通知をトリガー
