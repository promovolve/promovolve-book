# 目次

[なぜPromovolveなのか？](./why-promovolve.md)

# ストーリー

- [パブリッシャーが参加する](./story/01-publisher-joins.md)
- [広告主が参加する](./story/02-advertiser-joins.md)
- [最初のオークション](./story/03-the-auction.md)
- [読者が訪れる](./story/04-reader-arrives.md)
- [クリック](./story/05-the-click.md)
- [ある一日](./story/06-the-day.md)
- [一週間後](./story/07-week-later.md)

# 仕組み

- [技術的な概要](./introduction.md)
- [アドテクの仕組み（とPromovolveの違い）](./comparison/from-scratch.md)

# ディープダイブ

## アーキテクチャ

- [システムアーキテクチャ](./architecture/overview.md)
  - [Entity階層とClusterロール](./architecture/entity-hierarchy.md)
  - [データフロー：クロール vs 配信](./architecture/data-flow.md)

## オークションシステム

- [定期バッチオークション](./auction/periodic-auction.md)
  - [フェーズ1：ページ分類](./auction/page-classification.md)
  - [フェーズ2：カテゴリランキング](./auction/category-ranking.md)
  - [フェーズ3：入札収集](./auction/bid-collection.md)
  - [フェーズ4：候補ショートリスト](./auction/candidate-shortlisting.md)
  - [フェーズ5：ServeIndexキャッシング](./auction/serve-index-caching.md)
- [再オークションとイベントトリガー](./auction/re-auction.md)
- [なぜマルチ候補なのか？](./auction/why-multi-candidate.md)

## パブリッシャーによるクリエイティブ承認

- [パブリッシャーによるクリエイティブ承認](./approval/overview.md)

## 配信時の選択

- [Thompson Samplingをゼロから理解する](./serving/from-scratch.md)
- [Thompson Sampling (MAB)](./serving/thompson-sampling.md)
  - [Beta-Bernoulliモデル](./serving/beta-bernoulli.md)
  - [スコアリング式](./serving/scoring-formula.md)
  - [コールドスタート戦略](./serving/cold-start.md)
  - [Beta分布サンプリング](./serving/beta-sampling.md)
- [公平な候補選択](./serving/fair-selection.md)
  - [キャンペーンごとの多様性](./serving/campaign-diversity.md)
  - [フリークエンシーキャップ](./serving/frequency-capping.md)

## 予算ペーシング

- [ペーシング概要](./pacing/overview.md)
  - [レートトラッキング（EMA）](./pacing/rate-tracking.md)
  - [PI制御ループ](./pacing/pi-control.md)
  - [トラフィックシェイプ学習](./pacing/traffic-shape.md)
  - [グレースピリオドとハイブリッドモード](./pacing/grace-periods.md)

## 強化学習

- [強化学習をゼロから理解する](./rl/from-scratch.md)
- [DQN Agent概要](./rl/overview.md)
  - [状態空間](./rl/state-space.md)
  - [行動空間](./rl/action-space.md)
  - [報酬関数](./rl/reward-function.md)
  - [Double DQNアーキテクチャ](./rl/double-dqn.md)
  - [学習ループとハイパーパラメータ](./rl/training.md)

## 分散ステート

- [分散ステートをゼロから理解する](./distributed/from-scratch.md)
- [ServeIndexとDData](./distributed/serve-index.md)
  - [Bucketed LWWMap設計](./distributed/bucketed-lwwmap.md)
  - [TTLスイープと有効期限](./distributed/ttl-sweep.md)
  - [書き込み一貫性レベル](./distributed/consistency.md)

## 従来のアドテクとの比較

- [Promovolve vs SSP/DSP/Exchange](./comparison/vs-traditional.md)
  - [オークションタイミング：定期 vs リアルタイム](./comparison/auction-timing.md)
  - [落札者選択：MAB vs 最高入札](./comparison/winner-selection.md)
  - [価格発見とFirst-Priceモデル](./comparison/price-discovery.md)
  - [学習メカニズム](./comparison/learning.md)
  - [主要イノベーション](./comparison/innovations.md)
