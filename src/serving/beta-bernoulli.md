# Beta-Bernoulli Model

Thompson Sampling in Promovolve uses a **Beta-Bernoulli** conjugate model to represent uncertainty about each candidate's click-through rate (CTR).

## The Model

Each ad impression is a **Bernoulli trial**: click (success) or no click (failure). The unknown CTR `p` is represented by a **Beta distribution**.

### Conjugacy

The Beta distribution is the conjugate prior for the Bernoulli likelihood:

```
Prior:      Beta(α, β)
Likelihood: Bernoulli(p)
Posterior:  Beta(α + clicks, β + non_clicks)
```

Updates are trivial — just add counts. No MCMC, no variational inference, no gradient descent. Critical for serve-time performance.

### Prior

Promovolve uses `Beta(1, 1)` — uniform over [0, 1]:

```
Beta(1, 1) = Uniform(0, 1)
  Mean: 0.5
  Variance: 0.083
  → Maximum uncertainty
```

### Posterior from Time-Bucketed Stats

The posterior uses aggregated statistics from the 60-minute rolling window of 1-minute buckets:

```
impressions = sum of all bucket impression counts
clicks = sum of all bucket click counts

Posterior: Beta(clicks + 1, impressions - clicks + 1)
```

### Posterior Evolution

```
After 0 impressions:    Beta(1, 1)       mean=0.500  — wide, pure exploration
After 10 imp, 1 click:  Beta(2, 10)      mean=0.167  — starting to narrow
After 100 imp, 3 clk:   Beta(4, 98)      mean=0.039  — fairly confident
After 1000 imp, 30 clk: Beta(31, 971)    mean=0.031  — very confident
```

As data accumulates, the variance shrinks and samples cluster near the true CTR. This automatically reduces exploration for well-known creatives and maintains exploration for uncertain ones.

## 60-Minute Window Effect

Because stats are windowed to 60 minutes, the posterior **resets** as old data prunes. A creative that performed well an hour ago but has no recent data returns to higher uncertainty, enabling re-exploration. This is appropriate because CTR can vary by time of day, competing content, and audience composition.

## Why Not Just Use Mean CTR?

Using the mean (greedy strategy) would never explore. Once a creative gets lucky with early clicks, it dominates forever. Thompson Sampling uses the **full distribution** — the variance captures uncertainty and drives exploration proportionally.
