# Reinforcement Learningをゼロから学ぶ

この章では、Promovolveの入札最適化を題材として、RLをゼロから解説します。読み終わる頃には、`DQNAgent.scala`と`BidOptimizationAgent.scala`のすべての行を理解できるようになります。機械学習の予備知識は不要です。

---

## 問題：決定が多すぎて、時間が足りない

あなたが1つの広告キャンペーンを管理しているとしましょう。1日の予算は100ドル、最大入札額はCPM 5ドル（1,000インプレッションあたりのコスト）です。15分ごとに状況を確認し、オークションに勝つために入札額を上げるべきか、予算を節約するために下げるべきかを判断します。

手動で対処しようとすることもできるでしょう。しかし、広告マーケットプレイスは生き物です——競合他社は入札を変え、ユーザートラフィックは増減し、コンテンツによってクリック率は異なります。今日書いた固定ルールは明日には通用しなくなります。

本当に必要なのは、新入社員が最初の数週間で仕事が上達していくのと同じように、経験から*学習する*システムです。それがreinforcement learningです。

---

## 設定：Agent、Environment、Reward

すべてのRL問題には同じ3つの要素があります。

**Agent**は意思決定者です。Promovolveでは、agentは`BidOptimizationAgent`——入札の積極度を決定するコードです。これはアクターではなく、`CampaignEntity`アクターの内部に埋め込まれた普通のScalaオブジェクトで、各観測時に同期的に呼び出されます。

**Environment**はagentが制御できないすべてのものです：他の広告主の入札、ブラウジングしているユーザー数、閲覧しているコンテンツ。agentはenvironmentを観察できますが、直接変更することはできません。反応することしかできないのです。

**Reward**はagentの成果を伝えるシグナルです。各決定の後、environmentは1つの数値を返します：うまくいった場合は正、うまくいかなかった場合は負です。agentの唯一の目標は、時間の経過とともに収集するrewardの総量を最大化することです。

それだけです。この章のすべては、このループを機能させるための仕組みにすぎません。

---

## なぜルールを書くだけではダメなのか？

最初に思いつくのは、ロジックをハードコードすることです：「予算が60%以上残っていて正午を過ぎていたら、入札を上げる」。しかし、このようなルールはいくつかの理由で破綻します：

- 正しい閾値を事前に知ることができない。60%が正しいカットオフなのか？55%かもしれないし、70%かもしれない。
- 最適なルールは競合他社の行動に依存するが、それは見えず、常に変化している。
- トラフィックパターンは日、季節、コンテンツタイプによって異なる。
- キャンペーンごとに最適な戦略は異なる。

RLはこのすべてを回避します。ルールを書く代わりに、「良い」とは何かを定義し（reward）、agentに試行錯誤を通じて自らルールを見つけさせるのです。

---

## Agentが観察するもの

15分ごとに、agentは世界を見渡し、現在の状況のスナップショットを構築します。Promovolveでは、このスナップショット——**state**と呼ばれる——は8つの数値で構成されます：

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

これら8つの数値をまとめると、agentが置かれている状況を表現できます。チェスプレイヤーが次の手を決める前に盤面を見るのと同じように、agentはactionを決定する前にこのstateを見ます。

---

## Agentができること

stateが与えられると、agentは7つのactionのうち1つを選択します：

| Action | Multiplier | Meaning |
|--------|-----------|---------|
| 0 | 0.7× | Bid much lower — conserve budget aggressively |
| 1 | 0.8× | Bid lower |
| 2 | 0.9× | Bid slightly lower |
| 3 | 1.0× | Hold steady |
| 4 | 1.1× | Bid slightly higher |
| 5 | 1.2× | Bid higher |
| 6 | 1.4× | Bid much higher — be aggressive |

multiplierは現在の入札レベルに累積的に適用され、[0.5, 2.0]にクランプされます。agentはマーケットを変えることはできません。入札の積極度を調整し、次に何が起こるかを観察することしかできないのです。

---

## Rewardシグナル

15分間のウィンドウごとに、agentはrewardを受け取ります。Promovolveでは、次のように計算されます：

```
pacingScore = max(0.1, 1.0 - |spendRate - 1.0|)
reward = clicks × pacingScore - exhaustionPenalty × timeRemaining
```

平易に言うと：

- **ペーシング品質でスケーリングされたクリック数。** キャンペーンが完璧なペース（spendRate = 1.0）のとき、すべてのクリックが満額でカウントされます。2倍の速度で過剰支出している場合、各クリックの価値は10%に下がります。0.5倍で過少支出の場合、各クリックの価値は50%です。どちらの方向もペナルティを受けるため、agentは過剰入札で有利にすることはできません。
- **予算枯渇はペナルティが時間に比例。** 1日の80%を残して予算を使い果たすことは、20%を残して使い果たすよりも4倍悪いとされます。これにより、早期の予算枯渇は後半の枯渇よりもより多くの潜在的クリックを無駄にすることをagentに教えます。

この1つの数式が、agentが受け取る唯一の「成功」の定義です。agentが学習するすべてはこのシグナルから生まれます。reward関数を変更すれば、agentはまったく異なる戦略を学習します。

---

## 経験からの学習：核心となるアイデア

根本的な問いはこうです：agentはどのようにして*どの状況でどのactionを取るべきか*を学ぶのでしょうか？

端的に言えば：何が起こったかを記憶し、期待値を調整することによってです。

agentが予算70%でクリック率が高い状態にあり、入札を上げることにしたとしましょう。より多くのオークションに勝ち、より多くのクリックを獲得し、良いrewardを得ます。これで「この状況で入札を上げる」のは利益のある行動だとわかりました。

しかし、ここに微妙な点があります：agentは即時のrewardだけを気にするのではありません。*その日の残り全体で収集するrewardの総量*を気にするのです。積極的に入札すれば今すぐ多くのクリックを得られるかもしれませんが、午後2時までに予算を使い果たせば、残りの1日は何も得られず——ペーシングペナルティが厳しくのしかかります。

これが、RLが個々の決定ではなく**一連の決定**を重視する理由です。

---

## Q-Values：すべての選択肢をスコアリングする

一連の決定について推論するために、agentは**Q-value**と呼ばれる概念を使います。

`Q(state, action)`は、次の質問に対するagentの推定値です：*「この状況にいて、このactionを取り、その後残りの1日を最適にプレイした場合——合計でどれだけのrewardを獲得できるか？」*

例えば：

| Action | Multiplier | Q-value |
|--------|-----------|---------|
| 0 | 0.7× | 7.3 |
| 1 | 0.8× | 9.1 |
| 2 | 0.9× | 10.0 |
| 3 | 1.0× | 11.2 |
| 4 | 1.1× | 12.5 |
| 5 | 1.2× | 11.8 |
| 6 | 1.4× | 9.4 |

これらのQ-valuesから、agentはaction 4（入札をわずかに上げる）を選択します——Q-value 12.5が最も良い推定結果です。最も積極的なaction（1.4×）のQ-valueは穏当なものより低いことに注目してください——agentは過剰入札がペーシングを損なうことを学習したのです。

agentは将来について明示的に考える必要がありません。Q-valuesを参照し、最も高いものを選ぶだけです。長期的な推論はすべてQ-values自体に織り込まれています。

もちろん難しいのは、そもそも正確なQ-valuesを持つことです。それが訓練の目的です。

---

## Bellman Equation：Q-Valuesの由来

Q-valuesはどのように計算されるのでしょうか？**Bellman equation**と呼ばれる美しくシンプルな観察を通じてです。

次のように考えてください：あるactionの価値は2つのものを足し合わせたものに等しいです：
1. 今すぐ得られる即時reward
2. 次のstateから先で得られる最善の結果

数式で書くと：

```
Q(state, action) = immediate_reward + γ × max Q(next_state, any_action)
```

**γ（gamma）**は0から1の間の数値で、Promovolveでは0.99です。これは、agentが即時のrewardと比較して将来のrewardをどれだけ重視するかを表します。

なぜ将来を割引するのでしょうか？今のrewardは後の同じrewardよりも価値があるからです——そこに到達する前に予算が尽きるかもしれません。γ = 0.99の場合、1ステップ後のrewardは今のrewardの0.99の価値があります。100ステップ後のrewardは0.99^100 ≈ 0.37の価値しかありません。agentはより早い結果を好みます。

Bellman equationは難しい問題（将来のreward総量を予測する）を扱いやすい問題に変換します：即時rewardを予測し、次のstateからブートストラップするのです。

---

## 近似の問題

もしstateがチェスボードの64マスのように小さな固定の集合であれば、Q-valueテーブルをメモリに保存できるでしょう。1行がstate、1列がactionです。

しかし、Promovolveのstateは8つの連続した数値です。予算残高は0.70かもしれないし、0.701かもしれないし、0.7001かもしれません。可能なstateは無限に存在します。テーブルは論外です。

ここで**neural network**の出番です——neural networkが魔法だからではなく、ある特定のことが非常に得意だからです：例から関数を学習することです。

---

## Neural Networks：関数近似器

neural networkは、多くの調整可能なダイヤルを持つ数学的関数にすぎません。

入力としていくつかの数値を与えます。一連の計算が行われます。出力としていくつかの数値が生成されます。ダイヤル——**weights**と呼ばれる——がその計算の内容を決定します。

Promovolveでは、ネットワークは次のようになっています：

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

中間層は、ネットワークが自明でないパターンを学習できるようにするために存在します。「高い落札率かつ低い予算残高」は、どちらの指標単独では明らかにならない何かを示しているかもしれません。中間層は、ネットワークにそうした組み合わせを発見する余地を与えます。

これがコード上の`DenseNetwork.forward()`です。ネットワークは合計で約5,200のパラメータを持っています。

重要なポイント：このネットワークは**汎化**します。一度訓練されると、見たことのないstateに対しても、似たstateから補間することで、妥当なQ-value推定を生成できます。neural networkをルックアップテーブルの代わりに使う理由はまさにこの点にあります。

---

## 訓練：ダイヤルの調整

訓練とは、ネットワークのweightsを調整して、Q-value推定が正確になるようにするプロセスです。

agentがactionを取るたびに、**transition**を観察します：

```
(state, action, reward, next_state)
```

例えば：「state [0.7, 0.03, ...]にいて、action 4（入札をわずかに上げる）を選び、reward 2.7を獲得し、今はstate [0.65, 0.028, ...]にいる。」

このtransitionから、訓練は3つのステップで進みます：

**1. 予測。** 現在のstateをネットワークに通し、取ったactionに対する予測Q-valueを得る。

**2. あるべき値を計算。** Bellman equationを使って：
```
target = 2.7 + 0.99 × (best Q-value from next state)
```

**3. 調整。** 予測がtargetに近づくように、weightsをわずかに修正する。予測が10.0でtargetが12.5なら、出力を12.5に近づける方向に、すべてのweightが微小量だけ調整される。

この修正プロセス——gradient descentと呼ばれる——が`DenseNetwork.train()`で実装されているものです。これを数万回繰り返すことで、ネットワークの推定値は徐々に正確なQ-valuesに収束していきます。

---

## Experience Replay：相関を断ち切る

transitionを1つずつ学習することには実用上の問題があります。

午後2:15のstateは午後2:30のstateに非常に似ています。午後2:30のstateは午後2:45のstateに似ています。agentが各transitionをリアルタイムで学習すると、ほぼ同一の状況が繰り返される高い相関のあるストリームに基づいてweightsを調整することになります。weightsは直近1時間に特化して調整され、他の状況について学んだことを「忘れて」しまいます。

**Experience replay**はシンプルなトリックでこれを解決します：すぐに学習するのではなく、各transitionをバッファに保存します：

```
buffer = [
  (state from day 1, action, reward, next_state),
  (state from day 3, action, reward, next_state),
  (state from day 1 again, different action, ...),
  ...
]
```

そして、各訓練ステップでバッファのどこからでもランダムに32個のtransitionのバッチを取り出します。このバッチには今朝のtransition、3日前のtransition、まったく異なる予算レベルのtransitionが含まれるかもしれません。この多様性がネットワークを広く学習させ、現在の瞬間だけに特化させないようにします。

コード上では、これが`ReplayBuffer`です——最大10,000個のtransitionを保持する循環バッファです。満杯になると、新しいエントリが最も古いものを上書きします。`buffer.sample(32, rng)`がランダムなバッチを取り出します。

---

## Double DQN：バイアスの補正

標準的なDQNには微妙な欠陥があります。訓練targetの計算方法を見てみましょう：

```
target = reward + γ × max(network.forward(next_state))
```

`max`操作は次のstateで最も良さそうなactionを選びます。しかし、ネットワークから出てくる推定値にはノイズがあり、特に訓練初期でweightsがほとんど調整されていないときは顕著です。推定値にノイズがある場合、最も高い値は過大推定になりがちです——本当に良いから高いのと、現在のweight設定のランダムなノイズにより高くなっているのが混在するからです。

常に`max`を取ることで、agentは系統的にQ-valuesを過大推定します。これによりagentは過信状態になり、訓練が不安定になりえます。広告入札では、積極的な入札が実際よりも有益だとagentが考え——予算の使い果たしにつながります。

**Double DQN**は、この作業を2つの別々のネットワークに分割することで修正します：

- **Q-network**：メインのネットワークで、各訓練ステップ後に更新される。
- **Target network**：Q-networkのコピーで、100ステップごとにのみ更新される。

最善のactionの*選択*と*評価*に同じネットワークを使う代わりに、Double DQNはこれらを分離します：

```
best_action = argmax(q_network.forward(next_state))   // Q-net selects
target = reward + γ × target_network.forward(next_state)[best_action]  // target-net evaluates
```

target networkは安定した参照点です。100ステップごとにしか更新されないため、自分自身を追いかけ回すことがありません。Q-networkは常に変動するターゲットではなく、ゆっくり動くターゲットに対して学習します。

これは`DQNAgent.trainStep()`の83〜93行目で実装されています。

---

## Exploration対Exploitation

agentが常に最も高いQ-valueのactionを選ぶと、他のactionがさらに良いかもしれないことを発見できません。凡庸なルーティンに落ち着き、そこから抜け出せなくなる可能性があります。

この緊張関係——既知のものを活用するか、新しいものを試すか——は**explore/exploit tradeoff**と呼ばれます。RLにおける根本的な問題の1つです。

Promovolveは**epsilon-greedy**探索でこれを解決します。パラメータε（epsilon）は確率です：

```
if (rng.nextDouble() < epsilon)
  take a random action    // explore
else
  take the best-known action  // exploit
```

epsilonは1.0（完全にランダム）から始まり、各訓練ステップ後に0.995を掛けて減衰し、下限0.05まで下がります。

実際にはこれは次のことを意味します：

- **1日目**：ほぼ完全にランダム。agentは何も知らず、生の経験を蓄積している。
- **3〜5日目**：ほとんど学習済みのポリシーを活用しているが、まだ15〜30%はランダム。agentは有用な知識を持っているが、まだ精錬中。
- **8日目以降**：95%が活用、5%が探索。agentは学んだことを信頼しているが、現在のポリシーが見落としている機会を捉えるために小さなランダム要素を維持している。

減衰スケジュールは意図的です：無知なときは積極的に探索し、情報を得たら自信を持って活用する。

---

## すべてをまとめる

以下は、各`CampaignEntity`アクター内部で実行される完全なサイクルです。

### 各bid request（高速パス）

```
bid_cpm = campaign.max_cpm × agent.bid_multiplier
```

multiplierは単なるキャッシュされた数値です。ここではneural networkの計算は行われません。このパスはサブマイクロ秒です。

### 各impression

```
agent.record_impression(cpm)
agent.record_bid_opportunity(won=true)
```

ウィンドウカウンターをインクリメントします。これもサブマイクロ秒です。

### 各click

```
agent.record_click()
```

ウィンドウのクリックカウンターをインクリメントします。

### 15分ごと（低速パス）

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

### 1日の終わり

```
1. Store terminal transition (done=true)
2. Reset bid_multiplier to 1.0
3. Keep all network weights — the learned policy carries over to tomorrow
```

### エンティティ再起動時

```
1. Restore network weights from persisted snapshot
2. Replay buffer is empty — agent resumes with learned policy but needs
   to re-accumulate experience before it can train again
```

---

## Agentが実際に学習すること

数日間の運用後、十分に訓練されたagentは次のようなパターンを発見します——それらが存在すると教えられることなく：

- **1日の序盤で予算が満額**：ペースを維持しながらインプレッションを獲得するために穏当に入札する。
- **時間が残っているのに予算が少ない**：ペーシングスコアがrewardを低下させる前に引き下げる。
- **クリック率の高いコンテンツ**：入札を上げる価値がある——クリックがrewardであり、良好なペーシングがそれを増幅する。
- **過剰支出**：ペーシングスコアがすべてのクリックの価値を即座に低下させる——agentは1〜2回の観測で自己修正を学ぶ。
- **1日の終盤で予算が余っている**：残りの予算を生産的に使うために入札を上げる——過少支出もペーシングスコアを下げる。

これらはどれもプログラムされていません。rewardシグナルから、数千回の訓練ステップを通じて出現するのです。

---

## 主要なHyperparameters

これらはすべて`DQNAgent.Config`と`BidOptimizationAgent.Config`にあります。

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

## 理論からコードへ

| Concept | File | Key method |
|---|---|---|
| Neural network (forward + training) | `DenseNetwork.scala` | `forward()`, `train()` |
| Experience replay buffer | `ReplayBuffer.scala` | `store()`, `sample()` |
| Double DQN + epsilon-greedy | `DQNAgent.scala` | `selectAction()`, `trainStep()` |
| State / reward / action design | `BidOptimizationAgent.scala` | `toState()`, `computeReward()`, `observe()` |
| Integration with campaign actor | `CampaignEntity.scala` | `RLObserveTick`, `TryReserve` |

次の章では、これらの各コンポーネントを正確な数式と設定値とともに詳しく解説します。
