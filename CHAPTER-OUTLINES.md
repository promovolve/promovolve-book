# New Chapter Outlines

Planning artifact for chapters not yet written. Each outline lists the proposed file path, where it slots into `src/SUMMARY.md`, why the chapter exists, a section-by-section outline, and the source-of-truth code paths so the eventual writeup mirrors the actual implementation.

Lives at the book root (not under `src/`) so mdbook ignores it. Delete after the chapters land.

---

## 1. The Magazine Format

**Path:** `src/format/overview.md`
**SUMMARY position:** New top-level "## The Ad Format" section between "How It Works" and "Deep Dives".

### Why
This is the product differentiator. Today the book mentions the format in passing inside `why-promovolve.md` and `introduction.md` but never explains how it actually works. A reader who lands on the auction or serving chapters has no concrete picture of what's being served.

### Outline
- **From banner to spread.** Visual framing: collapsed view in slot → reader taps → full-screen overlay with cover, story pages, CTA → collapses back. Why a magazine and not a video or a popup.
- **Why expandable.** Attention is given, not stolen. The advertiser pays for the impression; engaged time is a bonus, and the reader controls whether they get it.
- **Anatomy of a creative.** Cover page (`coverPageIdx`), interior pages, CTA page. Per-page background color. Optional landing-url fallback for CTA.
- **The web component contract.** What the publisher embeds (`expandable-magazine-banner.js`). Shadow DOM. The DOM attributes the bootstrap fills in.
- **Lifecycle: impression → expand → CTA → fold.** The four engagement events and how they map to backend endpoints (`/v1/imp`, `/v1/click`, `/v1/cta`, `/v1/dogear-event`). Click idempotency (`_clickFired`).
- **What makes it work.** Quick pointers to fluid sizing (next chapter), the LP-to-creative pipeline (the chapter after), and the dog-ear (further down).

### Source of truth
- `platform/banner-component/src/banner.ts` — the web component
- `platform/banner-component/src/expand-effects.ts` — open/close animations
- `platform/banner-component/src/render-overlay.ts` — overlay markup
- `platform/banner-component/src/types.ts` — `BannerConfig`

---

## 2. Fluid Creatives

**Path:** `src/format/fluid-creatives.md`
**SUMMARY position:** Sub-chapter under "The Ad Format".

### Why
Author-once, fluid everywhere is concrete and demoable. The current book never explains *how* the same creative renders into a 300×250 sidebar and a 375px phone slot without separate variants — readers from the IAB-fixed-size world will assume it can't.

### Outline
- **The IAB matrix problem.** Why publishers maintain multiple creative sizes, why mobile usually gets a different creative or none at all, what that costs small advertisers.
- **Aspect ratio over pixel size.** Creatives are authored at an aspect ratio. The host gets `width:${w}px; max-width:100%; aspect-ratio:${w}/${h}`. The publisher slot wraps with the symmetric pattern.
- **CSS container queries.** Interior sizing uses `cqh`/`cqmin` so every text size, padding, and image stays proportional to the host. No `px` inside.
- **Reference pattern.** Walk through the publisher-site-ja example: how `[data-ad-width][data-ad-height]` attribute selectors plus a `@media (max-width:768px)` rule stack the sidebar on phones.
- **What this doesn't do.** It's not "responsive" in the squish-the-content sense — proportions are preserved. A creative that looks elegant at 300×250 will look elegant at 200×167; it won't reflow text into a vertical column.
- **Authoring discipline.** The designer enforces this; the rule for new editor surfaces is "container queries inside, `aspect-ratio` + `max-width` outside, never hardcoded px."

### Source of truth
- `platform/banner-component/src/banner.ts` — host sizing
- `modules/examples/publisher-site-ja/index.html` — canonical responsive slot pattern
- `platform/creative-designer/src/render/canvas.ts` — designer enforces the model

---

## 3. The LP-to-Creative Pipeline

**Path:** `src/format/lp-to-creative.md`
**SUMMARY position:** Sub-chapter under "The Ad Format".

### Why
This is what makes the format accessible to small advertisers. A local restaurant doesn't have a designer; they have a landing page. The pipeline turns that into a magazine creative automatically. Worth a chapter on its own because the ergonomic claim ("just enter a URL") is load-bearing for the whole product story.

### Outline
- **The advertiser experience.** Enter a landing page URL, set a budget and max CPM, pick a category. That's it. Show the actual onboarding screens.
- **Stage 1: Playwright extraction.** Headless browser fetches the LP, captures structured content (headings, body text, hero images, prices). Why a real browser instead of an HTTP fetch — JS-rendered LPs.
- **Stage 2: Gemini rewriting.** The extracted content is rewritten into magazine-style page copy. Constraints: keep facts, change tone, fit the page count. Why Gemini Flash specifically (latency, cost).
- **Stage 3: The designer.** `RichCreativeProcessor` orchestrates image download → layout selection → asset persistence to R2.
- **Stage 4: Verification.** Gemini reviews the rendered creative against the original LP for hallucination — the "did the model invent prices that aren't on the page" check.
- **Idempotency, retries, failure modes.** What happens when an LP times out, when Gemini returns malformed JSON, when image download fails.
- **What the advertiser sees and approves.** Preview before commit; once approved, the creative enters the auction pool.

### Source of truth
- `modules/core/src/main/scala/promovolve/creative/RichCreativeProcessor.scala`
- `modules/crawler/` — Playwright integration
- The Gemini client (find via `grep -rn "gemini" modules/`)

---

## 4. The Designer / Banner Stack

**Path:** `src/format/designer.md`
**SUMMARY position:** Sub-chapter under "The Ad Format".

### Why
The designer (`platform/creative-designer/`) is a substantial piece of the product surface — page builder, IAB-mode canvas lock, cover-page picker, color picker, font picker, animation toggles. Worth its own chapter because it's where advertisers customize the LP-pipeline output and where the "fluid creatives" rule gets enforced in tooling.

### Outline
- **What the designer is.** A web-based page builder that runs in the dashboard. Output is the same data structure the runtime banner consumes, so what you see in the editor is what readers see.
- **Canvas modes.** Free canvas vs IAB-locked (300×250, 728×90, …). Why we offer the lock at all if creatives are fluid: some publishers want a guaranteed minimum size for above-the-fold slots.
- **Page model.** Pages are an ordered list. Each has a background color, layout template, and a `coverPageIdx` marker. Thumbnails always render the cover.
- **Components.** Headlines, body text, images, CTA buttons. How container-query sizing flows through. Animation toggles per component.
- **The contract with the runtime banner.** A `BannerConfig` is the wire format; designer writes it, banner reads it. Backwards-compatibility expectations.
- **Where the LP pipeline plugs in.** Generated creatives land as designer documents the advertiser can then edit before approval.

### Source of truth
- `platform/creative-designer/src/`
- `platform/banner-component/src/types.ts` — `BannerConfig` shape
- `platform/creative-designer/src/ui/canvas-header.ts`
- `platform/creative-designer/src/render/canvas.ts`

---

## 5. The Dog-Ear

**Path:** `src/format/dog-ear.md`
**SUMMARY position:** Sub-chapter under "The Ad Format".

### Why
This is the reader-agency story. It's also the most novel mechanic in the product — there's nothing analogous in traditional programmatic. The story chapters now reference it but no chapter explains the protocol.

### Outline
- **The mechanic.** Reader expands a creative, decides they want to come back to it, folds the corner. Same affordance as a paper magazine. Visual treatment: corner triangle in the collapsed banner, toggleable overlay control when expanded.
- **Why pin storage lives in the reader's browser.** Privacy thesis: the server never knows who folded what; the pin is an IndexedDB row.
- **The FoldToken protocol.** Stateless 30-minute HMAC-signed tokens minted with the serve response. Payload: `pub|url|slot|cid|ver|bucket|camp|adv|nonce`. Why stateless — no server-side fold table to maintain.
- **`/v1/dogear-event`.** Verification: HMAC, freshness, slot/cid match. Idempotency via the token-hash request id.
- **Server-side telemetry.** Folds are an engagement signal, not billed. Dashboard projection counts them. No CPF, no per-fold budget.
- **Re-encounter.** On the next page load eligible for that advertiser, the bootstrap reads its IndexedDB, asks the server to honor the pin, and the server's pin-honor path serves the bookmarked creative — bypassing the auction reservation, the pacing throttle, and CPM clearing.
- **Revoke.** When a campaign pauses or a creative is unassigned, the pin is invalidated. `dogearFallthrough` with `isApproved` gate. IDB cleanup on the next bootstrap.
- **What this replaces.** Retargeting, but reader-driven. A magazine reader's choice instead of a publisher's tracking pixel.

### Source of truth
- `modules/core/src/main/scala/promovolve/common/FoldToken.scala`
- `modules/api/src/main/scala/promovolve/api/ServeRoutes.scala` — `/v1/dogear-event` handler, `foldTokenFor`
- `modules/api/src/main/scala/promovolve/api/LearningEventLog.scala` — `logFold`
- `modules/core/src/main/scala/promovolve/publisher/delivery/AdServer.scala` — pin-honor + `dogearFallthrough`
- `platform/banner-bootstrap/src/dogear-storage.ts` — IndexedDB layer
- `platform/banner-bootstrap/src/bootstrap.ts` — `displayImpl` + slot-level pin cleanup

---

## 6. Quality-Adjusted Pricing

**Path:** `src/auction/quality-adjusted-pricing.md`
**SUMMARY position:** Sub-chapter under "The Auction System", after "Phase 5: ServeIndex Caching".

### Why
The current `serving/scoring-formula.md` covers the score and clearing formula, but it's buried inside the serving section. The pricing mechanic is the thing that makes "no campaign-side bid optimizer" work, and it deserves a callout next to the auction phases that produced the candidates.

### Outline
- **The score recap.** `score = sampledCTR × CPM^α`, α publisher-tunable (Discovery / Balanced / Revenue). Cross-reference `serving/scoring-formula.md` for the full dial without duplicating.
- **The clearing formula.** `clearingCPM = (bestLoserScore / sampledCTR_winner)^(1/α)`. Where `bestLoserScore` comes from (`SelectionResult.bestLoserScore`). Clamp to floor and to winner's bid.
- **Worked examples.**
  - Standard exploit: high-CTR winner pays well below max CPM.
  - Tie at the runner-up: clearing equals second-best score divided by winner CTR.
  - Single candidate: `Solo` reason, pays floor.
  - Cold-start winners: `ColdStart` / `Warmup` / `Exploration` reasons all pay floor.
- **Why this is quality-adjusted second-price.** Prove the obvious incentive-compatibility: bid shading shrinks your score and your win probability without lowering what you pay (which is set by the runner-up, not by you).
- **Why no campaign-side RL.** The mechanism extracts honest bids; there's nothing for an agent to learn that the auction doesn't already enforce. This is the explicit deletion that motivates the cleanup commits.
- **Pinned re-encounters.** Bypass clearing entirely — they're free. Cross-reference `serving/pin-honoring.md`.

### Source of truth
- `modules/core/src/main/scala/promovolve/publisher/delivery/ThompsonSampling.scala` — `cpmScore`, `scoreCandidate`, `select`
- `modules/core/src/main/scala/promovolve/publisher/delivery/AdServer.scala` — clearing computation in `batchReserveWithRetry`

---

## 7. Pin-Honoring at Serve Time

**Path:** `src/serving/pin-honoring.md`
**SUMMARY position:** Sub-chapter under "Serve-Time Selection".

### Why
The dog-ear chapter (#5) covers the protocol from the reader's side. This chapter covers the server's side: how the pin slots into the existing serve pipeline (before frequency cap, before pacing, before Thompson Sampling) and what falls back when the pinned creative isn't available.

### Outline
- **Pipeline position.** Pin check runs first (after ServeIndex lookup) so that no other gate can drop a reader bookmark. The full pipeline diagram with the pin check highlighted.
- **Honor path.** Pinned creative present and approved → bypass reservation, bypass pacing, emit `DogearOutcome(honored=true)`, clearing price 0.
- **Fallthrough reasons.** `creative_removed` (truly gone), `not_in_pool` (eligible but not in this auction's shortlist), `revoked_advertiser`. Each maps to a different message back to the bootstrap so the IDB can clean up correctly.
- **`isApproved` gate.** Why we distinguish "creative not in pool right now" (transient) from "creative is removed/revoked" (clean up the pin). The gate prevents the reader from losing a pin to a transient pacing or rotation event.
- **Page-cap interaction.** Pinned slots still consume a campaign/creative slot in the page-cap state so other slots don't double up on the same advertiser.
- **Site-wide pin exclusion.** When a slot is pinned to creative C of campaign A, no other slot on that page can serve any creative of campaign A — pinning is "the reader's page is reserved for that advertiser's bookmarked creative; don't dilute it."
- **Tests.** Pointer to `AdServerPinHonorSpec` so a future contributor can see the exact semantics frozen in tests.

### Source of truth
- `modules/core/src/main/scala/promovolve/publisher/delivery/AdServer.scala` — `batchReserveWithRetry`, `dogearFallthrough`
- `modules/core/src/main/scala/promovolve/publisher/delivery/Protocol.scala` — `BatchSelect`, `DogearOutcome`
- `modules/core/src/test/scala/promovolve/publisher/delivery/AdServerPinHonorSpec.scala`

---

## 8. The Dashboard Projection

**Path:** `src/architecture/dashboard-projection.md`
**SUMMARY position:** Sub-chapter under "Architecture", after "Data Flow: Crawl vs Serve".

### Why
The dashboard is what publishers and advertisers actually look at; the projection is how event-sourced reality becomes queryable read models. None of this is documented. Useful for readers who want to extend the dashboard or wire a different read model.

### Outline
- **Why a separate projection.** Event sourcing on the write side (CampaignEntity, AdvertiserEntity, etc.); projections on the read side. Dashboards must not block actor mailboxes.
- **The journal.** `tracking_events` table. What gets written (impressions, clicks, CTAs, folds) and what doesn't (every actor message — only billable / engagement events).
- **The handler.** `DashboardProjectionHandler` consumes the journal and writes to per-bucket aggregate tables (hourly / daily, per-advertiser and per-publisher summaries, dog-ear counters).
- **Per-event ledgers.** What each event class produces. Spend on impressions, click-through-rate inputs, CTA conversions, fold counters.
- **Bucketed aggregates.** How hour and day buckets are computed; why we don't query the journal directly at dashboard time.
- **The dog-ear wing.** Folds and dogeared impressions are tracked separately from primary metrics. Folds aren't billed; dogeared impressions are billed via CPM like any other.
- **Backfill and replay.** What happens after a schema change — projection reset, replay from offset zero.

### Source of truth
- `modules/api/src/main/scala/promovolve/api/projection/TrackingEventJournal.scala`
- `modules/api/src/main/scala/promovolve/api/projection/DashboardProjectionHandler.scala`
- `docker/init-db.sql` — table shapes

---

## 9. The Crawler — Stealth and Scheduling

**Path:** `src/crawler/overview.md` + `src/crawler/stealth.md` + `src/crawler/scheduler.md`
**SUMMARY position:** New top-level "## Crawler" section between "Distributed State" and "Comparison".

### Why
The crawler is how content classifications get into the system. It's also a non-trivial subsystem (Playwright, stealth, concurrency-bounded scheduling, URL-block patterns) that's currently invisible in the book. Specifically worth documenting:
- Why we do stealth (LPs that block bots return useless content)
- Why URL-block (so the crawler can't fire real ad serves and pollute its own training data)
- Why a scheduler (avoid thundering herd on restart with hundreds of sites)

### Outline (3 sub-chapters)

**`overview.md`**
- What the crawler does: discover pages, classify them, feed AuctioneerEntity
- Trigger model: scheduled (Quartz cron) + on-demand
- Output: `Map[URL, Classification]` in AuctioneerEntity state, 48-hour recency window

**`stealth.md`**
- Why: many LPs block headless browsers, returning login walls or empty bodies
- Implementation: `BrowserContextFactory` injects `stealth.js` before the crawler init script
- What stealth.js does: removes `navigator.webdriver`, patches `permissions`, fakes `chrome` runtime, etc.
- Same context factory powers `PlaywrightWorker` (LP-to-creative pipeline) — stealth applies wherever we run a real browser
- URL-block: the crawler refuses to fetch our own ad endpoints (`/v1/serve/`, `/v1/imp`, `/v1/click`, `/v1/cta`, `/v1/dogear-event`) so it can't fire real serves while crawling

**`scheduler.md`**
- Why: hundreds of sites + restart = thundering herd
- `CrawlScheduler`: cluster-singleton concurrency-bounded scheduler. `RequestCrawlPermit` / `ReleaseCrawlPermit`. Default `maxConcurrent=8`
- Stale-release sweep (10 min) to clean up after worker crashes
- How `SiteEntity.StartCrawling` plumbs through the permit: `pipeToSelf(scheduler.request(siteId))` → `CrawlPermitGranted(crawlerConfig)` → spawn → `CrawlerTerminated` releases
- Pattern shared with `TokenBucketLimiter` — actor-based cluster-singleton primitive worth extracting (already done; mention as a generic primitive)

### Source of truth
- `modules/core/src/main/scala/promovolve/crawler/PlaywrightWorker.scala`
- `modules/crawler/src/main/scala/promovolve/crawler/BrowserContextFactory.scala`
- `modules/core/src/main/scala/promovolve/crawler/CrawlScheduler.scala`
- `modules/core/src/main/scala/promovolve/publisher/SiteEntity.scala` — crawl-permit plumbing
- `modules/core/src/main/scala/promovolve/TokenBucketLimiter.scala` — companion primitive

---

## Suggested order

1. **Magazine format overview** (#1) — anchor for the rest
2. **Quality-adjusted pricing** (#6) — small, mostly extracts content already in `scoring-formula.md` and frames it next to the auction phases
3. **Pin-honoring** (#7) — short, pure-server, well-tested already
4. **Dog-ear** (#5) — depends on #1, #7
5. **Fluid creatives** (#2) — short, depends on #1
6. **LP-to-Creative pipeline** (#3) — long, depends on #1
7. **Designer / banner stack** (#4) — depends on #1, #3
8. **Dashboard projection** (#8) — independent, can interleave anywhere
9. **Crawler** (#9) — independent, can interleave anywhere

Five short chapters (1, 2, 5, 6, 7) before the two long ones (3, 4) keeps each commit reviewable.
