# Cold Start Strategies

New candidates enter the system with zero impressions. Promovolve uses three structural strategies depending on the state of the candidate pool — plus a continuous **newcomer bonus** that boosts under-sampled creatives across all phases.

## Strategy 1: Full Cold Start

**Condition**: All candidates in the slot have 0 impressions.

**Algorithm**: Use `categoryScore` from the auction phase as a prior, with noise:

```
sampledCTR = categoryScore + random(-0.1, +0.1)
score = sampledCTR × CPM^α
```

The `categoryScore = classifierConfidence × rankerWeight` provides a signal from the TaxonomyRankerEntity. The ±0.1 noise ensures different candidates are selected across requests even when they have identical category scores.

## Strategy 2: Warmup Phase

**Condition**: All candidates have fewer than **10 impressions** (`WarmupImpressions = 10`).

**Algorithm**: **Round-robin** — always select the candidate with the fewest impressions:

```
select = argmin(candidate.impressions)
```

No Thompson Sampling runs during warmup. This guarantees every candidate gets at least 10 impressions before exploitation begins.

**Why 10?** At 10 impressions with a typical 2-5% CTR, the expected number of clicks is 0-1. The Beta distribution `Beta(1, 10)` or `Beta(2, 9)` has sufficient shape to distinguish different CTRs but is still wide enough for continued exploration after warmup ends.

## Strategy 3: Partial Cold Start

**Condition**: Some candidates have data (≥ 10 impressions) and some are new (0 impressions).

**Algorithm**: **Epsilon-greedy** with `ExplorationRate = 0.30`:

```
if random() < 0.30:
    select randomly from cold candidates (impressions == 0)
else:
    run Thompson Sampling on all candidates
```

The 30% rate is aggressive by design — new candidates need data quickly. Once they accumulate impressions, Thompson Sampling's Beta posterior handles exploration naturally.

**Note**: When Thompson Sampling runs in the else branch, it runs on **all** candidates including cold ones. Cold candidates use `categoryScore + random(-0.15, +0.15)` as their sampled CTR, **plus a fold rate sampled from `Beta(1, 1)`** (uniform [0, 1]) so cold creatives have a real fold component instead of a hardcoded zero. Without the fold prior, a cold creative's `engagement = sampledCTR + 0` could never beat a warm fold-rich one's `sampledCTR + 2.0 × foldRate` — the dominant exploration mechanism would silently fail. They still benefit from the [Newcomer Bonus](#newcomer-bonus-decaying-additive-boost) on top.

## Newcomer Bonus: Decaying Additive Boost

The three strategies above are *structural* — they redirect selection on specific conditions. Cutting across all of them is a **continuous additive bonus** applied during the score combiner that tilts the auction toward creatives with few impressions:

```
engagement = sampledCTR + FoldWeight × sampledFold + newcomerBonus(impressions)

newcomerBonus(n) = max(0, NewcomerBoost × (1 - n / NewcomerDecayImpressions))
```

With `NewcomerBoost = 0.5` and `NewcomerDecayImpressions = 50`, the curve is:

| Impressions | Bonus | Effect |
|---:|---:|---|
| 0  | +0.50 | Brand new — full boost |
| 10 | +0.40 | Past forced warmup, still strongly favored |
| 25 | +0.25 | Half-faded |
| 50 | 0.00  | Bonus exhausted — competing on its own posteriors |
| 100+ | 0.00 | No boost; warm creative |

This is a UCB (Upper Confidence Bound) flavored adjustment grafted onto Thompson Sampling. Pure TS already over-prefers high-variance candidates, but in practice the variance gain from a small impression count isn't always enough to outpace a confident warm creative with established stats. The decaying bonus closes that gap explicitly: brand new creatives get a guaranteed exploration runway, and the boost fades smoothly so the system isn't permanently subsidizing newcomers that turned out to be poor performers.

The bonus continues past `WarmupImpressions = 10` (where the forced round-robin ends) so the creative gets help during the early exploitation period when its posterior is wide but no longer being protected by the warmup phase.

## Strategy Selection Flow

```
Are all candidates at 0 impressions?
  └── Yes → Full Cold Start (categoryScore ± 0.1 noise)
  └── No  → Are all candidates under 10 impressions?
              └── Yes → Warmup (round-robin by fewest impressions)
              └── No  → Are some candidates at 0 impressions?
                          └── Yes → Partial Cold Start (30% epsilon-greedy)
                          └── No  → Standard Thompson Sampling
```

## Key Constants

| Constant | Value | Location |
|----------|-------|----------|
| `ExplorationRate` | 0.30 | ThompsonSampling.scala |
| `WarmupImpressions` | 10 | ThompsonSampling.scala |
| `NewcomerBoost` | 0.5 | ThompsonSampling.scala |
| `NewcomerDecayImpressions` | 50 | ThompsonSampling.scala |
| `FoldWeight` | 2.0 | ThompsonSampling.scala |
| Cold CTR noise range | ±0.15 | ThompsonSampling.scala |
| Cold fold prior | `Beta(1, 1)` | ThompsonSampling.scala |
| Full cold CTR noise range | ±0.1 | ThompsonSampling.scala |
