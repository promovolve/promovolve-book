# DQN Agent Overview

Each campaign in Promovolve has its own **Double DQN reinforcement learning agent** that learns to adjust the campaign's bid multiplier over time. The agent observes campaign performance metrics every 15 minutes and outputs an action that adjusts the bid.

## Architecture

```
┌──────────────────────────────────────┐
│          CampaignEntity              │
│                                      │
│  ┌────────────────────────────────┐  │
│  │   BidOptimizationAgent         │  │
│  │                                │  │
│  │  ┌──────────────────────────┐  │  │
│  │  │      DQNAgent            │  │  │
│  │  │  Q-network: [64, 64]    │  │  │
│  │  │  Target network (copy)  │  │  │
│  │  │  ReplayBuffer (10,000)  │  │  │
│  │  │  ε-greedy (1.0 → 0.05) │  │  │
│  │  └──────────────────────────┘  │  │
│  │                                │  │
│  │  bidMultiplier: [min, max]     │  │
│  │  Window: imps, clicks, spend   │  │
│  └────────────────────────────────┘  │
│                                      │
│  bidCpm = max(maxCpm × mult, floor)  │
└──────────────────────────────────────┘
```

## Two Speed Paths

### Fast Path (Per Bid Request)
```
1. Receive CampaignBidRequest
2. Check budget, eligibility, size match
3. Compute: bidCpm = max(maxCpm × bidMultiplier, floorCpm)
4. Return CampaignBidResponse with eligible creatives
```

No RL computation — `bidMultiplier` is a cached scalar.

### Slow Path (Every 15 Minutes)
```
1. Timer fires (rlObserveInterval = 15 minutes)
2. Compute timeRemaining = max(0, 1.0 - elapsed / rlDayDurationSeconds)
3. Call bidOptAgent.observe(observation)
   a. Build 8-dimensional state vector
   b. Compute reward from previous window
   c. Store transition (s, a, r, s') in replay buffer
   d. Select action via ε-greedy
   e. Apply action: adjust bidMultiplier
   f. Train DQN on batch from replay buffer
4. Reset window counters
```

### Event Recording (Per Request)
```
recordImpression(spendAmount)  → accumulates window metrics
recordClick()                   → increments window click counter
recordBidOpportunity(won)       → tracks win rate
```

## Day Reset

At daily budget rollover:
1. Store **terminal transition** with `done=true` (final reward = last window clicks)
2. Reset `bidMultiplier` to 1.0
3. Reset window counters and day stats
4. **Preserve** DQN weights — learned policy carries across days
5. Guard: `lastRolledEpochDay` prevents double-roll on same calendar day

## Inference Mode

```scala
val action = if (inferenceOnly)
  dqn.selectGreedy(state)   // Pure exploitation, no exploration
else
  dqn.selectAction(state)    // ε-greedy (training mode)
```

The `inferenceOnly` flag allows deploying a trained agent without further exploration.

## Persistence

The DQN agent's state is serialized as a `DQNAgent.Snapshot` (weights, biases, epsilon, step counters) and stored in `CampaignEntity.State.rlSnapshot`. This survives process crashes and restarts — the agent resumes training from where it left off.
