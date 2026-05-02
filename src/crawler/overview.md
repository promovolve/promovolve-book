# The Crawler

Promovolve's auction is offline (see [Periodic Batch Auction](../auction/periodic-auction.md)) — the system needs to know what each publisher page is *about* before any reader arrives. The crawler is what turns a publisher's site into the page-classification table the auction reads from.

## What the crawler does

Three jobs:

1. **Discover pages.** Start from a publisher's seed URL, follow same-host links breadth-first up to a configured depth.
2. **Render and extract.** For each page, render with headless Chromium (so JS-built content is captured), pull text from configured target elements (e.g., `article`, `main`, `.post-body`), and detect ad slots in the DOM.
3. **Hand off to classification.** The extracted text goes through the LLM classifier (Gemini Flash) which assigns IAB Content Taxonomy categories with confidence scores. The result is stored in `AuctioneerEntity` for the auction to read.

Output per page:

```scala
PageScrapedResult(
  url:    String,
  texts:  Seq[String],          // extracted text per target element
  links:  Seq[(href, anchor)],  // for breadth-first crawl
  slots:  Seq[DetectedSlot],    // ad slots found in DOM
  depth:  Int,
)
```

The classifier consumes `texts`, the crawl loop consumes `links`, and the publisher dashboard reads `slots` to surface "we found N ad slots on this page."

## Trigger model

Two ways a crawl starts:

- **Scheduled.** Each `SiteEntity` carries a Quartz cron expression (`crawlConfig.cronSchedule`). The cluster's Quartz scheduler fires the cron, sends `StartCrawling` to the site, and the entity requests a permit from `CrawlScheduler` before spawning.
- **On-demand.** A publisher clicks "Recrawl now" in the dashboard, which sends `StartCrawling` directly. Same permit handshake.

The 48-hour recency window in `AuctioneerEntity` prunes stale classifications, so a cron schedule that runs every 12–24 hours keeps the classification table fresh without overwhelming the LLM budget. Most publishers use daily.

## The browser context

Crawling uses a real headless Chromium (Playwright), not an HTTP fetch. Two reasons:

- **JS-rendered content.** Many sites build their article body with JavaScript. An HTTP fetch returns the empty SPA shell and the classifier has nothing to work with.
- **Anti-bot resilience.** Sites running Cloudflare Bot Management or Akamai will return blocked content (or empty bodies) to clients that look obviously automated.

The browser context is created by `BrowserContextFactory`, which injects a small **`stealth.js`** script before the target page's scripts run. The script patches the most common headless-Chromium tells (`navigator.webdriver`, missing `window.chrome`, empty `plugins`, the notification-permission mismatch) so anti-bot fingerprinters see real-browser-shaped values. The same factory backs the LP-to-creative pipeline's `LPAnalyzer`, so any improvements to stealth apply to both surfaces. Details live in `modules/crawler/src/main/resources/stealth.js`.

Each `PlaywrightWorker` rotates its browser context every 5 successful scrapes. Long-lived contexts accumulate cookies, local-storage state, and request fingerprints that can trip rate limits or freshness checks; rotation keeps each batch of pages presenting as a fresh browser session.

## URL-block: the crawler can't fire its own ads

This is the part of the crawler that's specific to running on top of Promovolve. The crawler is fetching publisher pages — pages that already embed Promovolve's own ad bootstrap. If we let the bootstrap run during the crawl, the crawler's headless browser would fire impression beacons, click through to landing pages, and burn advertiser budget on serves that no human will ever see.

`PlaywrightWorker` intercepts every request and aborts ones that match Promovolve's own delivery surface:

```scala
val isPromovolveAd =
  url.contains("promovolve-bootstrap") ||
  url.contains("/v1/serve/")           ||
  url.contains("/v1/imp")              ||
  url.contains("/v1/click")            ||
  url.contains("/v1/cta")              ||
  url.contains("/v1/dogear-event")

if (blockedTypes.contains(resourceType) || isPromovolveAd) route.abort()
else route.resume()
```

Same hook also blocks resource types that don't help classification: `image`, `font`, `media` (and `stylesheet` when no click-selector is configured). Crawls run faster and cheaper without downloading every image and webfont on the page.

The publisher's analytics, JS-rendered content, and any non-Promovolve scripts still load normally — only Promovolve's own delivery path is short-circuited.

## Failure modes

- **Bad HTTP status (≥ 400).** Dropped, returns an empty `PageScrapedResult`. Classifier gets nothing for that URL; auction won't include it.
- **Non-HTML content type.** Logged and skipped. Crawl continues to the next URL.
- **Navigation timeout (15s default).** Retried up to `maxRetries`; on final failure the URL is dropped with an empty result.
- **Browser crash / tab error.** Caught, page closed, browser context kept; same retry logic.

The crawler is best-effort. A page that consistently fails to render isn't a crisis — it just doesn't appear in the classification table, which means it doesn't appear in any auction. The auctioneer's 48-hour recency window means failed crawls also age out automatically.

## Where the [`CrawlScheduler`](./scheduler.md) fits in

A naive crawler with a singleton-per-site design would still produce a thundering herd on cluster restart: every `SiteEntity` activates simultaneously, every cron evaluates against "now" and fires immediately, every site's `PlaywrightWorker` spawns its own browser context, and a hundred concurrent Chromium processes try to share the same machine.

The `CrawlScheduler` is a cluster-singleton concurrency-bounded queue between `SiteEntity.StartCrawling` and the actual `PlaywrightWorker` spawn. Sites request permits, the scheduler grants up to `maxConcurrent` at a time (default 8), excess sites wait. Restart no longer blows up the host. The next chapter covers how it works, including its safety net for sites that crash mid-crawl without releasing their permit.

## Source of truth

- `modules/crawler/src/main/scala/promovolve/crawler/PlaywrightWorker.scala` — page-scrape actor, URL-block, resource filtering, retry policy
- `modules/crawler/src/main/scala/promovolve/crawler/BrowserContextFactory.scala` — context creation, stealth injection
- `modules/crawler/src/main/resources/stealth.js` — the stealth patches
- `modules/core/src/main/scala/promovolve/publisher/SiteEntity.scala` — `StartCrawling` handler, permit handshake with `CrawlScheduler`
- `modules/core/src/main/scala/promovolve/crawler/CrawlScheduler.scala` — see [next chapter](./scheduler.md)
