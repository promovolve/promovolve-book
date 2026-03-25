# Experience Replay: 過去から学ぶ

料理の学習を想像してください。5分前に作った料理だけを練習していたら、その1つのレシピだけが非常に上手になり、他のすべてを完全に忘れてしまうでしょう。さらに悪いことに、直近の5品がすべてパスタだった場合（パスタにハマっていたため）、料理とは*パスタのこと*だと思い始めてしまいます。レシピ帳をランダムにめくる必要があります -- 先週火曜日の炒め物、先月のスープ、昨日のサラダを再訪して -- バランスの取れた料理人になるためです。

DQNエージェントもまさにこの問題に直面します。この章では、深層強化学習を機能させる一見シンプルなデータ構造である**replay buffer**を紹介します。

## オンライン学習の問題

replay bufferがなければ、エージェントは各経験を発生順に1回だけ訓練に使うことになります。2つの問題が発生します:

**壊滅的忘却。** エージェントは最新の経験で訓練し、ニューラルネットワークの重みはそれに合わせて変化します。古い教訓は薄れていきます。エージェントが午前中に予算を節約することを学び、午後に積極的に入札することを学んだ場合、午後の訓練が午前の教訓を上書きしてしまいます。

**相関したサンプル。** 連続する経験はほぼ同一に見えます。エージェントが今過剰に支出している場合、次の5つの観測はすべて高い消化レート、減少する予算、類似したstate vectorを示します。ほぼ同一の5つの例で連続して訓練するのは、同じフラッシュカードを5回勉強して生産的なセッションと呼ぶようなものです。ニューラルネットワークは一般的なパターンを学ぶ代わりに、現在の状況に過学習してしまいます。

両方の問題の解決策は同じです: **すべての経験を保存し、訓練にはランダムにサンプリングする。**

## transitionとは何か

エージェントが意思決定を行い結果を観測するたびに、1つの**transition**が生成されます -- 1つの意思決定の完全な記録です:

| Field       | What It Means                              | Ad Bidding Example                                    |
|-------------|---------------------------------------------|-------------------------------------------------------|
| `state`     | What the world looked like                 | Budget 60% remaining, CTR 0.02, win rate 0.4          |
| `action`    | What the agent did                         | Action 4 = multiply bid by 1.1x (bid more aggressively) |
| `reward`    | What the agent got                         | 3 clicks, minus a small overspend penalty = 2.7       |
| `nextState` | What the world looked like afterward       | Budget 55% remaining, CTR 0.025, win rate 0.5         |
| `done`      | Is the episode over?                       | `false` (budget not exhausted, still time left in the day) |

transitionは1つの意思決定の前後のsnapshotです。エージェントはこれを数千個格納し、一度にランダムなまとまりで訓練します。

## ReplayBufferの全コード

Promovolveのreplay bufferはわずか64行です。全体を以下に示します:

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

各部分を見ていきましょう。

### ストレージ: 5つの並列配列

```scala
private val states     = new Array[Array[Double]](capacity)
private val actions    = new Array[Int](capacity)
private val rewards    = new Array[Double](capacity)
private val nextStates = new Array[Array[Double]](capacity)
private val dones      = new Array[Boolean](capacity)
```

bufferは配列の構造体（array-of-structsではなく**struct-of-arrays**）レイアウトを使用しています。10,000個の`Transition`オブジェクト（それぞれ5つのフィールドを持つ）を格納する代わりに、10,000要素の5つの配列を格納します。これはパフォーマンスに敏感なコードでよく見られるパターンで、オブジェクト割り当てのオーバーヘッドを回避し、単一フィールドを反復処理する際のメモリアクセスパターンをキャッシュフレンドリーに保ちます。

各配列はtransitionタプルの1つのコンポーネントを保持します。5つの配列すべてにわたる位置`i`が、1つの完全なtransitionを表します。

### 循環バッファ

```scala
private var writeIdx    = 0
private var currentSize = 0
```

2つの変数がbufferの状態を追跡します:

- `writeIdx` -- *次の*transitionが書き込まれる位置。
- `currentSize` -- 格納されている有効なtransitionの数（`capacity`が上限）。

新しいtransitionが到着すると:

```scala
writeIdx = (writeIdx + 1) % capacity
if (currentSize < capacity) currentSize += 1
```

剰余演算子（`% capacity`）がポイントです。`writeIdx`が10,000に達すると、0に戻り、最も古いtransitionの上書きを開始します。これが「循環」の部分です -- bufferはリングであり、成長するリストではありません。

`capacity = 5`のbufferにtransitionが到着する様子を示します:

```
Store #1:  [T1, _,  _,  _,  _ ]   writeIdx=1, size=1
Store #2:  [T1, T2, _,  _,  _ ]   writeIdx=2, size=2
Store #5:  [T1, T2, T3, T4, T5]   writeIdx=0, size=5  (full!)
Store #6:  [T6, T2, T3, T4, T5]   writeIdx=1, size=5  (T1 overwritten)
Store #7:  [T6, T7, T3, T4, T5]   writeIdx=2, size=5  (T2 overwritten)
```

最も古い経験が常に置き換えられます。リサイズなし、シフトなし、ガベージコレクションの圧力なし。毎回一定時間での挿入です。

### 配列をクローンする理由

`store`の次の行に注目してください:

```scala
states(writeIdx) = state.clone()
nextStates(writeIdx) = nextState.clone()
```

なぜ`clone()`するのでしょうか？Scala（およびJava）の配列はミュータブルな参照型だからです。呼び出し元は`state`配列を渡しますが、次の観測で同じ配列を再利用し、内容を上書きするかもしれません。クローンしなければ、bufferは呼び出し元の配列への参照を保持し、呼び出し元がそれを変更するたびに、格納されたすべてのtransitionが暗黙的に変わってしまいます。

これは微妙ですが重要な正確性の問題です。クローンにより、bufferが各state vectorの独立したコピーを所有することが保証されます。

### 一様ランダムサンプリング

```scala
val indices = Array.fill(batchSize)(rng.nextInt(currentSize))
```

訓練の時間になると、bufferは`batchSize`個のランダムなインデックスを（復元あり抽出で）選び、対応するtransitionを集めます:

```scala
ReplayBuffer.Batch(
  states     = indices.map(states),
  actions    = indices.map(actions),
  rewards    = indices.map(rewards),
  nextStates = indices.map(nextStates),
  dones      = indices.map(dones)
)
```

「復元あり」とは、同じtransitionが1つのbatchに2回出現する可能性があることを意味します。実際には、10,000個の格納されたtransitionとbatchサイズ32の場合、重複はまれで（約5%の確率）、問題を引き起こしません。

### Batch case class

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

`Batch`は、サンプリングされたtransitionを配列形式で保持するコンテナで、訓練ループが反復処理できるように準備されています。5つの配列にわたる各インデックス`i`が1つの完全なtransitionです。

## なぜ容量10,000なのか

Promovolveの設定から:

```scala
bufferSize = 10_000
```

これはトレードオフです。小さすぎると、エージェントは有用な古い経験を忘れます -- 2週間前の予算危機からの教訓を失うかもしれません。大きすぎると、もはや存在しない世界からの古いデータで訓練することになります（キャンペーンが終了し、トラフィックパターンが変化し、競合他社が入札を変更します）。

15分間隔の観測で1日96回の観測がある場合、10,000個のtransitionは約**104日間**の経験を表します。学習に十分な履歴でありながら、現在の広告市場を反映するのに十分新しいものです。

メモリコストは控えめです。各transitionは2つの8要素`Double`配列（stateとnextState）、1つの`Int`、1つの`Double`、1つの`Boolean`を格納します。これはtransitionあたり約150バイトになるため、bufferの全体は約1.5 MBを使用します。現代のサーバーでは無視できる量です。

## なぜ32個の経験まで待つのか

```scala
minBufferSize = 32
```

エージェントは、bufferに少なくとも32個のtransitionが蓄積されるまで訓練を拒否します。なぜでしょうか？

3つの経験で訓練したら、ニューラルネットワークはその3つの例を完璧に暗記し、一般的なことは何も学びません。試験勉強で3問だけ読んで、出題されるのはその3問だけだと思い込むようなものです。

32個の多様な経験 -- 過剰支出期のもの、過少支出期のもの、高CTRトラフィックのもの、低CTRのもの -- があれば、ネットワークは特定の例を暗記するのではなくパターンを抽出するのに十分な多様性を得られます。32という数はbatchサイズでもあり、最初の訓練ステップで利用可能なすべての経験が少なくとも1回はサンプリングされることを意味します。

## なぜbatchサイズ32なのか

```scala
batchSize = 32
```

各訓練ステップはbufferから32個のランダムなtransitionをサンプリングします。なぜ1ではないのでしょうか？なぜ1,000ではないのでしょうか？

**batchサイズ1**（オンライン学習）: 各重み更新は1つの例に基づきます。勾配はおおよそ正しい方向を向いていますが、膨大なノイズがあります。訓練は不安定で、ネットワークは1つの例から次の例へと揺れ動きます。

**batchサイズ1,000**: 勾配は1,000例の平均なので、非常に滑らかで安定しています。しかし、各訓練ステップは1,000倍コストがかかり、初期段階でbufferが小さいときは、訓練を開始する前に1,000個の経験が必要になります。

**batchサイズ32**は一般的なスイートスポットです。オプティマイザに信頼できる勾配方向を与えるのに十分なノイズを平均化しつつ、各観測ステップで実行できるほど安価です。この値はディープラーニングで非常に標準的で、ほぼ「デフォルト」の選択です。GPUを使う大規模モデルではより大きなbatchが有効な場合もありますが、PromovolveのようなCPU上で動作する小さな8入力・2隠れ層のネットワークには、32で十分以上です。

## 核心的な洞察

大きなbufferからランダムにサンプリングすることで、replay bufferは訓練例間の**時間的相関を断ち切ります**。

replayなしの場合:
```
Training step 1:  experience from 10:00am
Training step 2:  experience from 10:15am
Training step 3:  experience from 10:30am
Training step 4:  experience from 10:45am
```

4つの経験はすべて同じ午前中からのもので、類似のトラフィック、類似の予算レベル、類似のすべてです。ネットワークは世界が常に午前遅くのように見えると思い込みます。

replayありの場合:
```
Training step 1 (batch of 32):
  - experience from Monday 10:00am
  - experience from Friday 3:45pm
  - experience from Tuesday 8:15am
  - experience from Thursday 11:30pm
  - ... 28 more random picks
```

月曜朝の経験が金曜午後の経験の隣に並びます。予算がほぼ尽きた経験が、その日が始まったばかりの経験の隣に並びます。ネットワークは、毎回の訓練ステップで遭遇する可能性のある状況の全多様性を目にします。

これが、experience replayがオリジナルのAtari論文（Mnih et al., 2015）でDQNを機能させた重要なイノベーションの1つである理由です。これがなければ、ニューラルネットワークは不安定です。これがあれば、訓練は確実に収束します。そして見てきたように、実装は循環配列と乱数生成器に過ぎません。

---

次の章: 経験で満たされたbufferとサンプリング方法があります。次は正しい訓練目標を計算する必要があります -- そして、エージェントがactionの良さを系統的に過大評価してしまう微妙な罠を回避しなければなりません。
