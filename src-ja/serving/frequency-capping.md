# Frequency Capping

Frequency cappingは、同一ユーザーが同じ広告主の広告を見る回数を制限し、広告疲れを防止します。

## 仕組み

### ユーザー単位・クリエイティブ単位のキャップ

各キャンペーンは`frequencyCap: Option[Int]`を指定できます。これはそのキャンペーンのクリエイティブについて、ユーザーあたりの最大impression数を表します。

### チェックプロセス

配信時、pacing gateの前に実行されます：

```scala
// 1. Filter candidates with frequency caps
val cappedCandidates = candidates.filter(_.frequencyCap.isDefined)

// 2. Group by advertiser
val byAdvertiser = cappedCandidates.groupBy(_.advertiserId)

// 3. Query each AdvertiserEntity for user impression counts
//    Timeout: 100ms, fail-open

// 4. Filter
filtered = candidates.filter { c =>
  c.frequencyCap match {
    case None      => true  // No cap, always eligible
    case Some(cap) =>
      val impressions = impressionCountsMap.getOrElse(c.creativeId, 0)
      impressions < cap
  }
}
```

### Fail-Openセマンティクス

AdvertiserEntityが**100ms**以内に応答しない場合：

```
On timeout → include all candidates from that advertiser
```

**なぜfail-openなのか？** Frequency cappingは品質最適化です。代替策（fail-closed）では、ネットワーク障害時に広告が一切表示されなくなります。時折過剰に配信する方が、配信を完全にブロックするよりも好ましいです。

## パイプラインにおける位置

Frequency cappingはcontent recencyの**後**、pacing gateとThompson Samplingの**前**に実行されます：

```
Content recency → Frequency cap → Rate tracking → Pacing gate → Thompson Sampling
```

TSの前に実行することで以下が保証されます：
- TSはキャップ済みの候補に対して探索を無駄にしない
- フィルター後のプールは小さくなる場合があるが、TSはサイズ1以上であれば正しく動作する
- すべての候補がキャップ済みの場合、広告は表示されない（NoCandidates）

## Pacingとの相互作用

Frequency cappingとpacingは独立したフィルターです。候補は両方を通過する必要があります：

```
Candidates → Frequency Filter → Pacing Gate → Thompson Sampling
```

frequency capを先に実行することで、pacing gateが評価する候補数が削減されます。
