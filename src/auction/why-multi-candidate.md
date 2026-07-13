# Why Multi-Candidate?

The decision to keep multiple candidates per slot — rather than selecting a single auction winner — is the most important architectural choice in Promovolve.

## The Problem with Single-Winner Auctions

In a traditional ad exchange, each auction produces one winner:

1. **Exploitation trap**: The highest bidder always wins, even with terrible CTR
2. **No exploration**: No mechanism to discover if a lower-bidding creative performs better
3. **Fragile serving**: If the winner's budget runs out, the system must re-auction or show nothing
4. **Misaligned incentives**: Exchange optimizes for revenue, not user experience

## How Multi-Candidate Solves This

Promovolve's fair selection algorithm guarantees per-campaign diversity (one creative per campaign first, then fill remainder), and Thompson Sampling explores among them at serve time.

### The Scoring Formula

```
score = sampledCTR × CPM^α
       (full model: (sampledCTR + 2.0 × sampledFoldRate + newcomerBonus) × CPM^α)
```

Where `sampledCTR` is drawn from `Beta(clicks + 1, non_clicks + 1)` using time-bucketed statistics (1-minute granularity, 60-minute rolling window). The exponent **α (`bidWeight`)** is publisher-configurable: α=0.3 (Discovery) lets quality dominate, α=0.5 (Balanced) is the default `sqrt(CPM)`, α=0.7 (Revenue) tilts toward higher bids.

### Exploration in Action

```
Slot candidates after fair selection (α=0.5):
  Campaign A: CPM $5.00, Beta(6, 146)    → sample: 0.032
  Campaign B: CPM $4.20, Beta(3, 19)     → sample: 0.091
  Campaign C: CPM $3.80, Beta(1, 1)      → sample: 0.647

Scores:
  A: 0.032 × √5.00 = 0.032 × 2.236 = 0.0716
  B: 0.091 × √4.20 = 0.091 × 2.049 = 0.1865
  C: 0.647 × √3.80 = 0.647 × 1.949 = 1.261

→ C wins (exploration of unknown creative)
```

### Graceful Degradation

When Campaign A exhausts its budget:
1. Pacing gate checks budget **before** Thompson Sampling
2. Campaign A is filtered out
3. Thompson Sampling runs on B and C only
4. No re-auction needed — no DData operations
5. When A's budget resets next day, it resumes serving (entry was kept in ServeIndex)

### Publisher Alignment

The `sampledCTR` factor naturally favors creatives users actually click on. High-CPM but low-CTR creatives lose to engaging ones over time, aligning publisher interests (engagement, user trust) with advertiser interests (actual clicks).

## The Trade-off

Multi-candidate selection means the highest bidder doesn't always win. This reduces short-term CPM revenue but increases:

- **Long-term revenue**: Better CTR → more clicks → better campaign ROI → higher advertiser retention
- **System resilience**: Fallback candidates reduce re-auction frequency
- **Learning**: Thompson Sampling converges to the best performer without any exploration rate to tune
