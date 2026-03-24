# Thompson Sampling (MAB)

Thompson SamplingはPromovolveの配信時における中核アルゴリズムです。候補リストからどのクリエイティブを表示するかを選択し、不確実な選択肢の探索と既知のパフォーマンスの高い選択肢の活用をバランスさせます。

## アルゴリズム

各配信リクエストに対して（pacing gateとfrequency capフィルタリングの後）：

```
For each candidate c in the slot:
  stats = creativeStats[c.creativeId]  // 1-minute bucketed, 60-min window
  impressions = stats.totalImpressions
  clicks = stats.totalClicks

  if impressions == 0:
    sampledCTR = categoryScore + random(-0.15, +0.15)
  else:
    α = clicks + 1
    β = impressions - clicks + 1
    sampledCTR = sampleBeta(α, β)

  score = sampledCTR × log(1 + CPM)

Select candidate with highest score
```

`log(1 + CPM)`ファクターにより、入札価格が収穫逓減を伴って反映されます。$10 CPMは$1 CPMの10倍の効果にはなりません。

## 時間バケット統計

単純なカウンターとは異なり、Promovolveはimpressionとクリックを**60分間のローリングウィンドウ**の中で**1分間の時間バケット**で追跡します：

```scala
case class CreativeStats(
  buckets: Map[Long, (Int, Int)] = Map.empty,  // minute → (impressions, clicks)
  windowMinutes: Int = 60
)
```

各impressionまたはクリック時：
```scala
val minute = now.getEpochSecond / 60
val (imps, clks) = buckets.getOrElse(minute, (0, 0))
// Update the relevant counter, then prune old buckets:
buckets.filter { case (min, _) => min > cutoffMinute }
```

**なぜ時間バケットなのか？**
- 自動的な新しさ：古いデータは自然に削除され、手動の減衰処理が不要
- 遅延クリックの処理：10:15のimpressionに対する10:22のクリックは新しいバケットエントリを作成し、両方が合計に寄与する
- きれいなウィンドウ：「全期間」ではなく正確に60分間のデータにより、探索の減衰が遅くなりすぎることを防ぐ
- 永続化：統計のスナップショットは1時間ごとにDBに保存され、起動時に`CreativeStatsLoaded`を通じて読み込まれる

## 選択パイプラインにおける位置

Thompson Samplingはpacing gateとfrequency capフィルターの**後に**実行されます：

```
ServeIndex lookup → Content recency → Frequency cap → Pacing gate → Thompson Sampling → Budget reservation
```

この順序は重要です。pacing gateは広告を配信するか**どうか**を決定し（ボリュームのゲーティング）、Thompson Samplingは**どの**クリエイティブを表示するかを決定します（選択）。pacingをTSの前に実行することで、探索バイアスを防ぎます。

## サブチャプター

- [Beta-Bernoulli Model](./beta-bernoulli.md) — Thompson Samplingの背後にある確率モデル
- [Scoring Formula](./scoring-formula.md) — なぜ`sampledCTR × log(1 + CPM)`であり、他の代替案ではないのか
- [Cold Start Strategies](./cold-start.md) — impressionがゼロまたは少ない候補の処理
- [Beta Distribution Sampling](./beta-sampling.md) — 本番で使用されるMarsaglia-Tsang法
