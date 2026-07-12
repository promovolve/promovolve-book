# The LP-to-Creative Pipeline

A small-business advertiser doesn't have a creative team. They have a landing page. The LP-to-creative pipeline turns that landing page into a magazine creative — pages, copy, layouts, images — automatically. It's what makes the [magazine format](./overview.md) economically viable for advertisers without a production budget.

This chapter walks through the five stages of the pipeline and the Gemini and Playwright machinery behind each.

## What the advertiser does

Three inputs:

1. Paste a landing page URL.
2. Pick an ad product category (IAB Ad Product Taxonomy 2.0).
3. Set a daily budget and max CPM.

The dashboard runs the pipeline, presents a preview, and lets the advertiser tweak before publishing. From the advertiser's view it's "paste URL → see ad" with optional editing in between. Everything below is what runs server-side to make that happen.

## The five stages

```
URL                                                          Created creative
 │                                                                  ▲
 ▼                                                                  │
┌─────────────┐  ┌─────────────┐  ┌──────────────┐  ┌──────────┐  ┌────────────────┐
│ 1. Analyze  │→ │ 2. Rewrite  │→ │ 3. Generate  │→ │ 4. Save  │→ │ 5. Background  │
│ Playwright  │  │ Gemini 2.5  │  │ layouts      │  │ creative │  │ asset finalize │
│ extracts    │  │ Flash       │  │ Gemini 3.1   │  │ (pages + │  │ (images +      │
│ sections    │  │ → magazine  │  │ Flash-Lite   │  │ layouts) │  │ banner PNG +   │
│             │  │ pages       │  │ → PC+Mobile  │  │          │  │ category check)│
└─────────────┘  └─────────────┘  └──────────────┘  └──────────┘  └────────────────┘
```

Stages 1–3 happen during the advertiser's onboarding flow, in real time. Stage 4 is the save. Stage 5 runs in the background after save returns.

## Stage 1: LP analysis (Playwright)

`LPAnalyzer.analyze(url)` spins up a headless Chromium, navigates to the URL, and waits for the page to settle. Why a real browser instead of an HTTP fetch:

- Many landing pages render content with JavaScript. An HTTP fetch returns the empty SPA shell.
- Hero images are often loaded lazily; without rendering them, the analyzer can't capture them as image references.
- Some pages are gated behind cookie banners or anti-bot checks that need a real browser context (`LPAnalyzer` injects a stealth init script — `modules/browser/src/main/resources/stealth.js` — before navigation).

Once the page is rendered, the analyzer extracts a structured representation:

```
LPAnalysisResult(
  title:    String,             // <title> or og:title
  sections: Vector[LPSection],  // headings + body text
  images:   Vector[LPImage],    // hero + inline images with alt text
  locale:   (lang, country, tz) // inferred from URL TLD + page meta
)
```

Sections come from a heading-based segmentation (h1/h2/h3 + their following paragraphs). Images are captured with their natural dimensions and alt text. Locale is inferred so downstream stages can decide whether the rewrite should be in Japanese, English, or whatever the source page is.

The result is JSON; the dashboard surfaces a section picker that lets the advertiser choose which sections to include in the magazine. Up to ~5 sections work well; more than that and the magazine drags.

## Stage 2: Section rewrite (Gemini 2.5 Flash)

`LPExtractor.rewriteSections(sections)` takes the picked sections and asks Gemini to rewrite them into magazine-style page copy. The system prompt is opinionated:

- **Same language as the source.** A Japanese LP rewrites into Japanese, not translated to English.
- **Editor voice, not marketer voice.** Buzzwords like "unlock", "elevate", "seamless", "transform", "game-changing" are explicitly banned.
- **Field-length budgets per page.** `headline` 10–30 chars, `sub` 20–60, `body` 80–220, `caption` 10–40. Tight enough that the result reads like ad copy and not paraphrased web copy.
- **Design tokens.** Each page gets a `tag` (FEATURE / EXPERIENCE / PLAN / STORY / CTA), an `accent` hex color, a dark-gradient `bg`, and an `imgEmoji` for visual punch.
- **Last page only is the CTA.** `isCTA: true` is forced on the final page.

The output is a JSON array of `BannerPage` objects, one per input section, ordered as the advertiser arranged them. This is the structured copy that becomes the magazine's pages.

Why Gemini 2.5 Flash specifically: it's the cheapest Gemini that produces consistent JSON output at this prompt length. Latency is ~3-5 seconds; cost is fractions of a cent per call. Both matter — onboarding is interactive, and the pipeline runs once per advertiser per creative.

## Stage 3: Layout generation (Gemini 3.1 Flash-Lite)

A page with copy isn't a creative yet. The copy needs to live on a canvas — text positioned, sized, colored, with images placed and animations cued. That's the layout.

`LPExtractor.generateLayoutPair(page)` calls Gemini once per page with both the page content and a layout-prompt that asks for:

- **PC layout** at 16:9 aspect ratio.
- **Mobile layout** at 9:16 aspect ratio.

Both in one call. The "pair" is deliberate — generating them together produces variants that read as the *same composition reflowed*, not two unrelated layouts that happen to share copy. Item positions, font weights, and animation cues are paired across PC and mobile so a reader looking at the same page on different devices sees a recognizable design.

Since the reader went portrait-everywhere, the two variants land differently: the 9:16 layout is the expanded surface every device actually renders (and the designer's first tab), while the 16:9 layout is stored as `page.layout` — a tabless delivery artifact that wide collapsed slots and legacy readers still render.

The output is a JSON `LayoutItem[]` — text items with `(left, top, fontSize, color)`, image items with crops, animations with `(targetX, targetY, duration, delay)`. The same schema the [designer](./designer.md) uses for hand-authored creatives, which means hand-authored and AI-generated creatives are indistinguishable downstream.

The model here is **Gemini 3.1 Flash-Lite (preview)**, not 2.5 Flash. The structured-output quality at the layout-grammar level is meaningfully better in 3.1, and the cost is similar. Override with `LAYOUT_MODEL` env var if a future model wins on this task.

## Stage 4: Save (designer → API)

The designer takes the rewritten pages, the generated layouts, and any tweaks the advertiser made, and assembles them into a `BannerConfig` plus a `Pages` array. It POSTs to:

```
POST /advertiser/creatives/save        (Go dashboard)
POST /v1/advertisers/{id}/campaigns/{id}/creatives  (Scala API)
```

The Scala API's `createCreativeLogic` writes the creative row to `CreativeRepo` with the pages JSON, banner config, and reference to the campaign. At this point the creative exists in the database, but its assets aren't finalized yet — image references still point at external URLs (the LP's own CDN, ad-hoc Imgur uploads, etc.) and there's no rendered banner PNG for the dashboard's thumbnail.

The save returns immediately. Stage 5 runs asynchronously.

## Stage 5: Asset finalize (CreativeProcessor)

After save, the API sends a `Process` command to the [`CreativeProcessor`](../architecture/entity-hierarchy.md) actor (the artist formerly known as `RichCreativeProcessor`). Three sub-stages:

**5a. Image import.** External image references in the pages are downloaded with Pekko HTTP, content-addressed by SHA-256, and stored in R2 via `ImageStorage`. The pages JSON is rewritten so references point at our CDN. After this step, the creative is self-contained — no external image dependencies at serve time. If the LP's CDN goes down a year later, the ad still serves.

**5b. Banner render.** `LPAnalyzer.renderBanner(pagesJson, w, h)` spins up Playwright (the same Chromium used in stage 1), loads the magazine-banner web component with the assembled pages and config, paints it, and screenshots the result as a PNG. The PNG goes into R2. This becomes:

- The thumbnail in the creative list.
- The static-image fallback for legacy ad-tag flows.
- The image the publisher's approval queue shows so the publisher can decide before the creative serves.

**5c. Category verification.** If a `CategoryVerificationClient` is wired, the rendered banner + the advertiser's declared `adProductCategory` are sent to Gemini. The model says "this banner is consistent with Travel" or "this looks like Adult content not Travel." The result lands on the creative record:

- A match flips status to `Active` (creative enters the auction pool).
- A no-match flips it to `Flagged` for publisher review.

`skipVerify=true` (used for draft saves) runs sub-stages 5a and 5b but stops before 5c, leaving status as `Draft`. Drafts get a real thumbnail in the list — the advertiser can resume editing without losing their place.

## Idempotency, retries, and failure modes

The pipeline has obvious failure points: an LP that never finishes loading, Gemini returning malformed JSON, an image URL that 403s, R2 timing out. Each stage handles these:

- **LP fetch timeouts.** Playwright runs with a 30-second navigation timeout. On timeout, the analyzer returns an empty result and the dashboard surfaces "couldn't read this URL" with a retry button.
- **Gemini 5xx / rate limits.** Both rewrite and layout calls go through `HttpRetryPolicy.withRetry` — up to 5 attempts, capped exponential backoff with jitter, retries on 408/429/500/502/503/504 plus network failures. The shared `GeminiRateLimiter` token bucket keeps total RPM under the project's quota across all Gemini callers (rewrite, layout, taxonomy classification, category verification).
- **Image download failures.** A single failed image doesn't fail the creative; the page reference is left empty and the page renders without that image.
- **CreativeProcessor crashes mid-pipeline.** On startup, the actor scans `CreativeRepo` for creatives with `pages_json` set but `s3_key` empty (the marker for "stage 5 didn't finish") and re-runs from where the previous attempt died. A restart while the pipeline is mid-flight doesn't lose work.

## Why this matters for the product story

Without the pipeline, the magazine format is a feature for advertisers who can afford a designer. With the pipeline, it's a feature for the local restaurant.

The economic claim — "anyone with a landing page can run an ad" — depends on every step of this chain working end-to-end with no human in the loop except for the final approval. Each Gemini call costs fractions of a cent, runs in a few seconds, and produces something the advertiser can ship. The CreativeProcessor finalizes the assets in the background so the advertiser doesn't watch a spinner.

The other half of the same claim — "and it'll look good in any slot" — is the [Fluid Creatives](./fluid-creatives.md) chapter. The pipeline produces creatives that flow; the format ensures they flow correctly.

## Source of truth

- `modules/browser/src/main/scala/promovolve/browser/LPAnalyzer.scala` — Stage 1 + Stage 5b's `renderBanner`
- `modules/core/src/main/scala/promovolve/creative/LPExtractor.scala` — Stage 2 (rewriteSections), Stage 3 (generateLayoutPair)
- `modules/api/src/main/scala/promovolve/api/EndpointRoutes.scala` — `analyze-lp` / `rewrite-sections` / `generate-layout-pair` routes
- `modules/api/src/main/scala/promovolve/api/CreativeProcessor.scala` — Stage 5 orchestration
- `modules/core/src/main/scala/promovolve/publisher/assessment/CategoryVerificationClient.scala` — Gemini category verification
- `modules/core/src/main/scala/promovolve/llm/HttpRetryPolicy.scala` — shared retry policy for all Gemini calls
- `modules/core/src/main/scala/promovolve/GeminiRateLimiter.scala` — shared RPM budget
