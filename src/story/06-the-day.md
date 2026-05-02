# Chapter 6: A Day in the Life

Let's follow Takeshi's ryokan campaign through its first full day.

## Morning: The Grace Period (8:00-8:02am)

Yuki's site gets its first traffic of the day. The PI pacing controller has just started a new day — it doesn't know the request rate yet. For the first 10 seconds (or 10 requests, whichever is later), the controller is in **grace period**: it throttles at 99%, serving almost nothing.

Why? Because the controller needs to measure the traffic rate before it can regulate it. Serving aggressively without knowing the rate could blow the budget in the first few minutes. Better to be cautious for 10 seconds and get a baseline.

After 10 requests, the TrafficObserver has computed an exponentially-weighted moving average of the request rate: about 2 requests per second at this hour. The PI controller calculates a base throttle:

```
ideal_serve_rate = budget_remaining / time_remaining / avg_cpm × 1000
                 = $20 / 86400s / $5 × 1000 = 0.046 serves/second

throttle = 1 - (ideal_serve_rate / observed_rate) = 1 - (0.046 / 2.0) = 0.977
```

That's aggressive throttling — skip 97.7% of requests. But that's correct: $20 of budget at $5 CPM is only 4,000 impressions across the entire day. At 2 requests per second, that's about 2,000 seconds of full serving — but the day is 86,400 seconds long. The campaign needs to spread thin.

Grace period ends. Normal serving begins.

## Mid-Morning: Thompson Sampling Converges (8:00-11:00am)

Three hours in. Takeshi's ryokan has been shown 15 times, getting 2 clicks. The hiking gear ad has been shown 12 times, zero clicks.

The Thompson Sampling distributions have diverged:

```
Ryokan:     Beta(3, 14)  — mean ~18%, samples usually between 5-35%
Hiking Gear: Beta(1, 13) — mean ~7%, samples usually between 0-20%
```

The ryokan ad is winning most selections now. Not every time — Thompson Sampling still occasionally picks the hiking gear ad (when its sample happens to beat the ryokan's). But the ratio has shifted from 50/50 to roughly 70/30.

If the hiking gear ad gets a click in its next few impressions, the ratio will tighten. If it doesn't, it'll fade further. No one needs to decide when to stop testing. The system self-regulates.

## Noon: A Reader Folds the Corner (12:00pm)

Four hours in. A reader on her lunch break opens an article on Yuki's blog about hot springs in the Hakone region. Takeshi's ryokan ad is in the sidebar — the collapsed magazine creative showing the cover photo of his garden bath. She taps it. The overlay expands: the cover, then a story page about the rooms, another about the meals, a final page with a "Reserve" button. She isn't booking a trip today, but she might in autumn. Before collapsing the ad, she folds the corner.

A `POST /v1/dogear-event` fires from her browser, carrying a `FoldToken` the serve response handed her earlier:

```
{
  "token": "<HMAC-signed payload: pub|url|slot|cid|ver|bucket|camp|adv|nonce>",
  "slot":  "sidebar-1",
  "cid":   "ryokan-magazine-001"
}
```

The fold endpoint verifies the HMAC, checks the time bucket is fresh, and accepts. Three things happen, all engagement-only — no billing, no auction state change:

- **Pin stored in the reader's browser.** The `dogear-storage` IndexedDB row in her browser remembers `(advertiserId, creativeId)` so the next page load on Yuki's site that's eligible for Takeshi will surface this exact creative.
- **`logFold` writes a tracking event.** The dashboard projection ticks the campaign's fold counter — a reader-engagement signal Takeshi can see on his dashboard.
- **No CPM clearing, no budget reservation.** Folds are free. The fold isn't a billable event; the original impression already cleared.

There's no RL agent to "observe" this. The auction doesn't change behavior. What changes is that *this reader* is now linked, by her own choice, to Takeshi's campaign. Tomorrow, when she lands on a page where Takeshi is eligible, the bookmarked creative is the one served — bypassing the auction reservation and the pacing throttle. The pin is her vote, and the system honors it.

It's the first thing in this story that wouldn't happen on a traditional ad exchange. Readers don't get to bookmark ads anywhere else.

## Afternoon: Pacing Adjusts (2:00-5:00pm)

Traffic on Yuki's site shifts. The morning peak (8-11am) is over. Afternoon traffic is lighter — about 0.8 requests per second instead of 2. The PI controller detects the drop through its rate tracker and adjusts:

```
Previous throttle: 0.977 (skip 97.7%)
New throttle:      0.943 (skip 94.3%)
```

Less throttling because the traffic rate dropped. The campaign serves a larger fraction of the smaller number of requests, maintaining a steady spend rate.

But there's more: the **traffic shape tracker** has been learning Yuki's hourly traffic pattern. After a few days (not the first day — the tracker needs data), it will know:

```
Hour 8:  12% of daily traffic
Hour 9:  11%
Hour 10: 10%
...
Hour 14: 4%
Hour 15: 3%
...
Hour 20: 8%  (evening peak)
```

Instead of assuming linear time = linear spend, the pacing target will follow this shape. "Spend 12% of budget during the 8am hour, 3% during the 3pm hour." This prevents the common failure mode of conventional pacing: spending too much during peaks and running dry, or throttling too hard during peaks and having leftover budget at night.

## Evening: A Re-Auction (7:00pm)

A re-auction fires for Yuki's site. What's changed since 2am?

- **JR Rail Pass campaign ran out of budget** at 4pm. Its $8 CPM bid was the highest, but its CTR was mediocre — quality-adjusted clearing kept its eCPM lower than the bid, but the volume still drained the daily budget by mid-afternoon. The pacing controller has been throttling its serves for the last hour.
- **A new advertiser appeared**: a Kyoto pottery workshop, targeting East Asian Culture, $3 CPM.

The auction re-runs with the updated participants:

```
Slot 1 (banner):  Takeshi's Ryokan  — $5.00 CPM (honest bid)
Slot 2 (sidebar): Hiking Gear Co    — $4.00 CPM
Slot 3 (sidebar): Pottery Workshop  — $3.00 CPM (new!)
```

JR Rail Pass is gone — budget exhausted. But its creatives stay in the ServeIndex with a refreshed TTL (they'll be there when budget resets tomorrow). Takeshi's ryokan, which was the second-highest bidder this morning, is now the top bidder. Note Takeshi's bid hasn't changed — the auction extracts the right clearing price from the runner-up's score, so there's nothing for Takeshi to "tune."

The re-auction takes about 3 seconds. The new candidates propagate to all nodes within 2 seconds of gossip. The next reader sees the updated lineup.

## End of Day: Reset

At midnight (or the configured day boundary), the day resets.

**CampaignEntity**: Budget resets to $20. Spend counter goes to zero. The pacing buckets reset, the spend Bloom filter rolls. There's no agent to "reset" — the campaign always bids its honest $5 CPM, and the auction's quality-adjusted second-price clearing means Takeshi's effective price keeps drifting down as his CTR builds.

**TrafficShapeTracker**: Today's hourly traffic volumes are blended into the stored profile with `dayAlpha = 0.2`. After 5 days, the profile is a smoothed average of observed traffic patterns.

**Thompson Sampling stats**: The 60-minute rolling window means the last hour of creative stats carries into the new day. Older stats have already aged out. The system doesn't need an explicit reset.

**Budget event published**: A `CampaignBudgetReset` event tells the AuctioneerEntity that Takeshi's campaign has fresh budget. A debounced re-auction fires within 1 second, and the ryokan ad is back in the candidate pool at full strength.

Day 1 is done. The system served relevant ads, learned which creatives work, paced budgets smoothly, and adapted to traffic patterns — all automatically.

Tomorrow it will be slightly smarter.

---

*Technical deep dives: [PI Control Loop](../pacing/pi-control.md) · [Traffic Shape Learning](../pacing/traffic-shape.md) · [Grace Periods](../pacing/grace-periods.md) · [Re-Auction](../auction/re-auction.md)*
