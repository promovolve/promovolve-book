# TTL Sweep & 有効期限

ServeIndexのエントリには、古い広告が無期限に配信され続けることを防ぐためのTTL（有効期限）があります。

## TTLの割り当て

オークション結果の書き込み時：

```
expiresAtMs = System.currentTimeMillis() + ttlDurationMs
```

デフォルトTTL：**120分**。通常の運用では、次のオークションがTTLの期限切れ前にエントリをリフレッシュします。

### 予算枯渇時のTTLリフレッシュ

`CampaignBudgetExhausted`または`AdvertiserBudgetExhausted`の場合：

```
expiresAtMs = System.currentTimeMillis() + (dayDurationSeconds × 1.1 × 1000)
```

1.1倍の係数により、エントリは次の日次予算リセットを十分に超えるまで存続します。

## 定期的なSweep

`ServeIndexDData.scala`より：

```
SweepInterval = 2.minutes
MaxKeysRemovePerRun = 500
```

2分ごとに、各ノードがすべての32個のバケットをスキャンします：

```
for each bucket:
    entries = bucket.entries
    expired = entries.filter(e => now > e.expiresAtMs)
    remove up to 500 expired entries from this bucket
```

### 削除数の制限

バケットあたり500の制限により、大量の有効期限切れがDDataを圧倒することを防ぎます：
- 32バケット × 500 = sweepあたり最大16,000エントリ
- 実際には、有効期限切れは時間的に分散しているため、バッチは小さくなる

## なぜ即時の有効期限切れではないのか？

| アプローチ | 問題点 |
|----------|---------|
| 即時の有効期限切れ | ノード間のクロックスキュー → エントリが点滅する |
| 個別の削除 | 多数の小さなデルタ → gossipのオーバーヘッド |
| バッチsweep | 予測可能な負荷、クロックスキューに耐性がある |

2分のsweep間隔は、期限切れのエントリが最大2分余分に配信される可能性があることを意味します。これは許容範囲です — ペーシングゲートと予算チェックが配信時に追加の安全性を提供します。
