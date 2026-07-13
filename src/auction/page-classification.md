# Phase 1: Page Classification

Before any auction can run, the system must understand what a page is about. Page classification maps URLs to IAB Content Taxonomy 3.0 categories with confidence scores using LLM-based analysis.

## On-Demand, Traffic-Driven

Classification has no schedule and no crawler. It is triggered by traffic: when a page's first visitor arrives and the serve misses, the ad tag extracts the live page's text and slot geometry in the browser and POSTs it to `/v1/classify-page`. The endpoint replies `202 Accepted` immediately; SiteEntity single-flights the classification per URL, so concurrent visitors don't stack duplicate LLM calls.

Freshness is a token, not a timer: each serve response carries `reclassifyInMs`, computed from the publisher's classification-freshness window (default 48 hours). While the token is positive, the ad tag doesn't re-send text — fresh pages are never re-classified per serve. A page nobody visits never classifies, and has no impressions to sell, so that's correct by design.

## One Taxonomy, One Match

Both sides of the match speak **IAB Content Taxonomy 3.0** directly. The page's categories come from the LLM classifier; the campaign's target categories are an explicit advertiser declaration (seeded by Gemini's analysis of the advertiser's landing page, and editable). There is no content↔ad-product bridge — the advertiser's Ad Product Taxonomy category still exists, but only for publisher blocklists, not for matching.

At auction time, matching is **exact**: the page's content category must be in the campaign's target category set. There is no fuzzy or hierarchical matching at bid time.

## Classification Pipeline

Promovolve supports multiple LLM providers for classification, configured in `application.conf`:

| Provider | Config Key | Env Var |
|----------|-----------|---------|
| Gemini | `promovolve.gemini.api-key` | `GEMINI_API_KEY` |
| OpenAI | `promovolve.openai.api-key` | `OPENAI_API_KEY` |
| Anthropic | `promovolve.anthropic.api-key` | `ANTHROPIC_API_KEY` |

Gemini is enabled by default (`promovolve.gemini.enabled = true`).

## Classification Output

The LLM returns category IDs which are normalized to **IAB Content Taxonomy 3.0 IDs**. Legacy IDs — IAB 1.0 format (e.g., `"IAB17"`) or 2.x numeric — are converted via `TieredCategory.normalize()` through the migration table to their 3.0 equivalents. The result is a map of category-to-confidence:

```json
{
  "url": "https://example.com/sports/nba-finals-recap",
  "categories": {
    "547": 0.92,
    "483": 0.85,
    "489": 0.45
  }
}
```

Translated: Basketball (547), Sports (483), College Basketball (489). Each `Confidence` value is an opaque `Double` in [0, 1]. All downstream matching uses these Content Taxonomy 3.0 IDs.

## Top-K Category Selection

AuctioneerEntity selects the **top K categories** (default K=3) by confidence score. Only these categories proceed to ranking and bidding.

## Classification Storage

The durable copy lives in `SiteEntity.pageClassifications`, keyed by page URL and timestamped with `classifiedAt`. The AuctioneerEntity keeps an in-memory `lastPage` map — (categories, slots, `classifiedAt`) per URL — for re-auctions without re-extracting the page. It's reseeded at boot via `RestoreClassifications` and recovered per-URL from SiteEntity when a `Reevaluate` misses. Every 5 minutes, a cleanup task removes entries older than the freshness window.

## Role in Scoring

The confidence score feeds into category ranking:

```
categoryScore = classifierConfidence × rankerWeight
```

This composite score is stored in `CandidateView.categoryScore` and used as a prior for Thompson Sampling during cold start.
