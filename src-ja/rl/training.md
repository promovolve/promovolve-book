# 学習ループとハイパーパラメータ

## ハイパーパラメータ（DQNAgent.scalaおよびBidOptimizationAgent.scalaより）

| Parameter | Default | Source |
|-----------|---------|--------|
| Hidden layers | `[64, 64]` | DQNAgent.Config |
| Learning rate | 0.001 | DQNAgent.Config |
| Gamma (discount) | 0.99 | DQNAgent.Config |
| Replay buffer size | 10,000 | DQNAgent.Config |
| Batch size | 32 | DQNAgent.Config |
| Min buffer size | 100 | DQNAgent.Config (最初の学習ステップの前) |
| Target sync interval | 100 steps | DQNAgent.Config |
| Epsilon start | 1.0 | DQNAgent.Config |
| Epsilon end | 0.05 | DQNAgent.Config |
| Epsilon decay | 0.995 | DQNAgent.Config |
| Q-value clip | [-100, 100] | DQNAgent.Config |
| Observation interval | 15 minutes | `promovolve.rl.observe-interval` |
| Day duration | 86400s | `promovolve.rl.day-duration-seconds` |

## 学習スケジュール

15分ごと（実際の1日あたり96回）：

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

Epsilonは各学習ステップ後に減衰します：

```scala
epsilon = max(epsilonEnd, epsilon × epsilonDecay)
```

### 減衰タイムライン（96ステップ/日）

```
Day 1:   ε ≈ 1.00  → 100% random (pure exploration)
Day 2:   ε ≈ 0.62  → 62% random
Day 3:   ε ≈ 0.38  → 38% random
Day 5:   ε ≈ 0.15  → 15% random
Day 8:   ε ≈ 0.05  → 5% random (hits floor)
Day 8+:  ε = 0.05  → 5% random (steady-state)
```

5%のフロアにより、変化する条件に適応するための継続的なexplorationが保証されます。

## Replay Buffer（ReplayBuffer.scala）

### 構造
```scala
private val states: Array[Array[Double]]
private val actions: Array[Int]
private val rewards: Array[Double]
private val nextStates: Array[Array[Double]]
private val dones: Array[Boolean]
```

### メカニズム
- **容量**：10,000遷移（96ステップ/日で約104日分）
- **循環バッファ**：`writeIdx = (writeIdx + 1) % capacity`
- **サンプリング**：一様ランダム（`indices.map(rng.nextInt(currentSize))`）
- **最小サイズ**：100遷移が保存された後にのみ学習が開始
- **優先度付けなし**：すべての遷移が等しい確率でサンプリングされる

### なぜ一様サンプリングなのか？
- State spaceが小さい（8次元） — ネットワークは一様サンプルから素早く学習する
- Prioritized Experience Replayは複雑さ（sum trees、importance sampling）を追加するが、利益は限定的
- 15分ウィンドウにより、すでに安定したノイズの少ない遷移が提供される

## 終端遷移

日のロールオーバー時：

```scala
if prevState exists:
    terminalState = Array.fill(stateSize)(0.0)  // zero vector
    terminalReward = windowClicks.toDouble
    dqn.store(prevState, prevAction, terminalReward, terminalState, done = true)
```

`done = true`フラグにより、日の境界を越えたQ-valueのブートストラップが防止されます：

```scala
if done:
    target = reward                          // no future rewards
else:
    target = reward + γ × Q(s', argmax Q(s'; θ); θ⁻)  // Double DQN
```

## 収束特性

- **1-3日目**：ほとんどランダム（ε > 0.38）、replay bufferを構築中、Q-networkが良い/悪いactionの区別を開始
- **4-7日目**：エージェントが基本的な方策を発展（予算が十分なときは入札を上げ、過剰消化時は下げる）
- **8日目以降**：εがフロア（0.05）に到達、方策が安定し5%の継続的なexploration
- **日跨ぎ**：重みは永続化されるが、multiplierは毎日1.0にリセット — エージェントは蓄積したQ-networkの知識を使って毎日最適な軌道を再学習する

## モニタリング

```scala
// Q-values for inspection
def qValues(state: Array[Double]): Array[Double] = qNetwork.forward(state)

// Day statistics
DayStats(impressions, clicks, spend, observations, totalReward)
```

`DQNAgent.Snapshot`を通じて利用可能：epsilon、totalSteps、trainSteps、ネットワークの重み。
