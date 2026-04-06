# Putting It Together: The FloorCpmOptimizationAgent

We have built every piece individually: a neural network that estimates Q-values, a replay buffer that stores experience, and a Double DQN training loop that learns from that experience. Now it is time to see how Promovolve wires them into a single, working floor CPM agent.

The class is `FloorCpmOptimizationAgent`, and it lives in `modules/core/src/main/scala/promovolve/rl/FloorCpmOptimizationAgent.scala`. We will walk through it top to bottom.

## The architecture

The nesting looks like this:

```text
FloorCpmOptimizationAgent          (one per campaign)
  └── DQNAgent
       ├── qNetwork           (DenseNetwork: 8 → 64 → 64 → 7)
       ├── targetNetwork      (DenseNetwork: 8 → 64 → 64 → 7, periodically synced)
       └── replayBuffer       (ReplayBuffer: capacity 10,000)
```

`FloorCpmOptimizationAgent` is the outer shell that knows about campaigns, budgets, and ad serving. It translates real-world campaign metrics into the abstract language of states, actions, and rewards that the inner `DQNAgent` understands. The `DQNAgent` in turn owns the two neural networks and the replay buffer we built in earlier chapters.

One line creates the entire inner stack:

```scala
private val dqn = DQNAgent(config.dqnConfig, rng)
```

Everything else in `FloorCpmOptimizationAgent` is bookkeeping: tracking window counters, computing states, computing rewards, and applying actions back to the floor price.

## Configuration

Here is the actual default configuration that Promovolve ships with:

```scala
final case class Config(
    dqnConfig: DQNAgent.Config = DQNAgent.Config(
      stateSize = 8,
      actionSize = 7,
      hiddenSizes = Vector(64, 64),
      gamma = 0.99,
      learningRate = 0.001,
      epsilonStart = 1.0,
      epsilonEnd = 0.05,
      epsilonDecay = 0.995,
      bufferSize = 10_000,
      minBufferSize = 32,
      batchSize = 32,
      targetSyncInterval = 100,
      actionMultipliers = Vector(0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.4)
    ),
    minMultiplier: Double = 0.5,
    maxMultiplier: Double = 2.0,
    overspendPenalty: Double = 2.0,
    exhaustionPenalty: Double = 5.0,
    inferenceOnly: Boolean = false
)
```

Let's unpack the important choices.

**7 actions, asymmetric.** The action multipliers are `[0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.4]`. Notice they are not symmetric around 1.0. There are more options for bidding up (1.1, 1.2, 1.4) than for bidding down (0.7, 0.8, 0.9), and the most aggressive upward option (1.4x) is a bigger jump than the most aggressive downward option (0.7x). This reflects a deliberate design choice: in a competitive auction, missing out on impressions is often worse than slightly overpaying. The agent can slam the brakes hard when it needs to (0.7x), but it also has a "turbo" option (1.4x) for when it is underspending and needs to catch up fast.

**Hard bounds: 0.5 to 2.0.** No matter what sequence of actions the agent takes, the cumulative floor price is clamped to this range. A campaign will never bid less than half its base CPM, and never more than double. This is a safety rail that prevents the RL agent from doing anything catastrophic.

**Discount factor (gamma = 0.99).** The agent values future rewards almost as much as immediate ones. This makes sense for daily budget pacing: you do not want an agent that burns through the budget in the first hour just because it got a few clicks early on.

**Exploration (epsilon: 1.0 to 0.05, decay 0.995).** The agent starts fully random and slowly shifts toward exploiting what it has learned. With a decay of 0.995 per training step, after 100 training steps epsilon is about 0.61, after 300 steps about 0.22, and after 600 steps about 0.05 (the floor). Each observation triggers at most one training step, and observations happen every 15 minutes, so reaching the floor takes roughly a week of continuous operation.

**Penalties.** `overspendPenalty = 2.0` and `exhaustionPenalty = 5.0` shape the reward signal to discourage burning through the budget too fast. We will see exactly how these work when we look at the reward function.

## Window counters

Between observations (every 15 minutes), the agent accumulates raw events:

```scala
def recordImpression(spendAmount: Double): Unit = {
  windowImpressions += 1
  windowSpend += spendAmount
  dayImpressions += 1
  daySpend += spendAmount
}

def recordClick(): Unit = {
  windowClicks += 1
  dayClicks += 1
}

def recordBidOpportunity(won: Boolean): Unit = {
  windowBidOpportunities += 1
  if (won) windowWins += 1
}
```

The `window*` counters track what happened since the last observation. The `day*` counters track the entire day for monitoring. The CampaignEntity calls these methods as impressions, clicks, and bid opportunities flow through the system. By the time `observe()` is called, the window counters contain a summary of the last 15 minutes of activity.

## The state: translating campaign metrics into numbers

The `toState` method converts an `Observation` plus the window counters into an 8-dimensional array that the neural network can process:

```scala
private def toState(obs: Observation): Array[Double] = {
  val maxCpm = if (obs.maxCpm > 0) obs.maxCpm else 1.0
  val dailyBudget = if (obs.dailyBudget > 0) obs.dailyBudget else 1.0

  Array(
    // 0: effective CPM (normalized)
    math.min(2.0, (obs.maxCpm * _bidMultiplier) / maxCpm),
    // 1: CTR in window
    if (windowImpressions > 0) math.min(1.0, windowClicks.toDouble / windowImpressions)
    else 0.0,
    // 2: win rate
    if (windowBidOpportunities > 0) windowWins.toDouble / windowBidOpportunities
    else 0.5,
    // 3: budget remaining fraction
    math.max(0.0, math.min(1.0, obs.budgetRemaining / dailyBudget)),
    // 4: time remaining fraction
    math.max(0.0, math.min(1.0, obs.timeRemaining)),
    // 5: spend rate vs ideal (1.0 = on pace)
    spendRate(obs),
    // 6: impression rate (normalized by expected)
    normalizedImpressionRate(obs),
    // 7: CPC (normalized)
    if (windowClicks > 0) math.min(2.0, (windowSpend / windowClicks) / maxCpm)
    else 0.0
  )
}
```

Each dimension is normalized to a small range (roughly 0 to 2) so the neural network can learn effectively. Here is what each one tells the agent:

| Index | Feature | What it means |
|-------|---------|---------------|
| 0 | Effective CPM | How much we are currently bidding, relative to the base price. Equals the floor price itself. |
| 1 | CTR | Click-through rate in the last 15 minutes. Higher is better. |
| 2 | Win rate | Fraction of auctions we won. Low means we are being outbid. |
| 3 | Budget remaining | How much money is left today (1.0 = full, 0.0 = empty). |
| 4 | Time remaining | How much of the day is left (1.0 = start, 0.0 = end). |
| 5 | Spend rate | Current spending speed vs. ideal even pace. 1.0 means on track, 2.0 means spending twice as fast as we should. |
| 6 | Impression rate | How many impressions we got, normalized by a baseline of 100 per window. |
| 7 | CPC | Cost per click, normalized by the base CPM. Lower is better. |

The `Observation` case class provides the campaign-level data that is not directly available from window counters:

```scala
final case class Observation(
    maxCpm: Double,         // Campaign's base max CPM (before multiplier)
    dailyBudget: Double,    // Total daily budget in dollars
    budgetRemaining: Double, // Remaining budget in dollars
    timeRemaining: Double,  // Fraction of delivery period remaining
    timestamp: Instant      // When this observation was taken
)
```

The spend rate calculation deserves a closer look:

```scala
private def spendRate(obs: Observation): Double = {
  if (obs.dailyBudget <= 0 || obs.timeRemaining >= 1.0) return 1.0
  val elapsed = 1.0 - obs.timeRemaining
  if (elapsed <= 0) return 1.0
  val expectedSpend = obs.dailyBudget * elapsed
  if (expectedSpend <= 0) return 1.0
  val actualSpend = obs.dailyBudget - obs.budgetRemaining
  math.min(3.0, actualSpend / expectedSpend) // cap at 3x overspend
}
```

If 40% of the day has passed and we have spent 40% of the budget, the spend rate is 1.0 -- perfectly on pace. If we have spent 60% of the budget in that same time, the rate is 1.5 -- we are overspending. This single number gives the agent a strong signal about whether it should bid more or less aggressively.

## The reward: what the agent optimizes for

```scala
private def computeReward(obs: Observation): Double = {
  val clickReward = windowClicks.toDouble

  val rate = spendRate(obs)
  val overspendPenalty =
    if (rate > 1.5) config.overspendPenalty * (rate - 1.5) else 0.0

  val exhaustionPenalty =
    if (obs.budgetRemaining <= 0 && obs.timeRemaining > 0.1)
      config.exhaustionPenalty
    else 0.0

  clickReward - overspendPenalty - exhaustionPenalty
}
```

The reward is simple: clicks minus penalties. The agent gets +1 for each click in the window. But two things reduce the reward:

1. **Overspend penalty.** If the spend rate exceeds 1.5x (spending 50% faster than ideal), a penalty kicks in proportional to how far over 1.5 it is. With `overspendPenalty = 2.0`, a spend rate of 2.5 costs a penalty of `2.0 * (2.5 - 1.5) = 2.0` -- equivalent to losing 2 clicks worth of reward.

2. **Exhaustion penalty.** If the budget hits zero while more than 10% of the day remains, a flat penalty of 5.0 is applied. Running out of budget at 3pm when ads should run until midnight is a serious failure; this penalty makes sure the agent learns to avoid it.

The combination encourages the agent to maximize clicks while spending at a sustainable pace throughout the day.

## The observation loop

Here is the core method, called every 15 minutes:

```scala
def observe(obs: Observation): (Double, Option[Double]) = {
  val state = toState(obs)

  // If we have a previous state, store the transition and learn
  val loss = prevState match {
    case Some(ps) =>
      val reward = computeReward(obs)
      dayRewardSum += reward
      val done = obs.budgetRemaining <= 0 || obs.timeRemaining <= 0
      dqn.store(ps, prevAction.get, reward, state, done)
      dqn.trainStep()

    case None => None
  }
  dayObservations += 1

  // Select next action
  val action =
    if (config.inferenceOnly) dqn.selectGreedy(state)
    else dqn.selectAction(state)

  // Apply action: adjust multiplier
  val adjustment = config.dqnConfig.multiplierForAction(action)
  _bidMultiplier = math.max(
    config.minMultiplier,
    math.min(config.maxMultiplier, _bidMultiplier * adjustment)
  )

  // Save state for next observation
  prevObservation = Some(obs)
  prevState = Some(state)
  prevAction = Some(action)

  // Reset window counters
  windowImpressions = 0
  windowClicks = 0
  windowSpend = 0.0
  windowBidOpportunities = 0
  windowWins = 0

  (_bidMultiplier, loss)
}
```

Let's trace through what happens on each call, step by step.

**Step 1: Convert observation to state.** The `toState` method combines the `Observation` with window counters to produce an 8-element array of normalized features.

**Step 2: Learn from the previous action.** If this is not the first observation, we now know the result of the action we chose last time. We compute the reward (clicks minus penalties), build a transition `(prevState, prevAction, reward, currentState, done)`, store it in the replay buffer, and run one training step. The `done` flag is true if the budget is exhausted or the day is over.

**Step 3: Choose the next action.** If we are in inference-only mode, pick the action with the highest Q-value. Otherwise, use epsilon-greedy: with probability epsilon pick a random action, otherwise pick the greedy best.

**Step 4: Apply the action.** Look up the chosen action's multiplier (e.g., action 4 maps to 1.1x), multiply it into the current floor price, and clamp the result to [0.5, 2.0].

**Step 5: Save state for next time.** Store the current state and action so that on the next observation we can compute the reward and build a transition.

**Step 6: Reset window counters.** Clear all the impression, click, spend, and bid opportunity counters so they are fresh for the next 15-minute window.

The method returns the new floor price and the training loss (if training happened). The CampaignEntity uses the floor price for all bid responses until the next observation.

## The cumulative multiplier

A subtle but important point: actions do not set the multiplier directly. They *scale* it. Each action is a relative adjustment to whatever the current multiplier is.

Here is a concrete example of how the multiplier evolves through a day:

| Observation | Action chosen | Multiplier before | Calculation | Result |
|-------------|--------------|-------------------|-------------|--------|
| 1 (9:00 AM) | 0.9x | 1.0 | 1.0 x 0.9 | 0.9 |
| 2 (9:15 AM) | 1.2x | 0.9 | 0.9 x 1.2 | 1.08 |
| 3 (9:30 AM) | 0.7x | 1.08 | 1.08 x 0.7 | 0.756 |
| 4 (9:45 AM) | 1.4x | 0.756 | 0.756 x 1.4 | 1.058 |
| 5 (10:00 AM) | 1.4x | 1.058 | 1.058 x 1.4 | 1.482 |
| 6 (10:15 AM) | 1.4x | 1.482 | 1.482 x 1.4 | **2.0** (clamped) |

Notice observation 6: the raw result would be 2.074, but it exceeds the maximum and is clamped to 2.0. The hard bounds always apply. This is the safety mechanism in code:

```scala
_bidMultiplier = math.max(
  config.minMultiplier,
  math.min(config.maxMultiplier, _bidMultiplier * adjustment)
)
```

This cumulative design means the agent can make large adjustments over several steps (0.7 x 0.7 = 0.49, clamped to 0.5) while each individual step is a moderate change. It also means the agent has to learn to "undo" previous decisions -- if it overbid in the morning, it needs to choose multipliers below 1.0 in the afternoon to bring the overall multiplier back down.

## Day stats for monitoring

The agent tracks cumulative daily metrics for monitoring dashboards:

```scala
def dayStats: FloorCpmOptimizationAgent.DayStats = FloorCpmOptimizationAgent.DayStats(
  impressions = dayImpressions,
  clicks = dayClicks,
  spend = daySpend,
  observations = dayObservations,
  totalReward = dayRewardSum
)
```

The `DayStats` case class also provides derived metrics:

```scala
final case class DayStats(
    impressions: Long,
    clicks: Long,
    spend: Double,
    observations: Int,
    totalReward: Double
) {
  def ctr: Double = if (impressions > 0) clicks.toDouble / impressions else 0.0
  def costPerClick: Double = if (clicks > 0) spend / clicks else 0.0
}
```

These numbers let operators see how the agent is performing day over day. Is it getting more clicks? Is the cost per click improving? Is the total reward trending upward? We will see in the next chapter how to use these across days to watch the learning curve.

## Recap

`FloorCpmOptimizationAgent` is a thin translation layer. It converts the messy real world -- impressions, clicks, budgets, time of day -- into the clean abstractions that DQN needs: fixed-size state vectors, discrete actions, and scalar rewards. The actual learning happens inside `DQNAgent`, which we built in earlier chapters.

The key design decisions are:

- **8-dimensional state** that captures everything the agent needs to know about current performance and remaining resources.
- **7 asymmetric actions** that give the agent fine-grained control over bid adjustments, with more aggressive options for bidding up.
- **Cumulative multiplier** with hard bounds, so the agent adjusts incrementally and cannot do anything catastrophic.
- **Click-based reward with pacing penalties**, so the agent learns to maximize performance while spending sustainably.
- **15-minute observation cycle**, slow enough to observe meaningful patterns and fast enough to react to changing conditions.

In the next chapter, we will see how this agent handles the realities of production: day boundaries, persistence across restarts, cold starts, and the fact that many agents are learning simultaneously in the same marketplace.
