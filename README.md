# Profolio

Portfolio analyser: parses brokerage holdings (instrument, ISIN, quantity, price, per
account) and does portfolio analysis on them. No real financial data in this repo, ever —
everything committed uses synthetic data.

## Setup

### Git hooks

This repo ships a `commit-msg` hook that rejects commits carrying AI attribution trailers
(`Co-Authored-By: Claude`, `Generated with/by Claude`), backing up the `attribution` block
in `.claude/settings.json`. `core.hooksPath` is local git config, so it isn't set
automatically on a fresh clone — wire it up once per clone:

```sh
chmod +x .githooks/commit-msg
git config core.hooksPath .githooks
```
