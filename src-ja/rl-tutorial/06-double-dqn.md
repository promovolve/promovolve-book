# Double DQN: overestimationの修正

第4章で、DQN訓練の中核にあるBellman equationを見ました:

```
target = reward + gamma * max_a' Q(s', a')
```

これは合理的に見えます: state `s`でaction `a`を取ることの目標Q-valueは、即時のrewardに次のstateでの最良のactionの割引された価値を加えたものです。しかし、その`max`演算子に微妙な問題が潜んでおり、標準DQNはQ-valueを系統的に過大評価します。放置すると、このoverestimationは訓練を通じて蓄積し、エージェントの行動を台無しにする可能性があります。

Promovolveはこれを修正するために**Double DQN**（Van Hasselt et al., 2016）を使用しています。変更はわずか数行のコードですが、*なぜ*機能するかを理解するには、Double DQNなしで何がうまくいかないかを注意深く見る必要があります。

## overestimation問題

state `s'`で全7つのactionの真のQ-valueがちょうど10.0であるケースを考えます。完璧な世界では、ネットワークは`[10.0, 10.0, 10.0, 10.0, 10.0, 10.0, 10.0]`を出力し、`max`は10.0を返します。問題ありません。

しかし、ニューラルネットワークは完璧ではありません。推定誤差があり、値が少し高すぎることもあれば、少し低すぎることもあります。ネットワークが次のように出力したとします:

```
Q(s', a0) = 9.5    (underestimate by 0.5)
Q(s', a1) = 10.8   (overestimate by 0.8)
Q(s', a2) = 9.2    (underestimate by 0.8)
Q(s', a3) = 11.3   (overestimate by 1.3)  <-- max picks this
Q(s', a4) = 10.1   (overestimate by 0.1)
Q(s', a5) = 9.7    (underestimate by 0.3)
Q(s', a6) = 10.4   (overestimate by 0.4)
```

`max`演算子はQ(s', a3) = 11.3を選びます。真の値は10.0でした。誤差は+1.3です。

何が起こったか注目してください: `max`は最も高い*真の*値を持つactionを選ぶのではありません。最も高い*推定*値を持つactionを選びます。それは最大の正の推定誤差を持つものです。max演算子は過大推定に偏っています。

これは偶然ではありません。数学的な必然です。同じ量のN個のノイズの多い推定値があり、その最大値を取る場合、期待される最大値は常に真の値以上になります。推定値が多いほど（actionが多いほど）、overestimationは悪化します。Promovolveのような7つのactionでは、バイアスは有意です。

## overestimationが蓄積する仕組み

overestimationは1つのtransitionに留まりません。Bellman equationを通じて伝播します。

連鎖はこうです: state `s`のQ-value目標はstate `s'`の最大Q-valueに依存します。その最大値が過大評価されていれば、`s`の目標も高すぎます。ネットワークはその水増しされた目標で訓練するため、Q(s, a)も過大評価されます。それ以前のstate `s_prev`がQ(s, a)を使って目標を計算すると、overestimationはさらに後方に伝播します。

多くの訓練ステップにわたって、これは正のフィードバックループを作ります: 過大推定が目標に入り込み、他のQ-valueを膨張させ、さらに大きな過大推定を生み出します。Q-valueは上方にドリフトし、時には不合理に大きな数値に達します。

## 広告入札にとっての意味

Promovolveの文脈では、過大評価されたQ-valueは悪い入札行動につながります。積極的な入札action（1.2倍、1.4倍の倍率）のQ-valueが過大評価されると、エージェントは入札を上げれば実際よりもはるかに多くのクリックが得られると思い込みます。エージェントは積極的に入札し、キャンペーンの予算を最初の数時間で使い果たし、残りの1日のチャンスを逃します。

エージェントは意図的に無謀な行動をしているわけではありません。水増しされたQ-valueに基づいて、積極的な入札が最適な戦略であると心から信じています。overestimationがその価値感覚を歪めているのです。

さらに悪いことに、積極的な入札は*時折*短期的なクリックの急増をもたらします（高く入札するほど多くのオークションに勝つため）。これが部分的な正の強化を提供します。エージェントは時折、過度に楽観的な推定を確認するように見えるrewardを受け取り、問題からの脱却をさらに困難にします。

## Double DQNによる修正

Double DQNの背後にある洞察は、overestimation問題が最良のactionの*選択*とそのactionの*評価*の両方に同じネットワークを使うことから生じるということです。ネットワークがあるactionに対してノイズの多い過大推定を持っている場合、そのactionを（最良に見えるから）選択し、かつ水増しされた値を（同じノイズの多い推定であるから）提供します。

修正は2つのネットワークを使い、責任を分割することです:

1. **Q-network**（online network）が次のstateの最良のactionを選択します。
2. **Target network**がそのactionの良さを評価します。

2つのネットワークは異なる重みを持っているため（target networkはQ-networkの定期的なsnapshotで、最大100訓練ステップ遅れています）、それらの誤差はほぼ無相関です。Q-networkがaction 3を過大評価していても、target networkがaction 3に対して同じ過大推定を持っている可能性は低いです。target networkは選択されたactionのより地に足のついた評価を提供します。

Promovolveの`DQNAgent.trainStep()`の実際のコードを以下に示します:

```scala
val nextQOnline = qNetwork.forward(nextState)
val bestNextAction = argMax(nextQOnline)
val nextQTarget = targetNetwork.forward(nextState)
target(action) = reward + config.gamma * nextQTarget(bestNextAction)
```

4行です。順に追っていきましょう:

**1行目: `val nextQOnline = qNetwork.forward(nextState)`**
次のstateをQ-network（能動的に訓練されているもの）に通します。これにより、actionごとに1つ、7つのQ-value推定が生成されます。

**2行目: `val bestNextAction = argMax(nextQOnline)`**
Q-networkに従って最もQ-valueの高いactionを選びます。これが*選択*ステップです。Q-networkが最良と考えるactionを「指名」します。

**3行目: `val nextQTarget = targetNetwork.forward(nextState)`**
同じ次のstateをtarget network（凍結されたコピー）に通します。これにより、異なる7つのQ-value推定セットが生成されます。

**4行目: `target(action) = reward + config.gamma * nextQTarget(bestNextAction)`**
Q-networkが選択したactionに対するtarget networkのQ-valueを参照します。これが*評価*ステップです。target networkが、指名されたactionが実際にどれだけ良いかについて独立したセカンドオピニオンを提供します。

標準DQNとの比較。標準DQNではtarget networkを両方のステップに使用します:

```scala
// Standard DQN (NOT what Promovolve uses)
val nextQ = targetNetwork.forward(nextState)
target(action) = reward + config.gamma * nextQ(argMax(nextQ))
```

標準DQNでは、target networkが最良のactionを選択*し*、かつそれを評価します。target networkがあるactionに対してノイズの多い過大推定を持っていると、そのactionを選び、水増しされた値を報告します。Double DQNはこの結合を断ち切ります。

## 具体的な数値例

Double DQNが実際にどのように機能するかを確認するために、完全な訓練ステップを実際の数値で追ってみましょう。

**セットアップ:**
- エージェントが現在の状況を持つキャンペーンを観測: 実効CPM = 1.0、CTR = 0.03、勝率 = 0.6、予算残高 = 0.80、残り時間 = 0.70、消化レート = 1.05、インプレッションレート = 0.5、クリック単価 = 0.7。
- state vectorは`[1.0, 0.03, 0.6, 0.80, 0.70, 1.05, 0.5, 0.7]`。
- 前のactionは4（1.1倍で入札）、rewardは3.0クリック。
- episodeは終了していない（`done = false`）。
- 割引率gamma = 0.99。

**ステップ1: 現在のQ-valueを取得**

```scala
val currentQ = qNetwork.forward(state)
// currentQ = [2.1, 3.4, 5.2, 4.8, 3.9, 2.7, 4.1]
```

Q-networkは現在のstateで全7つのactionのQ-valueを推定します。action 4（取られたaction）にのみ関心がありますが、`currentQ.clone()`を目標の基礎として使うため、すべて必要です。

**ステップ2: 目標用にクローン**

```scala
val target = currentQ.clone()
// target = [2.1, 3.4, 5.2, 4.8, 3.9, 2.7, 4.1]
```

目標は現在のQ-valueのコピーとして始まります。`target(4)` -- action 4のスロットのみを変更します。他のすべての値はそのままなので、訓練はそれらのactionに対して勾配ゼロを生成します。ネットワークは実際に取られたactionについてのみ学習します。

**ステップ3: Double DQNの目標計算**

```scala
val nextQOnline = qNetwork.forward(nextState)
// nextQOnline = [1.8, 4.2, 6.1, 5.5, 4.7, 3.1, 5.9]
//                              ^ highest = index 2

val bestNextAction = argMax(nextQOnline)
// bestNextAction = 2

val nextQTarget = targetNetwork.forward(nextState)
// nextQTarget = [2.0, 3.9, 5.4, 5.8, 4.3, 3.5, 5.1]
//                          ^ index 2 = 5.4

target(action) = reward + config.gamma * nextQTarget(bestNextAction)
// target(4) = 3.0 + 0.99 * 5.4 = 3.0 + 5.346 = 8.346
```

Q-networkは次のstateでaction 2が最良と言います（Q = 6.1）。しかし、target networkのそのactionに対する推定はわずか5.4です。目標値はより保守的な5.4を使い、これは真の値に近くなります。

標準DQNでtarget networkを選択と評価の両方に使った場合:

```
nextQTarget = [2.0, 3.9, 5.4, 5.8, 4.3, 3.5, 5.1]
bestAction = argMax(nextQTarget) = 3  (Q = 5.8)
target(4) = 3.0 + 0.99 * 5.8 = 8.742
```

標準DQNはaction 2（Q = 5.4）の代わりにaction 3（Q = 5.8）を選び、Double DQNの8.346に対して8.742という高い目標を生成します。数千の訓練ステップにわたって、これらの小さな差が蓄積し、標準DQNのQ-valueは上方にドリフトします。

**ステップ4: クリップして訓練**

```scala
target(action) = math.max(-config.qClip, math.min(config.qClip, target(action)))
// target(4) = max(-100, min(100, 8.346)) = 8.346  (within bounds)

totalLoss += qNetwork.train(state, target, config.learningRate)
```

目標値は安全策として[-100, 100]の範囲にクリップされ（詳細は後述）、Q-networkはaction 4の出力を3.9（現在の推定）から8.346（目標）に向けて訓練されます。学習率0.001はその方向に小さなステップを取ることを意味します。

## target network: 凍結されたコピー

Double DQNには異なる重みを持つ2つのネットワークが必要です。Promovolveはこれを**target network** -- Q-networkと定期的に同期される別個の`DenseNetwork` -- で実現しています:

```scala
private val qNetwork = DenseNetwork(config.layerSizes, rng)
private val targetNetwork = DenseNetwork(config.layerSizes, rng)

// Initialize target to match Q-network
targetNetwork.copyFrom(qNetwork)
```

作成時、target networkはQ-networkの正確なコピーです。その後、訓練中にQ-networkの重みは各訓練ステップで変化しますが、target networkは凍結されたままです。100訓練ステップごとにtarget networkが更新されます:

```scala
if (trainSteps % config.targetSyncInterval == 0) {
  targetNetwork.copyFrom(qNetwork)
}
```

`copyFrom`メソッドは、効率のために`System.arraycopy`を使用してすべての重みとバイアスのディープコピーを行います:

```scala
def copyFrom(other: DenseNetwork): Unit = {
  var l = 0
  while (l < numLayers) {
    var j = 0
    while (j < weights(l).length) {
      System.arraycopy(other.weights(l)(j), 0, weights(l)(j), 0, weights(l)(j).length)
      j += 1
    }
    System.arraycopy(other.biases(l), 0, biases(l), 0, biases(l).length)
    l += 1
  }
}
```

なぜ連続的に更新する代わりに100ステップ凍結するのでしょうか？目標はQ-networkがマッチしようとしているものだからです。目標が各訓練ステップで動くと、Q-networkは絶えず変動する目標を追いかけることになります。一歩踏み出すたびに逃げる人を捕まえようとするようなものです。100ステップ凍結することで、Q-networkは目標が再び変わる前に安定した目標に収束する時間を得ます。

なぜ具体的に100ステップなのでしょうか？バランスです。少なすぎると（例えば10）、目標は連続的な更新とほぼ同じくらい不安定です。多すぎると（例えば10,000）、目標は古くなります -- Q-networkは大幅に優れた推定を学んでいるかもしれませんが、target networkはまだ古い、精度の低い重みを反映しています。100ステップは実際にうまく機能する広く使われているデフォルト値です。

## Q-valueクリッピング: 安全策

Double DQNを使っていても、rewardのスパイクや不運な更新の連続によりQ-valueが大きくなることがあります。Promovolveは目標Q-valueをクリップしてこれを防ぎます:

```scala
target(action) = math.max(-config.qClip, math.min(config.qClip, target(action)))
```

`qClip = 100.0`の場合、目標Q-valueは100を超えたり-100を下回ったりすることがありません。これは壊滅的な発散を防ぐハードシーリングです。

なぜ100なのでしょうか？Q-valueがPromovolveで何を表すか考えてください: エージェントが将来収集すると期待するクリックの合計です。15分ウィンドウあたり約0から10クリックのrewardで、割引率0.99の場合、丸1日（96ウィンドウ）の理論上の最大Q-valueには限界があります。非現実的に楽観的なシナリオでも、割引なしでウィンドウあたり10クリックなら960です。100のクリップは現実的なQ-valueに干渉しないほど十分寛容でありながら、数値的不安定性（NaN値、勾配爆発）を引き起こす前に発散をキャッチするのに十分な締まりがあります。

## terminal state: doneがtrueのとき

キャンペーンが予算を使い果たしたか、1日が終了すると、episodeは終了です。将来のrewardは考慮しません:

```scala
if (done) {
  target(action) = reward
}
```

`gamma * nextQTarget(bestNextAction)`の項はありません。Q-valueは即時のrewardそのものです。これは直感的に理解できます: キャンペーンに予算が残っていなければ、将来のstateに対するQ-valueの予測は関係ありません。将来のstateは存在しないのです。

`BidOptimizationAgent`では、`done`フラグは次の条件で設定されます:

```scala
val done = obs.budgetRemaining <= 0 || obs.timeRemaining <= 0
```

各日の終わりに、`resetDay()`もterminal transitionを格納します:

```scala
val terminalState = Array.fill(config.dqnConfig.stateSize)(0.0)
val terminalReward = windowClicks.toDouble
dqn.store(ps, pa, terminalReward, terminalState, done = true)
```

これにより、エージェントは1日に明確な終わりがあることを学びます。terminal transitionがなければ、エージェントは1日の後半のstateに対して非現実的に楽観的なQ-valueを発達させ、常に次にもっとrewardがあると信じるかもしれません。

## Double DQNが実際に重要な理由

標準DQNとDouble DQNの違いが常に劇的であるとは限りません。一部の環境では、標準DQNでも問題なく機能します。しかし、Q-valueが重要な意思決定に使われる環境 -- 広告入札にどれだけのお金を費やすかなど -- では、overestimationバイアスが重要になります。

訓練の経過を考えてみましょう:

- **標準DQN**: 積極的なaction（1.2倍、1.4倍の倍率）のQ-valueが徐々に膨張します。エージェントは高い入札が素晴らしい結果を生むことにますます確信を持ちます。過剰に支出し、予算を早々に使い果たし、午後と夕方のチャンスを逃します。

- **Double DQN**: Q-valueは地に足がついたままです。エージェントは積極的な入札には実際のコスト（予算消化の加速）があることを学び、1日を通して予算を分配するペース配分戦略を発達させます。

この違いは特に訓練の初期段階で顕著です。Q-networkの推定がノイズが多く、overestimationバイアスが最も強い時期です。Double DQNは、過信した戦略に固定される前に各actionの真の価値を学ぶ機会をエージェントに与えます。

## まとめ

標準DQNは最良の将来のQ-valueを推定するために`max`演算子を使いますが、これは`max`がノイズを拾い上げるため系統的にoverestimateします。Double DQNはシンプルな分離でこれを修正します:

1. **Q-network**が最良のactionを選択します（*どの*actionを評価するかを決定します）。
2. **Target network**がそのactionを評価します（そのactionが*どれだけ良いか*を決定します）。

2つのネットワークは異なる重みを持つため、それらの誤差は無相関であり、overestimationバイアスは大幅に軽減されます。Q-valueクリッピングとterminal stateの処理と組み合わせることで、Promovolveの入札最適化エージェントに安定した信頼性の高い訓練を提供します。

次の章では、すべてのピースを統合します -- ニューラルネットワーク、replay buffer、Double DQN、epsilon-greedy探索 -- そして完全な`DQNAgent`を統一されたシステムとして見ていきます。
