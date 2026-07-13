# Budget Pacing

A daily budget spent by 9 a.m. serves the advertiser badly — the evening
audience never sees the campaign, and the morning's impressions were bought
in a rush. Pacing's job is to make spend *track the day*, and its design
principle is the control engineer's, not the machine learner's: a simple
feedback loop, self-tuned by observation.

## The gate

Pacing acts at serve time as a probabilistic gate ahead of selection: each
request, each campaign is throttled with some probability; a throttled
campaign sits the impression out. The probability comes from a **PI
controller** on the spend ratio:

```
error      = smoothed(actualSpend / expectedSpend) − 1
throttle   = clamp(Kp·error + Ki·integral, 0, 0.99)
```

Overspending pushes the throttle up; underspending lets it fall. The
controller is deliberately asymmetric — over-pacing errors are amplified by
a multiplier (base 2×) because overspend is irrecoverable while underspend
can be caught up later.

The refinements are where the production behavior lives, and each earns its
place:

- **Self-tuning.** The overpace multiplier adjusts itself (between 1.5× and
  5×) from a rolling window of recent spend ratios: persistent overspend
  makes the controller more aggressive, well-paced days relax it, and the
  learned value carries across days. Fixed gains, self-tuned application.
- **Oscillation damping.** If the spend ratio starts see-sawing, smoothing
  increases until it settles — a controller that hunts is worse than one
  that lags.
- **Anti-windup.** The integral term is clamped and decays, so a long
  morning of underspend can't bank an afternoon of unthrottled spending.
- **Grace periods.** A fresh day (or a just-started campaign) gets a short
  window with gentle throttling — both a minimum time *and* a minimum
  request count, because low-traffic sites may take an hour to see ten
  requests. Without the request-count condition, small sites were throttled
  on the basis of no evidence at all.
- **Cross-day learning.** A campaign that exhausted its budget early today
  starts tomorrow with a boosted multiplier hint.

## Expected spend follows the traffic, not the clock

`expectedSpend` is the subtle half. Linear pacing (X% of budget by X% of
day) over-throttles the morning peak and sets impossible targets overnight.
Promovolve instead learns each site's **traffic shape**: 24 hourly volumes,
learned separately for weekdays and weekends, from the arrival times of ad
requests themselves.

The learning is deliberately conservative. A brand-new site bootstraps a
shape during its first day with a fast intra-day estimator; from then on —
permanently — the shape changes **only at the UTC-midnight rollover**, when
today's observed distribution blends 20/80 into the stored shape. Restarts
restore the persisted shapes (both day types) and re-enter the same regime;
snapshots are written hourly, at rollover, and on shutdown. Ten similar days
converge the shape; one anomalous day barely dents it.

Shapes are **learn-only**. There is no API or dashboard field to set one,
deliberately: a hand-authored shape encodes intuition, not measurement, and
a *wrong* shape is worse than none — flat degrades gracefully to exactly
linear pacing, while wrong throttles the real peak. Publishers can see the
learned shapes (they're charted on the site's observations page, and
exported in site stats) but not edit them.

The shape serves pacing twice: its cumulative curve becomes the expected
spend fraction the PI controller tracks, and its per-hour relative volume
scales the impression-rate target, interpolated across hour boundaries so
rates ramp instead of stepping.

## What isn't here

There is no per-impression bid adjustment, no predicted-win-rate model, and
no volatility-scheduled gain table (one was designed; production only ever
needed the self-tuned controller, so it was deleted). Pacing is a feedback
loop you can reason about with a napkin — which is exactly why it can be
trusted to gate every impression the platform serves.
