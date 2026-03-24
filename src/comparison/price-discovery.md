# Price Discovery & First-Price Model

Traditional exchanges use **second-price auctions** for price discovery. Promovolve uses **first-price with RL-adjusted bids**.

## Traditional: Second-Price Auctions

```
Bids: $8.00, $5.50, $3.20
Winner pays: $5.51 (second-highest + $0.01)
```

**Truthful bidding**: Bidders bid true value because overbidding doesn't increase cost.
**Price discovery**: Market-clearing price ($5.51) reveals impression value.

In practice, DSPs use bid-shading to game second-price mechanics, and many exchanges have shifted to first-price anyway.

## Promovolve: First-Price, RL-Adjusted

Advertisers set `maxCpm`. The DQN agent adjusts with a bid multiplier:

```scala
bidCpm = max(maxCpm × bidMultiplier, floorCpm)
```

The advertiser pays exactly this CPM — no second-price discount.

### Why First-Price Is Acceptable

1. **Single-publisher platform**: No competitive exchange dynamics requiring truthful revelation
2. **RL handles optimization**: The DQN agent learns the right bid level over days (5 actions: 0.8x to 1.2x, applied cumulatively)
3. **Simpler**: No second-bid tracking, reserve prices, or bid-shading countermeasures
4. **Thompson Sampling redefines "winning"**: High CPM alone doesn't win — creative must also have good CTR

### RL as Price Optimization

The DQN agent's reward function (clicks - overspend penalty) naturally discovers efficient bid levels:
- If overpaying (high CPC, spendRate > 1.5): reward drops → agent reduces multiplier
- If underbidding (low win rate, low impressions): agent increases multiplier
- Converges to the bid level that maximizes clicks within budget

## No Market-Clearing Price

Promovolve does **not** discover market-clearing prices:
- Advertisers set `maxCpm` based on business judgment
- RL optimizes pacing, not price discovery
- No mechanism to tell advertisers they're over/under-paying vs competition

This is acceptable for **internal advertising** where pricing is a business decision, not a market problem.

## Comparison

| Aspect | Second-Price (RTB) | First-Price (Promovolve) |
|--------|-------------------|-------------------------|
| Price paid | Second bid + $0.01 | Exactly the bid |
| Optimization | DSP bid-shading | DQN RL agent |
| Discovery | Market-clearing price | None |
| Complexity | High | Low |
| Floor price | `floorCpm` (default $0.50) | Same |
