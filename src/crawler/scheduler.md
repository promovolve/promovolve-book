# The Crawl Scheduler

The naive design — let every `SiteEntity` spawn its own `PlaywrightWorker` whenever it wants — works fine in dev with five sites. It blows up at a hundred. The crawl scheduler exists because of one specific failure mode: the post-restart thundering herd.

## The thundering herd

Every JVM restart wipes `AuctioneerEntity.lastPage` (an in-memory cache, not persisted). The next time each site's `PeriodicReauction` tick fires, the entity sees `lastPage.isEmpty` and concludes "I have no recent classifications, I should crawl." With 100 sites, that's 100 `SiteEntity` instances simultaneously deciding to crawl, simultaneously spawning a `PlaywrightWorker`, simultaneously launching a headless Chromium process.

A modern Mac can run maybe 8–12 Chromium processes before the OS starts killing things. A hundred is a guaranteed outage. Memory pressure spikes, the JVM gets OOM-killed, the cluster restarts, and the herd runs again.

The scheduler is a cluster singleton between `SiteEntity` and `PlaywrightWorker` that bounds concurrent crawls to `maxConcurrent` (default 8). Excess requests queue and run as slots free. Restart is no longer a self-inflicted denial-of-service.

## The protocol

```scala
sealed trait Command
final case class RequestCrawlPermit(siteId: SiteId, ackRef: ActorRef[CrawlGranted.type]) extends Command
final case class ReleaseCrawlPermit(siteId: SiteId) extends Command
case object Stop extends Command

case object CrawlGranted    // reply
```

Three messages. Sites ask for a permit, the scheduler replies `CrawlGranted` either immediately (if a slot is free) or whenever one frees. Sites release the permit when the crawl finishes. That's the whole external surface.

## The handshake

`SiteEntity.StartCrawling` doesn't spawn a worker directly any more. It pipes through the scheduler:

```
SiteEntity                       CrawlScheduler                 PlaywrightWorker
    │                                  │                              │
    │── RequestCrawlPermit ──────────▶│                              │
    │                                  │                              │
    │           (slot free)            │                              │
    │◀─── CrawlGranted ───────────────│                              │
    │                                  │                              │
    │── pipeToSelf(CrawlPermitGranted) │                              │
    │── spawn ────────────────────────────────────────────────────▶│
    │                                  │                              │── render…
    │                                  │                              │── extract…
    │◀─── CrawlerTerminated ────────────────────────────────────────│
    │── ReleaseCrawlPermit ──────────▶│                              │
    │                                  │── grant queued site ────▶ ...│
```

`SiteEntity` uses `pipeToSelf(scheduler.request(siteId))` to hold the request as a `Future` until the grant arrives, then sends itself a `CrawlPermitGranted` message that triggers the actual `PlaywrightWorker` spawn. When the worker terminates (either successfully or via crash), the `CrawlerTerminated` watcher fires, which sends `ReleaseCrawlPermit` back to the scheduler so the next queued site can run.

## State

The scheduler holds three mutable maps in memory — no persistence, no journal, no DB:

```scala
val running:      mutable.Map[SiteId, Instant]                              // siteId → grant time
val queue:        mutable.Queue[(SiteId, ActorRef[CrawlGranted.type])]      // FIFO waiters
val queuedSites:  mutable.Set[SiteId]                                        // dedup hint
```

`running` tracks who currently holds a permit and when they got it (timestamps drive the stale-release sweep, see below). `queue` is a FIFO of waiters; `queuedSites` is a side-set so duplicate-detection is O(1) instead of O(queue.size).

Why no persistence:

- The state is by definition wall-clock-ephemeral. A permit "for the next 10 minutes" doesn't make sense to persist across a singleton failover that takes 30 seconds.
- On singleton failover, the new singleton starts with empty `running` and `queue`. Any in-flight crawls keep running on their original nodes; they'll attempt `ReleaseCrawlPermit` when they finish, which becomes a no-op against the fresh singleton (the siteId isn't in `running` anyway).
- Callers waiting on a grant when the singleton fails over hit their ask-timeout (5 minutes) and `SiteEntity`'s normal failure path takes over — typically logging and trying again on the next periodic tick.

This is the same trade-off [`TokenBucketLimiter`](../architecture/entity-hierarchy.md) makes for the Gemini rate limiter: persist what's globally meaningful (none in this case), let everything else self-heal.

## Idempotency

Three idempotency cases that fall out of the implementation:

- **Already running.** A site requesting a permit it already holds gets a re-grant — `running.update(siteId, now)` refreshes the timestamp (so a long but legitimate crawl doesn't get stale-evicted) and the caller's ask completes immediately.
- **Already queued.** A site requesting a permit it already has queued gets its `ackRef` updated in place — most-recent-caller wins. Older asks die at their own timeouts.
- **Release of a non-running site.** No-op. Survives the singleton-failover case where `running` is empty.

These matter for the post-restart scenario specifically. After failover, every site starts re-requesting on its next tick; the idempotency rules ensure those re-requests are cheap and don't blow up the queue.

## The stale-release sweep

```scala
case object SweepStale extends Command   // internal, fired on a timer

case SweepStale =>
  val cutoff = now.minusSeconds(settings.staleAfter.toSeconds)
  val stale = running.collect { case (id, t) if t.isBefore(cutoff) => id }
  stale.foreach(releaseAndAdvance)
```

A `staleAfter` (10 minutes default) timeout exists for the case where a `PlaywrightWorker` crashes hard, the JVM dies, or a network partition leaves the scheduler thinking a site is still crawling when actually nothing is. Without the sweep, a single crashed worker would leak a permit forever; eight crashes and the scheduler grants nothing, ever again.

The sweep runs every `sweepInterval` (1 minute default). Permits older than `staleAfter` are auto-released, just as if the holder had sent `ReleaseCrawlPermit` correctly. Logged as a warning so an operator notices.

A real crawl rarely takes longer than a few minutes; 10 minutes is a generous upper bound. A site whose crawl is legitimately taking that long re-requests via the idempotency path, refreshing its timestamp.

## Settings

```scala
final case class Settings(
    singletonName: String     = "crawl-scheduler",
    maxConcurrent: Int        = 8,
    staleAfter: FiniteDuration = 10.minutes,
    sweepInterval: FiniteDuration = 1.minute,
)
```

`maxConcurrent = 8` is the headroom for one Mac dev machine. Production tunes this against the host's RAM and CPU; the bottleneck is Chromium memory more than anything else, so the right value is roughly `(available_ram_gb - 4) / 0.5` (each Chromium context is ~500 MB working set).

## Generic primitive: it's the same shape as TokenBucketLimiter

The scheduler is structurally identical to `promovolve.TokenBucketLimiter`:

- Cluster singleton with persistent identity but ephemeral state.
- Holds a small in-memory state plus a waiter queue.
- Idempotent acquire / explicit release semantics.
- Stale-safe via timeouts.
- No persistence — failover is acceptable because the state is by-definition wall-clock-ephemeral.

The two differ in what the state is:

| | `TokenBucketLimiter` | `CrawlScheduler` |
|--|--|--|
| State | Token count (numeric) | Running set (siteId → timestamp) |
| Refill | Continuous (tokens / second) | Explicit (`ReleaseCrawlPermit`) |
| Use case | RPM rate limiting (Gemini, Anthropic) | Concurrency capping (crawls) |

If a third use case shows up (say, "max-N parallel video transcodes"), the `TokenBucketLimiter` shape is the right pattern: persistent name, ephemeral state, ask/release protocol, stale safety net. The platform has two of these now; the third would feel boring to build, which is the point.

## Source of truth

- `modules/core/src/main/scala/promovolve/crawler/CrawlScheduler.scala` — the singleton + protocol
- `modules/core/src/main/scala/promovolve/publisher/SiteEntity.scala` — `StartCrawling` handler with `pipeToSelf(scheduler.request)` + `CrawlerTerminated` watcher with `release`
- `modules/core/src/main/scala/promovolve/cluster/ClusterBootstrap.scala` — singleton init wiring
- `modules/core/src/main/scala/promovolve/TokenBucketLimiter.scala` — the structurally-identical primitive for rate limiting
