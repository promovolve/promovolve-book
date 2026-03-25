# Double DQN: Fixing Overestimation

The previous chapter gave us a replay buffer full of past experiences. Now we need to train the neural network on those experiences. This chapter covers the core training loop in Promovolve's DQN agent -- and a subtle but devastating bug in standard DQN that Double DQN fixes.

## The Overestimation Problem

Recall from earlier chapters that the DQN training target for a transition `(state, action, reward, nextState)` is:

```
target = reward + gamma * max Q(nextState, a')
                          ^^^
                          over all actions a'
```

The agent asks: "What is the best possible future value from `nextState`?" and uses the answer to update the Q-value of the action it took.

The problem is the **max** operator. Here is why.

### Noise Becomes Optimism

Early in training, Q-values are essentially random numbers. The network has not learned anything yet, so its predictions are noise. Suppose the agent is evaluating `nextState` and there are 7 possible actions. The Q-network produces these estimates:

```
Q(nextState, action0) =  0.3   (true value: 0.5)
Q(nextState, action1) =  1.8   (true value: 0.4)  <-- overestimated!
Q(nextState, action2) = -0.2   (true value: 0.6)
Q(nextState, action3) =  0.7   (true value: 0.5)
Q(nextState, action4) =  0.1   (true value: 0.3)
Q(nextState, action5) =  0.4   (true value: 0.4)
Q(nextState, action6) =  0.9   (true value: 0.7)
```

The true best action is action 6 (true value 0.7), but `max` picks action 1 (estimated value 1.8) because it has the highest noise spike. The max operator acts as a **noise amplifier** -- it always selects the most overestimated value.

If Q-values were perfectly accurate, max would correctly identify the best action. But Q-values always have estimation error, especially early in training. And `max` systematically exploits that error in the upward direction. It can never underestimate (it picks the highest value), so the bias is always positive.

### Overestimation Compounds

This would be manageable if it only happened once. But the overestimated target gets baked into the Q-network's weights through training. On the next training step, the Q-network produces slightly higher values (because it was trained toward the inflated target), which produce an even more inflated max, which produces an even higher target. The overestimation feeds on itself.

After thousands of training steps, the agent can end up with Q-values that bear no relationship to reality. In ad bidding, this manifests as the agent believing that aggressive bidding (action 6 = 1.4x multiplier) is always the best choice, because the noisy early Q-values made it *look* good, and that initial overestimation compounded over time. The result: the agent overspends the campaign budget and burns through it in the first few hours.

## The Double DQN Fix

The insight behind Double DQN (Van Hasselt et al., 2016) is to **decouple action selection from action evaluation** using two separate networks.

Standard DQN uses the same network for both steps:

1. **Select** the best action: which action has the highest Q-value?
2. **Evaluate** that action: what is that Q-value?

When the same noisy network both picks the action and evaluates it, the noise reinforces itself. The network picks the action with the highest noise spike, then reports that inflated value as the evaluation.

Double DQN splits these responsibilities:

1. **Q-network** (online network) selects the best action for the next state.
2. **Target network** (a frozen copy) evaluates that action's value.

Even if the Q-network is wrong about *which* action is best, the target network's evaluation of that action is likely more conservative -- because the target network has different noise patterns (it is a snapshot from 100 training steps ago). The two networks' errors are unlikely to align.

Here is the difference in formulas:

```
Standard DQN:
  target = reward + gamma * max Q_target(nextState, a')
  (target network picks AND evaluates)

Double DQN:
  bestAction = argmax Q_online(nextState, a')    -- online network picks
  target = reward + gamma * Q_target(nextState, bestAction)  -- target network evaluates
```

The change is small -- just one line of code -- but it dramatically reduces overestimation.

## The Code

Here is the training loop from Promovolve's `DQNAgent.trainStep()`:

```scala
def trainStep(): Option[Double] = {
  if (replayBuffer.size < config.minBufferSize) return None

  val batch = replayBuffer.sample(config.batchSize, rng)
  var totalLoss = 0.0

  var i = 0
  while (i < batch.size) {
    val state     = batch.states(i)
    val action    = batch.actions(i)
    val reward    = batch.rewards(i)
    val nextState = batch.nextStates(i)
    val done      = batch.dones(i)

    // Current Q-values for this state
    val currentQ = qNetwork.forward(state)

    // Double DQN target:
    // 1. Q-network selects best action for next state
    // 2. Target network evaluates that action
    val target = currentQ.clone()
    if (done) {
      target(action) = reward
    } else {
      val nextQOnline    = qNetwork.forward(nextState)
      val bestNextAction = argMax(nextQOnline)
      val nextQTarget    = targetNetwork.forward(nextState)
      target(action) = reward + config.gamma * nextQTarget(bestNextAction)
    }

    // Clip target to prevent extreme Q-values
    target(action) = math.max(-config.qClip, math.min(config.qClip, target(action)))

    totalLoss += qNetwork.train(state, target, config.learningRate)
    i += 1
  }

  trainSteps += 1

  // Sync target network periodically
  if (trainSteps % config.targetSyncInterval == 0) {
    targetNetwork.copyFrom(qNetwork)
  }

  // Decay epsilon
  epsilon = math.max(config.epsilonEnd, epsilon * config.epsilonDecay)

  Some(totalLoss / batch.size)
}
```

Let's break this down piece by piece.

### Guard: Don't Train Too Early

```scala
if (replayBuffer.size < config.minBufferSize) return None
```

If the replay buffer has fewer than 32 experiences, skip training entirely. As discussed in the previous chapter, training on a tiny number of examples produces memorization, not learning. The method returns `None` to signal "no training happened."

### Sample a Batch

```scala
val batch = replayBuffer.sample(config.batchSize, rng)
```

Pull 32 random transitions from the 10,000-capacity replay buffer. This is where experience replay breaks the temporal correlation -- we might get a transition from Monday morning alongside one from Thursday evening.

### Build the Training Target

For each transition in the batch, the code needs to construct a target Q-value vector that the network will be trained toward. This is the heart of Double DQN:

```scala
val currentQ = qNetwork.forward(state)
val target = currentQ.clone()
```

First, compute the Q-network's current predictions for the state. Then clone that array to create the target. The target starts as a copy of the current predictions -- this is important because we only want to change the Q-value for the **action that was actually taken**. All other Q-values in the target remain equal to the current predictions, so they produce zero gradient (no learning signal).

### Terminal States

```scala
if (done) {
  target(action) = reward
}
```

When `done` is `true`, the episode is over -- the campaign's budget was exhausted or the delivery day ended. There is no future state to consider, so the target is simply the reward received. No discounting, no future value. The episode is finished.

### The Double DQN Core

```scala
val nextQOnline    = qNetwork.forward(nextState)
val bestNextAction = argMax(nextQOnline)
val nextQTarget    = targetNetwork.forward(nextState)
target(action) = reward + config.gamma * nextQTarget(bestNextAction)
```

This is where Double DQN differs from standard DQN. Four lines that are worth reading carefully:

1. **`nextQOnline = qNetwork.forward(nextState)`** -- The Q-network (the one being trained) evaluates all actions for the next state. These values are used *only* to decide which action looks best.

2. **`bestNextAction = argMax(nextQOnline)`** -- Pick the action with the highest Q-value according to the Q-network. This is the "selection" step.

3. **`nextQTarget = targetNetwork.forward(nextState)`** -- The target network (frozen copy) also evaluates all actions for the next state. These values are used *only* to evaluate the selected action.

4. **`target(action) = reward + config.gamma * nextQTarget(bestNextAction)`** -- The final target combines the actual reward with the *target network's* evaluation of the action that the *Q-network* selected. Selection and evaluation are decoupled.

If the Q-network's noise causes it to select the wrong "best" action, the target network's evaluation of that wrong action is likely to be mediocre (not inflated), which limits the damage.

### Q-Value Clipping

```scala
target(action) = math.max(-config.qClip, math.min(config.qClip, target(action)))
```

Even with Double DQN, Q-values can occasionally grow large during training instabilities. This safety clamp keeps targets within `[-100, 100]` (the default `qClip` value). It is a simple guardrail that prevents a single runaway target from destabilizing the entire network.

### Train the Network

```scala
totalLoss += qNetwork.train(state, target, config.learningRate)
```

This passes the (state, target) pair to the neural network for one step of backpropagation with stochastic gradient descent. The network adjusts its weights to make its predictions closer to the target. The method returns the MSE (mean squared error) loss, which we accumulate for monitoring.

Note that only the Q-network is trained. The target network's weights are never updated by backpropagation.

### Sync the Target Network

```scala
if (trainSteps % config.targetSyncInterval == 0) {
  targetNetwork.copyFrom(qNetwork)
}
```

Every 100 training steps, the target network's weights are replaced with a copy of the Q-network's current weights. This is the "hard sync" approach -- the target network is an exact copy, just 100 steps behind.

Why not sync every step? If the target network updated continuously with the Q-network, the training targets would shift with every weight update. The network would be chasing a moving target -- literally. Stable targets produce stable training.

Think of it this way: the Q-network is a student taking a 100-question test. The target network is the answer key. If someone kept changing the answer key while the student was working, the student could never converge on the right answers. By freezing the answer key for 100 questions at a time, the student can make meaningful progress before the key is updated.

With `targetSyncInterval = 100` and the agent training once per 15-minute observation, the target network updates roughly once per day (100 observations = 25 hours). This gives the Q-network a full day of stable targets to learn against before they shift.

### Epsilon Decay

```scala
epsilon = math.max(config.epsilonEnd, epsilon * config.epsilonDecay)
```

After each training step, the exploration rate decays. With `epsilonDecay = 0.995`, epsilon drops from 1.0 (pure exploration) to 0.05 (5% exploration) over about 600 training steps. The agent gradually shifts from random exploration to exploiting what it has learned.

## Walking Through a Concrete Example

Let's trace one complete training step with a batch of 3 transitions (the real batch size is 32, but 3 is easier to follow). The config uses `gamma = 0.99`.

### The Batch

| i | state (abbreviated) | action | reward | nextState (abbreviated) | done |
|---|---------------------|--------|--------|-------------------------|------|
| 0 | [1.0, 0.02, 0.4, 0.6, 0.5, 1.1, 0.8, 0.5] | 3 (hold at 1.0x) | 2.0 | [1.0, 0.03, 0.5, 0.55, 0.45, 1.0, 0.9, 0.4] | false |
| 1 | [1.2, 0.01, 0.3, 0.2, 0.1, 1.8, 0.5, 1.0] | 5 (bid 1.2x) | -1.0 | [1.4, 0.01, 0.2, 0.0, 0.05, 2.5, 0.3, 1.2] | true |
| 2 | [0.8, 0.04, 0.6, 0.8, 0.7, 0.8, 1.2, 0.3] | 1 (bid 0.8x) | 4.0 | [0.7, 0.03, 0.5, 0.75, 0.65, 0.9, 1.0, 0.3] | false |

### Transition 0: Normal Mid-Day Observation

The agent held steady (action 3 = 1.0x multiplier) and earned 2 clicks.

```
currentQ = qNetwork.forward(state_0)
         = [-0.5, 0.3, 1.2, 0.8, 0.6, 0.4, 0.1]
```

The Q-network currently thinks action 2 (0.9x) is the best choice from this state. Now we compute the Double DQN target for action 3 (the action that was actually taken):

```
nextQOnline = qNetwork.forward(nextState_0)
            = [0.1, 0.5, 1.5, 1.0, 0.7, 0.3, 0.2]
bestNextAction = argMax(nextQOnline) = 2   (action 2, value 1.5)

nextQTarget = targetNetwork.forward(nextState_0)
            = [0.2, 0.4, 1.1, 0.9, 0.8, 0.5, 0.3]
```

Notice: the Q-network selected action 2, but the target network's value for action 2 is **1.1**, not 1.5. The target network's estimate is more conservative.

```
target[3] = reward + gamma * nextQTarget[bestNextAction]
          = 2.0 + 0.99 * 1.1
          = 2.0 + 1.089
          = 3.089
```

With standard DQN (using the target network for both selection and evaluation), the target would have used `max(nextQTarget) = 1.1` here too. But imagine if the target network had a different noise pattern where action 4 had value 1.3 -- standard DQN would use 1.3 (the maximum), while Double DQN still uses 1.1 (the value of the *Q-network's* choice, as evaluated by the target network).

The final target vector for transition 0:

```
target = [-0.5, 0.3, 1.2, 3.089, 0.6, 0.4, 0.1]
                           ^^^^^
                     only this changed (action 3)
```

The network trains to push its Q-value for (state\_0, action 3) from 0.8 toward 3.089.

### Transition 1: Terminal State (Budget Exhausted)

The agent bid aggressively (action 5 = 1.2x) while the budget was already low (20% remaining, spend rate at 1.8x ideal pace). It received reward -1.0 (overspend penalty exceeded clicks). The next state shows budget at 0% with time remaining -- `done = true`.

```
target[5] = reward = -1.0    (no future discounting -- episode over)
```

This is the simplest case. The agent exhausted the budget with time left in the day, and it learns that aggressive bidding in this situation leads to a negative outcome. No need to estimate future value -- there is no future.

### Transition 2: Conservative Bidding, Good Outcome

The agent bid conservatively (action 1 = 0.8x) with plenty of budget and time remaining, and earned 4 clicks.

```
nextQOnline = qNetwork.forward(nextState_2)
            = [0.3, 0.8, 2.0, 1.5, 1.1, 0.6, 0.4]
bestNextAction = argMax(nextQOnline) = 2

nextQTarget = targetNetwork.forward(nextState_2)
            = [0.4, 0.7, 1.6, 1.2, 0.9, 0.5, 0.3]

target[1] = 4.0 + 0.99 * 1.6 = 5.584
```

The agent learns that conservative bidding with a healthy budget produces good outcomes with promising future value.

### After All Three

Each of the three (state, target) pairs is fed through `qNetwork.train(...)`, which runs backpropagation and nudges the Q-network's weights. The total loss is averaged and returned:

```
totalLoss / batchSize = average MSE across the 3 transitions
```

This is one training step. In Promovolve, this happens every 15 minutes when the `BidOptimizationAgent.observe()` method is called.

## Putting It All Together

Here is the full picture of how Double DQN training works in Promovolve, from observation to weight update:

1. Every 15 minutes, `BidOptimizationAgent.observe()` is called with the current campaign metrics.
2. The agent computes the reward from the previous action and stores the transition `(prevState, prevAction, reward, currentState, done)` in the replay buffer.
3. `DQNAgent.trainStep()` samples 32 random transitions from the buffer.
4. For each transition, it computes a Double DQN target: the Q-network selects the best next action, the target network evaluates it.
5. Terminal transitions (budget exhausted or day ended) use the raw reward as the target.
6. Q-value targets are clipped to `[-100, 100]` for stability.
7. The Q-network is trained via backpropagation on each (state, target) pair.
8. Every 100 training steps, the target network is synced with the Q-network.
9. Epsilon decays slightly, shifting the balance from exploration toward exploitation.

The result is an agent that steadily improves its bid multiplier decisions over days and weeks of operation, without the runaway overestimation that would cause it to blow through campaign budgets.

---

Next chapter: we have covered the neural network, the replay buffer, and the Double DQN training loop. Now it is time to see how these components wire together in the `BidOptimizationAgent` and connect to the live auction system.
