# Beta Distribution Sampling

Thompson Sampling requires drawing random samples from Beta distributions on every serve request. The implementation uses the **Marsaglia-Tsang** method for Gamma variates, then converts to Beta.

## Beta from Gamma

```
Beta(α, β) = X / (X + Y)
where X ~ Gamma(α, 1) and Y ~ Gamma(β, 1)
```

## Gamma Sampling: Marsaglia-Tsang

### Case 1: shape ≥ 1 (Rejection Sampling)

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

Acceptance rate is ~98% for shape ≥ 1, making this efficient for production use.

### Case 2: shape < 1 (Recursion + Power Trick)

```
Gamma(shape, 1) = Gamma(shape + 1, 1) × U^(1/shape)
where U ~ Uniform(0, 1)
```

Reduces to Case 1 since `shape + 1 ≥ 1`.

## Why Marsaglia-Tsang?

| Alternative | Problem |
|-------------|---------|
| Inverse CDF | Beta quantile function requires regularized incomplete beta — expensive |
| Pre-computed tables | Unbounded (α, β) pairs as stats change per impression |
| Normal approximation | Breaks for small α + β — exactly the exploration-critical case |

## Numerical Stability

The implementation handles edge cases:
- Degenerate draw (`x + y == 0`): returns 0.5 rather than dividing by zero
- Very large shape: Marsaglia-Tsang is naturally stable (with a squeeze
  fast-accept — `u < 1 − 0.0331·x⁴` — before the exact log test)
- Cold-start scores are floored at 0.001 downstream, so a zero sample
  never produces a zero score

## Performance

| Operation | Cost |
|-----------|------|
| One Beta sample | ~3 uniform random draws + arithmetic |
| Per-candidate scoring | 1 Beta sample + 1 log + 1 multiply |
| Full selection (K=3) | 3 Beta samples + argmax |

Total overhead: negligible compared to the DData lookup. The sampling is synchronous and runs on the Pekko dispatcher thread handling the serve request.
