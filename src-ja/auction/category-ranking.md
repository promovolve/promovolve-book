# フェーズ2: カテゴリランキング

ページ分類で上位Kカテゴリが特定された後、各カテゴリには**ランカー重み**が割り当てられます。これは、そのカテゴリの広告がこの特定のサイトで過去にどの程度のパフォーマンスを示したかを反映します。

## TaxonomyRankerEntity

各`(category, siteId)`ペアには独自のTaxonomyRankerEntityがあります。`application.conf`からの設定:

| パラメータ | デフォルト | 環境変数 |
|-----------|---------|---------|
| 半減期 | 7日 | `TAXONOMY_RANKER_HALF_LIFE` |
| 事前分布 α | 1.0 | `TAXONOMY_RANKER_PRIOR_ALPHA` |
| 事前分布 β | 1.0 | `TAXONOMY_RANKER_PRIOR_BETA` |
| フラッシュ間隔 | 5秒 | `TAXONOMY_RANKER_FLUSH_EVERY` |
| サイトブレンド閾値 | 20.0 | — |
| サイト最小インプレッション数 | 100.0 | `TAXONOMY_RANKER_SITE_MIN_IMPRESSIONS` |
| サイト統計最大保持期間 | 14日 | — |
| カテゴリあたり最大サイト数 | 5000 | `TAXONOMY_RANKER_MAX_SITES` |

### 重み計算

ランカーはBeta-BernoulliモデルによるThompson Samplingを使用します:

1. このサイトのカテゴリごとのクリック数/インプレッション数を管理する
2. CTRを`Beta(prior_α + clicks, prior_β + non_clicks)`としてモデル化する — デフォルトの事前分布は`Beta(1, 1)`（一様分布）
3. Beta分布から**サンプリング**して重みを取得する
4. サンプリングされた重みをAuctioneerEntityに返す

### サイトブレンディング

特定のサイトの観測数が`site-min-impressions`（100）より少ない場合、ランカーは`site-blend-threshold`（20.0）を使用して、サイト固有の統計をグローバルなカテゴリ統計とブレンドします。これにより、新しいサイトがコールドスタート問題に悩まされることを防ぎます。

### ファンアウトとタイムアウト

AuctioneerEntityはすべてのK個のTaxonomyRankerEntityに対して**800msのタイムアウト**で並列にクエリを送信します。

ランカーが800ms以内に応答しない場合:
- 半減期減衰を適用した**キャッシュ済みの重み**を使用: `weight × 0.5^(ageSeconds / halfLifeSeconds)`
- デフォルトでは`halfLifeSeconds = 7日 = 604800s`
- キャッシュデータがない場合は**事前分布の重み**（0.5）にフォールバック

### 統計のライフサイクル

- `site-stats-max-age`（14日）より古い統計は削除される
- カテゴリあたりのサイト数は`max-sites-per-category`（5000）で上限が設けられる
- 統計は`flush-every`（5秒）ごとに永続化される

## 最終カテゴリスコア

```
categoryScore = classifierConfidence × rankerWeight
```

このスコアは`CandidateView.categoryScore`に伝播し、配信時のコールドスタートにおけるThompson Samplingの事前分布として機能します。
