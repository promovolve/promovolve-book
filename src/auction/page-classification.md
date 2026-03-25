# Phase 1: Page Classification

Before any auction can run, the system must understand what a page is about. Page classification maps URLs to IAB Content Taxonomy 2.1 categories with confidence scores using LLM-based analysis.

## Two Taxonomies, One Match

Promovolve uses two distinct IAB taxonomies that meet at auction time:

| Taxonomy | Version | Who sets it | Purpose |
|----------|---------|-------------|---------|
| **Ad Product Taxonomy** | 2.0 | Advertiser | "What is my product?" (e.g., Travel, Kitchen Equipment) |
| **Content Taxonomy** | 2.1 | LLM classifier | "What is this page about?" (e.g., Destinations, Outdoor Recreation) |

The advertiser never sees content categories. They pick their product category, and `ContentToAdProductMapping` derives the matching content categories using the official IAB mapping file (`content_2.1_to_ad_product_2.0.tsv`). If no direct mapping exists for a product category, the system walks up the taxonomy's parent chain until it finds one.

At auction time, matching is **exact**: the page's content category must be in the campaign's derived content category set. There is no fuzzy or hierarchical matching at bid time — the hierarchy is resolved once, at campaign setup.

## Classification Pipeline

Promovolve supports multiple LLM providers for classification, configured in `application.conf`:

| Provider | Config Key | Env Var |
|----------|-----------|---------|
| Gemini | `promovolve.gemini.api-key` | `GEMINI_API_KEY` |
| OpenAI | `promovolve.openai.api-key` | `OPENAI_API_KEY` |
| Anthropic | `promovolve.anthropic.api-key` | `ANTHROPIC_API_KEY` |

Gemini is enabled by default (`promovolve.gemini.enabled = true`).

## Classification Output

The LLM returns category IDs which are normalized to **IAB Content Taxonomy 2.1 numeric IDs**. Legacy IAB 1.0 format IDs (e.g., `"IAB17"`) are converted via `TieredCategory.normalize()` to their 2.1 equivalents (e.g., `"483"`). The result is a map of category-to-confidence:

```json
{
  "url": "https://example.com/sports/nba-finals-recap",
  "categories": {
    "483": 0.92,
    "484": 0.85,
    "393": 0.45
  }
}
```

Each `Confidence` value is an opaque `Double` in [0, 1]. All downstream matching uses these numeric Content Taxonomy 2.1 IDs.

## Top-K Category Selection

AuctioneerEntity selects the **top K categories** (default K=3) by confidence score. Only these categories proceed to ranking and bidding.

## Classification Storage

Classifications are stored in AuctioneerEntity's state as a `Map[URL, Classification]`, keyed by page URL and timestamped with `classifiedAtMs`. Every 5 minutes, a cleanup task removes entries older than the 48-hour recency window.

## Role in Scoring

The confidence score feeds into category ranking:

```
categoryScore = classifierConfidence × rankerWeight
```

This composite score is stored in `CandidateView.categoryScore` and used as a prior for Thompson Sampling during cold start.
