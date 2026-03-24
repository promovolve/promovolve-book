# Chapter 4: A Reader Arrives

It's 10:15am. A traveler in Singapore is planning a November trip to Kyoto and finds Yuki's article through a search engine: "Autumn Foliage Hikes in Eastern Kyoto." The page loads. The article renders. And in the sidebar, an ad slot needs filling.

Yuki's JavaScript snippet fires a request to Promovolve:

```
GET /v1/serve?pub=yuki-site&url=https://yukiblog.jp/autumn-hikes&slot=sidebar-1
```

What happens next takes less than a millisecond.

## Step 1: Local DData Lookup

The API node handling this request looks up `yuki-site|sidebar-1` in its local DData replica. This is a hash map lookup in the JVM's memory — no network call, no database query. The candidates from last night's auction (refreshed by the 5-minute re-auction cycle) are right there:

```
Candidates:
  1. Takeshi's Ryokan — $5.00 CPM, Beta(1, 1)  [new, no impressions yet]
  2. Hiking Gear Co   — $4.00 CPM, Beta(1, 1)  [new, no impressions yet]
```

Both creatives were approved by Yuki. Both have budget remaining. Both are ready to serve.

## Step 2: Content Recency Check

The system checks: is this page still fresh? The classification timestamp says it was crawled 8 hours ago. The recency window for Yuki's site is 48 hours. Eight hours is well within that — the page is fresh. Proceed.

If the article were from last week and hadn't been re-crawled, the candidates might have expired (TTL 120 minutes) and the response would be `204 No Content` — an empty ad slot. This is by design: stale content doesn't get monetized.

## Step 3: The Pacing Gate

Before choosing a creative, the PI controller decides: should we serve at all?

It's 10:15am. Takeshi's ryokan campaign has a $20 daily budget. Based on the traffic shape the system has learned for Yuki's site (most traffic between 8am-11am JST, another peak at 8pm), the ideal spend by 10:15am is about 35% of the budget — $7. The campaign has spent $4 so far. It's slightly underpacing.

The PI controller computes a throttle probability: 0.12 (skip 12% of requests to stay on pace). A random number is drawn: 0.47. That's above 0.12, so this request passes the gate.

If the campaign were overspending — say, $12 spent by 10:15am — the throttle would be higher, maybe 0.65, and more requests would be skipped. The campaign would slow down, stretching its remaining budget across the afternoon.

This happens before creative selection. If the gate rejects the request, Thompson Sampling never runs — no exploration is wasted on a throttled impression.

## Step 4: Thompson Sampling

Now the system picks which creative to show. Both candidates are brand new — zero impressions, zero clicks. Their Beta distributions are both `Beta(1, 1)`, the uniform distribution.

Thompson Sampling draws a random sample from each:

```
Takeshi's Ryokan: sample from Beta(1, 1) → 0.72
  score = 0.72 × log(1 + 5.00) = 0.72 × 1.79 = 1.29

Hiking Gear Co:   sample from Beta(1, 1) → 0.34
  score = 0.34 × log(1 + 4.00) = 0.34 × 1.61 = 0.55
```

Takeshi's ryokan wins this round. Not because it's better — nobody knows yet — but because its random sample happened to be higher. Next time, the hiking gear ad might win. With `Beta(1, 1)` on both sides, it's nearly a coin flip, weighted slightly by CPM.

This is pure exploration. Over the next hundred impressions, the system will learn which creative readers actually click on, and the randomness will give way to informed selection.

## Step 5: Budget Reservation

Before serving the ad, the system reserves the spend. The CampaignEntity for Takeshi's campaign receives a `TryReserve` request:

- Amount: $5.00 / 1000 = $0.005 (one impression at $5 CPM)
- Budget remaining: $16.00
- Result: Reserved. Budget is now $15.995.

If the budget were exhausted, the response would be `InsufficientBudget`, and Thompson Sampling would try the next candidate (Hiking Gear Co). If all candidates are exhausted, the response is `204 No Content`. Graceful degradation, no errors.

The reservation is recorded in the CampaignEntity's ephemeral buffer. The RL agent notes the impression: `recordImpression($0.005)` and `recordBidOpportunity(won: true)`.

## Step 6: The Response

The API returns a JSON response in under a millisecond:

```json
{
  "assetUrl": "https://cdn.promovolve.dev/ryokan-hakone-300x250.jpg",
  "mime": "image/jpeg",
  "width": 300,
  "height": 250,
  "clickUrl": "https://api.promovolve.dev/v1/click?pub=yuki-site&...",
  "impUrl": "https://api.promovolve.dev/v1/imp?pub=yuki-site&...",
  "creativeId": "ryokan-001",
  "version": 1711090800000
}
```

The JavaScript snippet renders the image and fires the impression pixel (`impUrl`). The tracking URL is HMAC-signed — it can't be forged or tampered with.

## What the Reader Sees

A photo of a ryokan nestled in autumn mountains, next to an article about autumn hikes in Kyoto. The ad is relevant. It fits the context. The reader might not even register it as an "ad" in the intrusive sense — it feels like a recommendation.

This is what we set out to build: the magazine experience, on the web.

The reader reads the article. They notice the ryokan photo. They think, "that looks nice for our trip." They click.

---

*Technical deep dives: [Thompson Sampling](../serving/thompson-sampling.md) · [Scoring Formula](../serving/scoring-formula.md) · [Pacing Overview](../pacing/overview.md) · [Fair Selection](../serving/fair-selection.md)*
