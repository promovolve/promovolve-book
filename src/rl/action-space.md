# Action Space

The floor CPM agent selects from **7 discrete actions**, each representing a multiplicative adjustment to the current floor price.

| Action | Multiplier | Effect |
|--------|-----------|--------|
| 0 | × 0.90 | Decrease floor 10% |
| 1 | × 0.95 | Decrease floor 5% |
| 2 | × 0.98 | Decrease floor 2% |
| 3 | × 1.00 | Hold current floor |
| 4 | × 1.02 | Increase floor 2% |
| 5 | × 1.05 | Increase floor 5% |
| 6 | × 1.10 | Increase floor 10% |

## Why Gentle Steps?

The maximum change per observation is ±10%. Earlier versions used ±20%, which caused catastrophic overshoot — the agent would push the floor above all bids in a few steps, get zero revenue, then overcorrect to the minimum. Gentle steps give the agent time to observe the market response before making the next adjustment.

## Clamping

After applying the multiplier, the new floor is clamped to:

```
newFloor = max(publisherMinFloor, min(maxObservedCPM × 0.80, currentFloor × multiplier))
```

- **Lower bound:** The publisher's minimum floor (set in the dashboard). The agent cannot go below what the publisher considers acceptable.
- **Upper bound:** 80% of the highest observed bid. This prevents the agent from pricing out all advertisers. With the cap at 80%, at least one bidder always remains competitive.

## Why 7 Actions Instead of Continuous?

DQN works with discrete actions. Seven actions provide enough granularity for floor adjustment — the difference between a 2% and 5% change is meaningful in terms of market response, but finer granularity would not improve learning speed.

The "hold" action (×1.00) is important. It allows the agent to explicitly choose "the current floor is fine" rather than being forced to change every observation.
