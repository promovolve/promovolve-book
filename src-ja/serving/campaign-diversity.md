# キャンペーン単位の多様性

Promovolveは2つのメカニズムを通じて多様性を確保します。オークション時の公平な選択アルゴリズムと、配信時の集約pacingです。

## オークション時の多様性

候補のショートリスティングアルゴリズム（AuctioneerEntity内）はキャンペーン単位の代表を保証します：

```
1. Group candidates by campaign
2. Pick best creative per campaign (by CPM)
3. If #campaigns ≥ #slots:
     Take top campaigns by CPM → one creative each
4. Else:
     Each campaign gets 1 slot (guaranteed)
     Fill remaining slots with next-best creatives
```

これにより、3つのキャンペーンが3つのスロットを競う場合、高CPMの単一キャンペーンが3つすべてを埋めるのではなく、各キャンペーンが正確に1スロットを獲得します。

## 配信時の集約Pacing

pacing gateはキャンペーン単位ではなく**集約された**キャンペーンメトリクスに基づいて動作します：

```scala
PacingContext(
  dailyBudget = sum of all participating campaign budgets,
  todaySpend = sum of all campaign spends (including pending),
  avgCpm = CPM-weighted average across campaigns,
  competingCampaigns = count of campaigns with budget remaining,
  ...
)
```

### なぜ集約なのか？

キャンペーン単位のpacingでは、高予算キャンペーンが低予算キャンペーンを締め出す可能性があります：
- キャンペーンA（$1000/日）：ほとんどpacingされず、常に配信
- キャンペーンB（$10/日）：強くpacingされ、ほとんど配信されない

集約pacingは次のように問います。「ここにあるすべてのキャンペーンの**合計**予算を考慮して、合計の消費率は適切か？」これにより自然に配信がバランスされます。

## 自然な多様化手段としてのThompson Sampling

Thompson Sampling自体が明示的な制約なしに多様性を提供します：

- 各クリエイティブは独自の`Beta(clicks+1, impressions-clicks+1)`事後分布を持つ
- Betaからのサンプリングは自然に分散をもたらす — 支配的なクリエイティブでも時には低くサンプリングされる
- 新しいクリエイティブは広い分布を持つ → 高い分散 → 探索される
- クリエイティブごとの独立性により、各クリエイティブが独自の学習軌跡を得る

## Ad Product Blocklist

パブリッシャーはサイトごとにad product categoryのブロックリストを設定できます：

```scala
adProductBlocklist: Set[AdProductCategoryId]
```

DData（`AdProductBlocklistKey`）を通じて配信されるこのフィルターは、オークション時に実行され、特定カテゴリの広告（例：ギャンブル、アルコール）をパブリッシャーのインベントリから除外します。

## クリエイティブの重複排除

新しいオークション結果を既存の候補とマージする際：

```scala
mergedViews = (newCandidates ++ orphanedCreatives).distinctBy(_.creativeId)
```

これにより同じクリエイティブが複数回出現することを防ぎ、Thompson Samplingへのバイアスを回避します。
