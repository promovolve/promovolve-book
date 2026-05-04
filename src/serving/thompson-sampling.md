# Thompson Sampling (MAB)

Thompson Sampling is the core serve-time algorithm in Promovolve. It selects which creative to show from the shortlisted candidates, balancing exploration of uncertain options with exploitation of known performers.

## The Algorithm

For each serve request (after pacing gate and frequency cap filtering):

```
For each candidate c in the slot:
  stats = creativeStats[c.creativeId]  // 1-minute bucketed, 60-min window
  imps = stats.totalImpressions
  clicks = stats.totalClicks
  folds = stats.totalFolds

  if imps == 0:
    sampledCTR  = categoryScore + random(-0.15, +0.15)
    sampledFold = sampleBeta(1, 1)              // uniform [0,1] cold prior
  else:
    sampledCTR  = sampleBeta(clicks + 1, imps - clicks + 1)
    sampledFold = sampleBeta(folds  + 1, imps - folds  + 1)

  engagement  = sampledCTR + FoldWeight × sampledFold + newcomerBonus(imps)
  score       = engagement × CPM^α

Select candidate with highest score
```

Two probabilistic signals drive the choice. **CTR** (clicks per impression) is the canonical click-likelihood proxy. **Fold rate** (dog-ear bookmarks per impression) is a stronger intent signal — folding takes deliberate effort, where a click could be impulsive — so it carries weight `FoldWeight = 2.0` against CTR's 1.0 in the engagement combiner. See [Beta-Bernoulli Model](./beta-bernoulli.md) for why fold-rate fits the same Beta-conjugate framework.

The **newcomer bonus** (a UCB-flavored additive term) tilts the auction toward creatives that haven't yet had a chance to prove themselves. It decays linearly to zero as the creative accumulates its first 50 impressions, after which the candidate competes purely on its own posteriors. See [Cold Start Strategies](./cold-start.md) for the full curve.

The `CPM^α` factor ensures bid price matters with diminishing returns. The exponent α (`bidWeight`) is publisher-configurable: at the default α=0.5, a $10 CPM is only ~3.2× better than a $1 CPM (not 10×). See [Scoring Formula](./scoring-formula.md) for the full publisher dial.

## Time-Bucketed Statistics

Unlike simple counters, Promovolve tracks impressions and clicks in **1-minute time buckets** over a **60-minute rolling window**:

```scala
case class CreativeStats(
  // minute → (impressions, clicks, folds)
  buckets: Map[Long, (Int, Int, Int)] = Map.empty,
  windowMinutes: Int = 60
)
```

On each impression, click, or fold:
```scala
val minute = now.getEpochSecond / 60
val (imps, clks, folds) = buckets.getOrElse(minute, (0, 0, 0))
// Update the relevant counter, then prune old buckets:
buckets.filter { case (min, _) => min > cutoffMinute }
```

Folds share the same bucket as impressions and clicks at the same minute — three counters travel together so the fold posterior tracks the click posterior in lockstep, without needing a separate persistence path.

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
