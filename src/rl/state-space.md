# State Space

The DQN agent observes an **8-dimensional state vector** computed from the 15-minute observation window.

## State Dimensions (from BidOptimizationAgent.scala)

| Index | Name | Formula | Range | Signal |
|-------|------|---------|-------|--------|
| 0 | effectiveCpm | `clamp(2.0, (maxCpm × bidMultiplier) / maxCpm)` | [0, 2.0] | Current bid level |
| 1 | ctr | `min(1.0, windowClicks / windowImpressions)` | [0, 1.0] | Engagement quality |
| 2 | winRate | `windowWins / windowBidOpportunities` (default 0.5) | [0, 1] | Competitive position |
| 3 | budgetRemaining | `clamp(1.0, budgetRemaining / dailyBudget)` | [0, 1.0] | Budget utilization |
| 4 | timeRemaining | `clamp(1.0, 1.0 - elapsed / rlDayDurationSeconds)` | [0, 1.0] | Time pressure |
| 5 | spendRate | `min(3.0, actualSpend / expectedSpend)` | [0, 3.0] | Pacing accuracy |
| 6 | impressionRate | `min(2.0, windowImpressions / 100.0)` | [0, 2.0] | Delivery volume |
| 7 | costPerClick | `min(2.0, (windowSpend / windowClicks) / maxCpm)` | [0, 2.0] | Efficiency |

## Dimension Details

### effectiveCpm (index 0)
The normalized bid level: `bidMultiplier` itself, since `maxCpm × bidMultiplier / maxCpm = bidMultiplier`. Clamped to [0, 2.0]. Tells the agent what it decided last time.

### ctr (index 1)
Click-through rate in the current 15-minute observation window. Zero if no impressions. Provides immediate feedback on creative quality in the current traffic mix.

### winRate (index 2)
Fraction of bid opportunities that resulted in the creative being shortlisted. If no bid opportunities occurred, defaults to 0.5 (neutral). Low win rate → bid too low relative to competition.

### budgetRemaining (index 3)
Remaining budget as a fraction of daily budget. Combined with `timeRemaining`, this tells the agent whether it's on pace:
- High budget + low time → can bid aggressively
- Low budget + high time → must conserve

### timeRemaining (index 4)
Fraction of the delivery day remaining. Computed as `1.0 - elapsedSeconds / rlDayDurationSeconds` where `rlDayDurationSeconds` defaults to 86400 (real 24h day) but can be configured shorter for simulation via `RL_DAY_DURATION_SECONDS`.

### spendRate (index 5)
Ratio of actual to expected spend, capped at 3.0x. Expected spend assumes even linear distribution: `dailyBudget × (elapsed / totalTime)`. A spend rate of 1.0 = perfect pacing. Above 1.0 = over-spending.

### impressionRate (index 6)
Impressions per 15-minute window, normalized by a baseline of 100 impressions. Capped at 2.0x. Independent of spend — captures delivery volume.

### costPerClick (index 7)
Spend per click normalized by maxCpm. Only meaningful when clicks > 0 (returns 0.0 otherwise). High CPC relative to maxCpm suggests the bid is too high for the achieved CTR.

## Why These 8 Dimensions?

The state captures **minimal sufficient statistics** for bidding:

| Pair | Signal |
|------|--------|
| Budget + Time | Should I be aggressive or conservative? |
| Win Rate + CPM | Am I competitive? |
| CTR + CPC | Am I getting good value? |
| Spend Rate + Impression Rate | Am I on pace? |

## Normalization

All dimensions are bounded (mostly [0, 1] or [0, 2-3]) via `min()` or `clamp()`. This is critical for the neural network — unbounded features cause gradient issues. The capping prevents outliers from destabilizing Q-value estimates.
