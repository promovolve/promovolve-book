# オークションタイミング：定期的 vs リアルタイム

Promovolveと従来のアドテクとの最も根本的な違いは、オークションが**いつ**実行されるかです。

## 従来：リクエストごとのオークション

```
t=0ms    User loads page
t=5ms    SSP sends bid request to exchange
t=10ms   Exchange broadcasts to DSPs
t=80ms   DSPs respond with bids
t=85ms   Exchange picks winner
t=90ms   Ad creative URL returned
t=200ms  Ad renders on page
```

**利点**：最新の入札、競争的な価格発見
**欠点**：50〜200msのレイテンシ、オークションQPS = ページQPS、障害時 = 空の広告枠

## Promovolve：定期的なバッチオークション

```
Crawl time (background, 2am daily + 5-min re-auctions):
  t=0s     Crawler classifies page (LLM)
  t=1s     AuctioneerEntity starts auction
  t=3s     Bids collected (800ms timeout for taxonomy)
  t=4s     Candidates cached in DData

Serve time (user-facing):
  t=0.0ms  User loads page
  t=0.1ms  Local DData lookup
  t=0.2ms  Pacing gate + Thompson Sampling
  t=0.3ms  Ad response sent
```

**利点**：サブミリ秒配信、有限の計算量、優雅な障害処理、探索
**欠点**：古い入札（再オークション間隔最大5分）、ユーザーレベルのシグナルなし

## 定期的オークションが勝つ場合

1. **シグナルがユーザーではなくコンテンツである**：PromovolveはLLM分類によるコンテンツカテゴリをターゲティングします。コンテンツはゆっくり変化するため、定期的なオークションで十分です。
2. **単一パブリッシャーの管理**：クロスパブリッシャーの価格発見は不要です。
3. **配信レイテンシが重要**：パフォーマンスを重視するパブリッシャーにとって、広告枠ごとに100msを追加することは受け入れられません。
4. **探索に価値がある**：パブリッシャーは、どの広告主が最も多く支払うかだけでなく、どのクリエイティブがユーザーを引きつけるかを学びたいと考えています。

## リフレッシュサイクル

Promovolveの再オークション間隔（5分）は中間的な選択です：
- キャンペーンの予算変更に反応するのに十分な頻度
- エンティティアクターを圧倒しない程度の低頻度
- DData内の候補は120分のTTLで複数の再オークションサイクルを生き延びる
