# すべてを組み合わせる：BidOptimizationAgent

ここまで、Q値を推定するニューラルネットワーク、経験を蓄積するreplay buffer、そしてその経験から学習するDouble DQN学習ループと、すべてのパーツを個別に構築してきました。いよいよ、Promovolveがこれらを一つの動作する入札最適化エージェントとしてどのように組み上げるかを見ていきましょう。

そのクラスは `BidOptimizationAgent` で、`modules/core/src/main/scala/promovolve/rl/BidOptimizationAgent.scala` にあります。上から順に見ていきます。

## アーキテクチャ

ネスト構造は以下のようになっています：

```text
BidOptimizationAgent          (one per campaign)
  └── DQNAgent
       ├── qNetwork           (DenseNetwork: 8 → 64 → 64 → 7)
       ├── targetNetwork      (DenseNetwork: 8 → 64 → 64 → 7, periodically synced)
       └── replayBuffer       (ReplayBuffer: capacity 10,000)
```

`BidOptimizationAgent` は、キャンペーン、予算、広告配信について知っている外側のシェルです。現実のキャンペーン指標を、内側の `DQNAgent` が理解できるstate、action、rewardという抽象的な言語に変換します。`DQNAgent` は、前の章で構築した2つのニューラルネットワークとreplay bufferを所有しています。

一行で内部スタック全体が生成されます：

```scala
private val dqn = DQNAgent(config.dqnConfig, rng)
```

`BidOptimizationAgent` のそれ以外の部分はすべて補助的な処理です：ウィンドウカウンターの追跡、stateの計算、rewardの計算、そしてactionをbidMultiplierに反映することです。

## 設定

Promovolveが出荷時に持つ実際のデフォルト設定は以下の通りです：

```scala
final case class Config(
    dqnConfig: DQNAgent.Config = DQNAgent.Config(
      stateSize = 8,
      actionSize = 7,
      hiddenSizes = Vector(64, 64),
      gamma = 0.99,
      learningRate = 0.001,
      epsilonStart = 1.0,
      epsilonEnd = 0.05,
      epsilonDecay = 0.995,
      bufferSize = 10_000,
      minBufferSize = 32,
      batchSize = 32,
      targetSyncInterval = 100,
      actionMultipliers = Vector(0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.4)
    ),
    minMultiplier: Double = 0.5,
    maxMultiplier: Double = 2.0,
    overspendPenalty: Double = 2.0,
    exhaustionPenalty: Double = 5.0,
    inferenceOnly: Boolean = false
)
```

重要な設計選択を見ていきましょう。

**7つのaction、非対称。** actionMultiplierは `[0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.4]` です。1.0を中心に対称ではないことに注意してください。入札を上げるオプション（1.1, 1.2, 1.4）の方が下げるオプション（0.7, 0.8, 0.9）より多く、最も積極的な上方オプション（1.4倍）は最も積極的な下方オプション（0.7倍）よりも大きなジャンプです。これは意図的な設計選択を反映しています：競争的なオークションでは、インプレッションを逃すことの方が、わずかに過払いすることよりも悪い結果になることが多いのです。エージェントは必要なときにブレーキを強く踏むことができますが（0.7倍）、予算消化が遅れていてすぐに追いつく必要があるときのための「ターボ」オプション（1.4倍）も持っています。

**ハードバウンド：0.5から2.0。** エージェントがどんなactionの組み合わせをとっても、累積bidMultiplierはこの範囲にクランプされます。キャンペーンが基本CPMの半分以下で入札することも、2倍以上で入札することもありません。これはRLエージェントが壊滅的なことをするのを防ぐ安全柵です。

**割引率（gamma = 0.99）。** エージェントは将来のrewardを即時のrewardとほぼ同等に評価します。日次予算ペーシングにおいてこれは理にかなっています：序盤に数回クリックが得られたからといって、最初の1時間で予算を使い切ってしまうエージェントは望ましくありません。

**探索（epsilon：1.0から0.05、decay 0.995）。** エージェントは完全にランダムな状態からスタートし、徐々に学習した知識を活用する方向に移行します。学習ステップごとに0.995のdecayで、100ステップ後のepsilonは約0.61、300ステップ後は約0.22、600ステップ後は約0.05（下限）です。各観測で最大1回の学習ステップがトリガーされ、観測は15分ごとに行われるため、下限に到達するには約1週間の連続稼働が必要です。

**ペナルティ。** `overspendPenalty = 2.0` と `exhaustionPenalty = 5.0` は、予算を早く使い切りすぎないようにreward信号を形成します。reward関数を見るときに、これらがどう機能するかを正確に説明します。

## ウィンドウカウンター

観測の間（15分ごと）、エージェントは生のイベントを蓄積します：

```scala
def recordImpression(spendAmount: Double): Unit = {
  windowImpressions += 1
  windowSpend += spendAmount
  dayImpressions += 1
  daySpend += spendAmount
}

def recordClick(): Unit = {
  windowClicks += 1
  dayClicks += 1
}

def recordBidOpportunity(won: Boolean): Unit = {
  windowBidOpportunities += 1
  if (won) windowWins += 1
}
```

`window*` カウンターは前回の観測以降に何が起きたかを追跡します。`day*` カウンターは監視用に一日全体を追跡します。CampaignEntityは、インプレッション、クリック、入札機会がシステムを流れるたびにこれらのメソッドを呼び出します。`observe()` が呼ばれるまでに、ウィンドウカウンターには直近15分間のアクティビティのサマリーが含まれています。

## state：キャンペーン指標を数値に変換する

`toState` メソッドは `Observation` とウィンドウカウンターを組み合わせて、ニューラルネットワークが処理できる8次元の配列に変換します：

```scala
private def toState(obs: Observation): Array[Double] = {
  val maxCpm = if (obs.maxCpm > 0) obs.maxCpm else 1.0
  val dailyBudget = if (obs.dailyBudget > 0) obs.dailyBudget else 1.0

  Array(
    // 0: effective CPM (normalized)
    math.min(2.0, (obs.maxCpm * _bidMultiplier) / maxCpm),
    // 1: CTR in window
    if (windowImpressions > 0) math.min(1.0, windowClicks.toDouble / windowImpressions)
    else 0.0,
    // 2: win rate
    if (windowBidOpportunities > 0) windowWins.toDouble / windowBidOpportunities
    else 0.5,
    // 3: budget remaining fraction
    math.max(0.0, math.min(1.0, obs.budgetRemaining / dailyBudget)),
    // 4: time remaining fraction
    math.max(0.0, math.min(1.0, obs.timeRemaining)),
    // 5: spend rate vs ideal (1.0 = on pace)
    spendRate(obs),
    // 6: impression rate (normalized by expected)
    normalizedImpressionRate(obs),
    // 7: CPC (normalized)
    if (windowClicks > 0) math.min(2.0, (windowSpend / windowClicks) / maxCpm)
    else 0.0
  )
}
```

各次元は小さな範囲（おおよそ0から2）に正規化されているため、ニューラルネットワークが効果的に学習できます。各次元がエージェントに何を伝えるかは以下の通りです：

| Index | Feature | What it means |
|-------|---------|---------------|
| 0 | Effective CPM | 基本価格に対して現在どれだけ入札しているか。bidMultiplier自体に等しい。 |
| 1 | CTR | 直近15分間のクリック率。高いほど良い。 |
| 2 | Win rate | オークションの勝率。低い場合は他に負けている。 |
| 3 | Budget remaining | 今日の残り予算（1.0 = 満額、0.0 = 空）。 |
| 4 | Time remaining | 一日の残り時間（1.0 = 開始時、0.0 = 終了時）。 |
| 5 | Spend rate | 理想的な均等ペースに対する現在の支出速度。1.0はペース通り、2.0は理想の2倍の速さで支出していることを意味する。 |
| 6 | Impression rate | 取得したインプレッション数を、1ウィンドウあたり100の基準値で正規化したもの。 |
| 7 | CPC | 基本CPMで正規化したクリック単価。低いほど良い。 |

`Observation` case classは、ウィンドウカウンターから直接取得できないキャンペーンレベルのデータを提供します：

```scala
final case class Observation(
    maxCpm: Double,         // Campaign's base max CPM (before multiplier)
    dailyBudget: Double,    // Total daily budget in dollars
    budgetRemaining: Double, // Remaining budget in dollars
    timeRemaining: Double,  // Fraction of delivery period remaining
    timestamp: Instant      // When this observation was taken
)
```

spend rateの計算は、もう少し詳しく見る価値があります：

```scala
private def spendRate(obs: Observation): Double = {
  if (obs.dailyBudget <= 0 || obs.timeRemaining >= 1.0) return 1.0
  val elapsed = 1.0 - obs.timeRemaining
  if (elapsed <= 0) return 1.0
  val expectedSpend = obs.dailyBudget * elapsed
  if (expectedSpend <= 0) return 1.0
  val actualSpend = obs.dailyBudget - obs.budgetRemaining
  math.min(3.0, actualSpend / expectedSpend) // cap at 3x overspend
}
```

一日の40%が経過し、予算の40%を使った場合、spend rateは1.0 -- 完璧なペースです。同じ時間で予算の60%を使った場合、rateは1.5 -- 過剰支出しています。この一つの数値が、エージェントに入札をより積極的にすべきか控えめにすべきかについて強い信号を与えます。

## reward：エージェントが最適化する対象

```scala
private def computeReward(obs: Observation): Double = {
  val clickReward = windowClicks.toDouble

  val rate = spendRate(obs)
  val overspendPenalty =
    if (rate > 1.5) config.overspendPenalty * (rate - 1.5) else 0.0

  val exhaustionPenalty =
    if (obs.budgetRemaining <= 0 && obs.timeRemaining > 0.1)
      config.exhaustionPenalty
    else 0.0

  clickReward - overspendPenalty - exhaustionPenalty
}
```

rewardはシンプルです：クリック数からペナルティを引いたものです。エージェントはウィンドウ内の各クリックに対して+1を受け取ります。しかし2つのことがrewardを減少させます：

1. **Overspend penalty。** spend rateが1.5倍を超える（理想より50%速く支出している）場合、1.5をどれだけ超えているかに比例してペナルティが発生します。`overspendPenalty = 2.0` の場合、spend rateが2.5だとペナルティは `2.0 * (2.5 - 1.5) = 2.0` -- クリック2回分のrewardを失うのと同等です。

2. **Exhaustion penalty。** 一日の10%以上が残っている状態で予算がゼロになると、5.0のフラットペナルティが適用されます。広告が深夜まで配信されるべきところ午後3時に予算を使い果たすことは深刻な失敗です。このペナルティにより、エージェントはそれを回避することを確実に学習します。

この組み合わせにより、エージェントは一日を通して持続可能なペースで支出しながらクリック数を最大化することを促されます。

## 観測ループ

以下がコアメソッドで、15分ごとに呼び出されます：

```scala
def observe(obs: Observation): (Double, Option[Double]) = {
  val state = toState(obs)

  // If we have a previous state, store the transition and learn
  val loss = prevState match {
    case Some(ps) =>
      val reward = computeReward(obs)
      dayRewardSum += reward
      val done = obs.budgetRemaining <= 0 || obs.timeRemaining <= 0
      dqn.store(ps, prevAction.get, reward, state, done)
      dqn.trainStep()

    case None => None
  }
  dayObservations += 1

  // Select next action
  val action =
    if (config.inferenceOnly) dqn.selectGreedy(state)
    else dqn.selectAction(state)

  // Apply action: adjust multiplier
  val adjustment = config.dqnConfig.multiplierForAction(action)
  _bidMultiplier = math.max(
    config.minMultiplier,
    math.min(config.maxMultiplier, _bidMultiplier * adjustment)
  )

  // Save state for next observation
  prevObservation = Some(obs)
  prevState = Some(state)
  prevAction = Some(action)

  // Reset window counters
  windowImpressions = 0
  windowClicks = 0
  windowSpend = 0.0
  windowBidOpportunities = 0
  windowWins = 0

  (_bidMultiplier, loss)
}
```

各呼び出しで何が起こるか、ステップごとに追ってみましょう。

**ステップ1：観測をstateに変換。** `toState` メソッドが `Observation` をウィンドウカウンターと組み合わせ、正規化された8要素の配列を生成します。

**ステップ2：前回のactionから学習。** これが最初の観測でなければ、前回選択したactionの結果が分かっています。reward（クリック数からペナルティを引いたもの）を計算し、遷移 `(prevState, prevAction, reward, currentState, done)` を構築してreplay bufferに格納し、1回の学習ステップを実行します。`done` フラグは、予算が枯渇したか一日が終了した場合にtrueになります。

**ステップ3：次のactionを選択。** inference-onlyモードの場合は、最もQ値の高いactionを選びます。それ以外はepsilon-greedyを使用します：確率epsilonでランダムなactionを、そうでなければ貪欲な最善手を選びます。

**ステップ4：actionを適用。** 選択されたactionのmultiplierを参照し（例：action 4は1.1倍に対応）、現在のbidMultiplierに掛けて、結果を[0.5, 2.0]にクランプします。

**ステップ5：次回のためにstateを保存。** 次の観測時にrewardを計算して遷移を構築できるよう、現在のstateとactionを保存します。

**ステップ6：ウィンドウカウンターをリセット。** 次の15分ウィンドウに備えて、インプレッション、クリック、支出、入札機会のすべてのカウンターをクリアします。

メソッドは新しいbidMultiplierと学習ロス（学習が行われた場合）を返します。CampaignEntityは次の観測までのすべての入札応答にこのbidMultiplierを使用します。

## 累積multiplier

微妙ですが重要なポイント：actionはmultiplierを直接設定するのではなく、*スケーリング*します。各actionは、現在のmultiplierに対する相対的な調整です。

一日を通してmultiplierがどのように変化するかの具体例を示します：

| Observation | Action chosen | Multiplier before | Calculation | Result |
|-------------|--------------|-------------------|-------------|--------|
| 1 (9:00 AM) | 0.9x | 1.0 | 1.0 x 0.9 | 0.9 |
| 2 (9:15 AM) | 1.2x | 0.9 | 0.9 x 1.2 | 1.08 |
| 3 (9:30 AM) | 0.7x | 1.08 | 1.08 x 0.7 | 0.756 |
| 4 (9:45 AM) | 1.4x | 0.756 | 0.756 x 1.4 | 1.058 |
| 5 (10:00 AM) | 1.4x | 1.058 | 1.058 x 1.4 | 1.482 |
| 6 (10:15 AM) | 1.4x | 1.482 | 1.482 x 1.4 | **2.0** (clamped) |

観測6に注目してください：生の結果は2.074ですが、最大値を超えているため2.0にクランプされます。ハードバウンドは常に適用されます。これがコードにおける安全メカニズムです：

```scala
_bidMultiplier = math.max(
  config.minMultiplier,
  math.min(config.maxMultiplier, _bidMultiplier * adjustment)
)
```

この累積設計により、エージェントは複数のステップにわたって大きな調整を行えます（0.7 x 0.7 = 0.49、0.5にクランプ）が、個々のステップはそれぞれ穏やかな変更です。また、エージェントは以前の判断を「取り消す」ことを学習する必要があります -- 午前中に入札し過ぎた場合、全体のmultiplierを下げるために午後は1.0未満のmultiplierを選ぶ必要があります。

## 監視用の日次統計

エージェントは監視ダッシュボード用に累積日次指標を追跡します：

```scala
def dayStats: BidOptimizationAgent.DayStats = BidOptimizationAgent.DayStats(
  impressions = dayImpressions,
  clicks = dayClicks,
  spend = daySpend,
  observations = dayObservations,
  totalReward = dayRewardSum
)
```

`DayStats` case classは派生指標も提供します：

```scala
final case class DayStats(
    impressions: Long,
    clicks: Long,
    spend: Double,
    observations: Int,
    totalReward: Double
) {
  def ctr: Double = if (impressions > 0) clicks.toDouble / impressions else 0.0
  def costPerClick: Double = if (clicks > 0) spend / clicks else 0.0
}
```

これらの数値により、オペレーターはエージェントの日々のパフォーマンスを確認できます。クリック数は増えているか？クリック単価は改善しているか？合計rewardは上昇傾向にあるか？次の章では、学習曲線を監視するためにこれらを日をまたいでどう使用するかを見ていきます。

## まとめ

`BidOptimizationAgent` は薄い変換レイヤーです。インプレッション、クリック、予算、時刻という雑多な現実世界を、DQNが必要とするきれいな抽象概念 -- 固定サイズのstateベクトル、離散的なaction、スカラーのreward -- に変換します。実際の学習は、前の章で構築した `DQNAgent` の内部で行われます。

主要な設計上の判断は以下の通りです：

- **8次元のstate** -- 現在のパフォーマンスと残りリソースについてエージェントが知る必要のあるすべてを捉えます。
- **7つの非対称action** -- 入札調整に対する細かい制御を可能にし、入札を上げるためのより積極的なオプションを備えています。
- **ハードバウンド付きの累積multiplier** -- エージェントは段階的に調整し、壊滅的なことはできません。
- **ペーシングペナルティ付きのクリックベースreward** -- エージェントは持続可能に支出しながらパフォーマンスを最大化することを学習します。
- **15分の観測サイクル** -- 意味のあるパターンを観測するのに十分遅く、変化する状況に対応するのに十分速い。

次の章では、このエージェントが本番環境の現実にどう対処するかを見ていきます：日の境界、再起動をまたぐ永続化、cold start、そして多くのエージェントが同じマーケットプレイスで同時に学習しているという事実です。
