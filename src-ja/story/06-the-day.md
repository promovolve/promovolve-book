# 第6章: ある1日の生活

タケシの旅館キャンペーンの最初の丸1日を追ってみよう。

## 朝: グレースピリオド (8:00-8:02am)

ユキのサイトにその日最初のトラフィックが来る。PI pacing controllerは新しい1日を始めたばかりで、まだリクエストレートを把握していない。最初の10秒間（または10リクエスト、遅い方）、controllerは**グレースピリオド**に入る: 99%のスロットルで、ほとんど何も配信しない。

なぜか？ controllerがトラフィックレートを制御する前に、まず計測する必要があるからだ。レートを知らずに積極的に配信すると、最初の数分で予算を使い果たす可能性がある。10秒間慎重に行動してベースラインを得る方が良い。

10リクエスト後、TrafficObserverがリクエストレートの指数加重移動平均を計算する: この時間帯で約2リクエスト/秒。PI controllerがベーススロットルを計算する:

```
ideal_serve_rate = budget_remaining / time_remaining / avg_cpm × 1000
                 = $20 / 86400s / $5 × 1000 = 0.046 serves/second

throttle = 1 - (ideal_serve_rate / observed_rate) = 1 - (0.046 / 2.0) = 0.977
```

これは積極的なスロットリングだ。リクエストの97.7%をスキップする。しかしこれは正しい: $5 CPMで$20の予算は、1日を通してわずか4,000インプレッションだ。2リクエスト/秒では、約2,000秒のフル配信分だが、1日は86,400秒ある。キャンペーンは薄く広げる必要がある。

グレースピリオド終了。通常の配信が始まる。

## 午前中: Thompson Samplingが収束する (8:00-11:00am)

3時間経過。タケシの旅館は15回表示され、2クリックを獲得。ハイキング用品広告は12回表示され、クリックゼロ。

Thompson Samplingの分布が乖離してきた:

```
Ryokan:     Beta(3, 14)  — mean ~18%, samples usually between 5-35%
Hiking Gear: Beta(1, 13) — mean ~7%, samples usually between 0-20%
```

旅館広告がほとんどの選択で勝つようになった。毎回ではない。Thompson Samplingはまだ時々ハイキング用品広告を選ぶ（サンプルがたまたま旅館のサンプルを上回った時）。しかし比率は50/50からおよそ70/30にシフトした。

もしハイキング用品広告が次の数インプレッションでクリックを獲得すれば、比率は縮まる。獲得しなければ、さらにフェードする。いつテストを止めるか誰も決める必要がない。システムが自己調整する。

## 正午: RL Agentの最初の観測 (12:00pm)

4時間経過。RL agentの15分タイマーは1日の開始から16回発火した。毎回、以下を観測する:

```
state = [effectiveCpm, ctr, winRate, budgetRemaining,
         timeRemaining, spendRate, impressionRate, costPerClick]
```

正午の観測は以下のようになる:

```
state = [1.0,    — bidding at full CPM (multiplier = 1.0)
         0.13,   — 13% CTR (2 clicks / 15 impressions this window)
         0.82,   — winning 82% of bid opportunities
         0.75,   — 75% budget remaining ($15 out of $20)
         0.50,   — 50% time remaining (noon)
         0.90,   — slightly underpacing (spending at 90% of ideal rate)
         0.15,   — low impression volume
         0.38]   — cost per click / maxCpm
```

前のウィンドウからの報酬: 1クリック、overspendペナルティなし。

```
reward = 1.0 - 0.0 = 1.0
```

agentはこの遷移をreplay bufferに保存し、訓練する: 32個のランダムな遷移をサンプリングし、Double DQNターゲットを計算し、1ステップのSGDを実行する。そして次のアクションを選択する。

agentのepsilonはまだ高い（1日目で約0.92、ほぼ完全にランダム）。ランダムにaction 3（10%高く入札）を選択する: `multiplier = 1.0 × 1.1 = 1.1`。次の15分間の実効CPMは$5.50になる。

これは役に立つだろうか？ おそらく。高い入札はJR Rail Pass ($8 CPM) に対してより多くのオークションで勝つことを意味する。あるいは追加コストに見合わないかもしれない。agentはまだわからない。探索中だ。

## 午後: ペーシングが調整される (2:00-5:00pm)

ユキのサイトのトラフィックが変化する。午前のピーク（8-11am）は終わった。午後のトラフィックはより軽い。2リクエスト/秒ではなく約0.8リクエスト/秒。PI controllerがレートトラッカーを通じて低下を検出し、調整する:

```
Previous throttle: 0.977 (skip 97.7%)
New throttle:      0.943 (skip 94.3%)
```

トラフィックレートが低下したため、スロットリングが軽減される。キャンペーンは、より少ないリクエスト数のうちより大きな割合を配信し、安定した支出レートを維持する。

しかしそれだけではない: **traffic shape tracker**がユキのサイトの時間帯別トラフィックパターンを学習してきた。数日後（初日ではない。トラッカーにはデータが必要だ）、以下を把握するようになる:

```
Hour 8:  12% of daily traffic
Hour 9:  11%
Hour 10: 10%
...
Hour 14: 4%
Hour 15: 3%
...
Hour 20: 8%  (evening peak)
```

線形の時間 = 線形の支出を仮定する代わりに、ペーシングターゲットはこの形状に従う。「8時の時間帯に予算の12%を使い、3時の時間帯に3%を使う。」これにより、従来のペーシングの一般的な失敗モード（ピーク時に使いすぎて枯渇する、またはピーク時にスロットルしすぎて夜間に予算が残る）を防ぐ。

## 夕方: Re-Auction (7:00pm)

ユキのサイトのre-auctionが発火する。午前2時から何が変わったか？

- **JR Rail Passキャンペーンが午後4時に予算を使い果たした。** RL agentが攻めすぎた入札をし（multiplierが1.4に達した）、午後半ばまでに日次予算を燃やし尽くした。
- **新しい広告主が登場した**: 京都の陶芸ワークショップ、East Asian Cultureをターゲット、CPM $3。

更新された参加者でオークションが再実行される:

```
Slot 1 (banner):  Takeshi's Ryokan  — $5.50 CPM (multiplier bumped to 1.1)
Slot 2 (sidebar): Hiking Gear Co    — $4.00 CPM
Slot 3 (sidebar): Pottery Workshop  — $3.00 CPM (new!)
```

JR Rail Passは消えた。予算枯渇だ。しかしそのクリエイティブはServeIndexに更新されたTTLで残る（明日予算がリセットされた時に復活する）。今朝2番目に高い入札者だったタケシの旅館が、今やトップの入札者だ。

re-auctionは約3秒で完了する。新しい候補が2秒以内のgossipですべてのノードに伝播する。次の読者は更新されたラインナップを見る。

## 1日の終わり: リセット

深夜（または設定された日の区切り）に、1日がリセットされる。

**CampaignEntity**: 予算が$20にリセットされる。支出カウンターがゼロになる。RL agentの`resetDay()`が発火する: 最後のウィンドウからの最終報酬を含むterminal遷移を保存し、bid multiplierを1.0にリセットし、ウィンドウカウンターをクリアする。しかしDQNの重みは生き残る。今日学習したことすべてが明日に引き継がれる。

**TrafficShapeTracker**: 今日の時間帯別トラフィック量が`dayAlpha = 0.2`で保存されたプロファイルにブレンドされる。5日後には、プロファイルは観測されたトラフィックパターンの平滑化された平均になる。

**Thompson Sampling統計**: 60分のローリングウィンドウにより、最後の1時間のクリエイティブ統計が新しい日に引き継がれる。古い統計はすでにエージングアウトしている。システムは明示的なリセットを必要としない。

**予算イベントの発行**: `CampaignBudgetReset`イベントがAuctioneerEntityに、タケシのキャンペーンが新しい予算を持っていることを伝える。デバウンスされたre-auctionが1秒以内に発火し、旅館広告がフル能力で候補プールに復帰する。

1日目が終了した。システムは関連性のある広告を配信し、どのクリエイティブが効果的かを学習し、予算をスムーズにペーシングし、トラフィックパターンに適応した。すべて自動的に。

明日はわずかに賢くなっている。

---

*技術的な詳細: [PI Control Loop](../pacing/pi-control.md) · [Traffic Shape Learning](../pacing/traffic-shape.md) · [Grace Periods](../pacing/grace-periods.md) · [Re-Auction](../auction/re-auction.md)*
