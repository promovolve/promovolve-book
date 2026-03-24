# Double DQN Architecture

Promovolve uses **Double DQN** (Van Hasselt et al., 2016) with a custom pure-Scala neural network implementation — no external ML framework dependencies.

## The Overestimation Problem

Standard DQN uses the same network to both select and evaluate the best action:

```
target = reward + γ × max_a Q(s', a; θ)
```

The `max` operator introduces positive bias: noisy Q-values get selected at their peaks, systematically overestimating. Over many updates, this compounds into over-optimistic Q-values and suboptimal policies (e.g., over-bidding).

## Double DQN Solution

Decouple selection from evaluation:

```
a* = argmax_a Q(s', a; θ)             ← Q-network selects action
target = reward + γ × Q(s', a*; θ⁻)    ← Target network evaluates it
```

Since θ and θ⁻ have different parameters, their noise is independent, breaking the correlation.

## Network Architecture (DenseNetwork.scala)

```
Input Layer:  8 neurons (state dimensions)
     │
Hidden Layer 1: 64 neurons, ReLU activation
     │
Hidden Layer 2: 64 neurons, ReLU activation
     │
Output Layer: 5 neurons (Q-value per action, linear)
```

Both Q-network and target network share this architecture.

### Weight Initialization
**Xavier initialization** with Gaussian sampling:
```
scale = sqrt(2.0 / fanIn)
weight = rng.nextGaussian() × scale
```

### Forward Pass
Sequential layer computation:
- Hidden layers: `output = ReLU(W × input + bias)` where `ReLU(x) = max(0, x)`
- Output layer: `output = W × input + bias` (linear, no activation)

### Backpropagation
Standard SGD with MSE loss:
```
loss = sum((output[i] - target[i])²) / outputSize
gradient_output: delta[i] = 2.0 × (output[i] - target[i]) / outputSize
gradient_hidden: delta[k] = if (activation[k] > 0) nextDelta[k] else 0 (ReLU derivative)
weight_update: w[j][k] -= learningRate × delta[j] × activation[k]
bias_update:   b[j] -= learningRate × delta[j]
```

Loss is applied only to the taken action (one-hot).

## Target Network Sync

```scala
if (trainSteps % targetSyncInterval == 0):
    targetNetwork.copyFrom(qNetwork)  // Full weight copy via System.arraycopy
```

Initial sync on agent creation ensures both networks start identical.

## Q-Value Clipping

```scala
target[action] = clamp(-qClip, qClip, target[action])
```

Default `qClip = 100.0`. Safety measure against divergence during early training.

## Why Pure Scala?

The DQN implementation doesn't depend on TensorFlow, PyTorch, or DL4J:
- **Deployment simplicity**: No native library dependencies, runs on any JVM
- **Integration**: Lives inside the Pekko actor system, no inter-process communication
- **Scale**: The network is tiny (8→64→64→5 = ~4,800 parameters) — framework overhead would dominate
- **Persistence**: Weights serialize as `Array[Double]`, stored in Pekko's durable state alongside campaign data
