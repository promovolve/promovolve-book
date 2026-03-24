# 第3章: 最初のオークション

午前2時7分。クローラーがユキの最新記事「東京都東部の紅葉ハイキング」の分類を完了したところだ。ユキのサイトのAuctioneerEntityが分類結果を受け取る: Travel (0.95)、Hiking/Camping (0.85)、East Asian Culture (0.70)。

3つの広告枠を埋める必要がある。4つのキャンペーンがシステムに存在する。オークションが始まる。

## フェーズ1: カテゴリランキング

AuctioneerEntityが各カテゴリのTaxonomyRankerEntityに問い合わせる:「このサイトに対するあなたの重みは？」

各ランカーがBeta distributionからサンプリングする。カテゴリレベルのThompson Samplingだ:

| カテゴリ | 分布 | サンプル | 順位 |
|----------|-------------|--------|------|
| Travel | Beta(12, 88) — 実績のあるパフォーマー | 0.14 | 1位 |
| Hiking/Camping | Beta(3, 47) — まずまず、データあり | 0.08 | 2位 |
| East Asian Culture | Beta(1, 1) — 全く新しい、データなし | 0.61 | 3位（探索！） |

East Asian Cultureはデータがないにもかかわらず3位にランクインした。一様分布`Beta(1, 1)`が高い値をサンプリングしたからだ。これが探索だ: システムはこのカテゴリがユキのサイトで効果的かどうかを学習するために試行する。ほとんどの場合、確立されたカテゴリが勝つ。たまに、新しいカテゴリがチャンスを得る。

上位3カテゴリが入札に進む。

## フェーズ2: 入札収集

ランク付けされた各カテゴリについて、AuctioneerEntityが`CategoryBidderEntity`に問い合わせる:「このサイトのTravelに入札したいのは誰？」

CategoryBidderEntityは、そのカテゴリに登録されているすべてのキャンペーンにファンアウトする。各CampaignEntityが入札すべきかどうかを評価する:

**タケシの旅館** (Travel, Hiking): 予算残高あり？ はい ($20)。キャンペーンはアクティブ？ はい。このサイトでクリエイティブは承認済み？ はい。入札: `$5.00 × 1.0 (RL multiplier) = $5.00 CPM`。

**JR Rail Pass** (Travel): 予算残高あり？ はい。入札: `$8.00 × 1.0 = $8.00 CPM`。

**Hiking Gear Co** (Hiking): 予算残高あり？ はい。入札: `$4.00 × 1.0 = $4.00 CPM`。

**京都料理教室** (Food & Drink): このキャンペーンはTravel、Hiking、East Asian Cultureには登録されていない。入札しない。

3件の入札が集まった。すべてフロア価格 ($0.50) 以上。すべてが適格条件を通過: アクティブステータス、正の予算、クリエイティブサイズが少なくとも1つのスロットに適合。

## フェーズ3: 公平な候補選択

システムは候補をスロットに割り当てなければならない。ここでPromovolveは従来のオークションと異なる。

従来のオークションでは、3つのスロットすべてをJR Rail Passに与えるだろう。最高入札だからだ。しかしそれは全員にとって最悪だ: パブリッシャーは同じ広告を3回表示し（悪いUX）、他の広告主はチャンスを得られず（探索なし）、タケシの旅館広告の方がクリックされるかもしれないということをシステムは学習できない。

Promovolveは**公平な選択**を使用する: どのキャンペーンも2つ目のスロットを得る前に、各キャンペーンが1つのスロットを得る。

```
Slot 1 (banner):  JR Rail Pass     — $8.00 CPM (highest bidder, first pick)
Slot 2 (sidebar): Takeshi's Ryokan — $5.00 CPM (second highest, one slot each first)
Slot 3 (sidebar): Hiking Gear Co   — $4.00 CPM (third)
```

各スロットは（1つだけでなく）複数の候補を得る。CPM順に並べられるが、入札した各キャンペーンから少なくとも1つのクリエイティブが含まれることが保証される。この候補リストが、配信時の選択のためにキャッシュされるものだ。

## フェーズ4: ServeIndexへのキャッシュ

オークション結果はServeIndexに書き込まれる。これはPekkoのDistributed Data (DData) に基づくレプリケートされたインメモリストアだ。

各スロットにエントリが作成される:

```
Key: "yuki-site|banner-top|bucket-12"
Value: [
  {creative: jrpass-ad, cpm: 8.00, campaign: jrpass, advertiser: jr-west, ...},
  {creative: ryokan-ad, cpm: 5.00, campaign: takeshi, advertiser: takeshi, ...}
]

Key: "yuki-site|sidebar-1|bucket-7"
Value: [
  {creative: ryokan-ad, cpm: 5.00, campaign: takeshi, advertiser: takeshi, ...},
  {creative: hiking-boots, cpm: 4.00, campaign: hikegear, advertiser: hikegear-co, ...}
]
```

書き込みは`WriteLocal`で行われ、AuctioneerEntityが実行されているノード上で即座に完了する。2秒以内にgossipがクラスター内の他のすべてのノードにデータを伝播する。すべてのAPIノードがこれらの候補をローカルメモリに保持する。

候補のTTLは120分だ。re-auctionで更新されなければ期限切れとなり、スロットは空になる。しかしre-auctionは5分ごとに実行されるため、実際には候補は常に新鮮だ。

## 何が起きたか

約4秒のバックグラウンド処理で:

1. LLMがページコンテンツを広告カテゴリに分類した
2. Thompson Samplingがこのサイトでの過去のパフォーマンスに基づいてカテゴリをランク付けした
3. 適格なキャンペーンが最大CPMとRL multiplierに基づいて入札した
4. 公平な選択により各キャンペーンが代表権を得た
5. スロットごとの複数候補がクラスター全体のレプリケートされたメモリにキャッシュされた

読者は関与していない。ページの読み込みは遅延していない。オークション全体がバックグラウンドで行われ、結果はメモリ上で待機している。

いよいよ読者がやって来る。

---

*技術的な詳細: [Periodic Batch Auction](../auction/periodic-auction.md) · [Why Multi-Candidate?](../auction/why-multi-candidate.md) · [ServeIndex Caching](../auction/serve-index-caching.md)*
