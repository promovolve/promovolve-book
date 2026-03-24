# Scoring Formula

The Thompson Sampling score from the source code:

```scala
score = sampledCTR * math.log(1.0 + cpm)
```

## Why Multiply CTR and CPM?

The score represents expected value combining:
1. **sampledCTR**: Likelihood of engagement (publisher value)
2. **CPM**: Advertiser willingness to pay (revenue value)

Both dimensions must be reasonable. A $100 CPM with 0.001% CTR scores poorly. A 10% CTR with $0.10 CPM also scores poorly.

## Why log(1 + CPM)?

### Diminishing Returns
```
$10 / $1 = 10x advantage (linear)
log(11) / log(2) = 2.40 / 0.69 = 3.5x advantage (log)
```

The log compresses CPM differences, preventing high bidders from overwhelming better-performing creatives.

### The +1 Offset
`log(CPM)` would be undefined at CPM=0 and negative for CPM < 1. The `+1` ensures:
- CPM = 0 → log(1) = 0 (free ads score zero)
- CPM = 1 → log(2) = 0.69
- CPM = 10 → log(11) = 2.40

## Numerical Examples

| Candidate | CPM | True CTR | Sample | log(1+CPM) | Score |
|-----------|-----|----------|--------|------------|-------|
| A | $8.00 | 2.0% | 0.025 | 2.20 | 0.055 |
| B | $3.50 | 4.5% | 0.038 | 1.50 | 0.057 |
| C | $1.20 | 7.0% | 0.082 | 0.79 | 0.065 |

Despite Campaign C paying 6.7x less than A, it wins because its CTR advantage outweighs the log-compressed CPM difference. This is the publisher-aligned outcome.

## Cold Start Variant

When `impressions == 0` for a candidate, the score uses `categoryScore` instead of Beta sampling:

```scala
sampledCTR = categoryScore + random(-0.15, +0.15)
score = sampledCTR * math.log(1.0 + cpm)
```

The ±0.15 noise range ensures cold candidates still have variance for exploration. See [Cold Start Strategies](./cold-start.md) for details.
