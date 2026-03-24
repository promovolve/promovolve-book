# Grace Periodsとハイブリッドモード

PI controlには安定した入力信号が必要です。起動時や非アクティブ期間の後は、信号がノイズが多いか意味を持ちません。Grace periodsはこれらの過渡状態からコントローラを保護します。

## Grace Period：配信なし

grace中、throttle probabilityは`MaxThrottleProb = 0.99`に設定されます — 実質的に**配信なし**です。これは予想とは逆かもしれません：ウォームアップ中に自由に配信するのではなく、Promovolveは正しくペーシングするための十分なデータが得られるまで配信を抑制します。

**なぜ自由に配信せず抑制するのか？** 起動時の自由な配信は、PI controllerが起動する前に予算を使い果たす可能性があります。0.99のスロットル（1.0ではない）は、レートデータを構築するための「センサー」としてリクエストの約1%を通過させます。

## Grace Periodの条件

**両方の**条件が満たされるまでgraceはアクティブです：

```
graceSeconds = max(MinGraceSeconds, DefaultGracePeriodFraction × dayDurationSeconds)
             = max(10.0, 0.01 × dayDurationSeconds)

graceRequests = MinGraceRequests = 10

Grace ends when:
  elapsedSeconds >= graceSeconds AND requestCount >= graceRequests
```

さらに、EMAが安定するために`EmaStabilizationWindows = 3`ウィンドウ分のデータが必要です。

### Stalenessリセット

設定可能な期間リクエストが到着しない場合、graceに再突入します：

```
staleThreshold = BaseStaleRateThresholdMs = 30,000ms
                 (scaled proportionally for simulated short days)
                 (min: MinStaleRateThresholdMs = 1,000ms)

if (nowMs - lastRequestMs) > staleThreshold:
    resetGracePeriod()
```

**なぜ？** 30秒の無音の後、EMA平滑化レートは減衰しており、現在のトラフィックを表していません。古いレートデータでのPI補正は、不安定なスロットルの振れを引き起こします。

## Grace Periodの定数

| Constant | Value | Purpose |
|----------|-------|---------|
| `DefaultGracePeriodFraction` | 0.01 (1日の1%) | 基本grace期間 |
| `MinGraceSeconds` | 10.0 | 日の長さに関わらない最小grace |
| `MinGraceRequests` | 10 | PIが起動する前の最小リクエスト数 |
| `MaxGraceRequests` | 50 | （現在は下限として未使用） |
| `EmaStabilizationWindows` | 3 | EMAウォームアップウィンドウ |
| `BaseStaleRateThresholdMs` | 30,000 | Staleness検出 |
| `MinStaleRateThresholdMs` | 1,000 | 短いシミュレーション日の最小staleness |
| `MaxThrottleProb` | 0.99 | grace中のスロットル |

## Grace Periodのタイムライン

```
Time    Event                       Mode           Throttle
00:00   Site pacing starts          Grace          0.99 (~1% through)
00:05   5 requests arrived          Grace (count)  0.99
00:10   10s elapsed, 10+ requests   Grace (EMA)    0.99
00:13   3 EMA windows stable        PI active      Computed
...
01:30   No requests for 35s         Stale reset    0.99
01:31   Requests resume             Grace          0.99
01:41   Grace conditions met        PI active      Computed
```

## シミュレーション日

テストとシミュレーションのために、`dayDurationSeconds`は86400より短く設定できます（例：10分の「日」には600秒）。Grace periods、staleしきい値、RL観測間隔はすべて比例的にスケーリングされ、シミュレーションされた時間スケールに関わらずシステムが一貫した動作をすることが保証されます。
