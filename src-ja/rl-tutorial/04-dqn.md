# Q-tableからDeep Q-Networkへ

前の章では、2つのことを学びました。Q-valueはエージェントに各stateでの各actionの良さを伝えること、そしてニューラルネットワークが連続的な入力に対する関数を近似できることです。ここでこの2つを組み合わせます。

この章では、Promovolveの`DQNAgent.scala`に実装されているDeep Q-Network (DQN)アルゴリズムを扱います。最後まで読めば、エージェントが生の経験から広告入札を調整する方法を学ぶ仕組みと、target network、experience replay、epsilon decayといった一見任意に見える設計上の選択がそれぞれ特定の問題を解決している理由を理解できるようになります。

## Q-value: actionの価値

Q-value（Q(state, action)と表記）は、次の正確な質問に答えます: 「このstateにいて、このactionを取り、そこから先は最適に行動した場合、どれだけの合計rewardが期待できるか？」

Promovolveの広告入札システムでは、stateはキャンペーンの現在の状況を表します（8つの数値: 実効CPM、CTR、勝率、予算残高、残り時間、消化レート、インプレッションレート、クリック単価）。actionは7つの入札倍率調整（0.7倍から1.4倍）です。したがって、Q(state, action=3)は「キャンペーンの現在の指標を考慮して、入札を1.0倍のまま維持し、残りの1日を最適に行動した場合、何クリック得られるか？」を意味します。

エージェントの方策はシンプルです: 常にQ-valueが最も高いactionを選びます。Q-valueが正確であれば、これが最適な行動になります。

## Q-table: ここでは機能しない理由

小さな離散的な世界（例えば10個のstateと5個のaction）では、Q-valueを2次元のテーブルに格納できます:

| State | A0  | A1  | A2  | A3  | A4  |
|-------|-----|-----|-----|-----|-----|
| S0    | 0.2 | 0.5 | 0.1 | 0.3 | 0.0 |
| S1    | 0.4 | 0.1 | 0.6 | 0.2 | 0.8 |
| ...   | ... | ... | ... | ... | ... |

10個のstateと5個のactionの場合、テーブルには50個のエントリがあります。エージェントがstate `s`でaction `a`を取り、reward `r`を受け取り、state `s'`に遷移するたびに、以下の式を使ってエントリを更新します:

```
Q(s,a) <- Q(s,a) + alpha * [reward + gamma * max_a' Q(s',a') - Q(s,a)]
```

括弧内の項は**TD error**で、エージェントが期待した値と実際に観測した値の差です。学習率alphaは調整量を制御します。すべてのstate-actionペアに十分な回数訪問すれば、値は真のQ-valueに収束し、エージェントは最適に行動します。

しかし、Promovolveのstate空間には8つの連続次元があります。CTRの0.031と0.032は異なります。予算残高の0.7234と0.7235も異なります。可能なstateの数は事実上無限です。どんなテーブルもそれらすべてを保持できませんし、仮にできたとしても、エージェントはほとんどのstateを2回訪問することがないため、値は収束しません。

*汎化*する関数が必要です: ネットワークがこれまで見たことのないstateに対しても、過去に見た類似のstateから補間して妥当なQ-valueを生成できるものです。これはまさにニューラルネットワークが行うことです。

## DQNのアイデア

DeepMindの2015年の論文（Mnih et al., "Human-level control through deep reinforcement learning"）の核心的な洞察は明快です: Q-tableをニューラルネットワークで置き換えるというものです。

- **入力**: state vector（8つの数値）
- **出力**: 各actionに対するQ-value（7つの数値）
- **アーキテクチャ**: 第3章の`DenseNetwork` -- Input(8) -> Hidden(64, ReLU) -> Hidden(64, ReLU) -> Output(7, linear)

actionを選択するには、forward passを実行して最も高い値の出力を選びます:

```scala
def selectGreedy(state: Array[Double]): Int =
  argMax(qNetwork.forward(state))
```

`argMax`は最大要素のインデックスを返します:

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

Q-networkが`[1.2, 0.8, 2.1, 3.0, 1.5, 0.9, 2.3]`を出力した場合、エージェントはaction 3（Q-value 3.0、1.0倍の倍率 -- 現在の入札を維持）を選択します。

十分にシンプルです。しかし、2つの問題がすぐに生じます: このネットワークをどう訓練するか、そしてエージェントが良い戦略を発見するのに十分な探索を行うようにどう保証するかです。

## Epsilon-greedy探索

エージェントが常にQ-valueの最も高いactionを選ぶと、新しいことを試すことがありません。学習の初期段階では、Q-valueは本質的にランダムです（ネットワークはランダムな重みで初期化されたばかりです）。エージェントがたまたま最も良く見えたランダムなactionに固執すると、別のactionの方が良い結果をもたらすかもしれないことを発見できません。

これが**探索と活用のトレードオフ**です。活用とは現在の最良の知識を使うことです。探索とは、より良いものを見つける可能性のある新しいことを試すことです。優れたエージェントには両方が必要です。

Promovolveは**epsilon-greedy**探索を使用します: 確率epsilonでランダムなactionを選び、それ以外の場合は最良と分かっているactionを選びます。

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

重要なのは、epsilonが時間とともに変化することです:

- **開始時**: epsilon = 1.0（すべてのactionがランダム -- 純粋な探索）
- **各訓練ステップ**: epsilon *= 0.995（徐々に活用へシフト）
- **下限**: epsilon = 0.05（常に5%の探索を維持）

```scala
// Decay epsilon
epsilon = math.max(config.epsilonEnd, epsilon * config.epsilonDecay)
```

なぜ完全にランダムから始めるのでしょうか？初期のQ-valueは無意味だからです。でたらめな値に基づいてgreedyに行動すると、任意の戦略を強化するだけで時間の無駄です。まず広く探索し、多様な経験を収集し、ネットワークにそのすべてから学ばせる方がよいのです。

なぜ5%の下限を維持するのでしょうか？環境が変化する可能性があるからです。広告入札では、競争のダイナミクスは一日を通して変化します。午前9時に最適だった戦略が午後3時には最適でないかもしれません。少量の継続的な探索により、エージェントはこれらの変化を検出し、適応できます。

なぜもっと探索しないのでしょうか？探索的なactionはすべて、潜在的に無駄な入札です -- エージェントは「最適でない」と分かっていることを試します。探索が多すぎると、キャンペーンの予算を悪い入札に浪費します。1.0から0.05への緩やかな減衰はこのバランスを取ります: 無知なときは大量に探索し、知識が向上するにつれて活用を増やします。

## Bellman equation: Q-valueがあるべき値

Q-networkに正確なQ-valueを出力させたいのですが、「正確」とは何を意味するのでしょうか？あるstateとactionに対する*正しい*Q-valueとは何でしょうか？

**Bellman equation**がその答えを提供します:

```
Q(s, a) = reward + gamma * max_a' Q(s', a')
```

言葉で言えば: state `s`でaction `a`を取ることの価値は、得られる即時のrewardに、次のstate `s'`での最良のactionの割引された価値を加えたものです。

広告入札の例で具体的に見てみましょう。エージェントがstate `s`（予算残り60%、時間残り50%、CTR 0.03）にいるとします。action `a` = 「1.2倍で入札」を取ります。次の観測ウィンドウで3クリック（reward = 3.0）を得て、state `s'`（予算残り55%、時間残り45%、CTR 0.035）に遷移します。割引率gammaは0.99です。

Bellman equationは次のように述べます:

```
Q(s, bid_1.2x) = 3.0 + 0.99 * max_a' Q(s', a')
```

state `s'`での最良のQ-valueが15.0なら、目標Q-valueは`3.0 + 0.99 * 15.0 = 17.85`です。

**割引率** gamma = 0.99は、エージェントが将来のrewardをほぼ即時のrewardと同じくらい重視することを意味します。gammaが0なら、エージェントは完全に近視眼的になり、次のウィンドウのクリックだけを気にします。gammaが1なら、すべての将来のrewardを等しく重み付けしますが、数値的に不安定になり得ます。0.99は実用的な中間点です: エージェントは先を見据えますが、より早いrewardをわずかに好みます。

## 訓練ループ

すべてのピースが揃いました。Promovolveの`DQNAgent.trainStep()`がそれらをどのように組み合わせるかを見てみましょう:

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

ステップごとに見ていきましょう。

### ステップ1: 十分な経験を待つ

```scala
if (replayBuffer.size < config.minBufferSize) return None
```

エージェントは、replay bufferに少なくとも`minBufferSize`（32）個のtransitionが蓄積されるまで訓練を開始しません。これにより、訓練batchに十分な多様性が確保されます。

### ステップ2: batchをサンプリング

```scala
val batch = replayBuffer.sample(config.batchSize, rng)
```

replay bufferから32個のtransitionをランダムにサンプリングします。各transitionは(state, action, reward, nextState, done)のタプルです。replay bufferについては次の章で詳しく扱います -- 今のところ、過去の経験の大きな袋からランダムに取り出すものと考えてください。

### ステップ3: 目標Q-valueを計算

batchの各transitionについて:

```scala
val currentQ = qNetwork.forward(state)
val target = currentQ.clone()
```

まず、そのstateに対する現在のQ-valueを取得します。それをtarget配列にクローンします。実際に取られたactionのQ-valueのみを変更し、他の値はそのままにします。これにより、取らなかったactionに対してネットワークは勾配ゼロを受け取ります。

episodeが終了している場合（予算が尽きた、または時間が切れた）:

```scala
if (done) {
  target(action) = reward
}
```

将来がないので、Q-valueは即時のrewardそのものです。

それ以外の場合は、Bellman equationを適用します:

```scala
val nextQOnline = qNetwork.forward(nextState)
val bestNextAction = argMax(nextQOnline)
val nextQTarget = targetNetwork.forward(nextState)
target(action) = reward + config.gamma * nextQTarget(bestNextAction)
```

これは**Double DQN**のバリアント（Van Hasselt et al., 2016）です。標準DQNはtarget networkを最良の次のactionの選択と評価の両方に使用しますが、これはQ-valueを過大評価する傾向があります。Double DQNはこれらを分離します: Q-networkが最良のactionを選び、target networkがそのactionの実際の良さを評価します。この小さな変更により、overestimationバイアスが大幅に軽減されます。

目標値は暴走を防ぐために`[-100, 100]`にクリップされます:

```scala
target(action) = math.max(-config.qClip, math.min(config.qClip,
                          target(action)))
```

### ステップ4: Q-networkを訓練

```scala
totalLoss += qNetwork.train(state, target, config.learningRate)
```

これは第3章の`DenseNetwork.train()`メソッドを呼び出します。forward passを実行し、ネットワークの現在の出力と目標値の間のMSE lossを計算し、backpropagationで重みを更新します。学習率は0.001です。

### ステップ5: epsilonを減衰

```scala
epsilon = math.max(config.epsilonEnd, epsilon * config.epsilonDecay)
```

各訓練ステップ後、探索率を0.995倍します。これにより、エージェントは探索から活用へ徐々にシフトします。

この減衰はどのくらいの速さでしょうか？100訓練ステップ後: `1.0 * 0.995^100 = 0.606`。500ステップ後: `0.995^500 = 0.082`。約600ステップ後、epsilonは0.05の下限に達し、そこにとどまります。実際には、エージェントは最初の数百の観測ウィンドウの間は大量に探索し、その後は学んだことをほぼ活用するようになります。

### ステップ6: target networkを同期

```scala
if (trainSteps % config.targetSyncInterval == 0) {
  targetNetwork.copyFrom(qNetwork)
}
```

100訓練ステップごとに、Q-networkのすべての重みをtarget networkにコピーします。同期と同期の間、target networkは凍結されており、訓練のための安定した目標を提供します。

## 不安定性の問題

ここにDQNの根本的な課題があり、先ほど導入した2つの仕組み（target networkとexperience replay）が必要な理由です。

教師あり学習モデルを訓練するとき、訓練目標は固定されています。猫と犬の画像を分類する場合、「猫」というラベルはモデルの学習に伴って変化しません。モデルは静止した目標を狙っています。

DQNでは、目標は*ネットワーク自体から計算されます*:

```
target = reward + gamma * max_a' Q_target(s', a')
```

Q-networkが改善するにつれて、目標値が変化します。これは動く的を狙うようなものです -- 近づくたびに的がずれます。これにより激しい振動が起こり得ます: ネットワークが一方向に行き過ぎると目標値が変わり、それが反対方向への過剰補正を引き起こし、というように続きます。

2つの仕組みがこれを安定させます:

1. **Target network**: Q-networkのコピーを凍結し、100ステップごとにのみ更新することで、訓練期間中の目標値が安定します。的は動きますが、連続的にではなく離散的なジャンプで動くため、Q-networkが各目標セットに向かって収束する時間が得られます。

2. **Experience replay**（次の章で扱います）: 最新のtransitionだけで訓練するのではなく、エージェントは過去のすべての経験からランダムにサンプリングします。これにより、連続する訓練サンプル間の相関が断ち切られます。replayなしでは、エージェントは高度に相関したtransitionの列（すべて同じstate空間の領域から）で訓練することになり、ネットワークが最近の経験に過学習し、以前に学んだことを忘れる傾向があります。

これら2つのアイデアが合わさることで、DQNは不安定な好奇心の対象から実用的なアルゴリズムへと変貌しました。Promovolveは両方を実装しています。

## 全体像

Promovolveの入札最適化において、すべてのピースがどのように組み合わさるかをまとめましょう:

1. 各観測ウィンドウ（約15分）ごとに、campaign entityがエージェントに現在のstateの観測を送信します。

2. エージェントは観測を8次元のstate vector（実効CPM、CTR、勝率、予算残高、残り時間、消化レート、インプレッションレート、クリック単価）に変換します。

3. 前のstateがある場合、エージェントはtransition（前のstate、取ったaction、受け取ったreward、現在のstate）をreplay bufferに格納します。

4. エージェントは`trainStep()`を実行します: replay bufferからbatchをサンプリングし、Bellman targetを計算し、Q-networkを訓練し、epsilonを減衰させ、定期的にtarget networkを同期します。

5. エージェントはepsilon-greedyを使ってactionを選択します: ランダムなaction（探索）か、最もQ-valueの高いaction（活用）のいずれかです。

6. 選択されたactionは入札倍率調整にマッピングされ（例: action 5 -> 1.2倍）、キャンペーンのベースCPMに適用されます。

7. 次の15分間、調整された入札がオークションで競争します。結果（インプレッション、クリック、消費額）が次の観測となり、サイクルが繰り返されます。

1日の間に、エージェントは数十のtransitionを収集し、Q-value推定を徐々に洗練させ、ランダムな探索から情報に基づいた入札へとシフトします。複数日にわたって（snapshotを通じて重みが永続化されることで）、エージェントは数千のtransitionを蓄積し、クリック最大化と予算ペーシングのバランスを取る精緻な入札戦略を発達させます。

## 次のステップ

2つの重要なコンポーネントを省略しました: **experience replay buffer**（過去のtransitionがどのように格納・サンプリングされるか）と**target network**（別のコピーを凍結することで訓練が安定する理由）です。次の章では、Promovolveの`ReplayBuffer`の仕組みを詳しく見て、DQNを実用的にする安定性のダイナミクスを追っていきます。
