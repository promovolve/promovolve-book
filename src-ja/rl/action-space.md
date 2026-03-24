# Action Space

DQNエージェントは**5つの離散action**（設定可能）から選択し、それぞれが現在のbid multiplierへの乗算的な調整を表します。

## デフォルトのAction（BidOptimizationAgent.scalaより）

| Action Index | Adjustment Factor | Effect |
|-------------|-------------------|--------|
| 0 | 0.8x | 入札を20%削減 — 予算を節約 |
| 1 | 0.9x | 入札を10%削減 — 微減 |
| 2 | 1.0x | 維持 — 変更なし |
| 3 | 1.1x | 入札を10%増加 — 微増 |
| 4 | 1.2x | 入札を20%増加 — 積極的な入札 |

## 累積的な適用

Actionは既存のmultiplierに**累積的に**適用されます：

```scala
newMultiplier = clamp(
  minMultiplier,
  maxMultiplier,
  _bidMultiplier × actionMultipliers(action)
)
```

### シーケンスの例

```
Step 0: multiplier = 1.0 (start of day)
Step 1: action=4 (1.2x) → 1.0 × 1.2 = 1.20
Step 2: action=3 (1.1x) → 1.2 × 1.1 = 1.32
Step 3: action=0 (0.8x) → 1.32 × 0.8 = 1.056
Step 4: action=4 (1.2x) → 1.056 × 1.2 = 1.267
```

## Multiplierの境界

multiplierは`[minMultiplier, maxMultiplier]`にクランプされます（エージェントごとに設定可能）：

- **最小値**：入札が競争力を失うことを防止
- **最大値**：過払いを防止

有効な入札は常に`floorCpm`でフロアリングされます：

```scala
bidCpm = max(maxCpm × bidMultiplier, floorCpm)
```

## なぜ離散Actionなのか？

### 代替案：連続Action
連続action（例：multiplierを直接出力）にはDDPGやSACが必要です：
- より複雑で、個別のactorネットワークとcriticネットワークが必要
- 有界空間でのexplorationが困難
- この問題のサイズでは複雑さに見合わない

### 離散の利点
- **DQN**はよく理解された安定した手法
- 5つのactionで十分な粒度を提供（ステップあたり10-20%の調整）
- 各actionに明確な意味的解釈がある
- 累積的な適用により、複数ステップを通じて境界内の任意のmultiplierに到達可能

## 対称的な設計

非対称なaction範囲を使用する入札最適化システムとは異なり、Promovolveの5つのactionはhold action（1.0x）を中心に対称です：
- 2つの減少レベル：0.8x、0.9x
- 2つの増加レベル：1.1x、1.2x
- 1つの維持：1.0x

この対称性により、エージェントは入札の増減に対して均等な能力を持ち、どちらの方向にも組み込みバイアスがありません。
