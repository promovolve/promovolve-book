# Phase 1: Page Classification

Before any auction can run, the system must understand what a page is about. Page classification maps URLs to IAB Content Taxonomy categories with confidence scores using LLM-based analysis.

## Classification Pipeline

Promovolve supports multiple LLM providers for classification, configured in `application.conf`:

| Provider | Config Key | Env Var |
|----------|-----------|---------|
| Gemini | `promovolve.gemini.api-key` | `GEMINI_API_KEY` |
| OpenAI | `promovolve.openai.api-key` | `OPENAI_API_KEY` |
| Anthropic | `promovolve.anthropic.api-key` | `ANTHROPIC_API_KEY` |

Gemini is enabled by default (`promovolve.gemini.enabled = true`).

## Classification Output

The classifier produces a map of category-to-confidence:

```json
{
  "url": "https://example.com/sports/nba-finals-recap",
  "categories": {
    "IAB17": 0.92,
    "IAB17-1": 0.85,
    "IAB12": 0.45
  }
}
```

Each `Confidence` value is an opaque `Double` in [0, 1].

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
