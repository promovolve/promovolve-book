# Cold Start Strategies

New candidates enter the system with zero impressions. Promovolve uses three distinct strategies depending on the state of the candidate pool.

## Strategy 1: Full Cold Start

**Condition**: All candidates in the slot have 0 impressions.

**Algorithm**: Use `categoryScore` from the auction phase as a prior, with noise:

```
sampledCTR = categoryScore + random(-0.1, +0.1)
score = sampledCTR × log(1 + CPM)
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

**Note**: When Thompson Sampling runs in the else branch, it runs on **all** candidates including cold ones. Cold candidates use `categoryScore + random(-0.15, +0.15)` as their sampled CTR, so they still have a chance to win through the normal scoring mechanism.

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
| Cold noise range | ±0.15 | ThompsonSampling.scala |
| Full cold noise range | ±0.1 | ThompsonSampling.scala |
