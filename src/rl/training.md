# Training Loop & Hyperparameters

## Hyperparameters (from DQNAgent.scala and BidOptimizationAgent.scala)

| Parameter | Default | Source |
|-----------|---------|--------|
| Hidden layers | `[64, 64]` | DQNAgent.Config |
| Learning rate | 0.001 | DQNAgent.Config |
| Gamma (discount) | 0.99 | DQNAgent.Config |
| Replay buffer size | 10,000 | DQNAgent.Config |
| Batch size | 32 | DQNAgent.Config |
| Min buffer size | 100 | DQNAgent.Config (before first training step) |
| Target sync interval | 100 steps | DQNAgent.Config |
| Epsilon start | 1.0 | DQNAgent.Config |
| Epsilon end | 0.05 | DQNAgent.Config |
| Epsilon decay | 0.995 | DQNAgent.Config |
| Q-value clip | [-100, 100] | DQNAgent.Config |
| Observation interval | 15 minutes | `promovolve.rl.observe-interval` |
| Day duration | 86400s | `promovolve.rl.day-duration-seconds` |

## Training Schedule

Every 15 minutes (96 times per real day):

```
┌───────────────────────────────┐
│ 1. Timer fires in Campaign    │  rlObserveInterval = 15 min
│ 2. Compute timeRemaining      │  1.0 - elapsed / dayDuration
│ 3. Build observation          │  windowImps, clicks, spend, etc.
│ 4. Call bidOptAgent.observe()  │
│    a. Build 8-dim state        │
│    b. Compute reward           │  clicks - overspendPenalty
│    c. Store (s,a,r,s',done)    │  → replay buffer
│    d. ε-greedy action select   │  random if ε, else argmax Q(s)
│    e. Apply action             │  bidMultiplier *= adjustment
│    f. Sample batch (32)        │  from replay buffer
│    g. Compute Double DQN loss  │
│    h. Backprop + weight update │
│    i. Maybe sync target net    │  every 100 train steps
│ 5. Reset window counters      │
└───────────────────────────────┘
```

## Epsilon-Greedy Exploration

```scala
if (rng.nextDouble() < epsilon):
    action = rng.nextInt(actionSize)       // random exploration
else:
    action = argmax(qNetwork.forward(state))  // exploitation
```

Epsilon decays after each training step:

```scala
epsilon = max(epsilonEnd, epsilon × epsilonDecay)
```

### Decay Timeline (96 steps/day)

```
Day 1:   ε ≈ 1.00  → 100% random (pure exploration)
Day 2:   ε ≈ 0.62  → 62% random
Day 3:   ε ≈ 0.38  → 38% random
Day 5:   ε ≈ 0.15  → 15% random
Day 8:   ε ≈ 0.05  → 5% random (hits floor)
Day 8+:  ε = 0.05  → 5% random (steady-state)
```

The 5% floor ensures ongoing exploration to adapt to changing conditions.

## Replay Buffer (ReplayBuffer.scala)

### Structure
```scala
private val states: Array[Array[Double]]
private val actions: Array[Int]
private val rewards: Array[Double]
private val nextStates: Array[Array[Double]]
private val dones: Array[Boolean]
```

### Mechanics
- **Capacity**: 10,000 transitions (~104 days at 96 steps/day)
- **Circular buffer**: `writeIdx = (writeIdx + 1) % capacity`
- **Sampling**: Uniform random (`indices.map(rng.nextInt(currentSize))`)
- **Min size**: Training starts only after 100 transitions are stored
- **No prioritization**: All transitions are equally likely to be sampled

### Why Uniform?
- State space is small (8-D) — network learns quickly from uniform samples
- Prioritized Experience Replay adds complexity (sum trees, importance sampling) for marginal benefit
- 15-minute windows already provide stable, low-noise transitions

## Terminal Transitions

At day rollover:

```scala
if prevState exists:
    terminalState = Array.fill(stateSize)(0.0)  // zero vector
    terminalReward = windowClicks.toDouble
    dqn.store(prevState, prevAction, terminalReward, terminalState, done = true)
```

The `done = true` flag prevents Q-value bootstrapping across day boundaries:

```scala
if done:
    target = reward                          // no future rewards
else:
    target = reward + γ × Q(s', argmax Q(s'; θ); θ⁻)  // Double DQN
```

## Convergence Characteristics

- **Days 1-3**: Mostly random (ε > 0.38), building replay buffer, Q-network starts distinguishing good/bad actions
- **Days 4-7**: Agent develops basic policy (bid up when budget ample, down when overspending)
- **Day 8+**: ε hits floor (0.05), policy stabilizes with 5% ongoing exploration
- **Cross-day**: Weights persist, but multiplier resets to 1.0 daily — the agent re-learns optimal trajectory each day using its accumulated Q-network knowledge

## Monitoring

```scala
// Q-values for inspection
def qValues(state: Array[Double]): Array[Double] = qNetwork.forward(state)

// Day statistics
DayStats(impressions, clicks, spend, observations, totalReward)
```

Available via `DQNAgent.Snapshot`: epsilon, totalSteps, trainSteps, network weights.
