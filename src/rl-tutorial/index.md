# Learning Reinforcement Learning Through Ad Bidding

This tutorial teaches reinforcement learning (RL) from first principles, using Promovolve's bid optimization system as the running example. Every concept is grounded in real, production Scala code — no toy problems, no gym environments, no Python notebooks.

By the end, you'll understand:

- What reinforcement learning is and when to use it
- How to model a real-world problem as an RL task (states, actions, rewards)
- How neural networks learn to approximate value functions
- How DQN and Double DQN work, and why they matter
- How experience replay and target networks stabilize training
- How to deploy RL in a production system that handles real money

## Why ad bidding is a great RL problem

Most RL tutorials use video games or grid worlds. These are fine for building intuition, but they don't teach you how RL behaves when:

- **The environment is non-stationary** — traffic patterns change by hour, day, and season
- **Episodes have real economic consequences** — overspending wastes advertiser money, underspending leaves revenue on the table
- **Observations are noisy and delayed** — you only see aggregated metrics every 15 minutes, not instant per-action feedback
- **The state space is continuous** — not a grid, but a blend of rates, fractions, and normalized signals
- **Multiple agents interact** — hundreds of campaigns compete simultaneously, each learning its own policy

Promovolve's bid optimization agent faces all of these. It's a ~400-line pure Scala implementation with no ML framework dependencies — you can read every line of the forward pass, backpropagation, and training loop.

## Prerequisites

You should be comfortable with:

- Basic programming concepts (loops, arrays, functions)
- High school math (derivatives, basic probability)
- No prior ML/RL knowledge required — we build everything from scratch

## Chapters

1. [The Problem: Why Bid Optimization Needs RL](./01-the-problem.md)
2. [RL Fundamentals: Agent, Environment, Reward](./02-fundamentals.md)
3. [Building a Neural Network From Scratch](./03-neural-network.md)
4. [From Q-Tables to Deep Q-Networks](./04-dqn.md)
5. [Experience Replay: Learning From the Past](./05-replay-buffer.md)
6. [Double DQN: Fixing Overestimation](./06-double-dqn.md)
7. [Putting It Together: The BidOptimizationAgent](./07-full-agent.md)
8. [Training in Production: Episodes, Persistence, and Day Resets](./08-production.md)
