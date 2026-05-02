# The Dashboard Projection

The dashboard advertisers and publishers look at — impressions, spend, CTR, fold counts, time-series charts — is a *read model*. It is not the database the actors write to, and it is not the journal the engagement pixels hit. It's a separate set of aggregate tables, kept up to date by a streaming projection that reads from the journal and writes to the aggregates.

This chapter explains why the read side is separate, what flows through the journal, what the handler does with each event type, and where the dog-ear's separate metrics fit in.

## Why a separate projection

The serve-time write path has two hard constraints:

- **Don't block actor mailboxes.** A `CampaignEntity` recording a spend reservation can't wait on a hot DB query. Serve latency is < 1ms; nothing on that path can take longer.
- **Don't lose events.** Every impression, click, and CTA needs to land somewhere durable, even if the dashboard is down or the database is paged.

Querying the same data the actors are writing to would couple dashboard read latency to actor write latency. A 200ms time-range query on a busy dashboard would slow down every serve. Event sourcing on the write side plus projections on the read side is the standard way to break that coupling: the actors emit append-only events, a separate process reads them, and the dashboard queries the read-side aggregates.

```
serve / track endpoints                 dashboard reads
        │                                       ▲
        ▼                                       │
┌──────────────────┐    ┌────────────────────┐ │
│ TrackingEvent    │    │  campaign_stats    │─┤
│ Journal          │    │  creative_stats    │─┤
│ (append-only,    │ →  │  campaign_hourly_* │─┤
│  Pekko Streams)  │    │  campaign_daily_*  │─┤
└──────────────────┘    │  advertiser_summary│─┘
        │               └────────────────────┘
        │                       ▲
        └───── projection ──────┘
              (Pekko, exactly-once,
               offset = sequence_nr)
```

## The journal

`tracking_events` is the append-only journal. Schema (Slick definition in `TrackingEventJournal.scala`):

```sql
sequence_nr   bigserial PRIMARY KEY      -- monotonic offset for projection
event_type    text                       -- impression | click | cta_click | fold | unfold
event_time    timestamptz                -- wall-clock when the engagement happened
site_id       text
campaign_id   text NULL
advertiser_id text NULL
creative_id   text
category      text NULL
cpm           numeric NULL
url           text NULL
slot          text NULL
request_id    text NULL                  -- UUID (batch path) or 16-char hex hash (fold tokens)
user_id       text NULL                  -- for frequency cap analysis
dogeared      boolean DEFAULT false      -- true for impressions served via honored pin
```

What's recorded:

- **Impressions** (`/v1/imp`) — billable serves. CPM populated.
- **Clicks** (`/v1/click`) — first-expansion event from the magazine banner. CPM not relevant here; click is recorded per-creative.
- **CTA clicks** (`/v1/cta`) — reader tapped the call-to-action page after expanding.
- **Folds** (`/v1/dogear-event` with `event=fold`) — reader bookmarked the creative. Free engagement signal.
- **Unfolds** (`/v1/dogear-event` with `event=unfold`) — reader removed a bookmark.

What's not recorded: actor-internal messages (entity state changes, pacing decisions, auction shortlisting). The journal is the *engagement* trail, not the system's full event log.

## Writing to the journal

`TrackingEventJournal` uses a Pekko Stream to batch writes:

```scala
Source.queue[TrackingEvent](bufferSize = 10000, OverflowStrategy.dropNew)
  .groupedWithin(100, 100.millis)   // batch: max 100 events or 100ms
  .mapAsync(4) { batch =>           // 4 parallel DB writes
    db.run(trackingEvents ++= batch)
  }
```

The shape of this pipeline answers four questions at once:

- **Backpressure?** A bounded queue of 10K events with `OverflowStrategy.dropNew` — under sustained DB outage, new events drop rather than holding actor threads or eating heap. Logged when it happens.
- **Throughput?** Up to 100 events per round-trip × 4 parallel inserts. Plenty for the kinds of traffic Promovolve targets, with headroom.
- **Latency?** 100ms max wait before flushing a partial batch, so dashboard freshness lags by less than 200ms (one batch wait + one projection poll).
- **Durability?** Events fully cross the wire to the DB before the stream reports `done`. The trade-off is that an event in flight at server crash time is lost — fold tokens and click HMACs both make that idempotent on retry, so a lost event is at worst a missed impression count, not a billing or pin error.

`TrackEvent` (the in-memory shape used by `LearningEventLog`) becomes `TrackingEvent` (the persisted shape) inside each `writeXxx` method. The transformation is mechanical — copy the relevant fields, set `eventType`, derive `eventTime` from `e.ts`.

## Running the projection

`DashboardProjection.init` wires it up as a `ShardedDaemonProcess`:

```scala
ShardedDaemonProcess(system).init(
  name = "DashboardProjection",
  numberOfInstances = 1,            // single partition; can scale later
  behaviorFactory = { partition =>
    val projectionId = ProjectionId("dashboard", s"partition-$partition")
    val sourceProvider = new TrackingEventSourceProvider(dbConfig, partition, 1)
    val projection = SlickProjection.exactlyOnce(
      projectionId,
      sourceProvider,
      databaseConfig = dbConfig,
      handler = () => new DashboardProjectionHandler
    )
    ProjectionBehavior(projection)
  },
  settings = ShardedDaemonProcessSettings(system),
)
```

Three things to notice:

- **`exactlyOnce`** — the projection's offset is committed transactionally with the read-side update. A handler that processes event N and then crashes mid-write rolls back both the read-side update and the offset commit, so on restart the same event is reprocessed and lands exactly once.
- **`ProjectionId("dashboard", "partition-0")`** — one logical projection. Today there's one partition; scaling to N partitions sharded by `siteId hash % N` is a configuration change, not a rewrite.
- **Source provider polls** — `TrackingEventSourceProvider` polls `tracking_events` every 500ms for rows with `sequence_nr > lastOffset`. Not a notification system; deliberately simple. PostgreSQL handles 100s of polls/sec from a single process without breaking a sweat.

## The handler

`DashboardProjectionHandler` dispatches by `eventType`:

```scala
override def process(event: TrackingEvent): DBIO[Done] = event.eventType match {
  case "impression" => processImpression(event)
  case "click"      => processClick(event)
  case "cta_click"  => processCTAClick(event)
  case "fold"       => processFold(event)
  case "unfold"     => processUnfold(event)
  case other => log.warn("Unknown event type: {}", other); DBIO.successful(Done)
}
```

Each per-event-type method is a single transaction (`updates.transactionally`) that updates every aggregate the event affects.

## The aggregates

`processImpression` writes to five tables in one transaction:

| Table | Granularity | Per-impression delta |
|-------|-------------|-----------------------|
| `campaign_stats` | per campaign | `impressions += 1`, `total_spend += cpm/1000`, `last_impression_at`, optional `first_impression_at` |
| `creative_stats` | per (creative, campaign) | `impressions += 1`, `total_spend += cpm/1000` |
| `campaign_hourly_stats` | per (campaign, hour bucket) | `impressions += 1`, `spend += cpm/1000` |
| `campaign_daily_stats` | per (campaign, day bucket) | `impressions += 1`, `spend += cpm/1000`, `unique_sites += 1` |
| `advertiser_summary` | per advertiser | `total_impressions += 1`, `total_spend += cpm/1000` |

Bucketing is wall-clock-truncation, UTC:

```scala
val hourBucket = e.eventTime.truncatedTo(ChronoUnit.HOURS)
val dayBucket  = e.eventTime.atZone(ZoneOffset.UTC).toLocalDate
```

All five inserts use `INSERT … ON CONFLICT … DO UPDATE` (PostgreSQL upsert). First impression for a campaign creates the row; later impressions increment counters atomically. No read-modify-write, no race conditions.

`processClick` and `processCTAClick` follow the same pattern with their own counter columns (`clicks`, `cta_clicks`). `processFold` / `processUnfold` write to dog-ear-specific counters covered below.

The dashboard's queries hit these tables directly. Time-series charts read from `campaign_hourly_stats` or `campaign_daily_stats`; campaign-detail pages read from `campaign_stats`; advertiser overviews read from `advertiser_summary`. None of them touch the journal.

## The dog-ear wing

Folds and "dogeared impressions" are the format-specific metrics:

- **Folds** (the bookmark gesture itself) — counted on `processFold`. Free engagement signal, no spend involved.
- **Unfolds** — counted on `processUnfold`. Used to compute the **pin retention rate**: `(folds − unfolds) / folds`. An advertiser sees how many readers actually came back versus folded then changed their minds.
- **Dogeared impressions** — impressions served because of an honored pin. The journal flags them with `dogeared = true`; `processImpression` calls `bumpDogearedImpression` which adds to a parallel set of `dogeared_impressions` counters across `campaign_stats` / `creative_stats` / `campaign_hourly_stats` / `campaign_daily_stats`.

The key thing is that **dogeared impressions are still billable impressions** — they roll up into the primary `impressions` and `total_spend` counters like any other serve, AND into the `dogeared_impressions` counter as a separate dimension. Wait, that contradicts [Pin-Honoring](../serving/pin-honoring.md), where pinned re-encounters bypass clearing entirely…

It actually doesn't, but the seam needs explaining. The pin-honor path emits a `BatchSlotOutcome` with `clearingPrice = CPM.zero` and skips reservation. When the bootstrap fires the impression beacon, the `cpm` field on that beacon is zero. So in the journal: `dogeared = true`, `cpm = 0`. In the aggregates: `impressions += 1`, `total_spend += 0`. Dogeared impressions are counted but priced free, exactly as the pin-honoring chapter describes.

The dashboard surfaces this as a sub-counter: "Impressions: N (of which dogeared: M)" and "Spend: $X" where the dogeared portion contributes nothing to spend. Advertisers see how much of their reach is reader-driven rather than auction-driven, and it's free.

## Backfill and replay

If a schema change adds a new aggregate column or a new event type, the projection can be rewound:

1. Stop the `ShardedDaemonProcess`.
2. Reset the offset (`UPDATE pekko_projection_offset_store SET current_offset = 0 WHERE projection_name = 'dashboard'`).
3. Truncate the affected aggregate tables (or selectively recompute).
4. Restart the daemon.

The projection re-reads `tracking_events` from sequence_nr 0 and rebuilds the aggregates. Per-event handler logic is idempotent under upsert semantics, so the rebuild produces the same numbers regardless of whether it ran once or N times. A full rebuild on a busy site takes minutes, not hours; the journal is bounded by the engagement rate, not the actor message rate.

The simulation script `scripts/run-dev.sh --fresh` does exactly this as part of its DB reset, so a fresh dev environment always has a known-good projection state.

## Source of truth

- `modules/api/src/main/scala/promovolve/api/projection/TrackingEventJournal.scala` — journal write path + Slick table
- `modules/api/src/main/scala/promovolve/api/projection/DashboardProjection.scala` — `ShardedDaemonProcess` setup + custom `SourceProvider`
- `modules/api/src/main/scala/promovolve/api/projection/DashboardProjectionHandler.scala` — per-event-type aggregate updates
- `docker/init-db.sql` — read-side table definitions (campaign_stats, creative_stats, campaign_hourly_stats, campaign_daily_stats, advertiser_summary, plus their dogeared_impressions columns)
- `modules/api/src/main/scala/promovolve/api/LearningEventLog.scala` — produces the `TrackEvent` shape that becomes journal rows
