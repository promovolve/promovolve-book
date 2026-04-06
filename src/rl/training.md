# Training Loop & Hyperparameters

## Hyperparameters (from FloorCpmOptimizationAgent)

| Parameter | Value | Purpose |
|-----------|-------|---------|
| stateSize | 7 | Floor-related metrics |
| actionSize | 7 | Floor adjustment multipliers |
| hiddenSizes | [64, 32] | Smaller than typical — simple problem |
| γ (gamma) | 0.95 | Discount factor — floor effects are fairly immediate |
| learningRate | 0.0005 | Conservative — floor changes are high-impact |
| εStart | 0.8 | Initial exploration rate |
| εEnd | 0.05 | Minimum exploration |
| εDecay | 0.995 | Multiplicative decay per training step |
| bufferSize | 5,000 | Replay buffer capacity |
| minBufferSize | 4 | Start training after 4 transitions |
| batchSize | 4 | Mini-batch size |
| targetSyncInterval | 50 | Sync target network every 50 steps |
| qClip | 50.0 | Clip Q-value targets |
| maxFloorFraction | 0.80 | Never exceed 80% of highest observed CPM |
| bidSpreadThreshold | 1.5 | Only train when max/min bid ratio > 1.5x |

## Training Cycle

Every 15 minutes (or scaled shorter for simulated days):

```
1. Check activation gate:
   - No auctions in window? → skip
   - No bid spread and no floor rejections? → skip (homogeneous market)

2. Encode state (7 dimensions from window metrics)

3. Compute reward from previous action's outcome

4. Store transition: (prevState, prevAction, reward, newState)

5. Sample mini-batch of 4 from replay buffer

6. Train Q-network:
   - For each transition: target = reward + γ × Q_target(s', argmax Q_online(s'))
   - MSE loss, backprop through 2-layer network
   - Gradient clipping at ±5.0

7. Every 50 steps: sync target network from Q-network

8. Select next action (ε-greedy)

9. Apply action: multiply floor by selected multiplier

10. Clamp to [publisherMinFloor, maxObservedCPM × 0.80]

11. Persist DQN snapshot in SiteEntity state

12. Send UpdateFloorCpm to AuctioneerEntity

13. Publish new floor via DData (PacingConfig)
```

## Convergence Timeline

With 4 observations per hour (15-minute intervals):

| Phase | ε | Observations | Behavior |
|-------|---|-------------|----------|
| Early | 0.8 | 0–50 | Mostly random floor changes, filling replay buffer |
| Mid | 0.5 | 50–150 | Learning kicks in, floor starts trending toward optimal |
| Late | 0.1 | 300+ | Mostly exploiting, fine-tuning around optimal floor |

In real time, ε decays from 0.8 to 0.05 over roughly 2–3 weeks. The agent keeps adapting after that — if the market shifts (new campaigns enter, budgets change), it adjusts.

## Why DQN?

DQN is arguably overkill for a 7-state, 7-action problem. A simpler approach (hill climbing, bandit) might work nearly as well. The DQN was chosen because:

1. The infrastructure was already built for the (now-removed) campaign bid optimization
2. It handles non-stationary environments (the market changes over time)
3. The computational cost is negligible (one forward pass every 15 minutes)
4. The replay buffer provides sample efficiency — the agent can learn from past experiences even as the market changes

## Persistence

The DQN weights (Q-network + target network), epsilon, and step counts are serialized as a `DQNAgent.Snapshot` and stored in `SiteEntity.State.floorAgentSnapshot`. This survives server restarts — the agent picks up where it left off without retraining.
