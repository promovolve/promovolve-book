# Beta Distribution Sampling

Thompson Samplingは配信リクエストごとにBeta distributionからランダムサンプルを抽出する必要があります。実装ではGamma変量に対する**Marsaglia-Tsang**法を使用し、それをBetaに変換しています。

## GammaからBetaへの変換

```
Beta(α, β) = X / (X + Y)
where X ~ Gamma(α, 1) and Y ~ Gamma(β, 1)
```

## Gamma Sampling：Marsaglia-Tsang法

### ケース1：shape ≥ 1（棄却サンプリング）

```
d = shape - 1/3
c = 1 / sqrt(9 × d)

repeat:
    x ~ Normal(0, 1)
    v = (1 + c × x)³
    u ~ Uniform(0, 1)
until v > 0 AND log(u) < 0.5 × x² + d - d × v + d × log(v)

return d × v
```

shape ≥ 1の場合、受理率は約98%であり、本番環境での使用に十分な効率性を持ちます。

### ケース2：shape < 1（再帰 + べき乗トリック）

```
Gamma(shape, 1) = Gamma(shape + 1, 1) × U^(1/shape)
where U ~ Uniform(0, 1)
```

`shape + 1 ≥ 1`となるため、ケース1に帰着されます。

## なぜMarsaglia-Tsang法なのか？

| Alternative | Problem |
|-------------|---------|
| Inverse CDF | Beta quantile function requires regularized incomplete beta — expensive |
| Pre-computed tables | Unbounded (α, β) pairs as stats change per impression |
| Normal approximation | Breaks for small α + β — exactly the exploration-critical case |

## 数値安定性

実装ではエッジケースを処理しています：
- αまたはβが非常に小さい場合（< 0.01）：べき乗トリックでのゼロ除算を避けるためにクランプされる
- shapeが非常に大きい場合：Marsaglia-Tsang法は本質的に安定
- サンプルが0または1の場合：後段のスコアリングでlog(0)を回避するため[ε, 1-ε]にクランプされる

## パフォーマンス

| Operation | Cost |
|-----------|------|
| One Beta sample | ~3 uniform random draws + arithmetic |
| Per-candidate scoring | 1 Beta sample + 1 log + 1 multiply |
| Full selection (K=3) | 3 Beta samples + argmax |

トータルのオーバーヘッド：DDataルックアップと比較して無視できるレベルです。サンプリングは同期的で、配信リクエストを処理するPekkoディスパッチャースレッド上で実行されます。
