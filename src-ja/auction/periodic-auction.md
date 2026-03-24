# 定期バッチオークション

Promovolveの最も重要なアーキテクチャ上の選択は、オークションがリクエスト単位ではなく**事前に**実行されることです。コンテンツがクロールされると（デフォルトスケジュール: Quartz cronにより毎日午前2時）、システムは多段階オークションを完全に実行し、結果をDDataにキャッシュして、配信時に即座にルックアップできるようにします。

## オークションパイプライン

```
┌─────────────────────────┐
│ Page Classification     │  LLM-based (Gemini/OpenAI/Anthropic)
│                         │  → IAB categories + confidence scores
└────────┬────────────────┘
         ▼
┌─────────────────────────┐
│ Category Ranking        │  TaxonomyRankerEntity per (category, site)
│                         │  → Thompson-sampled weights, 7-day half-life
└────────┬────────────────┘
         ▼
┌─────────────────────────┐
│ Bid Collection          │  CategoryBidderEntity (5 virtual shards)
│                         │  → CampaignDistributor (8 workers)
│                         │  → CampaignEntity bid responses
└────────┬────────────────┘
         ▼
┌─────────────────────────┐
│ Candidate Shortlisting  │  Fair selection: 1 per campaign, fill remainder
│                         │  → Top K per slot (default K=3)
└────────┬────────────────┘
         ▼
┌─────────────────────────┐
│ ServeIndex Caching      │  DData WriteLocal, 120-minute TTL
│                         │  → Replicated to all API nodes via gossip
└─────────────────────────┘
```

## 定期再オークション

クロールサイクルの間、システムは48時間の鮮度ウィンドウ内の最近のコンテンツに対して、**5分ごとに定期再オークション**（`promovolve.auction.reauction-interval`）を実行します。さらに、キャンペーンや広告主の状態変更によるイベント駆動型再オークションもトリガーされます。

## コンテンツ鮮度ウィンドウ

直近**48時間**以内に分類されたページのみがオークションに参加します。5分ごとに、AuctioneerEntityはクリーンアップを実行し、48時間より古い分類を削除します。

## 主要な設定

| パラメータ | 値 | 環境変数 |
|-----------|-------|---------|
| 再オークション間隔 | 5分 | `REAUCTION_INTERVAL` |
| コンテンツ鮮度 | 48時間 | — |
| クロールcronスケジュール | `"0 0 2 * * ?"` | サイト別設定 |
| クロール最大深度 | 2 | サイト別設定 |
| クロール並行数 | 5 | サイト別設定 |
| ServeIndex TTL | 120分 | — |
| Taxonomy問い合わせタイムアウト | 800ms | — |
