# データフロー: CrawlとServe

Promovolveはワークロードを、根本的に異なるパフォーマンス特性を持つ2つのフェーズに分離しています。

## Crawlフェーズ（書き込みパス）

Crawlフェーズは設定可能なスケジュール（デフォルト: Quartz cron `"0 0 2 * * ?"` — 毎日午前2時）で実行され、「重い」計算パスです。サイトごとのクロール設定には`maxDepth`（デフォルト: 2）と`concurrency`（デフォルト: 5）が含まれ、4つの固定スレッドを持つ専用の`crawler-dispatcher`上で実行されます。

```mermaid
graph TD
    Crawler["External Crawler<br/>(4-thread pool)"] --> Classification["Page Classification<br/>(LLM: Gemini/OpenAI/Anthropic)<br/>categories + confidence scores"]
    Classification --> Auctioneer["AuctioneerEntity<br/>(sharded by siteId)"]
    Auctioneer --> Taxonomy["TaxonomyRankerEntity<br/>(800ms timeout)<br/>Thompson-sampled weights, 7-day half-life<br/>site-blend threshold: 20.0, min imps: 100"]
    Auctioneer --> CatBid["CategoryBidderEntity fan-out<br/>(5 virtual shards)"]
    CatBid --> CampDist["CampaignDistributor (8 workers)"]
    CampDist --> CampResp["CampaignEntity bid responses<br/>bidCpm = max(maxCpm × multiplier, floor)"]
    Auctioneer --> ServeIndex["Candidate shortlisting → ServeIndex<br/>(DData, WriteLocal, 120-min TTL)"]
```

## Serveフェーズ（読み取りパス）

Serveフェーズはすべての広告リクエストを処理するため、極めて高速でなければなりません。

```mermaid
graph TD
    User["User Request (page load)"] --> API["API Node (HTTP, port 8080)"]
    API --> Lookup["Lookup ServeIndex from local DData<br/>Key: siteId|slotId → Vector of CandidateView"]
    Lookup --> Recency["Content Recency Filter<br/>classifiedAtMs within 48h window"]
    Recency --> FreqCap["Frequency Cap Check<br/>(100ms timeout, fail-open)<br/>query AdvertiserEntity per user"]
    FreqCap --> Rate["Rate Tracking<br/>(synchronous EMA, 1s window, α=0.3)"]
    Rate --> Pacing["Pacing Gate (PI control)<br/>aggregate budget from CachedSpendInfo<br/>throttle probability 0.0–0.99"]
    Pacing -->|"random() < throttle"| Skip["Skip (204)"]
    Pacing -->|pass| TS["Thompson Sampling Selection<br/>sample Beta(clicks+1, non_clicks+1)<br/>score = sampledCTR × log(1 + CPM)<br/>argmax"]
    TS --> Budget["Budget Reservation<br/>CampaignEntity.Reserve +<br/>AdvertiserEntity.GetBudgetStatus"]
    Budget -->|failure| Next["Try next-best by Thompson score"]
    Budget -->|success| Serve["Serve ad"]
    Next -->|all exhausted| NoCandidates["NoCandidates (204)"]
```

## なぜ2つのフェーズに分けるのか?

| 関心事 | Crawlフェーズ | Serveフェーズ |
|---------|-------------|-------------|
| レイテンシ | 数秒かかっても問題ない | 1ms未満が必須 |
| 計算量 | フルオークション、LLM分類 | キャッシュルックアップ + Beta sampling |
| Fan-out | 多数のentity | ゼロ（ローカルDData） |
| 障害時の動作 | 次回クロールでリトライ | キャッシュされた候補を配信 |
| スケーリング | entityノードの追加 | APIノードの追加 |
| Dispatcher | `crawler-dispatcher` (4 threads) | デフォルトのPekko dispatcher |

この分離により:
1. **オークションの複雑さが配信レイテンシに影響しない** — LLM分類とマルチentityのfan-outはバックグラウンドで実行される
2. **配信キャパシティが独立してスケールする** — APIノードの追加によりオークション負荷に影響を与えずにリクエストスループットを向上できる
3. **一時的な障害がユーザーに見えない** — キャッシュされた候補は120分のTTLが切れるまでServeIndexに残り続ける
