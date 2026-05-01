# Thompson Sampling (MAB)

Thompson Sampling is the core serve-time algorithm in Promovolve. It selects which creative to show from the shortlisted candidates, balancing exploration of uncertain options with exploitation of known performers.

## The Algorithm

For each serve request (after pacing gate and frequency cap filtering):

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

  score = sampledCTR × CPM^α

Select candidate with highest score
```

The `CPM^α` factor ensures bid price matters with diminishing returns. The exponent α (`bidWeight`) is publisher-configurable: at the default α=0.5, a $10 CPM is only ~3.2× better than a $1 CPM (not 10×). See [Scoring Formula](./scoring-formula.md) for the full publisher dial.

## Time-Bucketed Statistics

Unlike simple counters, Promovolve tracks impressions and clicks in **1-minute time buckets** over a **60-minute rolling window**:

```scala
case class CreativeStats(
  buckets: Map[Long, (Int, Int)] = Map.empty,  // minute → (impressions, clicks)
  windowMinutes: Int = 60
)
```

On each impression or click:
```scala
val minute = now.getEpochSecond / 60
val (imps, clks) = buckets.getOrElse(minute, (0, 0))
// Update the relevant counter, then prune old buckets:
buckets.filter { case (min, _) => min > cutoffMinute }
```

**Why time-bucketed?**
- Automatic recency: old data prunes naturally, no manual decay needed
- Late click handling: a click at 10:22 for an impression at 10:15 creates a new bucket entry — both contribute to totals
- Clean window: exactly 60 minutes of data, not "all time" which would make exploration decay too slowly
- Persistence: stats snapshot to DB hourly, loaded on startup via `CreativeStatsLoaded`

## Selection Pipeline Position

Thompson Sampling runs **after** the pacing gate and frequency cap filter:

```
ServeIndex lookup → Content recency → Frequency cap → Pacing gate → Thompson Sampling → Budget reservation
```

This ordering is critical — the pacing gate decides whether to serve **at all** (volume gating), while Thompson Sampling decides **which creative** to show (choice). Running pacing before TS prevents exploration bias.

## Sub-chapters

- [Beta-Bernoulli Model](./beta-bernoulli.md) — the probabilistic model behind Thompson Sampling
- [Scoring Formula](./scoring-formula.md) — why `sampledCTR × CPM^α` and the publisher's α dial
- [Cold Start Strategies](./cold-start.md) — handling candidates with zero or few impressions
- [Beta Distribution Sampling](./beta-sampling.md) — the Marsaglia-Tsang method used in production
