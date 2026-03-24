# 公平な候補選択

配信時の選択パイプラインは、Thompson Samplingが実行される前に複数のフィルターを適用し、適格な候補のみが考慮されるようにします。

## 完全な選択パイプライン

AdServerのソースコードにおける正確な処理順序：

```
1. Lookup ServeView from DData
   Key: "siteId|slotId"
   → Vector[CandidateView]

2. Content Recency Filter
   Keep if: (now - classifiedAtMs) ≤ contentRecencyWindowMs (48h)

3. Frequency Cap Check (if userId provided AND any caps exist)
   → Group candidates by advertiserId
   → Query AdvertiserEntity for user impression counts (100ms timeout)
   → Filter: keep if impressions < frequencyCap
   → Fail open on timeout (include all)

4. Rate Tracking (synchronous)
   → TrafficObserver.recordRequest(nowMs)
   → Update EMA-smoothed request rate (1s window, α=0.3)
   → BEFORE any async operations

5. Pacing Gate (BEFORE Thompson Sampling)
   → Fetch CachedSpendInfo for all participating campaigns
   → Compute aggregate PacingContext
   → PacingStrategy.throttleProbability(ctx) → [0.0, 0.99]
   → if random() < throttleProb: return NoCandidates (204)
   → Pacing gates VOLUME, not CHOICE

6. Thompson Sampling Selection
   → Cold start strategy selection (full cold / warmup / partial / standard)
   → Score: sampledCTR × log(1 + CPM)
   → Select argmax

7. Budget Reservation
   → CampaignEntity.Reserve(spend estimate)
   → AdvertiserEntity.GetBudgetStatus()
   → On failure: loop to next-best Thompson score candidate
   → All exhausted: return NoCandidates
```

## なぜPacingをThompson Samplingの前に行うのか？

もしpacingがTSの後に実行された場合：
- TSがクリエイティブを選択 → pacingがスロットル → **探索の無駄**（何も学べない）
- TSが一貫して高CTRのクリエイティブを選択し、それがスロットルされるため、将来の選択にバイアスがかかる

pacingをTSの前に実行すると：
- スロットル判断はクリエイティブの選択と独立
- リクエストがゲートを通過した場合、TSは適格な候補全体を探索する
- すべてのThompson Samplingの判断が有用なデータに貢献する

## キャンペーンミックスの変更検知

リクエスト間で参加キャンペーンのセットが変わった場合：

```scala
if lastCampaignSet.nonEmpty && currentCampaignSet != lastCampaignSet:
    log campaign mix changed (added/removed)
    pacingStrategy.reset()  // Don't let PI compensate for mix changes
```

これにより、PIコントローラーが古いキャンペーンデータに基づいて補正を行うことを防ぎます。

## 孤立クリエイティブの保持

新しいオークション結果が到着した際、前回のオークションからのクリエイティブで新しいセットに含まれないものは「孤立」として保持されます：

```scala
orphanedCreatives = existingCandidates.filterNot(c =>
    newAuctionCreativeIds.contains(c.creativeId)
)
mergedCandidates = (newCandidates ++ orphanedCreatives).distinctBy(_.creativeId)
```

これにより、マルチキャンペーンの多様性がオークションサイクルをまたいで維持され、承認状態も保持されます。
