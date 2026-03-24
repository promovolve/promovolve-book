# Cold Start Strategies

新しい候補はimpressionゼロの状態でシステムに入ります。Promovolveは候補プールの状態に応じて3つの異なる戦略を使用します。

## 戦略1：Full Cold Start

**条件**：スロット内のすべての候補のimpressionが0。

**アルゴリズム**：オークションフェーズの`categoryScore`をノイズ付きの事前分布として使用：

```
sampledCTR = categoryScore + random(-0.1, +0.1)
score = sampledCTR × log(1 + CPM)
```

`categoryScore = classifierConfidence × rankerWeight`はTaxonomyRankerEntityからのシグナルを提供します。±0.1のノイズにより、同一のcategory scoreを持つ候補でもリクエストごとに異なる候補が選択されます。

## 戦略2：Warmupフェーズ

**条件**：すべての候補のimpressionが**10回**未満（`WarmupImpressions = 10`）。

**アルゴリズム**：**Round-robin** — impressionが最も少ない候補を常に選択：

```
select = argmin(candidate.impressions)
```

warmup中はThompson Samplingは実行されません。これにより、活用が始まる前にすべての候補が最低10回のimpressionを確保します。

**なぜ10回なのか？** 10回のimpressionで一般的な2-5%のCTRの場合、期待されるクリック数は0-1回です。Beta distribution `Beta(1, 10)`や`Beta(2, 9)`は異なるCTRを区別するのに十分な形状を持ちつつも、warmup終了後も継続的な探索が可能なほど十分に広い分布です。

## 戦略3：Partial Cold Start

**条件**：一部の候補にはデータがあり（impressionが10以上）、一部は新しい（impressionが0）。

**アルゴリズム**：`ExplorationRate = 0.30`の**Epsilon-greedy**：

```
if random() < 0.30:
    select randomly from cold candidates (impressions == 0)
else:
    run Thompson Sampling on all candidates
```

30%の探索率は意図的に高く設定されています。新しい候補は素早くデータを必要とします。impressionが蓄積されれば、Thompson SamplingのBeta事後分布が自然に探索を処理します。

**注意**：elseブランチでThompson Samplingが実行される場合、cold状態の候補を**含むすべての**候補に対して実行されます。cold状態の候補はsampledCTRとして`categoryScore + random(-0.15, +0.15)`を使用するため、通常のスコアリングメカニズムを通じて勝つ可能性は依然としてあります。

## 戦略選択フロー

```
Are all candidates at 0 impressions?
  └── Yes → Full Cold Start (categoryScore ± 0.1 noise)
  └── No  → Are all candidates under 10 impressions?
              └── Yes → Warmup (round-robin by fewest impressions)
              └── No  → Are some candidates at 0 impressions?
                          └── Yes → Partial Cold Start (30% epsilon-greedy)
                          └── No  → Standard Thompson Sampling
```

## 主要定数

| Constant | Value | Location |
|----------|-------|----------|
| `ExplorationRate` | 0.30 | ThompsonSampling.scala |
| `WarmupImpressions` | 10 | ThompsonSampling.scala |
| Cold noise range | ±0.15 | ThompsonSampling.scala |
| Full cold noise range | ±0.1 | ThompsonSampling.scala |
