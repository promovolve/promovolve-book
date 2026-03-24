# Scoring Formula

ソースコードにおけるThompson Samplingのスコア：

```scala
score = sampledCTR * math.log(1.0 + cpm)
```

## なぜCTRとCPMを掛け合わせるのか？

スコアは以下を組み合わせた期待値を表します：
1. **sampledCTR**：エンゲージメントの可能性（パブリッシャーにとっての価値）
2. **CPM**：広告主の支払い意欲（収益の価値）

両方の次元が妥当でなければなりません。$100 CPMでCTR 0.001%のクリエイティブは低スコアになります。CTR 10%でCPM $0.10のクリエイティブも低スコアになります。

## なぜlog(1 + CPM)なのか？

### 収穫逓減
```
$10 / $1 = 10x advantage (linear)
log(11) / log(2) = 2.40 / 0.69 = 3.5x advantage (log)
```

対数はCPMの差を圧縮し、高額入札者がパフォーマンスの良いクリエイティブを圧倒することを防ぎます。

### +1のオフセット
`log(CPM)`はCPM=0で未定義、CPM < 1で負になります。`+1`により以下が保証されます：
- CPM = 0 → log(1) = 0（無料広告はスコアゼロ）
- CPM = 1 → log(2) = 0.69
- CPM = 10 → log(11) = 2.40

## 数値例

| Candidate | CPM | True CTR | Sample | log(1+CPM) | Score |
|-----------|-----|----------|--------|------------|-------|
| A | $8.00 | 2.0% | 0.025 | 2.20 | 0.055 |
| B | $3.50 | 4.5% | 0.038 | 1.50 | 0.057 |
| C | $1.20 | 7.0% | 0.082 | 0.79 | 0.065 |

キャンペーンCはAの6.7分の1しか支払っていないにもかかわらず勝利します。CTRの優位性が対数圧縮されたCPMの差を上回っているためです。これはパブリッシャーにとって望ましい結果です。

## Cold Startでの変形

候補のimpressionが0の場合、スコアはBeta samplingの代わりに`categoryScore`を使用します：

```scala
sampledCTR = categoryScore + random(-0.15, +0.15)
score = sampledCTR * math.log(1.0 + cpm)
```

±0.15のノイズ範囲により、cold状態の候補でも探索のための分散が確保されます。詳細は[Cold Start Strategies](./cold-start.md)を参照してください。
