# Learning Reinforcement Learning Through Floor Price Optimization

This tutorial teaches reinforcement learning (RL) from first principles, using Promovolve's floor CPM optimization system as the running example. Every concept is grounded in real, production Scala code — no toy problems, no gym environments, no Python notebooks.

By the end, you'll understand:

- What reinforcement learning is and when to use it
- How to model a real-world problem as an RL task (states, actions, rewards)
- How neural networks learn to approximate value functions
- How DQN and Double DQN work, and why they matter
- How experience replay and target networks stabilize training
- How to deploy RL in a production system that handles real money

## Why floor price optimization is a great RL problem

Most RL tutorials use video games or grid worlds. These are fine for building intuition, but they don't teach you how RL behaves when:

- **The environment is non-stationary** — the advertiser market changes constantly as campaigns start, pause, exhaust budgets, and adjust bids
- **Actions have real economic consequences** — a floor set too high drives away advertisers, too low leaves money on the table
- **Observations are noisy and delayed** — you only see aggregated metrics every 15 minutes, not instant per-action feedback
- **The state space is continuous** — not a grid, but a blend of rates, fractions, and normalized signals
- **There's no dominant strategy** — unlike campaign bidding (where truthful bidding is always optimal), floor pricing has no closed-form solution

Promovolve's floor CPM agent faces all of these. It's a pure Scala implementation with no ML framework dependencies — you can read every line of the forward pass, backpropagation, and training loop.

## Prerequisites

You should be comfortable with:

- Basic programming concepts (loops, arrays, functions)
- High school math (derivatives, basic probability)
- No prior ML/RL knowledge required — we build everything from scratch

## Chapters

1. [The Problem: Why Floor Optimization Needs RL](./01-the-problem.md)
2. [RL Fundamentals: Agent, Environment, Reward](./02-fundamentals.md)
3. [Building a Neural Network From Scratch](./03-neural-network.md)
4. [From Q-Tables to Deep Q-Networks](./04-dqn.md)
5. [Experience Replay: Learning From the Past](./05-replay-buffer.md)
6. [Double DQN: Fixing Overestimation](./06-double-dqn.md)
7. [Putting It Together: The FloorCpmOptimizationAgent](./07-full-agent.md)
8. [Training in Production: Episodes, Persistence, and Day Resets](./08-production.md)
