# From Q-Tables to Deep Q-Networks

In the previous chapters, we learned two things: Q-values tell an agent how good each action is in a given state, and neural networks can approximate functions over continuous inputs. Now we put them together.

This chapter covers the Deep Q-Network (DQN) algorithm as implemented in Promovolve's `DQNAgent.scala`. By the end, you will understand how the agent learns to adjust ad bids from raw experience, and why several seemingly arbitrary design choices -- target networks, experience replay, epsilon decay -- are each solving a specific problem.

## Q-values: the value of an action

A Q-value, written Q(state, action), answers a precise question: "If I am in this state and take this action, then act optimally from here on, what total reward can I expect?"

In Promovolve's ad bidding system, the state describes a campaign's current situation (8 numbers: effective CPM, CTR, win rate, budget remaining, time remaining, spend rate, impression rate, cost per click). The actions are 7 bid multiplier adjustments (0.7x through 1.4x). So Q(state, action=3) means: "Given the campaign's current metrics, if I hold the bid steady at 1.0x and then act optimally for the rest of the day, how many clicks will I get?"

The agent's policy is simple: always pick the action with the highest Q-value. If the Q-values are accurate, this is optimal behavior.

## The Q-table: why it can't work here

In a small, discrete world -- say, 10 states and 5 actions -- you could store Q-values in a 2D table:

| State | A0  | A1  | A2  | A3  | A4  |
|-------|-----|-----|-----|-----|-----|
| S0    | 0.2 | 0.5 | 0.1 | 0.3 | 0.0 |
| S1    | 0.4 | 0.1 | 0.6 | 0.2 | 0.8 |
| ...   | ... | ... | ... | ... | ... |

With 10 states and 5 actions, the table has 50 entries. Each time the agent takes action `a` in state `s`, receives reward `r`, and lands in state `s'`, it updates the entry using:

```
Q(s,a) <- Q(s,a) + alpha * [reward + gamma * max_a' Q(s',a') - Q(s,a)]
```

The term in brackets is the **TD error** -- the difference between what the agent expected and what it actually observed. The learning rate alpha controls how much to adjust. Given enough visits to every state-action pair, the values converge to the true Q-values and the agent behaves optimally.

But Promovolve's state space has 8 continuous dimensions. A CTR of 0.031 is different from 0.032. A budget remaining fraction of 0.7234 is different from 0.7235. The number of possible states is effectively infinite. No table can hold them all, and even if it could, the agent would never visit most states twice, so the values would never converge.

We need a function that *generalizes*: given a state the network has never seen before, it should produce reasonable Q-values by interpolating from similar states it has seen. This is exactly what a neural network does.

## The DQN idea

The key insight from DeepMind's 2015 paper (Mnih et al., "Human-level control through deep reinforcement learning") is straightforward: replace the Q-table with a neural network.

- **Input**: the state vector (8 numbers)
- **Output**: a Q-value for each action (7 numbers)
- **Architecture**: the `DenseNetwork` from Chapter 3 -- Input(8) -> Hidden(64, ReLU) -> Hidden(64, ReLU) -> Output(7, linear)

To select an action, run the forward pass and pick the output with the highest value:

```scala
def selectGreedy(state: Array[Double]): Int =
  argMax(qNetwork.forward(state))
```

Where `argMax` returns the index of the largest element:

```scala
private def argMax(arr: Array[Double]): Int = {
  var bestIdx = 0
  var bestVal = arr(0)
  var i = 1
  while (i < arr.length) {
    if (arr(i) > bestVal) {
      bestVal = arr(i)
      bestIdx = i
    }
    i += 1
  }
  bestIdx
}
```

If the Q-network outputs `[1.2, 0.8, 2.1, 3.0, 1.5, 0.9, 2.3]`, the agent picks action 3 (Q-value 3.0, which maps to a 1.0x multiplier -- hold the current bid).

Simple enough. But two problems immediately arise: how do we train this network, and how do we make sure the agent explores enough to discover good strategies?

## Epsilon-greedy exploration

If the agent always picks the action with the highest Q-value, it will never try anything new. In the early stages of learning, the Q-values are essentially random (the network was just initialized with random weights). If the agent latches onto whichever random action happened to look best, it will never discover that a different action might yield better results.

This is the **explore-exploit tradeoff**. Exploiting means using your current best knowledge. Exploring means trying something new to potentially find something better. A good agent needs both.

Promovolve uses **epsilon-greedy** exploration: with probability epsilon, pick a random action; otherwise, pick the best known action.

```scala
def selectAction(state: Array[Double]): Int = {
  totalSteps += 1
  if (rng.nextDouble() < epsilon) {
    rng.nextInt(config.actionSize) // explore: random action
  } else {
    argMax(qNetwork.forward(state)) // exploit: best known action
  }
}
```

The key is that epsilon changes over time:

- **Start**: epsilon = 1.0 (every action is random -- pure exploration)
- **Each training step**: epsilon *= 0.995 (gradually shift toward exploitation)
- **Floor**: epsilon = 0.05 (always keep 5% exploration)

```scala
// Decay epsilon
epsilon = math.max(config.epsilonEnd, epsilon * config.epsilonDecay)
```

Why start fully random? Because the initial Q-values are meaningless. Acting greedily on garbage values wastes time reinforcing an arbitrary strategy. Better to explore widely first, collect diverse experience, and let the network learn from all of it.

Why keep a 5% floor? Because the environment can change. In ad bidding, competitive dynamics shift throughout the day. A strategy that was optimal at 9 AM may be suboptimal at 3 PM. A small amount of ongoing exploration lets the agent detect and adapt to these shifts.

Why not explore more? Every exploratory action is potentially a wasted bid -- the agent tries something it "knows" is suboptimal. Too much exploration squanders the campaign's budget on bad bids. The gradual decay from 1.0 to 0.05 balances this: explore heavily when ignorant, exploit increasingly as knowledge improves.

## The Bellman equation: what the Q-values should be

We want the Q-network to output accurate Q-values. But what does "accurate" mean? What is the *correct* Q-value for a given state and action?

The **Bellman equation** provides the answer:

```
Q(s, a) = reward + gamma * max_a' Q(s', a')
```

In words: the value of taking action `a` in state `s` equals the immediate reward you get, plus the discounted value of the best action in the next state `s'`.

Let's make this concrete with an ad bidding example. Suppose the agent is in state `s` (budget 60% remaining, time 50% remaining, CTR 0.03). It takes action `a` = "bid 1.2x". Over the next observation window, it gets 3 clicks (reward = 3.0) and transitions to state `s'` (budget 55% remaining, time 45% remaining, CTR 0.035). The discount factor gamma is 0.99.

The Bellman equation says:

```
Q(s, bid_1.2x) = 3.0 + 0.99 * max_a' Q(s', a')
```

If the best Q-value in state `s'` is 15.0, then the target Q-value is `3.0 + 0.99 * 15.0 = 17.85`.

The **discount factor** gamma = 0.99 means the agent values future rewards almost as much as immediate ones. A gamma of 0 would make the agent completely myopic -- only caring about the next window's clicks. A gamma of 1 would weight all future rewards equally, which can cause numerical instability. 0.99 is a practical middle ground: the agent plans ahead but slightly prefers sooner rewards.

## The training loop

Now we have all the pieces. Here is how Promovolve's `DQNAgent.trainStep()` puts them together:

```scala
def trainStep(): Option[Double] = {
  if (replayBuffer.size < config.minBufferSize) return None

  val batch = replayBuffer.sample(config.batchSize, rng)
  var totalLoss = 0.0

  var i = 0
  while (i < batch.size) {
    val state = batch.states(i)
    val action = batch.actions(i)
    val reward = batch.rewards(i)
    val nextState = batch.nextStates(i)
    val done = batch.dones(i)

    // Current Q-values
    val currentQ = qNetwork.forward(state)

    // Double DQN target:
    // 1. Q-network selects best action for next state
    // 2. Target network evaluates that action
    val target = currentQ.clone()
    if (done) {
      target(action) = reward
    } else {
      val nextQOnline = qNetwork.forward(nextState)
      val bestNextAction = argMax(nextQOnline)
      val nextQTarget = targetNetwork.forward(nextState)
      target(action) = reward + config.gamma * nextQTarget(bestNextAction)
    }

    // Clip target to prevent extreme Q-values
    target(action) = math.max(-config.qClip, math.min(config.qClip,
                              target(action)))

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

Let's walk through this step by step.

### Step 1: Wait for enough experience

```scala
if (replayBuffer.size < config.minBufferSize) return None
```

The agent does not start training until it has collected at least `minBufferSize` (32) transitions in its replay buffer. This ensures there is enough variety in the training batch.

### Step 2: Sample a batch

```scala
val batch = replayBuffer.sample(config.batchSize, rng)
```

Randomly sample 32 transitions from the replay buffer. Each transition is a tuple of (state, action, reward, nextState, done). We will cover the replay buffer in detail in the next chapter -- for now, think of it as a big bag of past experiences that we draw from randomly.

### Step 3: Compute the target Q-value

For each transition in the batch:

```scala
val currentQ = qNetwork.forward(state)
val target = currentQ.clone()
```

First, get the current Q-values for the state. Clone them into a target array. We will only modify the Q-value for the action that was actually taken -- the other values stay the same, so the network receives zero gradient for actions it did not take.

If the episode is done (budget exhausted or time expired):

```scala
if (done) {
  target(action) = reward
}
```

There is no future, so the Q-value is just the immediate reward.

Otherwise, apply the Bellman equation:

```scala
val nextQOnline = qNetwork.forward(nextState)
val bestNextAction = argMax(nextQOnline)
val nextQTarget = targetNetwork.forward(nextState)
target(action) = reward + config.gamma * nextQTarget(bestNextAction)
```

This is the **Double DQN** variant (Van Hasselt et al., 2016). Standard DQN would use the target network for both selecting and evaluating the best next action, which tends to overestimate Q-values. Double DQN decouples these: the Q-network picks the best action, but the target network evaluates how good that action actually is. This small change significantly reduces overestimation bias.

The target is also clipped to `[-100, 100]` to prevent runaway values:

```scala
target(action) = math.max(-config.qClip, math.min(config.qClip,
                          target(action)))
```

### Step 4: Train the Q-network

```scala
totalLoss += qNetwork.train(state, target, config.learningRate)
```

This calls the `DenseNetwork.train()` method from Chapter 3. It runs a forward pass, computes MSE loss between the network's current output and the target, and backpropagates to update the weights. The learning rate is 0.001.

### Step 5: Decay epsilon

```scala
epsilon = math.max(config.epsilonEnd, epsilon * config.epsilonDecay)
```

After each training step, reduce the exploration rate by multiplying by 0.995. This gradually shifts the agent from exploration toward exploitation.

How fast does this decay? After 100 training steps: `1.0 * 0.995^100 = 0.606`. After 500 steps: `0.995^500 = 0.082`. After about 600 steps, epsilon hits the floor of 0.05 and stays there. In practice, this means the agent explores heavily for the first few hundred observation windows, then settles into mostly exploiting what it has learned.

### Step 6: Sync the target network

```scala
if (trainSteps % config.targetSyncInterval == 0) {
  targetNetwork.copyFrom(qNetwork)
}
```

Every 100 training steps, copy all weights from the Q-network into the target network. Between syncs, the target network is frozen -- it provides stable targets for training.

## The instability problem

Here is the fundamental challenge of DQN, and the reason for the two complications we just introduced (target network and experience replay).

When you train a supervised learning model, the training targets are fixed. If you are classifying images of cats and dogs, the label "cat" does not change as the model learns. The model is trying to hit a stationary target.

In DQN, the targets are *computed from the network itself*:

```
target = reward + gamma * max_a' Q_target(s', a')
```

As the Q-network improves, the target values change. It is like trying to hit a moving bullseye -- every time you get closer, the bullseye shifts. This can cause wild oscillations: the network overshoots in one direction, which changes the targets, which causes it to overcorrect in the other direction, and so on.

Two mechanisms stabilize this:

1. **Target network**: by freezing a copy of the Q-network and only updating it every 100 steps, the targets remain stable for stretches of training. The bullseye moves, but it moves in discrete jumps rather than continuously, giving the Q-network time to converge toward each set of targets.

2. **Experience replay** (covered in the next chapter): instead of training only on the most recent transition, the agent samples randomly from all past experience. This breaks the correlation between consecutive training samples. Without replay, the agent would train on a sequence of highly correlated transitions (all from the same part of the state space), which tends to cause the network to overfit to recent experience and forget what it learned earlier.

Together, these two ideas transformed DQN from an unstable curiosity into a practical algorithm. Promovolve implements both.

## The full picture

Let's summarize how all the pieces fit together in Promovolve's bid optimization:

1. Every observation window (~15 minutes), the campaign entity sends the agent an observation of its current state.

2. The agent converts the observation into an 8-dimensional state vector (effective CPM, CTR, win rate, budget remaining, time remaining, spend rate, impression rate, cost per click).

3. If there was a previous state, the agent stores the transition (previous state, action taken, reward received, current state) in the replay buffer.

4. The agent runs `trainStep()`: sample a batch from the replay buffer, compute Bellman targets, train the Q-network, decay epsilon, and periodically sync the target network.

5. The agent selects an action using epsilon-greedy: either a random action (exploration) or the action with the highest Q-value (exploitation).

6. The selected action maps to a bid multiplier adjustment (e.g., action 5 -> 1.2x), which is applied to the campaign's base CPM.

7. Over the next 15 minutes, the adjusted bid competes in auctions. The results (impressions, clicks, spend) become the next observation, and the cycle repeats.

Over the course of a day, the agent collects dozens of transitions, gradually refines its Q-value estimates, and shifts from random exploration to informed bidding. Over multiple days (with weights persisted via snapshots), the agent accumulates thousands of transitions and develops a nuanced bidding strategy that balances click maximization against budget pacing.

## What's next

We have glossed over two important components: the **experience replay buffer** (how past transitions are stored and sampled) and the **target network** (why freezing a separate copy stabilizes training). The next chapter dives deep into both, showing how Promovolve's `ReplayBuffer` works and walking through the stability dynamics that make DQN practical.
