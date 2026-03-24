# Beta-Bernoulli Model

PromovolveのThompson Samplingは、各候補のclick-through rate（CTR）に対する不確実性を表現するために**Beta-Bernoulli**共役モデルを使用しています。

## モデル

各広告impressionは**Bernoulli試行**です。クリック（成功）またはクリックなし（失敗）のいずれかです。未知のCTR `p`は**Beta distribution**で表現されます。

### 共役性

Beta distributionはBernoulli尤度の共役事前分布です：

```
Prior:      Beta(α, β)
Likelihood: Bernoulli(p)
Posterior:  Beta(α + clicks, β + non_clicks)
```

更新は単にカウントを加えるだけです。MCMCも変分推論も勾配降下法も不要です。配信時のパフォーマンスにとって重要な特性です。

### 事前分布

Promovolveは`Beta(1, 1)`を使用します。これは[0, 1]上の一様分布です：

```
Beta(1, 1) = Uniform(0, 1)
  Mean: 0.5
  Variance: 0.083
  → Maximum uncertainty
```

### 時間バケット統計からの事後分布

事後分布は、1分間バケットの60分間ローリングウィンドウから集約された統計を使用します：

```
impressions = sum of all bucket impression counts
clicks = sum of all bucket click counts

Posterior: Beta(clicks + 1, impressions - clicks + 1)
```

### 事後分布の推移

```
After 0 impressions:    Beta(1, 1)       mean=0.500  — wide, pure exploration
After 10 imp, 1 click:  Beta(2, 10)      mean=0.167  — starting to narrow
After 100 imp, 3 clk:   Beta(4, 98)      mean=0.039  — fairly confident
After 1000 imp, 30 clk: Beta(31, 971)    mean=0.031  — very confident
```

データが蓄積されるにつれて分散は縮小し、サンプルは真のCTRの近くに集中します。これにより、よく知られたクリエイティブの探索は自動的に減少し、不確実なクリエイティブの探索は維持されます。

## 60分ウィンドウの効果

統計が60分にウィンドウ化されているため、古いデータが削除されると事後分布は**リセット**されます。1時間前には良いパフォーマンスだったが最近のデータがないクリエイティブは、不確実性が高い状態に戻り、再探索が可能になります。CTRは時間帯、競合コンテンツ、オーディエンスの構成によって変動しうるため、これは適切な振る舞いです。

## なぜ平均CTRだけを使わないのか？

平均を使う（貪欲戦略）場合、探索は一切行われません。あるクリエイティブが初期のクリックで幸運に恵まれると、永久に支配してしまいます。Thompson Samplingは**分布全体**を使用します。分散が不確実性を捉え、それに比例して探索を駆動します。
