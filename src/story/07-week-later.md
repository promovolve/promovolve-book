# Chapter 7: A Week Later

Seven days have passed. Let's see what the system has learned.

## Takeshi's Effective CPM Has Drifted Down

Takeshi's max CPM is still $5 — he hasn't touched it. He's never going to touch it; there's nothing to touch. But his *effective* CPM, what he actually pays per won impression, has been dropping all week.

The reason is the auction itself. Quality-adjusted second-price clearing computes the winner's payment as the minimum CPM that would still beat the runner-up given its sampled CTR:

```
clearingCPM = (bestLoserScore / sampledCTR_winner) ^ (1/α)
```

As Takeshi's `Beta(15, 299)` distribution narrowed around 4.8% CTR, his `sampledCTR_winner` settled higher than most competitors. Higher CTR → lower clearing CPM. By day 7, Takeshi's eCPM is around $3.40 — well under his $5 max. He's getting a 32% quality discount, automatic, with no agent in the loop.

The JR Rail Pass campaign tells the opposite story. Its $8 max bid would dominate a pure first-price auction, but with a 3.1% CTR competing against Takeshi's 4.8%, its effective CPM stays close to its bid — the auction has nothing to discount. It still wins many slots (its raw CPM is high enough to overcome the CTR gap), but it pays for them.

This is what replaces a campaign-side bid optimizer. The auction itself extracts honest bids and rewards quality. There's nothing for an RL agent to learn here — bid shading would just lose impressions, and the right price for any given impression depends on the runner-up, which the campaign can't observe in advance anyway.

## A Few Readers Have Dog-Eared the Ad

The dashboard projection has been counting fold events:

```
Takeshi's ryokan-magazine-001:
  Folds this week:  9
  Pin re-encounters: 4 (so far)
```

Nine readers have folded the corner of Takeshi's creative this week. Four of them have already returned to a page where Takeshi was eligible — and instead of the auction running, the ad they bookmarked was the one served. Those re-encounters bypass CPM clearing (free), bypass pacing throttle (a bookmark is a reader's choice, not a billable serve), and don't count against the daily budget.

For Takeshi, this is a quietly powerful effect. Nine reader-driven bookmarks in a week is more loyalty than a typical retargeting campaign produces, and he didn't pay for the re-encounters. The pins live in the readers' own browsers; the server doesn't know who they are, only that *someone* with that browser folded that creative.

In a few months, when one of those readers actually plans an autumn trip and lands on a Hakone article, Takeshi's ryokan will be the ad they see. The bookmark is doing the work that retargeting tries to do, without the surveillance.

## Thompson Sampling Has Converged

After hundreds of impressions, the creative stats tell a clear story:

| Creative | Impressions | Clicks | Distribution | Mean CTR |
|----------|------------|--------|-------------|----------|
| Takeshi's Ryokan | 312 | 14 | Beta(15, 299) | 4.8% |
| JR Rail Pass | 287 | 8 | Beta(9, 280) | 3.1% |
| Hiking Gear Co | 89 | 1 | Beta(2, 89) | 2.2% |
| Pottery Workshop | 45 | 3 | Beta(4, 43) | 8.5% |

Takeshi's ryokan gets the most impressions — it has a proven CTR and a decent CPM. JR Rail Pass has a higher CPM but lower CTR; the scoring formula `sampledCTR × CPM^α` (publisher α=0.5) keeps them competitive but Takeshi's CTR advantage matters — and translates directly into a lower clearing price for him.

The pottery workshop is interesting. It has fewer impressions (it started later in the week) but its CTR is the highest — 8.5%. Its `Beta(4, 43)` distribution is still fairly wide, though. Thompson Sampling is giving it more exploration to confirm whether this high CTR is real or noise.

The hiking gear ad has mostly faded out. `Beta(2, 89)` samples near zero most of the time. It gets about 5% of impressions — just enough exploration to detect if something changes (new creative, seasonal shift). If the advertiser uploaded a better creative, the system would detect the improvement within hours.

Nobody made any of these allocation decisions. No one paused the hiking gear campaign or boosted the pottery workshop. The system found the right distribution through pure learning.

## The Category Ranker Has Opinions

The TaxonomyRankerEntity for Yuki's site has accumulated a week of data:

```
Travel:           Beta(45, 355)  — 11.3% CTR, tight distribution
Adventure Travel: Beta(8, 192)  — 4.0% CTR, fairly confident
Asia Travel:      Beta(5, 45)   — 10.0% CTR, still exploring
Food & Drink:     Beta(2, 28)    — 6.7% CTR, early data
```

Travel dominates — it gets the highest weight in most auctions. But Asia Travel is a surprise performer. The pottery workshop (Asia Travel category) is driving this. The ranker is giving Asia Travel more auction weight, which means more bidding opportunities for advertisers in that category.

This creates a virtuous cycle: good category performance → more auction weight → more candidates → more data → better Thompson Sampling → better ads → higher CTR → higher category performance.

## Traffic Shapes Are Calibrated

The TrafficShapeTracker now has 7 days of hourly data for Yuki's site, blended with `dayAlpha = 0.2`:

```
Weekday profile:
  Hour  0-6:   1-2% each  (late night, minimal traffic)
  Hour  7:     4%          (morning commute)
  Hour  8-10: 10-12% each (peak reading time)
  Hour 11-13:  6-7% each  (lunch)
  Hour 14-17:  3-4% each  (afternoon lull)
  Hour 18-20:  7-9% each  (evening reading)
  Hour 21-23:  3-4% each  (winding down)
```

The PI controller uses this shape instead of a linear time fraction. At 10am, it knows 32% of daily traffic has typically passed (not 42% if you assumed linear). This means the pacing target at 10am is "have spent about 32% of budget" — not 42%. The result: budgets stretch correctly across the day's actual traffic pattern, not an imaginary uniform distribution.

## Pacing Has Self-Tuned

The PI controller has been adjusting itself:

- **Overpace multiplier**: Started at 2.0×. After detecting that JR Rail Pass occasionally overpaced by 20% in the morning (its $8 CPM combined with peak traffic kept burning through budget faster than the linear target), it increased to 2.8×. This means the controller responds more aggressively to overspending — a correction learned from experience.

- **Spend ratio smoothing**: The adaptive EMA alpha settled at 0.25. The traffic on Yuki's site is moderately volatile (it spikes when she publishes a new article and posts to social media). The controller learned to smooth more than the default to avoid overreacting to these spikes.

## What Yuki Sees

Yuki checks her publisher dashboard:

```
This Week:
  Impressions served:  1,847
  Revenue:             $9.24
  Active advertisers:  4
  Top category:        Travel (58% of impressions)
  Approval queue:      2 new creatives pending review
```

The revenue isn't life-changing — it's a small blog. But the ads are relevant, the site is fast, and her readers haven't complained. She approves the two pending creatives (a Kyoto walking tour and a Japanese language school) and goes back to writing her next article.

## What Takeshi Sees

Takeshi checks his advertiser dashboard:

```
This Week:
  Impressions:  312
  Clicks:       14
  CTR:          4.5%
  Spend:        $1.56
  Avg CPC:      $0.11
```

Fourteen people clicked through to his ryokan's booking page from a travel blog — exactly the kind of reader he wanted to reach. His cost per click is $0.11. He didn't have to manage bids, adjust targeting, or learn a DSP interface. He uploaded a photo, set a budget, and the system did the rest.

He increases his daily budget to $30.

## The Floor Has Nudged Up

Yuki hasn't touched her site's floor CPM all week — but it's not the same number it started at.

The publisher-side floor sweep optimizer has been quietly experimenting on Yuki's site. Most of the week, four campaigns have been competing for her slots at $3, $4, $5, and $8 — enough spread that where the floor sits actually moves outcomes. The sweep tried candidate floors, measured what each actually earned in served revenue, and kept the winner — nudging the floor from $0.50 to $0.80 over five days. Fill stayed healthy; clearing prices on cold-start serves came in higher; Yuki's revenue ticked up about 6% on top of what the auction itself was earning her.

If the spread had been narrow — every bidder offering the same CPM — the agent would have stayed put. Moving the floor in a homogeneous market just shrinks fill without raising prices. The agent is gated by exactly this signal.

There is no learning algorithm behind it — just controlled measurement, rediscovering the revenue-optimal floor each cycle. It runs on the publisher's side; advertisers see honest second-price clearing regardless of where the floor sits.

## The System Keeps Learning

Day 8 begins. The system has found its rhythm: a travel blog with relevant ads, a local ryokan reaching interested travelers, creative performance continuously sharpened by Thompson Sampling, budgets paced smoothly, the publisher's floor tuned to the actual bid spread, and a small but growing set of readers who have explicitly bookmarked the ads they want to come back to.

It isn't done learning. New advertisers will join. Yuki's traffic shape will shift with the seasons. Some readers will fold ads; others will block them; the dashboard will reflect both. The pottery workshop's `Beta(4, 43)` is still wide enough that next week could swing either way.

But notice what's *not* happening: nobody is tuning a bid multiplier. Takeshi isn't checking his "bid strategy." There's no auto-bidder cycling through state-action pairs in a Q-table. The auction itself extracts honest bids, the readers vote with their dog-ears, and the publisher's floor agent handles the one piece of price-side learning that's actually informative.

This is what advertising looks like when you start with the content, the format, and the reader — instead of the user profile.

---

*Technical deep dives: [Scoring Formula](../serving/scoring-formula.md) · [Traffic Shape Learning](../pacing/traffic-shape.md) · [Key Innovations](../comparison/innovations.md)*
