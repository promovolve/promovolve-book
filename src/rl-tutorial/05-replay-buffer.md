# Experience Replay: Learning From the Past

Imagine you are learning to cook. If you only practiced the dish you made five minutes ago, you would get very good at that one recipe and completely forget everything else. Worse, if your last five dishes were all pasta (because you went on a pasta streak), you would start to think cooking *is* pasta. You need to flip back through your recipe journal at random -- revisiting last Tuesday's stir fry, last month's soup, yesterday's salad -- to become a well-rounded cook.

A DQN agent faces exactly this problem. This chapter introduces the **replay buffer**, a deceptively simple data structure that makes deep reinforcement learning work.

## The Problem With Learning Online

Without a replay buffer, the agent would train on each experience exactly once, in the order it happened. Two things go wrong:

**Catastrophic forgetting.** The agent trains on the most recent experiences, and the neural network's weights shift to fit them. Older lessons fade. If the agent spent the morning learning to conserve budget and the afternoon learning to bid aggressively, the afternoon training overwrites the morning's lessons.

**Correlated samples.** Consecutive experiences look almost identical. If the agent is overspending right now, the next five observations will all show a high spend rate, declining budget, and similar state vectors. Training on five near-identical examples in a row is like studying the same flashcard five times and calling it a productive session. The neural network overfits to the current situation instead of learning general patterns.

Both problems have the same fix: **store every experience, then sample randomly for training.**

## What Is a Transition?

Every time the agent makes a decision and observes the outcome, it produces one **transition** -- the complete record of a single decision:

| Field       | What It Means                              | Ad Bidding Example                                    |
|-------------|---------------------------------------------|-------------------------------------------------------|
| `state`     | What the world looked like                 | Budget 60% remaining, CTR 0.02, win rate 0.4          |
| `action`    | What the agent did                         | Action 4 = multiply bid by 1.1x (bid more aggressively) |
| `reward`    | What the agent got                         | 3 clicks, minus a small overspend penalty = 2.7       |
| `nextState` | What the world looked like afterward       | Budget 55% remaining, CTR 0.025, win rate 0.5         |
| `done`      | Is the episode over?                       | `false` (budget not exhausted, still time left in the day) |

A transition is a before-and-after snapshot of one decision. The agent stores thousands of these and trains on random handfuls at a time.

## The Full ReplayBuffer Code

Promovolve's replay buffer is only 64 lines. Here it is in its entirety:

```scala
package promovolve.rl

import scala.util.Random

/** Fixed-size circular experience replay buffer for DQN training.
  *
  * Stores (state, action, reward, nextState, done) transitions.
  * Supports uniform random sampling for mini-batch training.
  */
final class ReplayBuffer(val capacity: Int) {

  private val states     = new Array[Array[Double]](capacity)
  private val actions    = new Array[Int](capacity)
  private val rewards    = new Array[Double](capacity)
  private val nextStates = new Array[Array[Double]](capacity)
  private val dones      = new Array[Boolean](capacity)

  private var writeIdx    = 0
  private var currentSize = 0

  def size: Int = currentSize

  def store(
      state: Array[Double],
      action: Int,
      reward: Double,
      nextState: Array[Double],
      done: Boolean
  ): Unit = {
    states(writeIdx)     = state.clone()
    actions(writeIdx)    = action
    rewards(writeIdx)    = reward
    nextStates(writeIdx) = nextState.clone()
    dones(writeIdx)      = done
    writeIdx = (writeIdx + 1) % capacity
    if (currentSize < capacity) currentSize += 1
  }

  /** Sample a random mini-batch. */
  def sample(batchSize: Int, rng: Random): ReplayBuffer.Batch = {
    require(currentSize >= batchSize,
      s"Not enough experiences: $currentSize < $batchSize")
    val indices = Array.fill(batchSize)(rng.nextInt(currentSize))
    ReplayBuffer.Batch(
      states     = indices.map(states),
      actions    = indices.map(actions),
      rewards    = indices.map(rewards),
      nextStates = indices.map(nextStates),
      dones      = indices.map(dones)
    )
  }
}

object ReplayBuffer {

  final case class Batch(
      states: Array[Array[Double]],
      actions: Array[Int],
      rewards: Array[Double],
      nextStates: Array[Array[Double]],
      dones: Array[Boolean]
  ) {
    def size: Int = states.length
  }
}
```

Let's walk through each part.

### Storage: Five Parallel Arrays

```scala
private val states     = new Array[Array[Double]](capacity)
private val actions    = new Array[Int](capacity)
private val rewards    = new Array[Double](capacity)
private val nextStates = new Array[Array[Double]](capacity)
private val dones      = new Array[Boolean](capacity)
```

The buffer uses a **struct-of-arrays** layout rather than an array-of-structs. Instead of storing 10,000 `Transition` objects (each with five fields), it stores five arrays of 10,000 elements. This is a common pattern in performance-sensitive code -- it avoids object allocation overhead and keeps memory access patterns cache-friendly when iterating over a single field.

Each array holds one component of the transition tuple. Position `i` across all five arrays represents a single complete transition.

### The Circular Buffer

```scala
private var writeIdx    = 0
private var currentSize = 0
```

Two variables track the buffer's state:

- `writeIdx` -- where the *next* transition will be written.
- `currentSize` -- how many valid transitions are stored (capped at `capacity`).

When a new transition arrives:

```scala
writeIdx = (writeIdx + 1) % capacity
if (currentSize < capacity) currentSize += 1
```

The modulo operator (`% capacity`) is the key. When `writeIdx` reaches 10,000, it wraps around to 0 and starts overwriting the oldest transitions. This is the "circular" part -- the buffer is a ring, not a growing list.

Here is what happens as transitions arrive in a buffer with `capacity = 5`:

```
Store #1:  [T1, _,  _,  _,  _ ]   writeIdx=1, size=1
Store #2:  [T1, T2, _,  _,  _ ]   writeIdx=2, size=2
Store #5:  [T1, T2, T3, T4, T5]   writeIdx=0, size=5  (full!)
Store #6:  [T6, T2, T3, T4, T5]   writeIdx=1, size=5  (T1 overwritten)
Store #7:  [T6, T7, T3, T4, T5]   writeIdx=2, size=5  (T2 overwritten)
```

The oldest experience is always the one that gets replaced. No resizing, no shifting, no garbage collection pressure. Constant-time insertion, every time.

### Why Clone Arrays

Notice this line in `store`:

```scala
states(writeIdx) = state.clone()
nextStates(writeIdx) = nextState.clone()
```

Why `clone()`? Because arrays in Scala (and Java) are mutable reference types. The caller passes in a `state` array, but they might reuse that same array for the next observation -- overwriting its contents. Without cloning, the buffer would hold a reference to the caller's array, and every stored transition would silently change whenever the caller mutates it.

This is a subtle but critical correctness issue. The clone ensures that the buffer owns its own independent copy of every state vector.

### Uniform Random Sampling

```scala
val indices = Array.fill(batchSize)(rng.nextInt(currentSize))
```

When it is time to train, the buffer picks `batchSize` random indices (with replacement) and gathers the corresponding transitions:

```scala
ReplayBuffer.Batch(
  states     = indices.map(states),
  actions    = indices.map(actions),
  rewards    = indices.map(rewards),
  nextStates = indices.map(nextStates),
  dones      = indices.map(dones)
)
```

"With replacement" means the same transition could appear twice in one batch. In practice, with 10,000 stored transitions and a batch size of 32, duplicates are rare (about a 5% chance of any duplicate), and they do not cause problems.

### The Batch Case Class

```scala
final case class Batch(
    states: Array[Array[Double]],
    actions: Array[Int],
    rewards: Array[Double],
    nextStates: Array[Array[Double]],
    dones: Array[Boolean]
) {
  def size: Int = states.length
}
```

The `Batch` is just a container that holds the sampled transitions in array form, ready for the training loop to iterate over. Each index `i` across the five arrays is one complete transition.

## Why 10,000 Capacity?

From Promovolve's configuration:

```scala
bufferSize = 10_000
```

This is a tradeoff. Too small, and the agent forgets useful old experiences -- it might lose the lessons from a budget crisis two weeks ago. Too large, and the agent trains on stale data from a world that no longer exists (campaigns end, traffic patterns shift, competitors change their bids).

At 15-minute observation intervals with 96 observations per day, 10,000 transitions represent roughly **104 days** of experience. That is plenty of history to learn from, while still being recent enough to reflect the current advertising landscape.

The memory cost is modest. Each transition stores two 8-element `Double` arrays (state and nextState), one `Int`, one `Double`, and one `Boolean`. That comes out to about 150 bytes per transition, so the full buffer uses approximately 1.5 MB. Negligible on any modern server.

## Why Wait Until 32 Experiences?

```scala
minBufferSize = 32
```

The agent refuses to train until the buffer holds at least 32 transitions. Why?

If you trained on 3 experiences, the neural network would memorize those 3 examples perfectly and learn nothing general. It would be like studying for an exam by reading only three questions and assuming those are the only three questions that could possibly appear.

With 32 diverse experiences -- some from periods of overspending, some from underspending, some from high-CTR traffic, some from low -- the network sees enough variety to extract patterns rather than memorize specifics. The number 32 is also the batch size, which means the very first training step will sample every available experience at least once.

## Why Batch Size 32?

```scala
batchSize = 32
```

Each training step samples 32 random transitions from the buffer. Why not 1? Why not 1,000?

**Batch size 1** (online learning): each weight update is based on a single example. The gradient points in roughly the right direction but with enormous noise. Training is erratic -- the network lurches from one example to the next.

**Batch size 1,000**: the gradient is an average over 1,000 examples, so it is very smooth and stable. But each training step is 1,000 times more expensive, and in the early stages when the buffer is small, you would need 1,000 experiences before you could train at all.

**Batch size 32** is a common sweet spot. It averages out enough noise to give the optimizer a reliable gradient direction, while remaining cheap enough to run on every observation step. This value is so standard in deep learning that it is almost the "default" choice. Larger models on GPUs sometimes benefit from bigger batches, but for Promovolve's small 8-input, 2-hidden-layer network running on CPU, 32 is more than adequate.

## The Key Insight

By sampling randomly from a large buffer, the replay buffer **breaks the temporal correlation** between training examples.

Without replay:
```
Training step 1:  experience from 10:00am
Training step 2:  experience from 10:15am
Training step 3:  experience from 10:30am
Training step 4:  experience from 10:45am
```

All four experiences come from the same morning, with similar traffic, similar budget levels, similar everything. The network thinks the world always looks like late morning.

With replay:
```
Training step 1 (batch of 32):
  - experience from Monday 10:00am
  - experience from Friday 3:45pm
  - experience from Tuesday 8:15am
  - experience from Thursday 11:30pm
  - ... 28 more random picks
```

A Monday morning experience sits next to a Friday afternoon one. An experience where budget was nearly exhausted sits next to one where the day had just started. The network sees the full diversity of situations it might encounter, every single training step.

This is why experience replay was one of the key innovations that made DQN work in the original Atari paper (Mnih et al., 2015). Without it, the neural network is unstable. With it, training converges reliably. And as you have seen, the implementation is nothing more than a circular array and a random number generator.

---

Next chapter: we have a buffer full of experiences and a way to sample them. Now we need to compute the right training targets -- and avoid a subtle trap where the agent systematically overestimates how good its actions are.
