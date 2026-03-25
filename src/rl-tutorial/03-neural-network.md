# Building a Neural Network From Scratch

In Chapter 2, we explored how an agent learns Q-values -- estimates of how good each action is in a given state. We stored those Q-values in a table, one entry per state-action pair. That works when the world is small and discrete: a grid with a handful of squares, a game with a few dozen positions.

But Promovolve's bid optimization agent lives in a continuous world. Its state is a vector of 8 floating-point numbers -- CTR, win rate, budget remaining, spend rate, and more. Each of those can take on essentially infinite values. There is no table large enough to hold a Q-value for every possible combination of those 8 numbers.

We need a function that can take *any* 8-number state as input and produce a Q-value for each possible action. That function is a neural network.

## What a neural network does

Think of a neural network as a programmable formula. You feed in numbers on one side, and it produces numbers on the other. In between, it has thousands of adjustable knobs (called *weights* and *biases*) that determine exactly how the input maps to the output. Training the network means finding the right settings for all those knobs.

In Promovolve's case:

- **Input**: 8 numbers describing the campaign's current state (effective CPM, CTR, win rate, budget remaining, time remaining, spend rate, impression rate, cost per click)
- **Output**: 7 numbers, one per possible action (each action adjusts the bid multiplier: 0.7x, 0.8x, 0.9x, 1.0x, 1.1x, 1.2x, 1.4x)

The output number for each action is the network's estimate of the Q-value for that action. The agent picks the action with the highest Q-value.

## The architecture

Promovolve's network is defined with a single line:

```scala
val layerSizes = Vector(8, 64, 64, 7)
```

This describes four *layers* of neurons:

1. **Input layer (8 neurons)**: one for each state feature
2. **First hidden layer (64 neurons)**: an internal processing stage
3. **Second hidden layer (64 neurons)**: a second processing stage
4. **Output layer (7 neurons)**: one Q-value per action

The word "hidden" just means these layers are internal -- they are not directly visible as input or output. Their job is to discover useful intermediate representations.

How many adjustable knobs does this create? Between each pair of adjacent layers, every neuron in the first layer connects to every neuron in the next. Each connection has a weight, and each neuron in the receiving layer has a bias. So:

| Connection          | Weights     | Biases | Total |
|---------------------|-------------|--------|-------|
| Input to Hidden 1   | 8 x 64 = 512   | 64     | 576   |
| Hidden 1 to Hidden 2| 64 x 64 = 4,096 | 64     | 4,160 |
| Hidden 2 to Output  | 64 x 7 = 448   | 7      | 455   |
| **Total**           |             |        | **5,191** |

Roughly 5,000 parameters. The network will learn values for all of them.

## A concrete example: a tiny network

Before we look at the real code, let's walk through a network small enough to compute by hand. Suppose we have a 2-input, 3-hidden, 1-output network.

```
Input (2)  -->  Hidden (3, ReLU)  -->  Output (1, linear)
```

Say the weights and biases are:

**Layer 1 (input to hidden):**

| | input\_0 | input\_1 | bias |
|---|---------|---------|------|
| hidden\_0 | 0.5 | -0.3 | 0.1 |
| hidden\_1 | -0.2 | 0.8 | 0.0 |
| hidden\_2 | 0.4 | 0.4 | -0.5 |

**Layer 2 (hidden to output):**

| | hidden\_0 | hidden\_1 | hidden\_2 | bias |
|---|----------|----------|----------|------|
| output\_0 | 0.6 | -0.4 | 0.9 | 0.2 |

Now feed in the input `[1.0, 2.0]`.

**Step 1 -- hidden layer (before activation):**

```
hidden_0 = 0.5*1.0 + (-0.3)*2.0 + 0.1 = 0.5 - 0.6 + 0.1 = 0.0
hidden_1 = (-0.2)*1.0 + 0.8*2.0 + 0.0 = -0.2 + 1.6 + 0.0 = 1.4
hidden_2 = 0.4*1.0 + 0.4*2.0 + (-0.5) = 0.4 + 0.8 - 0.5 = 0.7
```

**Step 2 -- apply ReLU activation:**

ReLU means: if the value is negative, replace it with zero. Otherwise, keep it.

```
hidden_0 = max(0, 0.0)  = 0.0
hidden_1 = max(0, 1.4)  = 1.4
hidden_2 = max(0, 0.7)  = 0.7
```

**Step 3 -- output layer (linear, no ReLU):**

```
output_0 = 0.6*0.0 + (-0.4)*1.4 + 0.9*0.7 + 0.2
         = 0.0 - 0.56 + 0.63 + 0.2
         = 0.27
```

The network outputs `0.27`. If this were a Q-value, the agent would use it to decide whether this action is worth taking. The entire forward pass is just multiply, add, and clamp-to-zero, repeated layer by layer.

## Xavier initialization: starting with sensible weights

Before the network has learned anything, what should the initial weights be? If they are all zero, every neuron computes the same thing -- the network cannot learn. If they are huge random numbers, the signals explode through the layers. If they are tiny, the signals shrink to nothing.

Xavier initialization (also called He initialization for ReLU networks) picks random weights from a normal distribution scaled to the number of inputs each neuron receives:

```scala
val scale = math.sqrt(2.0 / fanIn)
Array.tabulate(fanOut) { _ =>
  Array.tabulate(fanIn) { _ => rng.nextGaussian() * scale }
}
```

`fanIn` is the number of inputs to the layer. For the first hidden layer in Promovolve's network, `fanIn = 8`, so `scale = sqrt(2/8) = 0.5`. Weights are drawn from a normal distribution with mean 0 and standard deviation 0.5.

Why does this work? Each neuron sums up `fanIn` weighted inputs. If each weight has variance `2/fanIn`, the sum has variance roughly 2 -- not too big, not too small. This keeps the signal magnitude stable as it passes through many layers. Without this, deep networks are extremely difficult to train: the signals either explode (and the weights diverge) or vanish (and the weights never update).

Biases start at zero:

```scala
private val biases: Array[Array[Double]] =
  Array.tabulate(numLayers) { l => Array.fill(layerSizes(l + 1))(0.0) }
```

## The forward pass: how the network computes output from input

Here is the actual `layerForward` method from Promovolve's `DenseNetwork.scala`:

```scala
private def layerForward(
    w: Array[Array[Double]],
    b: Array[Double],
    input: Array[Double],
    relu: Boolean
): Array[Double] = {
  val out = new Array[Double](w.length)
  var j = 0
  while (j < w.length) {
    var sum = b(j)
    val wj = w(j)
    var k = 0
    while (k < wj.length) {
      sum += wj(k) * input(k)
      k += 1
    }
    out(j) = if (relu && sum < 0.0) 0.0 else sum
    j += 1
  }
  out
}
```

For each neuron `j` in the output:

1. Start with the bias: `sum = b(j)`
2. For each input `k`, add `weight * input`: `sum += wj(k) * input(k)`
3. Apply ReLU if this is a hidden layer: if `sum < 0`, set it to `0`

The full forward pass chains this through all layers:

```scala
def forward(input: Array[Double]): Array[Double] = {
  var activation = input
  var l = 0
  while (l < numLayers) {
    activation = layerForward(weights(l), biases(l), activation,
                              relu = l < numLayers - 1)
    l += 1
  }
  activation
}
```

Notice `relu = l < numLayers - 1` -- every layer gets ReLU except the last one. The output layer is *linear* because Q-values can be negative, and ReLU would clamp them to zero.

## Why ReLU?

ReLU (Rectified Linear Unit) is the activation function `f(x) = max(0, x)`. It does one simple thing: it kills negative values.

Why not just use the raw weighted sum everywhere? Without a nonlinear activation, stacking multiple layers is pointless. A linear function of a linear function is still just a linear function -- you get no more expressive power from depth. ReLU introduces nonlinearity, which lets the network learn curved decision boundaries instead of just flat planes.

Why ReLU specifically? There are many activation functions (sigmoid, tanh, etc.), but ReLU is popular for practical reasons:

- **Cheap to compute**: just a comparison and possibly a zero assignment
- **Avoids vanishing gradients**: for positive inputs, the gradient is always 1.0. Sigmoid and tanh squash large values into a flat region where the gradient approaches zero, which can stall learning in deep networks.
- **Works well in practice**: decades of empirical evidence across many problem domains

## Backpropagation: teaching the network

Forward pass gives us an output. But how do we improve the weights so the output gets closer to what we want?

The idea is straightforward: measure how wrong the output is, then trace backward through the network to figure out which weights contributed most to the error, and nudge each weight in the direction that reduces the error.

### MSE loss: measuring how wrong we are

Promovolve uses **Mean Squared Error** (MSE):

```
loss = sum((output_i - target_i)^2) / n
```

If the network outputs `[0.3, -0.1, 0.5]` and the target is `[0.3, 0.2, 0.5]`, the loss is:

```
loss = ((0.3-0.3)^2 + (-0.1-0.2)^2 + (0.5-0.5)^2) / 3
     = (0 + 0.09 + 0) / 3
     = 0.03
```

### The chain rule: tracing blame backward

Backpropagation uses the chain rule from calculus. If you vaguely remember that from school, great -- if not, here is the intuition.

Imagine you are in a factory assembly line. The final product has a defect. You need to trace back through the line to find which stations caused the problem and by how much. Backpropagation does exactly this, but with math: it propagates the error signal backward through each layer, computing how much each weight contributed to the final error.

### The actual backprop code

Here is the `train` method from `DenseNetwork.scala`, with annotations:

```scala
def train(input: Array[Double], target: Array[Double], lr: Double): Double = {
  val activations = forwardFull(input)
  val output = activations(numLayers)
  val outputSize = output.length

  // MSE loss
  var loss = 0.0
  var i = 0
  while (i < outputSize) {
    val diff = output(i) - target(i)
    loss += diff * diff
    i += 1
  }
  loss /= outputSize
```

First, run the forward pass and save every layer's activations (we need them to compute gradients). Compute the MSE loss.

```scala
  // Output layer gradient: dL/dz = 2(output - target) / n, clipped
  var delta = new Array[Double](outputSize)
  i = 0
  while (i < outputSize) {
    delta(i) = math.max(-GradClip, math.min(GradClip,
      2.0 * (output(i) - target(i)) / outputSize))
    i += 1
  }
```

The **output gradient** tells us, for each output neuron, which direction and how much we need to adjust. The formula `2 * (output - target) / n` is the derivative of the MSE loss. If the output is too high, the gradient is positive, pushing the output down. If too low, the gradient is negative, pushing it up.

The gradient is clipped to the range `[-5.0, 5.0]` (`GradClip = 5.0`) to prevent extreme values from destabilizing training. This is called **gradient clipping**.

```scala
  // Backprop through layers (reverse order)
  var l = numLayers - 1
  while (l >= 0) {
    val act = activations(l)
    val w = weights(l)
    val b = biases(l)
    val nextDelta = if (l > 0) new Array[Double](w(0).length) else null

    var j = 0
    while (j < w.length) {
      // Update bias
      b(j) -= lr * delta(j)
      val wj = w(j)
      var k = 0
      while (k < wj.length) {
        // Accumulate gradient for previous layer
        if (nextDelta != null) {
          nextDelta(k) += delta(j) * wj(k)
        }
        // Update weight
        wj(k) -= lr * delta(j) * act(k)
        k += 1
      }
      j += 1
    }
```

This is the heart of backpropagation. For each layer, going from the output backward:

- **Bias update**: `b(j) -= lr * delta(j)` -- the bias moves in the opposite direction of the gradient, scaled by the learning rate.
- **Weight update**: `wj(k) -= lr * delta(j) * act(k)` -- each weight is updated proportionally to (a) how much the output needs to change (`delta(j)`) and (b) how active the input was (`act(k)`). If the input neuron was not active (zero), the weight does not change -- it did not contribute to the error.
- **Gradient propagation**: `nextDelta(k) += delta(j) * wj(k)` -- the error signal for the previous layer is the sum of all the deltas from this layer, weighted by the connections. This is the chain rule in action.

```scala
    // Apply ReLU derivative for hidden layers, with gradient clipping
    if (nextDelta != null) {
      val prevAct = activations(l)
      delta = new Array[Double](nextDelta.length)
      var k = 0
      while (k < nextDelta.length) {
        val g = if (prevAct(k) > 0.0) nextDelta(k) else 0.0
        delta(k) = math.max(-GradClip, math.min(GradClip, g))
        k += 1
      }
    }

    l -= 1
  }

  loss
}
```

The **ReLU derivative** is simple: if the neuron's activation was positive during the forward pass, the gradient passes through unchanged. If the activation was zero or negative, the gradient is killed -- set to zero. This makes intuitive sense: if a neuron did not fire (ReLU set it to zero), it did not contribute to the output, so adjusting its incoming weights would have no effect.

Again, gradient clipping is applied after the ReLU derivative, bounding each gradient to `[-5.0, 5.0]`.

### Walking through the example

Let's trace backpropagation through our tiny 2-3-1 network. Suppose:

- Input: `[1.0, 2.0]`
- Target: `[1.0]`
- Forward pass output: `0.27` (as we computed earlier)
- Learning rate: `0.1`

**Output gradient:**

```
delta_output = 2 * (0.27 - 1.0) / 1 = -1.46
```

The network output 0.27 but should have output 1.0. The negative gradient says "push the output higher."

**Update output layer weights and biases:**

Recall the hidden activations were `[0.0, 1.4, 0.7]`.

```
bias_0   -= 0.1 * (-1.46)       -->  bias increases by 0.146
w(0,0)   -= 0.1 * (-1.46) * 0.0 -->  no change (hidden_0 was zero)
w(0,1)   -= 0.1 * (-1.46) * 1.4 -->  weight increases by 0.2044
w(0,2)   -= 0.1 * (-1.46) * 0.7 -->  weight increases by 0.1022
```

Notice that `hidden_0` was zero (killed by ReLU), so its weight does not change. Only active neurons get their weights updated.

**Propagate gradient to hidden layer:**

```
nextDelta(0) = (-1.46) * 0.6  = -0.876
nextDelta(1) = (-1.46) * (-0.4) = 0.584
nextDelta(2) = (-1.46) * 0.9  = -1.314
```

**Apply ReLU derivative:**

```
hidden_0 activation was 0.0  -->  delta(0) = 0.0    (gradient dies)
hidden_1 activation was 1.4  -->  delta(1) = 0.584  (gradient passes)
hidden_2 activation was 0.7  -->  delta(2) = -1.314 (gradient passes)
```

Then the first layer's weights update using these deltas and the original input `[1.0, 2.0]`. The process is the same: `weight -= lr * delta * input`.

## Learning rate: the step size

The learning rate (`lr`) controls how much the weights change in each update. Promovolve uses `0.001`.

- **Too high** (e.g., 0.1): the weights overshoot the optimum and oscillate wildly, possibly diverging to infinity.
- **Too low** (e.g., 0.00001): the weights barely move and learning takes forever.
- **Just right** (e.g., 0.001): the weights converge smoothly toward good values.

There is no formula for the "right" learning rate -- it depends on the problem. 0.001 is a common starting point that works well across many domains.

## Target network sync: `copyFrom`

In DQN (covered in the next chapter), we maintain two copies of the network: a *Q-network* that is actively learning, and a *target network* that provides stable training targets. Periodically, we copy the Q-network's weights into the target network:

```scala
def copyFrom(other: DenseNetwork): Unit = {
  var l = 0
  while (l < numLayers) {
    var j = 0
    while (j < weights(l).length) {
      System.arraycopy(other.weights(l)(j), 0, weights(l)(j), 0,
                       weights(l)(j).length)
      j += 1
    }
    System.arraycopy(other.biases(l), 0, biases(l), 0, biases(l).length)
    l += 1
  }
}
```

This is a deep copy using `System.arraycopy` -- fast, element-by-element duplication of every weight and bias array. After this call, the target network is an exact clone of the Q-network, but subsequent training updates only affect the Q-network.

## Serialization: saving and restoring the network

A trained network is useless if it vanishes when the process restarts. Promovolve serializes the network by flattening all weights and biases into simple one-dimensional arrays:

```scala
def serialize(): DenseNetwork.Snapshot = {
  val flatWeights = weights.flatMap(_.flatMap(_.toSeq)).toArray
  val flatBiases = biases.flatMap(_.toSeq).toArray
  DenseNetwork.Snapshot(layerSizes, flatWeights, flatBiases)
}
```

The `Snapshot` case class holds three things: the layer sizes (so we know the architecture), the flat weight array, and the flat bias array. To restore, we create a new network with the same architecture and copy the weights back into the nested array structure:

```scala
def restore(snapshot: DenseNetwork.Snapshot): Unit = {
  require(snapshot.layerSizes == layerSizes, "Layer sizes mismatch")
  var wi = 0
  var l = 0
  while (l < numLayers) {
    var j = 0
    while (j < weights(l).length) {
      System.arraycopy(snapshot.weights, wi, weights(l)(j), 0,
                       weights(l)(j).length)
      wi += weights(l)(j).length
      j += 1
    }
    l += 1
  }
  // (similar loop for biases)
}
```

This is integrated with Pekko Persistence -- when the campaign entity takes a snapshot, the DQN agent's network weights are included and survive process restarts.

## Summary

A neural network is a learnable function made of layers of simple operations: multiply, add, and clamp-to-zero. Promovolve's `DenseNetwork` implements one in roughly 200 lines of pure Scala, with no external ML libraries:

- **Xavier initialization** keeps signals stable across layers
- **Forward pass** chains matrix multiplications with ReLU activations
- **Backpropagation** traces errors backward to compute weight updates
- **Gradient clipping** prevents numerical instability
- **Serialization** enables persistence across restarts

With this network in hand, we are ready to use it as a Q-value approximator. In the next chapter, we will combine it with experience replay and target networks to build a full Deep Q-Network.
