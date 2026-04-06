# Neural Networkをゼロから構築する

第2章では、agentがQ-value --- 与えられたstateで各actionがどれだけ良いかの推定値 --- をどのように学習するかを探りました。Q-valueをテーブルに保存しました。state-actionペアごとに1エントリです。世界が小さく離散的な場合にはこれで機能します: いくつかのマスしかないグリッド、数十のポジションしかないゲームなど。

しかし、Promovolveの入札最適化agentは連続的な世界に存在しています。そのstateは8個の浮動小数点数のベクトルです --- CTR、勝率、残り予算、支出レートなど。それぞれは本質的に無限の値を取ることができます。8個の数値のすべての可能な組み合わせに対するQ-valueを保持できるほど大きなテーブルは存在しません。

*任意の*8数値stateを入力として受け取り、各可能なactionに対するQ-valueを生成できる関数が必要です。その関数がneural networkです。

## Neural networkが行うこと

Neural networkをプログラム可能な数式と考えてください。片側から数値を入力すると、もう片側から数値が出力されます。その間には、入力が出力にどのようにマッピングされるかを決定する数千の調整可能なノブ（*weight*と*bias*と呼ばれます）があります。ネットワークのトレーニングとは、すべてのノブの正しい設定を見つけることです。

Promovolveの場合:

- **入力**: キャンペーンの現在のstateを記述する8個の数値（effective CPM、CTR、勝率、残り予算、残り時間、支出レート、impression rate、cost per click）
- **出力**: 7個の数値、可能なactionごとに1つ（各actionはfloor priceを調整: 0.7x、0.8x、0.9x、1.0x、1.1x、1.2x、1.4x）

各actionの出力数値は、そのactionに対するネットワークのQ-value推定値です。Agentは最も高いQ-valueを持つactionを選びます。

## アーキテクチャ

Promovolveのネットワークは1行で定義されています:

```scala
val layerSizes = Vector(8, 64, 64, 7)
```

これはニューロンの4つの*レイヤー*を記述しています:

1. **入力レイヤー（8ニューロン）**: 各state特徴量に1つ
2. **第1隠れレイヤー（64ニューロン）**: 内部処理段階
3. **第2隠れレイヤー（64ニューロン）**: 2番目の処理段階
4. **出力レイヤー（7ニューロン）**: actionごとに1つのQ-value

「隠れ」という言葉は単にこれらのレイヤーが内部的であることを意味します --- 入力や出力として直接見えません。その役割は有用な中間表現を発見することです。

調整可能なノブはいくつ作られるのでしょうか? 隣接するレイヤーの各ペア間で、最初のレイヤーのすべてのニューロンが次のレイヤーのすべてのニューロンに接続します。各接続にはweightがあり、受信側レイヤーの各ニューロンにはbiasがあります。したがって:

| 接続          | Weight     | Bias | 合計 |
|---------------------|-------------|--------|-------|
| Input to Hidden 1   | 8 x 64 = 512   | 64     | 576   |
| Hidden 1 to Hidden 2| 64 x 64 = 4,096 | 64     | 4,160 |
| Hidden 2 to Output  | 64 x 7 = 448   | 7      | 455   |
| **合計**           |             |        | **5,191** |

約5,000個のパラメータです。ネットワークはこれらすべての値を学習します。

## 具体例: 小さなネットワーク

実際のコードを見る前に、手計算できるほど小さなネットワークを見ていきましょう。2入力、3隠れ、1出力のネットワークを仮定します。

```
Input (2)  -->  Hidden (3, ReLU)  -->  Output (1, linear)
```

weightとbiasが以下のようになっているとします:

**レイヤー1（入力から隠れへ）:**

| | input\_0 | input\_1 | bias |
|---|---------|---------|------|
| hidden\_0 | 0.5 | -0.3 | 0.1 |
| hidden\_1 | -0.2 | 0.8 | 0.0 |
| hidden\_2 | 0.4 | 0.4 | -0.5 |

**レイヤー2（隠れから出力へ）:**

| | hidden\_0 | hidden\_1 | hidden\_2 | bias |
|---|----------|----------|----------|------|
| output\_0 | 0.6 | -0.4 | 0.9 | 0.2 |

入力`[1.0, 2.0]`を与えます。

**ステップ1 -- 隠れレイヤー（activation前）:**

```
hidden_0 = 0.5*1.0 + (-0.3)*2.0 + 0.1 = 0.5 - 0.6 + 0.1 = 0.0
hidden_1 = (-0.2)*1.0 + 0.8*2.0 + 0.0 = -0.2 + 1.6 + 0.0 = 1.4
hidden_2 = 0.4*1.0 + 0.4*2.0 + (-0.5) = 0.4 + 0.8 - 0.5 = 0.7
```

**ステップ2 -- ReLU activationの適用:**

ReLUの意味: 値が負の場合、ゼロに置き換える。それ以外はそのまま保持する。

```
hidden_0 = max(0, 0.0)  = 0.0
hidden_1 = max(0, 1.4)  = 1.4
hidden_2 = max(0, 0.7)  = 0.7
```

**ステップ3 -- 出力レイヤー（linear、ReLUなし）:**

```
output_0 = 0.6*0.0 + (-0.4)*1.4 + 0.9*0.7 + 0.2
         = 0.0 - 0.56 + 0.63 + 0.2
         = 0.27
```

ネットワークは`0.27`を出力します。これがQ-valueであれば、agentはこのactionを取る価値があるかどうかの判断に使います。forward pass全体は、乗算、加算、ゼロへのクランプを、レイヤーごとに繰り返すだけです。

## Xavier initialization: 適切なweightで始める

ネットワークが何も学習する前に、初期weightはどうあるべきでしょうか? すべてゼロだと、すべてのニューロンが同じ計算をし、ネットワークは学習できません。大きな乱数だと、信号がレイヤーを通じて爆発します。小さすぎると、信号が消滅します。

Xavier initialization（ReLUネットワークではHe initializationとも呼ばれます）は、各ニューロンが受け取る入力の数に応じてスケーリングされた正規分布からランダムなweightを選びます:

```scala
val scale = math.sqrt(2.0 / fanIn)
Array.tabulate(fanOut) { _ =>
  Array.tabulate(fanIn) { _ => rng.nextGaussian() * scale }
}
```

`fanIn`はレイヤーへの入力数です。Promovolveのネットワークの第1隠れレイヤーでは、`fanIn = 8`なので、`scale = sqrt(2/8) = 0.5`です。Weightは平均0、標準偏差0.5の正規分布から抽出されます。

なぜこれが機能するのか? 各ニューロンは`fanIn`個の重み付き入力を合計します。各weightが`2/fanIn`の分散を持つ場合、合計はおよそ2の分散を持ちます --- 大きすぎず、小さすぎません。これにより、信号の大きさが多くのレイヤーを通過しても安定します。これがないと、深いネットワークのトレーニングは極めて困難です: 信号が爆発する（weightが発散する）か、消滅する（weightが更新されない）かのどちらかです。

Biasはゼロで初期化されます:

```scala
private val biases: Array[Array[Double]] =
  Array.tabulate(numLayers) { l => Array.fill(layerSizes(l + 1))(0.0) }
```

## Forward pass: ネットワークが入力から出力を計算する方法

以下はPromovolveの`DenseNetwork.scala`の実際の`layerForward`メソッドです:

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

出力の各ニューロン`j`について:

1. biasから始める: `sum = b(j)`
2. 各入力`k`について、`weight * input`を加える: `sum += wj(k) * input(k)`
3. 隠れレイヤーの場合はReLUを適用: `sum < 0`なら`0`に設定

完全なforward passは、すべてのレイヤーを通じてこれを連鎖させます:

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

`relu = l < numLayers - 1`に注目してください --- 最後のレイヤー以外のすべてのレイヤーにReLUが適用されます。出力レイヤーは*linear*です。Q-valueは負になり得るため、ReLUだとゼロにクランプされてしまうからです。

## なぜReLUか?

ReLU (Rectified Linear Unit) はactivation関数`f(x) = max(0, x)`です。シンプルなことを1つ行います: 負の値を除去します。

なぜ生の重み付き和をどこでも使わないのでしょうか? 非線形なactivationがなければ、複数のレイヤーを積み重ねる意味がありません。線形関数の線形関数は依然として単なる線形関数です --- 深さから表現力の向上は得られません。ReLUは非線形性を導入し、ネットワークが平面だけでなく曲線的な決定境界を学習できるようにします。

なぜ特にReLUなのでしょうか? 多くのactivation関数（sigmoid、tanhなど）がありますが、ReLUは実用的な理由で人気です:

- **計算コストが低い**: 比較と場合によってはゼロの代入だけ
- **Vanishing gradientを回避する**: 正の入力に対してgradientは常に1.0。SigmoidやtanhはLarge valueを勾配がゼロに近づくフラットな領域に押し込み、深いネットワークで学習が停滞する可能性がある
- **実践でうまく機能する**: 多くの問題領域にわたる数十年の実証的証拠

## Backpropagation: ネットワークを教える

Forward passは出力を与えてくれます。しかし、出力が望む値に近づくようにweightを改善するにはどうすればよいのでしょうか?

アイデアは簡単です: 出力がどれだけ間違っているかを測定し、ネットワークを逆方向にたどって、どのweightが誤差に最も寄与したかを特定し、各weightを誤差が減る方向に少し動かします。

### MSE loss: どれだけ間違っているかを測定する

Promovolveは**Mean Squared Error** (MSE) を使用します:

```
loss = sum((output_i - target_i)^2) / n
```

ネットワークが`[0.3, -0.1, 0.5]`を出力し、ターゲットが`[0.3, 0.2, 0.5]`の場合、lossは:

```
loss = ((0.3-0.3)^2 + (-0.1-0.2)^2 + (0.5-0.5)^2) / 3
     = (0 + 0.09 + 0) / 3
     = 0.03
```

### Chain rule: 責任を逆方向にたどる

Backpropagationは微積分のchain ruleを使います。学校で何となく覚えているなら結構です --- そうでなければ、直感的な説明を示します。

工場の組立ラインにいると想像してください。最終製品に欠陥があります。ラインをたどって、どのステーションが問題を引き起こしたか、そしてどの程度かを見つける必要があります。Backpropagationはまさにこれを行いますが、数学を使って: 各レイヤーを通じてエラーシグナルを逆方向に伝播し、各weightが最終的なエラーにどれだけ寄与したかを計算します。

### 実際のbackpropコード

以下は`DenseNetwork.scala`の`train`メソッドです。注釈付きです:

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

まず、forward passを実行し、各レイヤーのactivationを保存します（gradientの計算に必要です）。MSE lossを計算します。

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

**出力gradient**は、各出力ニューロンについて、どの方向にどれだけ調整する必要があるかを示します。式`2 * (output - target) / n`はMSE lossの微分です。出力が高すぎる場合、gradientは正で、出力を下げます。低すぎる場合、gradientは負で、出力を上げます。

Gradientは`[-5.0, 5.0]`（`GradClip = 5.0`）の範囲にクリップされ、極端な値がトレーニングを不安定にするのを防ぎます。これが**gradient clipping**です。

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

これがbackpropagationの核心です。各レイヤーについて、出力から逆方向に:

- **Bias更新**: `b(j) -= lr * delta(j)` -- biasはgradientの反対方向に、learning rateでスケーリングされて移動します。
- **Weight更新**: `wj(k) -= lr * delta(j) * act(k)` -- 各weightは(a) 出力がどれだけ変化する必要があるか（`delta(j)`）と(b) 入力がどれだけ活性化していたか（`act(k)`）に比例して更新されます。入力ニューロンが活性化していなかった（ゼロ）場合、weightは変化しません --- エラーに寄与しなかったからです。
- **Gradient伝播**: `nextDelta(k) += delta(j) * wj(k)` -- 前のレイヤーのエラーシグナルは、このレイヤーからのすべてのdeltaを接続で重み付けした合計です。これがchain ruleの実際の動作です。

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

**ReLU微分**はシンプルです: forward pass中にニューロンのactivationが正だった場合、gradientはそのまま通過します。activationがゼロまたは負だった場合、gradientは消滅します --- ゼロに設定されます。これは直感的に理解できます: ニューロンが発火しなかった場合（ReLUがゼロに設定した場合）、出力に寄与しなかったため、その入力weightを調整しても効果がありません。

ここでもReLU微分の後にgradient clippingが適用され、各gradientは`[-5.0, 5.0]`に制限されます。

### 例を通じて追跡する

小さな2-3-1ネットワークでbackpropagationをたどってみましょう。仮定:

- 入力: `[1.0, 2.0]`
- ターゲット: `[1.0]`
- Forward pass出力: `0.27`（先ほど計算した通り）
- Learning rate: `0.1`

**出力gradient:**

```
delta_output = 2 * (0.27 - 1.0) / 1 = -1.46
```

ネットワークは0.27を出力しましたが、1.0を出力すべきでした。負のgradientは「出力をもっと高くせよ」と言っています。

**出力レイヤーのweightとbiasの更新:**

隠れレイヤーのactivationは`[0.0, 1.4, 0.7]`だったことを思い出してください。

```
bias_0   -= 0.1 * (-1.46)       -->  bias increases by 0.146
w(0,0)   -= 0.1 * (-1.46) * 0.0 -->  no change (hidden_0 was zero)
w(0,1)   -= 0.1 * (-1.46) * 1.4 -->  weight increases by 0.2044
w(0,2)   -= 0.1 * (-1.46) * 0.7 -->  weight increases by 0.1022
```

`hidden_0`がゼロだったことに注目してください（ReLUによって消されました）。そのため、そのweightは変化しません。活性化したニューロンのみがweight更新を受けます。

**隠れレイヤーへのgradient伝播:**

```
nextDelta(0) = (-1.46) * 0.6  = -0.876
nextDelta(1) = (-1.46) * (-0.4) = 0.584
nextDelta(2) = (-1.46) * 0.9  = -1.314
```

**ReLU微分の適用:**

```
hidden_0 activation was 0.0  -->  delta(0) = 0.0    (gradient dies)
hidden_1 activation was 1.4  -->  delta(1) = 0.584  (gradient passes)
hidden_2 activation was 0.7  -->  delta(2) = -1.314 (gradient passes)
```

次に、第1レイヤーのweightがこれらのdeltaと元の入力`[1.0, 2.0]`を使って更新されます。プロセスは同じです: `weight -= lr * delta * input`。

## Learning rate: ステップサイズ

Learning rate（`lr`）は、各更新でweightがどれだけ変化するかを制御します。Promovolveは`0.001`を使用しています。

- **高すぎる**（例: 0.1）: weightが最適値を通り越して激しく振動し、無限大に発散する可能性がある
- **低すぎる**（例: 0.00001）: weightがほとんど動かず、学習に永遠にかかる
- **ちょうど良い**（例: 0.001）: weightが良い値に向かってスムーズに収束する

「正しい」learning rateの公式はありません --- 問題に依存します。0.001は多くの領域でうまく機能する一般的な開始点です。

## Target networkの同期: `copyFrom`

DQN（次の章で扱います）では、ネットワークの2つのコピーを維持します: 積極的に学習する*Q-network*と、安定したトレーニングターゲットを提供する*target network*です。定期的に、Q-networkのweightをtarget networkにコピーします:

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

これは`System.arraycopy`を使ったdeep copyです --- すべてのweightとbias配列の高速な要素単位の複製です。この呼び出しの後、target networkはQ-networkの正確なクローンですが、それ以降のトレーニング更新はQ-networkにのみ影響します。

## シリアライゼーション: ネットワークの保存と復元

トレーニング済みのネットワークは、プロセスが再起動すると消えてしまっては意味がありません。Promovolveはすべてのweightとbiasをシンプルな1次元配列にフラット化してネットワークをシリアライズします:

```scala
def serialize(): DenseNetwork.Snapshot = {
  val flatWeights = weights.flatMap(_.flatMap(_.toSeq)).toArray
  val flatBiases = biases.flatMap(_.toSeq).toArray
  DenseNetwork.Snapshot(layerSizes, flatWeights, flatBiases)
}
```

`Snapshot` case classは3つのものを保持します: レイヤーサイズ（アーキテクチャがわかるように）、フラットなweight配列、フラットなbias配列。復元するには、同じアーキテクチャで新しいネットワークを作成し、weightをネストされた配列構造にコピーし戻します:

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

これはPekko Persistenceと統合されています --- キャンペーンエンティティがsnapshotを取得すると、DQN agentのネットワークweightが含まれ、プロセス再起動後も存続します。

## まとめ

Neural networkは、シンプルな操作のレイヤーで構成された学習可能な関数です: 乗算、加算、ゼロへのクランプ。Promovolveの`DenseNetwork`は、外部MLライブラリなしに約200行の純粋なScalaで実装されています:

- **Xavier initialization**がレイヤー間で信号を安定させる
- **Forward pass**が行列乗算をReLU activationと連鎖させる
- **Backpropagation**がエラーを逆方向にたどってweight更新を計算する
- **Gradient clipping**が数値的な不安定性を防ぐ
- **シリアライゼーション**が再起動をまたいだ永続化を可能にする

このネットワークを手に入れたことで、Q-value近似器として使う準備ができました。次の章では、experience replayとtarget networkを組み合わせて、完全なDeep Q-Networkを構築します。
