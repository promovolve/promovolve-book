# Phase 2: Category Ranking

After page classification identifies the top K categories, each category is assigned a **ranker weight** that reflects how well ads in that category have historically performed on this specific site.

## TaxonomyRankerEntity

Each `(category, siteId)` pair has its own `TaxonomyRankerEntity`. Configuration from `application.conf`:

| Parameter | Default | Env Var |
|-----------|---------|---------|
| Half-life | 7 days | `TAXONOMY_RANKER_HALF_LIFE` |
| Prior α | 1.0 | `TAXONOMY_RANKER_PRIOR_ALPHA` |
| Prior β | 1.0 | `TAXONOMY_RANKER_PRIOR_BETA` |
| Flush interval | 5 seconds | `TAXONOMY_RANKER_FLUSH_EVERY` |
| Site blend threshold | 20.0 | — |
| Site min impressions | 100.0 | `TAXONOMY_RANKER_SITE_MIN_IMPRESSIONS` |
| Site stats max age | 14 days | — |
| Max sites per category | 5000 | `TAXONOMY_RANKER_MAX_SITES` |

### Weight Calculation

The ranker uses Thompson Sampling with a Beta-Bernoulli model:

1. Maintain per-category click/impression counts for this site
2. Model CTR as `Beta(prior_α + clicks, prior_β + non_clicks)` — default prior is `Beta(1, 1)` (uniform)
3. **Sample** from the Beta distribution to get a weight
4. Return sampled weight to AuctioneerEntity

### Fan-Out and Timeout

AuctioneerEntity queries all K TaxonomyRankerEntities in parallel with an **800ms timeout**.

If a ranker doesn't respond within 800ms:
- Use **cached weight** with half-life decay: `weight × 0.5^(ageSeconds / halfLifeSeconds)`
- Where `halfLifeSeconds` is the auctioneer's `priorHalfLife` = **1 hour**
  (distinct from the ranker's internal 7-day stats decay)
- Fall back to **prior weight** (0.5) if no cached data exists

### Stats Lifecycle

- Each ranker entity's own statistics decay with a **7-day half-life**
- Stats are flushed to persistence every `flush-every` (5 seconds)
- Because each entity is keyed per `(category, site)`, there is no
  cross-site blending: a new site's rankers start from the `Beta(1, 1)`
  prior. (The `site-blend-threshold` / `site-min-impressions` /
  `site-stats-max-age` / `max-sites-per-category` config keys are
  reserved for a blending design that was never implemented — they are
  read by nothing.)

## Final Category Score

```
categoryScore = classifierConfidence × rankerWeight
```

This score propagates to `CandidateView.categoryScore` and serves as the Thompson Sampling prior during cold start at serve time.
