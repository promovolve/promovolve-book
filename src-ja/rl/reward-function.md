# Reward Function

Reward functionは、DQNエージェントが何を最適化するかを定義します。`BidOptimizationAgent.scala`より：

## 数式

```scala
reward = clickReward - overspendPenalty

where:
  clickReward = windowClicks.toDouble

  overspendPenalty = if (spendRate > 1.5)
                       config.overspendPenalty × (spendRate - 1.5)
                     else 0.0
```

**デフォルトのペナルティ係数**：`overspendPenalty = 2.0`

## 構成要素の分解

### クリック（主要な信号）

15分の観測ウィンドウ内の生のクリック数。これがポジティブな信号です — 広告主が重視するものであるため、エージェントはクリックを最大化します。

**なぜインプレッションではなくクリックか？**
- インプレッションは価値を示さない — ユーザーの視点からは「無料」
- クリックは実際のエンゲージメントを表す
- クリックの最大化は自然にCTRの高いプレースメントを選択する

**なぜ収益ではなくクリックか？**
- 収益（CPM × インプレッション）は可能な限り高い入札を促すインセンティブになる
- これは効率的な消化に対する広告主の利益に反する
- クリックはエージェントを広告主のROIに合致させる

### 過剰消化ペナルティ

```
overspendPenalty = 2.0 × max(0, spendRate - 1.5)
```

- **1.5倍での閾値**：目標より50%速く消化するまでペナルティなし。良い機会があるときにエージェントが積極的に入札する自由を与えます。
- **2.0倍の係数**：1.5倍を超える過剰消化の各単位に2.0のrewardポイントのコスト
- **連続的**：ハードウォールに当たるのではなく、エージェントがトレードオフを学習できる

例：
```
spendRate = 1.0 → penalty = 0      (on pace)
spendRate = 1.5 → penalty = 0      (at threshold)
spendRate = 2.0 → penalty = 1.0    (moderate overspend)
spendRate = 3.0 → penalty = 3.0    (severe overspend)
```

## エピソードの終了

エピソードは以下の場合に終了します：

```scala
done = (budgetRemaining <= 0.0) || (timeRemaining <= 0.0)
```

終了時に、特別な終端遷移が保存されます：

```scala
val terminalState = Array.fill(stateSize)(0.0)   // Zero vector
val terminalReward = windowClicks.toDouble        // Final clicks (no penalty)
dqn.store(prevState, prevAction, terminalReward, terminalState, done = true)
```

`done = true`フラグはDQNにエピソード境界を越えて将来のrewardをブートストラップしないよう指示します。

## Rewardの例

| Window | Clicks | spendRate | Penalty | Reward |
|--------|--------|-----------|---------|--------|
| Normal pacing | 3 | 1.0 | 0 | 3.0 |
| Good CTR | 8 | 1.2 | 0 | 8.0 |
| Slight overspend | 5 | 1.8 | 0.6 | 4.4 |
| Severe overspend | 2 | 3.0 | 3.0 | -1.0 |
| At threshold | 4 | 1.5 | 0 | 4.0 |

## 設計のシンプルさ

reward functionに**含まれていない**ものに注目してください：
- 予算消尽ペナルティなし — 予算がゼロになるとエピソードが単に終了する
- CPA信号なし — コンバージョントラッキングはスパースであり、クリックは十分なプロキシ
- 勝率ボーナスなし — 勝率はstate spaceに含まれており、エージェントが自身のトレードオフを学習できる

このシンプルさにより、reward信号はクリーンで解釈しやすくなっています。エージェントはクリックが良いことと過剰消化が悪いことを学習します — それ以外はstate spaceから自ら理解します。
