# Reinforcement Learning from Scratch

This chapter teaches RL from zero, using Promovolve's bid optimization as the running example. By the end, you'll understand every line of `DQNAgent.scala` and `BidOptimizationAgent.scala`.

## The Setup: An Agent in a World

Imagine you're managing a single advertising campaign. You have a daily budget of $100 and a maximum bid of $5 CPM (cost per thousand impressions). Every 15 minutes, you look at how things are going and decide: should I bid higher to win more auctions, or bid lower to conserve budget?

This is a **reinforcement learning** problem. You have:

- An **agent** — your bidding strategy (in Promovolve: `BidOptimizationAgent`)
- An **environment** — the ad auction marketplace (other campaigns, user traffic, click patterns)
- **States** — what you can observe about the current situation (budget remaining, time left, click rate, etc.)
- **Actions** — what you can do (bid higher, bid lower, hold steady)
- **Rewards** — feedback on how well you did (clicks received, minus penalties for overspending)

The agent's goal: learn a **policy** — a mapping from states to actions — that maximizes total reward over time.

## Why Not Just Use Rules?

You could write rules: "if budget is more than 60% remaining and we're past noon, bid higher." But:

- You don't know the right thresholds in advance
- The right strategy depends on competitors' behavior, which changes
- Traffic patterns vary by day and season
- Different campaigns have different optimal strategies

RL learns these rules automatically from experience. The agent tries different actions, observes what happens, and gradually figures out what works.

## The Reward Signal

The reward is the only feedback the agent gets. It defines what "good" means.

In Promovolve, every 15 minutes the agent receives:

```
reward = clicks_in_window − penalty

where penalty = 2.0 × max(0, spend_rate − 1.5)
```

- **Clicks** are the primary goal — we want engagement
- **Penalty** kicks in only when spending more than 1.5× the ideal pace — some overspend is fine, but burning through budget by noon is bad

This is the reward function in `BidOptimizationAgent.computeReward()`. Everything the agent learns flows from this single signal.

## Q-Values: Rating Actions

Here's the core idea of Q-learning. For every state the agent might be in, we want to know: **how good is each action?**

A **Q-value** `Q(state, action)` answers: "if I'm in this state and take this action, then act optimally afterward, how much total reward will I get?"

For example:
- State: 70% budget remaining, 50% time remaining, CTR is high
- `Q(state, bid_higher)` = 12.5 (bidding higher here tends to yield 12.5 total future reward)
- `Q(state, hold)` = 10.0
- `Q(state, bid_lower)` = 7.3

The agent just picks the action with the highest Q-value. The hard part is learning accurate Q-values.

## The Bellman Equation: Learning from Experience

After taking an action, the agent observes what happened:

```
(state, action, reward, next_state)
```

For example: "I was at 70% budget with high CTR, I bid higher, I got 3 clicks (reward=3.0), and now I'm at 65% budget with slightly lower CTR."

The **Bellman equation** says:

```
Q(state, action) = reward + γ × max_a Q(next_state, a)
```

Translation: the value of taking an action in a state equals the immediate reward plus the discounted best possible value from the next state.

**γ (gamma)** is the **discount factor** (0.99 in Promovolve). It means future rewards are worth slightly less than immediate ones. A reward of 1.0 next step is worth 0.99 now. A reward 100 steps from now is worth 0.99^100 ≈ 0.37. This prevents the agent from being infinitely patient — it prefers rewards sooner.

## From Table to Neural Network

If states were simple (like grid positions), you could store Q-values in a table. But Promovolve's state has 8 continuous dimensions — budget fraction, time fraction, CTR, win rate, etc. There are infinitely many possible states. A table won't work.

Instead, we use a **neural network** to approximate the Q-function. The network takes a state (8 numbers) as input and outputs a Q-value for each action (5 numbers):

```
Input: [0.7, 0.03, 0.65, 0.70, 0.50, 1.1, 0.8, 0.4]
         ↓
   [64 neurons, ReLU] → [64 neurons, ReLU] → [5 outputs, linear]
         ↓
Output: [12.5, 10.0, 7.3, 11.2, 9.8]
          ↑
     Q-values for each action
     (pick the highest: action 0, bid lower aggressively)
```

This is `DenseNetwork.forward()` in the code. The network has about 4,800 parameters (weights and biases) that are learned through training.

## Training: How the Network Learns

Training works by repeatedly:

1. **Predict**: Run the network forward to get predicted Q-values for a state
2. **Compute target**: Using the Bellman equation, calculate what the Q-value *should* be
3. **Update**: Adjust the network's weights to make the prediction closer to the target

Concretely, for a transition `(state, action=2, reward=3.0, next_state)`:

```
predicted = network.forward(state)[2]          // what we predicted for action 2
target    = 3.0 + 0.99 × max(network.forward(next_state))  // what it should be
loss      = (predicted - target)²              // how wrong we were
```

Then backpropagation adjusts the weights to reduce the loss. This is `DenseNetwork.train()` — standard gradient descent.

Over thousands of updates, the network's Q-value predictions become accurate, and the agent's policy improves.

## Experience Replay: Learning from Memory

There's a problem with learning from transitions one at a time: consecutive experiences are highly correlated (state at 2:15pm is very similar to state at 2:30pm). Neural networks learn poorly from correlated data.

**Experience replay** solves this. Instead of learning from each transition immediately, the agent stores it in a buffer:

```
buffer = [(state₁, action₁, reward₁, next_state₁),
          (state₂, action₂, reward₂, next_state₂),
          ...
          (state₁₀₀₀₀, ...)]
```

Then, for each training step, it samples a random batch of 32 transitions from the buffer. This breaks the correlation — a batch might contain transitions from day 1, day 3, and day 7, from different budget levels and different times of day.

In the code, this is `ReplayBuffer` — a circular buffer with capacity 10,000. When full, new transitions overwrite the oldest ones. `buffer.sample(32, rng)` returns a random batch.

## Double DQN: Fixing Overestimation

Standard DQN has a subtle bug. When computing the target:

```
target = reward + γ × max(network.forward(next_state))
```

The same network both **selects** the best action (via `max`) and **evaluates** it. This causes systematic overestimation — the network tends to overvalue actions, especially early in training when predictions are noisy.

**Double DQN** fixes this by maintaining two networks:

- **Q-network**: Updated every training step. Used to **select** the best action.
- **Target network**: A delayed copy of the Q-network. Used to **evaluate** the selected action.

```
best_action = argmax(q_network.forward(next_state))     // Q-net picks
target = reward + γ × target_network.forward(next_state)[best_action]  // target-net evaluates
```

The target network is synced from the Q-network every 100 training steps (`targetNetwork.copyFrom(qNetwork)`). This decoupling reduces overestimation and makes training more stable.

This is lines 83-93 of `DQNAgent.trainStep()`.

## Exploration vs Exploitation

If the agent always picks the action with the highest Q-value, it might never discover that a different action is actually better. It could get stuck on a mediocre strategy.

**Epsilon-greedy** exploration solves this. With probability **ε (epsilon)**, the agent takes a random action instead of the best one:

```scala
if (rng.nextDouble() < epsilon)
  rng.nextInt(actionSize)    // explore: random action
else
  argMax(qNetwork.forward(state))  // exploit: best known action
```

Epsilon starts high (1.0 = fully random) and decays over time (0.995× per training step) to a floor of 0.05. This means:

- **Day 1**: Nearly all random — the agent is exploring
- **Day 3-5**: Mostly exploiting its learned policy, still 15-30% random
- **Day 8+**: 95% exploitation, 5% exploration — the agent is confident but still occasionally tries new things

The decay schedule means the agent explores aggressively when it knows nothing and gradually shifts to using what it's learned.

## Putting It All Together

Here's the complete cycle, as it runs inside each `CampaignEntity` actor:

### Every bid request (fast path)
```
bid_cpm = campaign.max_cpm × agent.bid_multiplier
```
The multiplier is just a cached number. No neural network involved. Sub-microsecond.

### Every impression
```
agent.record_impression(cpm)
agent.record_bid_opportunity(won=true)
```
Increments window counters. Also sub-microsecond.

### Every click
```
agent.record_click()
```
Increments window click counter.

### Every 15 minutes (slow path)
```
1. Build state vector from window metrics:
   [effective_cpm, ctr, win_rate, budget_remaining,
    time_remaining, spend_rate, impression_rate, cost_per_click]

2. If we have a previous state:
   a. reward = clicks - overspend_penalty
   b. Store (prev_state, prev_action, reward, state, done) in replay buffer
   c. Sample batch of 32 from buffer
   d. For each sample: compute Double DQN target, train network (SGD)

3. Select action: epsilon-greedy
4. Apply: bid_multiplier *= action_adjustment (e.g., 1.1×)
5. Clamp: bid_multiplier in [0.5, 2.0]
6. Reset window counters
```

### At day end
```
1. Store terminal transition (done=true) if we took any actions
2. Reset bid_multiplier to 1.0
3. Keep all network weights (the learned policy carries over)
```

### On entity restart
```
1. Restore network weights from persisted snapshot
2. Replay buffer is empty (ephemeral) — agent resumes with learned policy
   but needs to re-accumulate experience for training
```

## What the Agent Learns

Over several days, a well-performing agent learns patterns like:

- **Early in the day with full budget**: Bid aggressively (multiplier > 1.0) to capture high-quality impressions
- **Budget running low with time remaining**: Pull back (multiplier < 1.0) to stretch remaining budget
- **High CTR content**: Worth bidding up — clicks are the reward
- **Overspending**: Reduce bids before the penalty threshold (1.5× pace) is reached
- **End of day with leftover budget**: Bid up to use remaining budget productively

These aren't programmed rules. They emerge from the reward signal and thousands of training steps.

## Key Hyperparameters

| Parameter | Value | What it controls |
|-----------|-------|-----------------|
| γ (gamma) | 0.99 | How much future rewards matter (high = patient) |
| Learning rate | 0.001 | How fast the network updates (too high = unstable) |
| ε start | 1.0 | Initial exploration rate (fully random) |
| ε end | 0.05 | Minimum exploration (always try 5% random) |
| ε decay | 0.995 | How fast to shift from explore to exploit |
| Buffer size | 10,000 | How much experience to remember |
| Batch size | 32 | Transitions per training step |
| Target sync | 100 steps | How often target network copies Q-network |
| Hidden layers | [64, 64] | Network capacity (bigger = more complex policies) |
| Q-clip | ±100 | Prevents extreme Q-value estimates |
| Grad clip | ±5.0 | Prevents exploding gradients during training |

These are all in `DQNAgent.Config` and `BidOptimizationAgent.Config`.

## From Theory to Code

Now you can read the source directly:

| Concept | File | Key method |
|---------|------|-----------|
| Neural network (forward + backprop) | `DenseNetwork.scala` | `forward()`, `train()` |
| Experience replay buffer | `ReplayBuffer.scala` | `store()`, `sample()` |
| Double DQN + epsilon-greedy | `DQNAgent.scala` | `selectAction()`, `trainStep()` |
| State/reward/action design | `BidOptimizationAgent.scala` | `toState()`, `computeReward()`, `observe()` |
| Integration with campaign actor | `CampaignEntity.scala` | `RLObserveTick`, `TryReserve` |

The next chapters cover each of these components in detail with exact formulas and configuration values.
