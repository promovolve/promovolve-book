# Training in Production: Episodes, Persistence, and Day Resets

Most RL tutorials end with a training loop and a plot of rising rewards. Real systems have to deal with everything that comes after: what happens at midnight? What happens when the server restarts? What happens on the first day when the agent knows nothing? This chapter covers the production concerns that tutorials usually skip.

## Episodes are days

In the textbook formulation, an RL episode is a sequence of states and actions that ends when the agent reaches a terminal state. In Promovolve, each delivery day is one episode. The agent starts the day with a bid multiplier of 1.0, makes observations every 15 minutes throughout the day, and the episode ends at midnight (or when the budget runs out, whichever comes first).

The `resetDay()` method handles the transition between episodes:

```scala
def resetDay(): Unit = {
  // Store terminal transition only if we have both a pending state AND a real action
  // (prevAction is None if observe() was never called this day — no transition to record)
  for {
    ps <- prevState
    pa <- prevAction
  } {
    val terminalState = Array.fill(config.dqnConfig.stateSize)(0.0)
    val terminalReward = windowClicks.toDouble
    dqn.store(ps, pa, terminalReward, terminalState, done = true)
  }

  _bidMultiplier = 1.0
  prevObservation = None
  prevState = None
  prevAction = None
  windowImpressions = 0
  windowClicks = 0
  windowSpend = 0.0
  windowBidOpportunities = 0
  windowWins = 0
  dayImpressions = 0
  dayClicks = 0
  daySpend = 0.0
  dayObservations = 0
  dayRewardSum = 0.0
}
```

There is a lot happening here, so let's break it down.

**The terminal transition.** The last observation of the day chose an action, but we never got to see the result during a normal `observe()` call. The `resetDay()` method closes this gap by storing one final transition: the last state and action, a reward based on whatever clicks accumulated in the final window, a zero-filled terminal state, and `done = true`. Without this, the agent would lose information about the end of every day -- which is often the most interesting part, since that is when budget exhaustion or underspend tends to show up.

The `for` comprehension guards against the case where `observe()` was never called during the day (perhaps the campaign was paused). In that case there is no pending state or action, so there is nothing to record.

**Reset the multiplier.** The bid multiplier goes back to 1.0. Each day starts fresh. The agent does not carry forward yesterday's multiplier because the market conditions, traffic patterns, and competitive landscape may be completely different today.

**Clear all counters.** Window counters, day counters, and the previous state/action references are all zeroed out.

**Keep the learned weights.** This is the crucial part: `resetDay()` does not touch the `DQNAgent`. The Q-network's weights, the target network's weights, the replay buffer's stored experiences, and the current epsilon -- all of these survive across days. The agent forgets what happened today in terms of raw counters, but it remembers everything it has learned about how to bid.

## Persistence: surviving restarts

The agent's learned weights must survive process restarts. A server crash or deployment should not erase weeks of learning. Promovolve handles this through snapshots.

`DQNAgent.snapshot()` captures the complete learnable state:

```scala
def snapshot(): DQNAgent.Snapshot =
  DQNAgent.Snapshot(
    config = config,
    qNetworkSnapshot = qNetwork.serialize(),
    targetNetworkSnapshot = targetNetwork.serialize(),
    epsilon = epsilon,
    totalSteps = totalSteps,
    trainSteps = trainSteps
  )
```

Each neural network serializes itself by flattening all weights and biases into one-dimensional arrays:

```scala
def serialize(): DenseNetwork.Snapshot = {
  val flatWeights = weights.flatMap(_.flatMap(_.toSeq)).toArray
  val flatBiases = biases.flatMap(_.toSeq).toArray
  DenseNetwork.Snapshot(layerSizes, flatWeights, flatBiases)
}
```

For our 8-64-64-7 network, that is `(8*64) + (64*64) + (64*7) = 512 + 4096 + 448 = 5,056` weight values plus `64 + 64 + 7 = 135` bias values. Two networks means about 10,382 floating-point numbers total. Stored as doubles, that is roughly 83 KB -- small enough to persist frequently without concern.

These snapshots are stored via Pekko's durable state mechanism, backed by PostgreSQL. On restart, `DQNAgent.fromSnapshot()` reconstructs the agent:

```scala
def fromSnapshot(snapshot: Snapshot, rng: Random): DQNAgent = {
  val agent = new DQNAgent(snapshot.config, rng)
  agent.restore(snapshot)
  agent
}
```

And `restore()` puts everything back:

```scala
def restore(snap: DQNAgent.Snapshot): Unit = {
  qNetwork.restore(snap.qNetworkSnapshot)
  targetNetwork.restore(snap.targetNetworkSnapshot)
  epsilon = snap.epsilon
  totalSteps = snap.totalSteps
  trainSteps = snap.trainSteps
}
```

**The replay buffer is not persisted.** This is a deliberate choice. The buffer holds up to 10,000 raw transitions -- serializing it would be much larger, and more importantly, it is not necessary. The neural network's weights already contain the distilled knowledge from all those transitions. After a restart, the buffer starts empty and refills naturally from new experience. Training resumes as soon as 32 new transitions accumulate (the `minBufferSize`), which takes about 8 hours at 15-minute intervals. In the meantime, the agent still makes decisions using its pre-restart weights -- it just does not learn from new data until the buffer has enough samples.

## Inference-only mode

Sometimes you want an agent that has trained enough and should just run its learned policy without further exploration. The `inferenceOnly` flag controls this:

```scala
val action =
  if (config.inferenceOnly) dqn.selectGreedy(state)
  else dqn.selectAction(state)
```

When `inferenceOnly` is true, the agent calls `selectGreedy()` instead of `selectAction()`. The difference is simple: `selectGreedy()` always picks the action with the highest Q-value, while `selectAction()` uses epsilon-greedy and will occasionally pick a random action.

```scala
def selectGreedy(state: Array[Double]): Int =
  argMax(qNetwork.forward(state))
```

In inference-only mode the agent still calls `observe()`, still records transitions, and still accumulates day stats. It just never explores. This is useful for campaigns where the advertiser wants predictable, stable behavior and the agent has already learned a good policy.

## The cold start problem

A brand new campaign has an agent with:

- **Random weights** (Xavier initialization). The Q-values it produces are essentially noise. It has no idea which actions are good.
- **Epsilon = 1.0.** Every action is chosen randomly. The agent never consults its Q-values.
- **Empty replay buffer.** Even if the agent wanted to train, there are no transitions to learn from.

This sounds bad, but it is actually fine. When you know nothing, random exploration is the right strategy. The agent will try different bid adjustments, observe the results, and start building up experience.

Here is the timeline for a new campaign:

**Hours 0-8 (observations 1-32).** The agent takes random actions and accumulates transitions. No training happens because the replay buffer has not reached its minimum size of 32. The bid multiplier bounces around randomly within the [0.5, 2.0] bounds. This is wasteful but unavoidable -- the agent needs data before it can learn.

**Hours 8-24 (observations 33-96).** Training begins. Each observation now triggers a training step: sample 32 transitions from the buffer, compute Double DQN targets, update the Q-network. Epsilon is still high (around 0.85 after 64 training steps), so most actions are still random, but the Q-values are starting to become meaningful.

**Days 2-7.** Epsilon drops from roughly 0.85 to about 0.05 over the course of the first week. The agent increasingly relies on its learned Q-values rather than random exploration. It starts to exhibit recognizable behavior: conserving budget when ahead of pace, bidding up when underspending, backing off when the win rate is already high.

**Week 2 and beyond.** Epsilon has hit its floor of 0.05. The agent is 95% exploitation, 5% exploration. It has developed a stable policy tuned to this campaign's traffic patterns, budget, and competitive environment. The 5% exploration ensures it can adapt if conditions change.

This is slow. It takes days of real data to produce a competent agent. This is one reason why Promovolve does not rely solely on RL for bid optimization. A separate PI (proportional-integral) pacing controller handles real-time delivery smoothing within each observation window. RL optimizes the overall bidding strategy over days; PI keeps delivery smooth within hours.

## Multiple agents, one marketplace

Every campaign in Promovolve has its own `BidOptimizationAgent`. If there are 50 active campaigns, there are 50 independent agents, each with its own Q-network, replay buffer, and epsilon schedule. They do not communicate with each other and have no knowledge of each other's existence.

This creates an interesting situation. From any one agent's perspective, the environment is non-stationary: the other 49 agents are also adjusting their bids, which changes auction dynamics, win rates, and effective prices. An action that worked well yesterday might work poorly today because a competitor raised its bids overnight.

Why does this work despite the non-stationarity? Several factors keep things stable:

**Small adjustments.** Each action changes the multiplier by a factor between 0.7 and 1.4. No single agent can dramatically shift the marketplace in one step.

**Slow updates.** Agents observe every 15 minutes. The marketplace has time to absorb changes before the next round of adjustments.

**Continuous learning.** Because epsilon never reaches zero (it floors at 0.05), agents always do some exploration and can adapt to changing conditions. If a competitor starts bidding aggressively, our agent will observe lower win rates and learn to adjust.

**PI pacing as a stabilizer.** The PI pacing controller handles fast reactions to marketplace changes within each 15-minute window. RL handles the slow, strategic adjustments. This separation of timescales prevents oscillation.

The result is a system where many learning agents coexist, each gradually converging on a good policy for its own campaign. It is not a Nash equilibrium in the game-theoretic sense, but it is stable enough for a real ad marketplace.

## What the agent actually learns over weeks

If you deploy a new campaign and watch the agent's behavior over time, here is roughly what you will see:

**Week 1: mostly random.** Epsilon is around 0.7 for most of the week. The agent makes many random bid adjustments. Day-over-day reward is noisy. The multiplier time series looks like a random walk with clamps. You might see the agent exhaust the budget early on some days and underspend on others.

**Week 2: starting to exploit.** Epsilon has dropped to around 0.3. The agent is choosing its learned policy 70% of the time. You can start to see patterns: the multiplier tends to decrease when budget consumption is ahead of pace, and increase when it is behind. The exhaustion penalty kicks in less often. Daily reward starts trending upward.

**Week 3-4: stable policy.** Epsilon reaches its floor of 0.05. The agent is 95% exploitation. It has learned the campaign's traffic pattern -- when impressions are plentiful, when they are scarce, how aggressive competitors are at different times of day. The multiplier follows a smooth daily pattern instead of bouncing randomly. Budget pacing is tight. Clicks per dollar are near optimal for the campaign's targeting and creative quality.

**Ongoing.** The agent continues to learn and adapt, but changes are incremental. The 5% exploration ensures it notices if traffic patterns shift (seasonal changes, new competitors, different creative rotation). Major changes in campaign configuration (new budget, new targeting) effectively create a new environment that the agent must partially relearn.

The key takeaway: RL is slow. It needs days of real data to produce results. This is fundamentally different from supervised learning, where you can train on a dataset in minutes. The agent must interact with the real marketplace, observe real outcomes, and learn from real consequences. There are no shortcuts.

## Monitoring: watching the learning curve

The `dayStats` method provides a daily summary for dashboards:

```scala
def dayStats: BidOptimizationAgent.DayStats = BidOptimizationAgent.DayStats(
  impressions = dayImpressions,
  clicks = dayClicks,
  spend = daySpend,
  observations = dayObservations,
  totalReward = dayRewardSum
)
```

By plotting these values across days, you can watch the agent learn:

- **Total reward** should trend upward over the first 1-2 weeks, then plateau. If it is flat from day one, the agent may not be training (check that `inferenceOnly` is false and that `observe()` is being called).
- **Clicks** should increase as the agent learns to bid more effectively.
- **CTR** (`clicks / impressions`) may increase if the agent learns to win auctions at better times of day when users are more engaged.
- **Cost per click** (`spend / clicks`) should decrease or stabilize as the agent gets better at bidding just enough to win without overpaying.
- **Observations** should be around 96 per day (24 hours x 4 observations per hour). Significantly fewer means the campaign is pausing or running out of budget.

For deeper debugging, `currentQValues` shows what the agent "thinks" about its current state:

```scala
def currentQValues: Option[Array[Double]] = prevState.map(dqn.qValues)
```

This returns the Q-value for each of the 7 actions given the most recent state. If the agent is well-trained, you should see clear differentiation: one or two actions with notably higher Q-values than the rest. If all Q-values are nearly identical, the agent has not yet learned to distinguish between actions -- it needs more training time.

You can also check `epsilon` to see where the agent is on its exploration schedule:

```scala
def epsilon: Double = dqn.currentEpsilon
```

If epsilon is still high (above 0.5), the agent is mostly exploring and you should not expect consistent behavior yet. If epsilon is at 0.05, the agent is running its learned policy and any erratic behavior is a sign that the policy itself needs more training data -- or that the environment has changed.

## Recap

Production RL is a different discipline from research RL. The core algorithm (Double DQN) is the same, but the engineering around it matters enormously:

- **Episodes map to days.** The terminal transition at day's end closes the learning loop. The multiplier resets; the weights persist.
- **Persistence is lightweight.** Two networks serialized to flat arrays, plus epsilon and step counts. About 83 KB per campaign. The replay buffer is not persisted because the network weights already encode what it learned.
- **Cold start is handled by design.** Random exploration with epsilon = 1.0 is the correct strategy when you know nothing. Training begins after about 8 hours of experience.
- **Multi-agent stability comes from slow, small adjustments.** Each agent learns independently, but the marketplace stays stable because changes are incremental and the PI pacing controller handles fast reactions.
- **Monitoring is essential.** Daily reward, clicks, CPC, and Q-value inspection let operators verify that learning is happening and catch problems early.

The RL agent is not a standalone system. It is one component in a larger architecture where PI pacing handles short-term delivery smoothing, Thompson Sampling handles creative selection at serve time, and the RL agent optimizes the overall bidding strategy over days and weeks. Each piece operates at a different timescale, and together they produce a system that is both responsive and adaptive.
