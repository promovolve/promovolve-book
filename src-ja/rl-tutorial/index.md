# 広告入札を通じてReinforcement Learningを学ぶ

このチュートリアルでは、Promovolveの入札最適化システムを題材として、reinforcement learning (RL) を基礎から学びます。すべての概念は実際のプロダクションScalaコードに基づいています。おもちゃの問題、gymの環境、Pythonノートブックは一切使いません。

最後まで読み終えると、以下のことが理解できるようになります:

- Reinforcement learningとは何か、いつ使うべきか
- 実世界の問題をRLタスクとしてモデル化する方法（state、action、reward）
- Neural networkがvalue functionをどのように近似するか
- DQNとDouble DQNの仕組みと、それらが重要な理由
- Experience replayとtarget networkがどのように学習を安定化させるか
- 実際のお金を扱うプロダクションシステムでRLをデプロイする方法

## なぜ広告入札はRLに最適な問題なのか

ほとんどのRLチュートリアルはビデオゲームやgrid worldを使っています。直感を養うにはそれで十分ですが、以下のようなRLの振る舞いは学べません:

- **環境が非定常である** --- トラフィックパターンは時間、曜日、季節によって変化する
- **エピソードに実際の経済的影響がある** --- 過剰支出は広告主の資金を無駄にし、過少支出は収益の機会を逃す
- **観測がノイジーで遅延している** --- アクションごとの即時フィードバックではなく、15分ごとの集約メトリクスしか見えない
- **State空間が連続的である** --- グリッドではなく、レート、比率、正規化されたシグナルの組み合わせ
- **複数のagentが相互作用する** --- 数百のキャンペーンが同時に競争し、それぞれが独自のpolicyを学習している

Promovolveの入札最適化agentは、これらすべてに直面します。これはMLフレームワークの依存関係を持たない約400行の純粋なScala実装であり、forward pass、backpropagation、トレーニングループのすべての行を読むことができます。

## 前提知識

以下に慣れていることが望ましいです:

- 基本的なプログラミングの概念（ループ、配列、関数）
- 高校レベルの数学（微分、基本的な確率）
- ML/RLの事前知識は不要 --- すべてゼロから構築します

## 章構成

1. [問題: なぜ入札最適化にRLが必要なのか](./01-the-problem.md)
2. [RLの基礎: Agent、Environment、Reward](./02-fundamentals.md)
3. [Neural Networkをゼロから構築する](./03-neural-network.md)
4. [Q-TableからDeep Q-Networkへ](./04-dqn.md)
5. [Experience Replay: 過去から学ぶ](./05-replay-buffer.md)
6. [Double DQN: 過大評価の修正](./06-double-dqn.md)
7. [すべてを統合する: BidOptimizationAgent](./07-full-agent.md)
8. [プロダクションでのトレーニング: エピソード、永続化、日次リセット](./08-production.md)
