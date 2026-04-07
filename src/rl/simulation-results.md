# A Week of Learning

It is Monday morning. Yuki's travel blog has just joined Promovolve. Five advertisers are already targeting travel content: a small ryokan in Hakone ($2 CPM), a regional bus company ($4), a Tokyo travel agency ($6), a premium hotel chain ($8), and a luxury resort ($10). Each has a daily budget of $15.

Yuki sets her minimum floor to 10 cents — she wants every advertiser to have a chance — and leaves Ad Selection Priority on Balanced. The floor optimization agent wakes up, sees a blank slate, and begins.

## Monday: The Agent Knows Nothing

The agent's first state vector is almost entirely zeros. No auctions have run. No impressions have been served. No traffic shape has been observed. Epsilon is 0.80 — the agent will make random decisions 80% of the time.

The floor starts at $0.50. The agent has no opinion about whether this is right.

Traffic arrives. Yuki's article about autumn foliage in Kyoto draws readers through the morning. The pacing controller, also starting fresh, observes the request pattern and begins sketching a traffic shape: busier in the afternoon, quieter at night.

Thompson Sampling explores all ten creatives roughly equally. With no click history, it is flipping coins. The luxury resort's $10 creative wins some impressions. So does the small ryokan's $2 creative. Both are exploring.

The quality-adjusted pricing means the luxury resort doesn't pay $10. When it wins against the hotel chain, it pays the minimum bid that would still beat the hotel's score given its CTR — maybe $4 or $5. When the ryokan wins on a lucky CTR sample, it pays even less.

By the end of Monday, the floor has drifted to $0.69. The agent pushed it up slightly — one of its random actions. Fill rate stayed at 99.9%. The pacing controller throttled half a percent of requests. All five campaigns have budget remaining.

The agent stores 60 transitions in its replay buffer. It has begun training, but with this little data, the Q-network knows almost nothing.

## Tuesday through Thursday: Exploring the Boundaries

The agent tries things. On Tuesday, it holds the floor around $0.65 — similar to Monday. Fill rate stays high. Revenue is steady. The agent doesn't learn much from holding steady.

On Wednesday, the floor drops to $0.44. Did revenue change? Not really. All five bidders were already above the old floor, so lowering it made no difference. The agent learns: *going down from $0.65 doesn't help.*

On Thursday, it pushes further down to $0.19. Same result — no change. The floor is below every bidder. It is doing nothing.

This is not wasted time. The agent is mapping the terrain. It now knows that floors between $0.19 and $0.69 all produce roughly the same outcome with these five bidders. The Q-values for "decrease floor" in this state are converging to "neutral — doesn't hurt, doesn't help."

Meanwhile, the traffic shape tracker has built a clear picture:

```
▄▃▃▃▃▄▅▆▆▇▇▆▆▆▆▇█▇▆▅▄▄▃▃
```

Peak traffic at hour 16-17. Valley at hour 3. The afternoon is 2.7 times busier than the night. The agent sees this as a state dimension: traffic ratio 1.20 during peaks, 0.85 during valleys.

## Friday and Saturday: The Interesting Discovery

On Friday, epsilon is 0.24. The agent is mostly exploiting what it has learned. The floor dips to $0.12 — but then something changes.

On Saturday, with epsilon at 0.13, the agent pushes the floor up to $0.64, then $1.40. This is not random exploration — epsilon is too low for that. The Q-network is actually predicting that a higher floor will produce better outcomes.

Why? The agent has 300+ transitions of experience at this point. It has learned that the floor between $0.10 and $0.65 makes no difference. But it hasn't thoroughly explored $0.65 to $1.50. The Q-values for "increase" in this unexplored region are slightly optimistic (a known DQN tendency — it overestimates the value of unexplored states).

The floor reaches $1.40. Still, all five bidders are above $1.40. Fill rate holds. But the clearing dynamics shift subtly: when the ryokan ($2) wins as a solo candidate (the others' budgets are momentarily low during the serve cycle), it pays $1.40 — the floor — instead of $0.50. The agent notices a small revenue uptick.

## Sunday: Settling

By Sunday, epsilon is 0.087 — the agent makes the greedy (best-known) choice 91% of the time.

The floor settles around $1.71. The agent found that a moderate floor — high enough to provide a meaningful minimum payment for solo winners, but low enough that all five bidders qualify — marginally outperforms the near-zero floor. It is not a dramatic difference. With five competitive bidders, the quality-adjusted pricing does most of the work.

This is the correct conclusion for this market. The floor's main value here is not filtering bidders (all five are well above the floor) but setting a minimum clearing price for the moments when only one candidate wins.

## The Numbers

Over seven days, the system delivered 71,367 impressions with 99.9% fill rate. Zero budget exhaustions. Pacing throttled at most 0.5% of requests. The traffic shape was learned accurately. The floor agent trained on 447 observations across the week.

These are not remarkable numbers. They are *unremarkable* — which is exactly the point. The system worked quietly and correctly for a week without human intervention. The publisher set two parameters (minimum floor and ad priority), and everything else was discovered through experience.

## What the Publisher Saw

Yuki checked her dashboard a few times during the week. She saw:

- **Floor CPM: $1.71** — the optimizer found this level
- **Min Floor: $0.10** — her setting, untouched
- **Ad Priority: Balanced** — her setting, untouched
- **Five campaigns serving**, impression shares roughly proportional to their CTR quality

She didn't see the 447 DQN training steps, the epsilon decay from 0.80 to 0.087, the 7-dimensional state encoding, or the adaptive floor cap that prevented catastrophic exploration. She saw a number that the system chose for her, and ads that kept serving.

That is how it should be.

---

*See also: [How the floor agent works](./overview.md) · [State space](./state-space.md) · [Reward function](./reward-function.md)*
