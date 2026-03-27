# Reinforcement Learning from Scratch

This chapter teaches RL from zero, using Promovolve's bid optimization as the running example. By the end, you'll understand every line of `DQNAgent.scala` and `BidOptimizationAgent.scala`. No prior machine learning knowledge required.

---

## The Problem: Too Many Decisions, Too Little Time

Imagine you're managing a single advertising campaign. You have a daily budget of $100 and a maximum bid of $5 CPM (cost per thousand impressions). Every 15 minutes, you look at how things are going and decide: should I bid higher to win more auctions, or bid lower to conserve budget?

You could try to figure this out manually. But the ad marketplace is a living thing — competitors change their bids, user traffic surges and dips, some content drives more clicks than others. Any fixed rule you write today will be wrong tomorrow.

What you really want is a system that *learns* from experience, the same way a new employee gets better at their job over the first few weeks. That's reinforcement learning.

---

## The Setup: Agent, Environment, Reward

Every RL problem has the same three ingredients.

**The agent** is the decision-maker. In Promovolve, the agent is `BidOptimizationAgent` — the piece of code that decides how aggressively to bid. It's not an actor — it's a plain Scala object embedded inside the `CampaignEntity` actor, called synchronously during each observation.

**The environment** is everything the agent can't control: other advertisers' bids, how many users are browsing, what content they're viewing. The agent can observe the environment, but can't change it directly. It can only respond to it.

**The reward** is the signal that tells the agent how it's doing. After each decision, the environment hands back a single number: positive if things went well, negative if they didn't. The agent's entire goal is to maximize the total reward it collects over time.

That's it. Everything in this chapter is just machinery for making this loop work.

---

## Why Not Just Write Rules?

The first instinct is to hard-code the logic: "if budget is more than 60% remaining and it's past noon, bid higher." But rules like this break for a few reasons:

- You don't know the right thresholds in advance. Is 60% the right cutoff? Maybe it should be 55%, or 70%.
- The optimal rule depends on your competitors' behavior, which you can't see and which changes constantly.
- Traffic patterns vary by day, season, and content type.
- Different campaigns have different optimal strategies.

RL sidesteps all of this. Instead of writing rules, you define what "good" means (the reward), then let the agent figure out the rules on its own through trial and error.

---

## What the Agent Observes

Every 15 minutes, the agent looks at the world and builds a snapshot of the current situation. In Promovolve, that snapshot — called the **state** — contains eight numbers:

| Measurement | Example |
|---|---|
| Current effective CPM | $3.20 |
| Click-through rate this window | 0.03 (3%) |
| Bid win rate this window | 0.65 (65%) |
| Fraction of daily budget remaining | 0.70 (70%) |
| Fraction of day remaining | 0.50 (50%) |
| Current spend rate vs. ideal pace | 1.10 (10% ahead of pace) |
| Impression rate | 0.80 |
| Cost per click | $0.40 |

These eight numbers, taken together, describe the situation the agent is in. The same way a chess player looks at the board position before deciding their move, the agent looks at this state before deciding its action.

---

## What the Agent Can Do

Given a state, the agent picks one of seven actions:

| Action | Multiplier | Meaning |
|--------|-----------|---------|
| 0 | 0.7× | Bid much lower — conserve budget aggressively |
| 1 | 0.8× | Bid lower |
| 2 | 0.9× | Bid slightly lower |
| 3 | 1.0× | Hold steady |
| 4 | 1.1× | Bid slightly higher |
| 5 | 1.2× | Bid higher |
| 6 | 1.4× | Bid much higher — be aggressive |

The multiplier is applied cumulatively to the current bid level and clamped to [0.5, 2.0]. The agent can't change the market. It can only adjust how aggressively it bids, and observe what happens next.

---

## The Reward Signal

After each 15-minute window, the agent receives a reward. In Promovolve, it's calculated as:

```
pacingScore = max(0.1, 1.0 - |spendRate - 1.0|)
reward = clicks × pacingScore - exhaustionPenalty × timeRemaining
```

In plain language:

- **Clicks scaled by pacing quality.** When the campaign is perfectly on pace (spendRate = 1.0), every click counts fully. When overspending at 2×, each click is worth only 10%. When underspending at 0.5×, each click is worth 50%. Both directions are penalized — the agent can't game it by overbidding.
- **Budget exhaustion is penalized proportionally.** Running out of budget with 80% of the day left is 4× worse than running out with 20% left. This teaches the agent that early exhaustion wastes more potential clicks than late exhaustion.

This single formula is the only definition of "success" the agent ever gets. Everything it learns flows from this signal. If you change the reward function, the agent will learn a completely different strategy.

---

## Learning from Experience: The Core Idea

Here's the fundamental question: how does the agent learn *which action to take in which situation*?

The short answer is: by remembering what happened and adjusting its expectations.

Suppose the agent is at 70% budget with a high click-through rate, and it decides to bid higher. It wins more auctions, gets more clicks, and earns a good reward. Now it knows that "bid higher in this situation" was a profitable move.

But here's the subtlety: the agent doesn't just care about the immediate reward. It cares about the *total* reward it'll collect for the rest of the day. Bidding aggressively might earn a lot of clicks right now, but if it burns through the budget by 2pm, the rest of the day earns nothing — and the pacing penalty kicks in hard.

This is why RL cares about **sequences of decisions**, not just individual ones.

---

## Q-Values: Scoring Every Option

To reason about sequences, the agent uses a concept called a **Q-value**.

`Q(state, action)` is the agent's estimate of the answer to this question: *"If I'm in this situation and I take this action, then play optimally for the rest of the day — how much total reward will I collect?"*

For example:

| Action | Multiplier | Q-value |
|--------|-----------|---------|
| 0 | 0.7× | 7.3 |
| 1 | 0.8× | 9.1 |
| 2 | 0.9× | 10.0 |
| 3 | 1.0× | 11.2 |
| 4 | 1.1× | 12.5 |
| 5 | 1.2× | 11.8 |
| 6 | 1.4× | 9.4 |

Given these Q-values, the agent picks action 4 (bid slightly higher) — Q-value 12.5, the best estimated outcome. Notice that the most aggressive action (1.4×) has a lower Q-value than moderate ones — the agent has learned that overbidding hurts pacing.

The agent doesn't need to think about the future explicitly. It just looks up its Q-values and picks the highest one. All the long-term reasoning is baked into the Q-values themselves.

The hard part, of course, is having accurate Q-values in the first place. That's what training is for.

---

## The Bellman Equation: Where Q-Values Come From

How do Q-values get calculated? Through a beautifully simple observation called the **Bellman equation**.

Think of it this way: the value of an action equals two things added together:
1. The immediate reward you get right now
2. The best you can do from the next state onward

Written as a formula:

```
Q(state, action) = immediate_reward + γ × max Q(next_state, any_action)
```

The **γ (gamma)** is a number between 0 and 1 — in Promovolve, it's 0.99. It represents how much the agent values future rewards compared to immediate ones.

Why discount the future at all? Because a reward now is worth more than the same reward later — you might run out of budget before you get there. With γ = 0.99, a reward one step from now is worth 0.99 of a reward right now. A reward 100 steps from now is worth only 0.99^100 ≈ 0.37. The agent prefers results sooner.

The Bellman equation turns a hard problem (predict total future reward) into a tractable one: predict immediate reward, then bootstrap from the next state.

---

## The Approximation Problem

If states were a small, fixed set — like the 64 squares of a chessboard — you could store a Q-value table in memory. One row per state, one column per action.

But Promovolve's state is eight continuous numbers. Budget remaining can be 0.70, or 0.701, or 0.7001. There are infinitely many possible states. A table is out of the question.

This is where a **neural network** comes in — not because neural networks are magic, but because they're very good at one specific thing: learning a function from examples.

---

## Neural Networks: A Function Approximator

A neural network is just a mathematical function with a lot of adjustable dials.

You give it some numbers as input. It does a sequence of calculations. It produces some numbers as output. The dials — called **weights** — determine what those calculations are.

In Promovolve, the network looks like this:

```
Input: [0.7, 0.03, 0.65, 0.70, 0.50, 1.1, 0.8, 0.4]
  (8 numbers describing the current state)
         ↓
   [64 intermediate values]
         ↓
   [64 intermediate values]
         ↓
Output: [7.3, 9.1, 10.0, 11.2, 12.5, 11.8, 9.4]
  (Q-values for each of the 7 actions)
```

The intermediate layers exist to let the network learn non-obvious patterns. Maybe "high win rate AND low budget remaining" signals something that neither measurement reveals on its own. The intermediate layers give the network room to discover those combinations.

This is `DenseNetwork.forward()` in the code. The network has roughly 5,200 parameters total.

The key insight: this network **generalizes**. Once trained, it can produce reasonable Q-value estimates for states it has never seen before, by interpolating from similar states it has seen. That's the whole point of using a neural network instead of a lookup table.

---

## Training: Adjusting the Dials

Training is the process of adjusting the network's weights so that its Q-value estimates become accurate.

After every action the agent takes, it observes a **transition**:

```
(state, action, reward, next_state)
```

For example: "I was at state [0.7, 0.03, ...], I picked action 4 (bid higher slightly), I earned a reward of 2.7, and now I'm at state [0.65, 0.028, ...]."

From this transition, training works in three steps:

**1. Predict.** Run the current state through the network to get the predicted Q-value for the action taken.

**2. Calculate what it should be.** Using the Bellman equation:
```
target = 2.7 + 0.99 × (best Q-value from next state)
```

**3. Adjust.** The weights are nudged slightly so that the prediction moves closer to the target. If the prediction was 10.0 and the target is 12.5, every weight is adjusted a tiny amount in the direction that would have pushed the output toward 12.5.

This nudging process — called gradient descent — is what `DenseNetwork.train()` implements. Repeat this tens of thousands of times, and the network's estimates gradually converge toward accurate Q-values.

---

## Experience Replay: Breaking Correlation

There's a practical problem with learning from transitions one at a time.

The state at 2:15pm is very similar to the state at 2:30pm. The state at 2:30pm is similar to the state at 2:45pm. If the agent learns from each transition as it comes in, it ends up adjusting the weights based on a highly repetitive stream of near-identical situations. The weights get tuned specifically for the last hour and "forget" what they learned about other situations.

**Experience replay** fixes this with a simple trick: don't learn immediately. Instead, store each transition in a buffer:

```
buffer = [
  (state from day 1, action, reward, next_state),
  (state from day 3, action, reward, next_state),
  (state from day 1 again, different action, ...),
  ...
]
```

Then, for each training step, pull a random batch of 32 transitions from anywhere in the buffer. This batch might include a transition from this morning, one from three days ago, and one from a completely different budget level. The variety helps the network learn broadly, not just for the current moment.

In the code, this is `ReplayBuffer` — a circular buffer that holds up to 10,000 transitions. When full, new arrivals overwrite the oldest ones. `buffer.sample(32, rng)` pulls a random batch.

---

## Double DQN: Correcting a Bias

Standard DQN has a subtle flaw. Look at how the training target is calculated:

```
target = reward + γ × max(network.forward(next_state))
```

The `max` operation picks the best-looking action from the next state. But the estimates coming out of the network are noisy, especially early in training when the weights are barely tuned. When estimates are noisy, the highest one tends to be an overestimate — it happens to be high partly because it's genuinely good, and partly due to random noise in the current weight settings.

By always taking the `max`, the agent systematically overestimates Q-values. This makes the agent overconfident and can destabilize training. In ad bidding, this manifests as the agent thinking aggressive bidding is more rewarding than it actually is — leading to budget blowouts.

**Double DQN** fixes this by splitting the job between two separate networks:

- **Q-network**: The main network, updated after every training step.
- **Target network**: A copy of the Q-network, updated only every 100 steps.

Instead of using the same network to both *select* the best action and *evaluate* it, Double DQN separates these:

```
best_action = argmax(q_network.forward(next_state))   // Q-net selects
target = reward + γ × target_network.forward(next_state)[best_action]  // target-net evaluates
```

The target network is a stable reference point. Because it only updates every 100 steps, it doesn't chase its own tail. The Q-network learns against a slowly-moving target rather than a constantly shifting one.

This is implemented in lines 83–93 of `DQNAgent.trainStep()`.

---

## Exploration vs. Exploitation

If the agent always picks the action with the highest Q-value, it never discovers whether some other action might be even better. It could settle into a mediocre routine and never escape.

This tension — use what you know vs. try something new — is called the **explore/exploit tradeoff**. It's one of the fundamental problems in RL.

Promovolve solves it with **epsilon-greedy** exploration. The parameter ε (epsilon) is a probability:

```
if (rng.nextDouble() < epsilon)
  take a random action    // explore
else
  take the best-known action  // exploit
```

Epsilon starts at 1.0 (fully random) and decays multiplicatively by 0.995 after every training step, down to a floor of 0.05.

In practice this means:

- **Day 1**: Almost entirely random. The agent knows nothing and is gathering raw experience.
- **Days 3–5**: Mostly exploiting its learned policy, but still 15–30% random. The agent has useful knowledge but is still refining it.
- **Day 8+**: 95% exploitation, 5% exploration. The agent trusts what it's learned, but keeps a small random element to catch opportunities its current policy might be missing.

The decay schedule is deliberate: explore aggressively when ignorant, exploit confidently once informed.

---

## Putting It All Together

Here's the complete cycle as it runs inside each `CampaignEntity` actor.

### Every bid request (fast path)

```
bid_cpm = campaign.max_cpm × agent.bid_multiplier
```

The multiplier is just a cached number. No neural network computation happens here. This path is sub-microsecond.

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

Increments the window click counter.

### Every 15 minutes (slow path)

```
1. Build state vector from window metrics:
   [effective_cpm, ctr, win_rate, budget_remaining,
    time_remaining, spend_rate, impression_rate, cost_per_click]

2. If we have a previous state:
   a. Compute pacing-scaled reward
   b. Store (prev_state, prev_action, reward, state, done) in replay buffer
   c. Sample batch of 32 from buffer
   d. For each sample: compute Double DQN target, train network

3. Select action: epsilon-greedy (one of 7 multiplier adjustments)
4. Apply: bid_multiplier *= action_adjustment (e.g., 1.1×)
5. Clamp: bid_multiplier stays in [0.5, 2.0]
6. Reset window counters
```

### At day end

```
1. Store terminal transition (done=true)
2. Reset bid_multiplier to 1.0
3. Keep all network weights — the learned policy carries over to tomorrow
```

### On entity restart

```
1. Restore network weights from persisted snapshot
2. Replay buffer is empty — agent resumes with learned policy but needs
   to re-accumulate experience before it can train again
```

---

## What the Agent Actually Learns

After several days of operation, a well-trained agent discovers patterns like these — without ever being told they exist:

- **Early in the day with full budget**: Bid moderately to capture impressions while maintaining pace.
- **Budget running low with time remaining**: Pull back before the pacing score tanks the reward.
- **High click-through rate content**: Worth bidding up — clicks are the reward, and good pacing amplifies them.
- **Overspending**: The pacing score immediately reduces the value of every click — the agent learns to self-correct within one or two observations.
- **End of day with leftover budget**: Bid up to use remaining budget productively — underspending also reduces the pacing score.

None of these are programmed in. They emerge from the reward signal, through thousands of training steps.

---

## Key Hyperparameters

These are all found in `DQNAgent.Config` and `BidOptimizationAgent.Config`.

| Parameter | Value | What it does |
|---|---|---|
| γ (gamma) | 0.99 | How much future rewards matter. High = patient. |
| Learning rate | 0.001 | How aggressively to adjust weights per training step. |
| ε start | 1.0 | Initial exploration rate (fully random). |
| ε end | 0.05 | Minimum exploration (always 5% random). |
| ε decay | 0.995 | How fast to shift from explore to exploit. |
| Buffer size | 10,000 | How much experience to remember. |
| Batch size | 32 | Transitions pulled per training step. |
| Target sync | 100 steps | How often the target network copies the Q-network. |
| Hidden layers | [64, 64] | Size of intermediate layers in the network. |
| Actions | 7 | Multipliers: [0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.4] |
| Multiplier range | [0.5, 2.0] | Hard bounds on the cumulative bid multiplier. |
| Q-clip | ±100 | Prevents extreme Q-value estimates. |
| Grad clip | ±5.0 | Prevents catastrophically large weight adjustments. |

---

## From Theory to Code

| Concept | File | Key method |
|---|---|---|
| Neural network (forward + training) | `DenseNetwork.scala` | `forward()`, `train()` |
| Experience replay buffer | `ReplayBuffer.scala` | `store()`, `sample()` |
| Double DQN + epsilon-greedy | `DQNAgent.scala` | `selectAction()`, `trainStep()` |
| State / reward / action design | `BidOptimizationAgent.scala` | `toState()`, `computeReward()`, `observe()` |
| Integration with campaign actor | `CampaignEntity.scala` | `RLObserveTick`, `TryReserve` |

The next chapters cover each of these components in detail with exact formulas and configuration values.
