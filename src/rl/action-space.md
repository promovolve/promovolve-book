# Action Space

The DQN agent selects from **5 discrete actions** (configurable), each representing a multiplicative adjustment to the current bid multiplier.

## Default Actions (from BidOptimizationAgent.scala)

| Action Index | Adjustment Factor | Effect |
|-------------|-------------------|--------|
| 0 | 0.8x | Bid 20% less — conserve budget |
| 1 | 0.9x | Bid 10% less — slight reduction |
| 2 | 1.0x | Hold — no change |
| 3 | 1.1x | Bid 10% more — slight increase |
| 4 | 1.2x | Bid 20% more — aggressive bidding |

## Cumulative Application

Actions are applied **cumulatively** to the existing multiplier:

```scala
newMultiplier = clamp(
  minMultiplier,
  maxMultiplier,
  _bidMultiplier × actionMultipliers(action)
)
```

### Example Sequence

```
Step 0: multiplier = 1.0 (start of day)
Step 1: action=4 (1.2x) → 1.0 × 1.2 = 1.20
Step 2: action=3 (1.1x) → 1.2 × 1.1 = 1.32
Step 3: action=0 (0.8x) → 1.32 × 0.8 = 1.056
Step 4: action=4 (1.2x) → 1.056 × 1.2 = 1.267
```

## Multiplier Bounds

The multiplier is clamped to `[minMultiplier, maxMultiplier]` (configurable per agent):

- **Minimum**: Prevents the bid from becoming uncompetitive
- **Maximum**: Prevents overpaying

The effective bid is always floored at `floorCpm`:

```scala
bidCpm = max(maxCpm × bidMultiplier, floorCpm)
```

## Why Discrete Actions?

### Alternative: Continuous Actions
Continuous actions (e.g., output multiplier directly) would require DDPG or SAC:
- More complex, separate actor and critic networks
- Harder to explore in bounded spaces
- Not worth the complexity for this problem size

### Advantages of Discrete
- **DQN** is well-understood and stable
- 5 actions provide sufficient granularity (10-20% adjustments per step)
- Each action has a clear semantic interpretation
- Cumulative application allows reaching any multiplier within bounds over multiple steps

## Symmetric Design

Unlike some bid optimization systems that use asymmetric action ranges, Promovolve's 5 actions are symmetric around the hold action (1.0x):
- Two decrease levels: 0.8x, 0.9x
- Two increase levels: 1.1x, 1.2x
- One hold: 1.0x

This symmetry means the agent has equal capacity to increase or decrease bids, with no built-in bias toward either direction.
