# Pacing Overview

Budget pacing ensures campaigns spend their daily budgets smoothly throughout the day. Promovolve uses a **self-tuning PI control loop** with traffic shape awareness, leaky integrator anti-windup, oscillation detection, and cross-day learning.

## Why Pacing Matters

Without pacing, a campaign with a $100 daily budget and $5 CPM would exhaust after 20,000 impressions. If those arrive in the morning peak, the campaign goes dark for the remaining day.

## Why PI Control Works Here

PI (Proportional-Integral) control is a technique from industrial process control — thermostats, motor speed regulation, chemical plant flow rates. It works well when the controller can observe the system's output and adjust a single input to drive it toward a target.

Budget pacing in Promovolve fits this model because it's a **closed system**. The platform controls both sides of the equation:

- **The input**: the throttle probability (what fraction of ad requests to serve)
- **The output**: the spend rate (how fast budget is consumed)
- **The target**: even delivery across the day (spend rate = budget / time remaining)

The controller observes the spend rate, compares it to the target, and adjusts the throttle. Overspending? Throttle up (skip more requests). Underspending? Throttle down (serve more). The feedback loop is tight and the response is predictable.

This wouldn't work in the traditional programmatic stack. In RTB, the publisher submits impressions to an exchange and has no control over whether a campaign wins any given auction — that depends on competing bids from unknown DSPs. The campaign's delivery rate is a function of market dynamics the pacing controller can't observe or influence. You can adjust your bid, but you can't control the outcome.

In Promovolve, there's no external auction to compete in at serve time. The candidates are already cached. The pacing gate is a simple yes/no decision on each request, and the controller has full authority over that decision. This makes the system **controllable** in the control-theory sense — the input (throttle) directly determines the output (delivery rate), with no unobservable external disturbances.

That's why a PI controller — a well-understood, stable, analytically tractable technique — works for a problem that the traditional ad tech industry solves with heuristic rules and hope.

## Promovolve's Approach

```
┌─────────────────┐     ┌──────────────┐     ┌───────────────┐
│ Traffic Observer │ ──► │ PI Control   │ ──► │ Throttle Prob  │
│ (EMA rate, 1s)  │     │ (self-tuning)│     │ [0.0, 0.99]   │
└─────────────────┘     └──────────────┘     └───────────────┘
       ▲                       │                     │
       │                       ▼                     ▼
       │               ┌──────────────┐     ┌───────────────┐
       │               │ Traffic Shape│     │ Bernoulli     │
       │               │ (weekday/wknd│     │ Serve or Skip │
       └───────────────│  24h buckets)│     └───────────────┘
                       └──────────────┘
```

## Key Components

1. **[Rate Tracking (EMA)](./rate-tracking.md)**: Synchronous, 1-second window, α=0.3
2. **[PI Control Loop](./pi-control.md)**: Self-tuning gains, asymmetric response, leaky integrator
3. **[Traffic Shape Learning](./traffic-shape.md)**: Separate weekday/weekend 24-hour profiles
4. **[Grace Periods](./grace-periods.md)**: Startup protection with MaxThrottleProb (0.99)

## Pipeline Position

Pacing operates as a **volume gate** before Thompson Sampling:

```
Content recency → Frequency cap → Rate tracking → Pacing gate → Thompson Sampling
```

The pacing gate makes a Bernoulli decision: `if random() < throttleProbability → skip (204)`. This gates volume, not choice — Thompson Sampling only runs for requests that pass the gate.

## Key Constants (from AdaptivePacing.scala)

| Constant | Value |
|----------|-------|
| `MaxThrottleProb` | 0.99 (1.0 reserved for hard-stop) |
| `DefaultKp` | 0.5 |
| `DefaultKi` | 0.3 |
| `BaseOverpaceGainMultiplier` | 2.0 |
| `IntegralDecayFactor` | 0.995 (leaky integrator) |
| `SpendRatioSmoothingAlpha` | 0.3 |
| `DefaultAvgCpm` | $5.00 |
