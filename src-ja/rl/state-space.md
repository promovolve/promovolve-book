# State Space

DQNエージェントは、15分の観測ウィンドウから計算される**8次元のstate vector**を観測します。

## Stateの次元（BidOptimizationAgent.scalaより）

| Index | Name | Formula | Range | Signal |
|-------|------|---------|-------|--------|
| 0 | effectiveCpm | `clamp(2.0, (maxCpm × bidMultiplier) / maxCpm)` | [0, 2.0] | 現在の入札レベル |
| 1 | ctr | `min(1.0, windowClicks / windowImpressions)` | [0, 1.0] | エンゲージメント品質 |
| 2 | winRate | `windowWins / windowBidOpportunities` (default 0.5) | [0, 1] | 競争力 |
| 3 | budgetRemaining | `clamp(1.0, budgetRemaining / dailyBudget)` | [0, 1.0] | 予算消化状況 |
| 4 | timeRemaining | `clamp(1.0, 1.0 - elapsed / rlDayDurationSeconds)` | [0, 1.0] | 時間的プレッシャー |
| 5 | spendRate | `min(3.0, actualSpend / expectedSpend)` | [0, 3.0] | ペーシング精度 |
| 6 | impressionRate | `min(2.0, windowImpressions / 100.0)` | [0, 2.0] | 配信ボリューム |
| 7 | costPerClick | `min(2.0, (windowSpend / windowClicks) / maxCpm)` | [0, 2.0] | 効率性 |

## 各次元の詳細

### effectiveCpm（index 0）
正規化された入札レベル：`maxCpm × bidMultiplier / maxCpm = bidMultiplier`なので、`bidMultiplier`そのものです。[0, 2.0]にクランプされます。エージェントに前回の決定を伝えます。

### ctr（index 1）
現在の15分観測ウィンドウ内のクリック率。インプレッションがない場合はゼロ。現在のトラフィックミックスにおけるクリエイティブ品質に関する即時フィードバックを提供します。

### winRate（index 2）
入札機会のうち、クリエイティブがショートリストに入った割合。入札機会がなかった場合、デフォルトは0.5（中立）。低い勝率 → 競合と比較して入札が低すぎる。

### budgetRemaining（index 3）
日次予算に対する残り予算の割合。`timeRemaining`と組み合わせることで、エージェントにペースが合っているかを伝えます：
- 予算多い + 残り時間少ない → 積極的に入札可能
- 予算少ない + 残り時間多い → 節約が必要

### timeRemaining（index 4）
配信日の残り時間の割合。`1.0 - elapsedSeconds / rlDayDurationSeconds`として計算されます。`rlDayDurationSeconds`のデフォルトは86400（実際の24時間）ですが、`RL_DAY_DURATION_SECONDS`を通じてシミュレーション用に短く設定できます。

### spendRate（index 5）
実際の消化額と期待消化額の比率で、3.0倍にキャップされます。期待消化額は均等な線形分布を仮定：`dailyBudget × (elapsed / totalTime)`。spendRateが1.0 = 完璧なペーシング。1.0を超える = 過剰消化。

### impressionRate（index 6）
15分ウィンドウあたりのインプレッション数で、100インプレッションのベースラインで正規化。2.0倍にキャップ。消化額とは独立 — 配信ボリュームを捕捉します。

### costPerClick（index 7）
maxCpmで正規化されたクリックあたりの消化額。クリック > 0の場合にのみ意味があります（それ以外は0.0を返します）。maxCpmに対して高いCPCは、達成されたCTRに対して入札が高すぎることを示唆します。

## なぜこの8次元なのか？

stateは入札に必要な**最小十分統計量**を捕捉しています：

| Pair | Signal |
|------|--------|
| Budget + Time | 積極的にすべきか保守的にすべきか？ |
| Win Rate + CPM | 競争力があるか？ |
| CTR + CPC | 良い価値を得ているか？ |
| Spend Rate + Impression Rate | ペースは合っているか？ |

## 正規化

すべての次元は`min()`または`clamp()`により有界（主に[0, 1]または[0, 2-3]）です。これはニューラルネットワークにとって重要です — 無制限の特徴量は勾配の問題を引き起こします。キャッピングにより、外れ値がQ-value推定を不安定にすることを防ぎます。
