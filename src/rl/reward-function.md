# Reward Function

The reward function defines what the floor CPM agent optimizes for. From `FloorCpmOptimizationAgent.scala`:

```
reward = normalizedRevenue × fillRate
       − emptyPenalty
       − budgetExhaustionPenalty
       − volatilityPenalty
       − boundaryPenalty
```

## Revenue × Fill Rate

The primary signal. Revenue is normalized by a baseline (one impression at floor price) so the signal is independent of absolute floor level.

Multiplying by fill rate provides a gradient signal even when revenue is zero. Without it, the agent only sees "zero revenue" when the floor is too high, with no indication of *how bad* it is. Fill rate provides that gradient:
- Floor slightly too high → fillRate=0.6 → partial reward
- Floor way too high → fillRate=0.0 → zero reward

## Empty Auction Penalty

```
emptyPenalty = weight × max(0, 0.5 − fillRate)
```

Activates when fill rate drops below 50%. The penalty increases linearly as fill rate drops — a stronger signal than the multiplicative revenue×fillRate term when fill rate is very low.

## Budget Exhaustion Penalty (weight = 2.0)

```
budgetExhaustionPenalty = 2.0 × budgetExhaustionRate
```

Where `budgetExhaustionRate = budgetDeniedServes / totalServeAttempts`.

This is the most important penalty. A high floor causes solo winners to pay floor price on every impression. Higher floor → higher per-impression cost → faster budget drain → budget exhaustion → zero revenue. The penalty catches this cascade early:

1. Floor rises to $4 (only one $5 bidder remains)
2. Solo winner pays $4 per thousand impressions (was paying $2 with competition)
3. Budget drains 2x faster
4. After a few hours, budget exhausted — all serves denied
5. Agent sees budgetExhaustionRate spike → penalty fires → agent lowers floor

Without this penalty, the agent would only learn "high floor = bad" after the budget exhausts and revenue drops to zero — a delayed signal that leads to slow learning.

## Volatility Penalty

```
volatilityPenalty = 0.3 × |currentFloor − prevFloor| / prevFloor
```

Discourages wild swings. Advertisers need price stability — if the floor jumps 20% every 15 minutes, they can't plan budgets. The penalty is proportional to the relative change, so a $0.10 change at a $5 floor (2%) is penalized less than a $0.10 change at a $0.50 floor (20%).

## Boundary Penalty

```
boundaryPenalty = 0.1 if floor is within 5% of min or max limit (and ε < 0.3)
```

A soft nudge away from the boundaries. Only active during exploitation (ε < 0.3) — during exploration, boundary hits are expected and shouldn't be penalized.

## Design Principle

The reward function is intentionally simple. Complex reward functions with many terms are hard to debug and can create unexpected local optima. Each term has a clear purpose:

- Revenue × fillRate: "maximize publisher income"
- Empty penalty: "don't let auctions go unfilled"
- Budget penalty: "don't drain advertiser budgets"
- Volatility penalty: "be stable"
- Boundary penalty: "don't get stuck at limits"
