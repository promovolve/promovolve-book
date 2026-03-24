# Reward Function

The reward function defines what the DQN agent optimizes for. From `BidOptimizationAgent.scala`:

## Formula

```scala
reward = clickReward - overspendPenalty

where:
  clickReward = windowClicks.toDouble

  overspendPenalty = if (spendRate > 1.5)
                       config.overspendPenalty × (spendRate - 1.5)
                     else 0.0
```

**Default penalty factor**: `overspendPenalty = 2.0`

## Component Breakdown

### Clicks (Primary Signal)

Raw number of clicks in the 15-minute observation window. This is the positive signal — the agent maximizes clicks because that's what advertisers care about.

**Why clicks, not impressions?**
- Impressions don't indicate value — they're "free" from the user's perspective
- Clicks represent actual engagement
- Maximizing clicks naturally selects for high-CTR placements

**Why clicks, not revenue?**
- Revenue (CPM × impressions) would incentivize bidding as high as possible
- This contradicts the advertiser's interest in efficient spending
- Clicks align the agent with advertiser ROI

### Overspend Penalty

```
overspendPenalty = 2.0 × max(0, spendRate - 1.5)
```

- **Threshold at 1.5x**: No penalty for spending up to 50% faster than target. Gives the agent freedom to bid aggressively when opportunities are good.
- **2.0x factor**: Each unit of overspend above 1.5x costs 2.0 reward points
- **Continuous**: Allows the agent to learn the trade-off rather than hitting a hard wall

Examples:
```
spendRate = 1.0 → penalty = 0      (on pace)
spendRate = 1.5 → penalty = 0      (at threshold)
spendRate = 2.0 → penalty = 1.0    (moderate overspend)
spendRate = 3.0 → penalty = 3.0    (severe overspend)
```

## Episode Termination

The episode terminates when:

```scala
done = (budgetRemaining <= 0.0) || (timeRemaining <= 0.0)
```

At termination, a special terminal transition is stored:

```scala
val terminalState = Array.fill(stateSize)(0.0)   // Zero vector
val terminalReward = windowClicks.toDouble        // Final clicks (no penalty)
dqn.store(prevState, prevAction, terminalReward, terminalState, done = true)
```

The `done = true` flag tells DQN not to bootstrap future rewards beyond the episode boundary.

## Reward Examples

| Window | Clicks | spendRate | Penalty | Reward |
|--------|--------|-----------|---------|--------|
| Normal pacing | 3 | 1.0 | 0 | 3.0 |
| Good CTR | 8 | 1.2 | 0 | 8.0 |
| Slight overspend | 5 | 1.8 | 0.6 | 4.4 |
| Severe overspend | 2 | 3.0 | 3.0 | -1.0 |
| At threshold | 4 | 1.5 | 0 | 4.0 |

## Design Simplicity

Note what the reward function **does not** include:
- No exhaustion penalty — the episode simply ends when budget hits zero
- No CPA signal — conversion tracking is sparse, clicks are a sufficient proxy
- No win-rate bonus — win rate is in the state space, letting the agent learn its own trade-offs

This simplicity makes the reward signal clean and easy to interpret. The agent learns that clicks are good and overspending is bad — everything else it figures out from the state space.
