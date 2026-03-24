# ゼロから学ぶ強化学習

この章では、Promovolveの入札最適化を実行例として使いながら、RLをゼロから解説します。最後まで読めば、`DQNAgent.scala`と`BidOptimizationAgent.scala`のすべての行を理解できるようになります。

## セットアップ：世界の中のエージェント

あなたが1つの広告キャンペーンを管理していると想像してください。1日の予算は$100で、最大入札額は$5 CPM（1,000インプレッションあたりのコスト）です。15分ごとに状況を確認し、オークションで勝つためにより高く入札すべきか、予算を節約するために低く入札すべきかを決定します。

これは**強化学習**の問題です。以下の要素があります：

- **エージェント** — 入札戦略（Promovolveでは：`BidOptimizationAgent`）
- **環境** — 広告オークション市場（他のキャンペーン、ユーザートラフィック、クリックパターン）
- **State** — 現在の状況について観測できるもの（残り予算、残り時間、クリック率など）
- **Action** — 実行できること（入札を上げる、下げる、維持する）
- **Reward** — どれだけうまくいったかのフィードバック（獲得クリック数、過剰消化のペナルティを差し引いたもの）

エージェントの目標：時間を通じた総報酬を最大化する**方策** — stateからactionへのマッピング — を学習することです。

## なぜルールベースではダメなのか？

ルールを書くことはできます：「予算が60%以上残っていて正午を過ぎていたら、入札を上げる」。しかし：

- 適切な閾値が事前にわからない
- 正しい戦略は競合他社の行動に依存し、それは変化する
- トラフィックパターンは日や季節によって異なる
- キャンペーンごとに最適な戦略が異なる

RLは経験から自動的にこれらのルールを学習します。エージェントはさまざまなactionを試し、何が起こるかを観察し、徐々に何がうまくいくかを理解していきます。

## Reward信号

Rewardはエージェントが得る唯一のフィードバックです。これが「良い」とは何かを定義します。

Promovolveでは、15分ごとにエージェントが受け取るのは：

```
reward = clicks_in_window − penalty

where penalty = 2.0 × max(0, spend_rate − 1.5)
```

- **クリック**が主要な目標 — エンゲージメントを求めています
- **ペナルティ**は消化レートが理想的なペースの1.5倍を超えた場合にのみ発動 — 若干の過剰消化は許容されますが、正午までに予算を使い果たすのは問題です

これが`BidOptimizationAgent.computeReward()`のreward functionです。エージェントが学習するすべてのことは、この単一の信号から生まれます。

## Q-Values：Actionの評価

Q-learningの核となるアイデアがここにあります。エージェントが取り得るすべてのstateについて、**各actionはどれくらい良いか？**を知りたいのです。

**Q-value** `Q(state, action)`は次の問いに答えます：「このstateでこのactionを取り、その後最適に行動した場合、どれだけの総報酬を得られるか？」

例えば：
- State：予算70%残、時間50%残、CTRが高い
- `Q(state, bid_higher)` = 12.5（ここで入札を上げると将来の報酬が12.5になる傾向がある）
- `Q(state, hold)` = 10.0
- `Q(state, bid_lower)` = 7.3

エージェントは最も高いQ-valueを持つactionを選ぶだけです。難しいのは正確なQ-valueの学習です。

## Bellman方程式：経験からの学習

actionを取った後、エージェントは何が起きたかを観察します：

```
(state, action, reward, next_state)
```

例えば：「予算70%でCTRが高い状態で、入札を上げて、3クリック（reward=3.0）を得て、今は予算65%でCTRがわずかに低い状態になった。」

**Bellman方程式**は次のように述べます：

```
Q(state, action) = reward + γ × max_a Q(next_state, a)
```

訳すと：あるstateでactionを取ることの価値は、即時のrewardに加えて、次のstateからの割引された最良の価値に等しい。

**γ (gamma)**は**discount factor**（Promovolveでは0.99）です。これは将来のrewardが即時のものよりわずかに価値が低いことを意味します。次のステップでのreward 1.0は現在0.99の価値があります。100ステップ先のrewardは0.99^100 ≈ 0.37の価値です。これにより、エージェントが無限に辛抱強くなることを防ぎ、より早いrewardを好むようになります。

## テーブルからニューラルネットワークへ

stateが単純（グリッド位置など）であれば、Q-valueをテーブルに格納できます。しかしPromovolveのstateは8つの連続次元を持ちます — 予算割合、時間割合、CTR、勝率など。可能なstateは無限にあります。テーブルでは対応できません。

代わりに、**ニューラルネットワーク**を使ってQ関数を近似します。ネットワークはstate（8つの数値）を入力として受け取り、各action（5つの数値）のQ-valueを出力します：

```
Input: [0.7, 0.03, 0.65, 0.70, 0.50, 1.1, 0.8, 0.4]
         ↓
   [64 neurons, ReLU] → [64 neurons, ReLU] → [5 outputs, linear]
         ↓
Output: [12.5, 10.0, 7.3, 11.2, 9.8]
          ↑
     Q-values for each action
     (pick the highest: action 0, bid lower aggressively)
```

これがコード中の`DenseNetwork.forward()`です。ネットワークには学習によって獲得される約4,800個のパラメータ（重みとバイアス）があります。

## 学習：ネットワークがどのように学ぶか

学習は以下を繰り返し行います：

1. **予測**：ネットワークをフォワードパスで実行し、あるstateの予測Q-valueを得る
2. **ターゲット計算**：Bellman方程式を使って、Q-valueが*あるべき*値を計算する
3. **更新**：予測をターゲットに近づけるようにネットワークの重みを調整する

具体的に、遷移`(state, action=2, reward=3.0, next_state)`の場合：

```
predicted = network.forward(state)[2]          // what we predicted for action 2
target    = 3.0 + 0.99 × max(network.forward(next_state))  // what it should be
loss      = (predicted - target)²              // how wrong we were
```

次にbackpropagationが損失を減らすように重みを調整します。これが`DenseNetwork.train()` — 標準的な勾配降下法です。

数千回の更新を経て、ネットワークのQ-value予測は正確になり、エージェントの方策は改善されます。

## Experience Replay：記憶からの学習

遷移を1つずつ学習することには問題があります：連続する経験は高度に相関しています（午後2:15のstateは午後2:30のstateに非常に似ています）。ニューラルネットワークは相関したデータからの学習が苦手です。

**Experience replay**がこれを解決します。各遷移をすぐに学習するのではなく、エージェントはバッファに格納します：

```
buffer = [(state₁, action₁, reward₁, next_state₁),
          (state₂, action₂, reward₂, next_state₂),
          ...
          (state₁₀₀₀₀, ...)]
```

そして、各学習ステップで、バッファから32の遷移をランダムにサンプリングします。これにより相関が断ち切られます — バッチには1日目、3日目、7日目の遷移が含まれ、異なる予算レベルや異なる時間帯のものが混在する可能性があります。

コード中では、これは`ReplayBuffer` — 容量10,000の循環バッファです。満杯になると、新しい遷移が最も古いものを上書きします。`buffer.sample(32, rng)`がランダムなバッチを返します。

## Double DQN：過大推定の修正

標準的なDQNには微妙なバグがあります。ターゲットを計算する際：

```
target = reward + γ × max(network.forward(next_state))
```

同じネットワークが最良のactionの**選択**（`max`による）と**評価**の両方を行います。これは系統的な過大推定を引き起こします — ネットワークはactionを過大評価する傾向があり、特に予測にノイズが多い学習初期に顕著です。

**Double DQN**は2つのネットワークを維持することでこれを修正します：

- **Q-network**：毎学習ステップで更新。最良のactionを**選択**するために使用。
- **Target network**：Q-networkの遅延コピー。選択されたactionを**評価**するために使用。

```
best_action = argmax(q_network.forward(next_state))     // Q-net picks
target = reward + γ × target_network.forward(next_state)[best_action]  // target-net evaluates
```

Target networkは100学習ステップごとにQ-networkから同期されます（`targetNetwork.copyFrom(qNetwork)`）。この分離により過大推定が減少し、学習がより安定します。

これは`DQNAgent.trainStep()`の83-93行目です。

## Explorationとexploitation

エージェントが常に最高のQ-valueを持つactionを選択すると、実は別のactionの方が良いことを発見できないかもしれません。平凡な戦略に固定されてしまう可能性があります。

**Epsilon-greedy** explorationがこれを解決します。確率**ε (epsilon)**で、エージェントは最良のものの代わりにランダムなactionを取ります：

```scala
if (rng.nextDouble() < epsilon)
  rng.nextInt(actionSize)    // explore: random action
else
  argMax(qNetwork.forward(state))  // exploit: best known action
```

Epsilonは高い値（1.0 = 完全にランダム）から始まり、時間とともに減衰（学習ステップごとに0.995倍）してフロアの0.05まで下がります。これは以下を意味します：

- **1日目**：ほぼすべてランダム — エージェントは探索中
- **3-5日目**：主に学習した方策を活用し、まだ15-30%がランダム
- **8日目以降**：95%が活用、5%が探索 — エージェントは自信を持っているが、時折新しいことを試す

この減衰スケジュールにより、エージェントは何も知らないときは積極的に探索し、徐々に学んだことの活用に移行します。

## すべてをまとめる

以下が各`CampaignEntity`アクター内で実行される完全なサイクルです：

### 各入札リクエスト（高速パス）
```
bid_cpm = campaign.max_cpm × agent.bid_multiplier
```
multiplierは単にキャッシュされた数値です。ニューラルネットワークは関与しません。サブマイクロ秒。

### 各インプレッション
```
agent.record_impression(cpm)
agent.record_bid_opportunity(won=true)
```
ウィンドウカウンターをインクリメントします。同様にサブマイクロ秒。

### 各クリック
```
agent.record_click()
```
ウィンドウクリックカウンターをインクリメントします。

### 15分ごと（低速パス）
```
1. Build state vector from window metrics:
   [effective_cpm, ctr, win_rate, budget_remaining,
    time_remaining, spend_rate, impression_rate, cost_per_click]

2. If we have a previous state:
   a. reward = clicks - overspend_penalty
   b. Store (prev_state, prev_action, reward, state, done) in replay buffer
   c. Sample batch of 32 from buffer
   d. For each sample: compute Double DQN target, train network (SGD)

3. Select action: epsilon-greedy
4. Apply: bid_multiplier *= action_adjustment (e.g., 1.1×)
5. Clamp: bid_multiplier in [0.5, 2.0]
6. Reset window counters
```

### 日の終わりに
```
1. Store terminal transition (done=true) if we took any actions
2. Reset bid_multiplier to 1.0
3. Keep all network weights (the learned policy carries over)
```

### エンティティ再起動時
```
1. Restore network weights from persisted snapshot
2. Replay buffer is empty (ephemeral) — agent resumes with learned policy
   but needs to re-accumulate experience for training
```

## エージェントが学ぶこと

数日にわたり、良好なパフォーマンスを発揮するエージェントは次のようなパターンを学習します：

- **1日の序盤で予算が十分ある場合**：積極的に入札する（multiplier > 1.0）ことで質の高いインプレッションを獲得
- **予算が少なく残り時間がある場合**：引き下げる（multiplier < 1.0）ことで残り予算を延ばす
- **CTRの高いコンテンツ**：入札を上げる価値がある — クリックがreward
- **過剰消化**：ペナルティ閾値（1.5倍ペース）に達する前に入札を下げる
- **1日の終わりに予算が余っている場合**：残り予算を生産的に使うために入札を上げる

これらはプログラムされたルールではありません。reward信号と数千の学習ステップから創発するものです。

## 主要なハイパーパラメータ

| Parameter | Value | What it controls |
|-----------|-------|-----------------|
| γ (gamma) | 0.99 | 将来のrewardの重要度（高い = 辛抱強い） |
| Learning rate | 0.001 | ネットワークの更新速度（高すぎると = 不安定） |
| ε start | 1.0 | 初期exploration率（完全にランダム） |
| ε end | 0.05 | 最小exploration（常に5%ランダム） |
| ε decay | 0.995 | exploreからexploitへの移行速度 |
| Buffer size | 10,000 | 記憶する経験の量 |
| Batch size | 32 | 学習ステップあたりの遷移数 |
| Target sync | 100 steps | Target networkがQ-networkからコピーする頻度 |
| Hidden layers | [64, 64] | ネットワーク容量（大きい = より複雑な方策） |
| Q-clip | ±100 | 極端なQ-value推定を防止 |
| Grad clip | ±5.0 | 学習中の勾配爆発を防止 |

これらはすべて`DQNAgent.Config`と`BidOptimizationAgent.Config`に含まれています。

## 理論からコードへ

これでソースコードを直接読むことができます：

| Concept | File | Key method |
|---------|------|-----------|
| Neural network (forward + backprop) | `DenseNetwork.scala` | `forward()`, `train()` |
| Experience replay buffer | `ReplayBuffer.scala` | `store()`, `sample()` |
| Double DQN + epsilon-greedy | `DQNAgent.scala` | `selectAction()`, `trainStep()` |
| State/reward/action design | `BidOptimizationAgent.scala` | `toState()`, `computeReward()`, `observe()` |
| Integration with campaign actor | `CampaignEntity.scala` | `RLObserveTick`, `TryReserve` |

次の章では、これらの各コンポーネントを正確な数式と設定値とともに詳細に解説します。
