---
inclusion: always
description: "SuperBrain — workspace orchestrator. Ensures all repos are cloned, installed and connected. This is the only repo you need to connect."
---

# SuperBrain Protocol

SuperBrain orchestrates the workspace from `manifest.json`, which is the single
source of truth. Trust the manifest over anything hardcoded in a script.

## At Session Start

The `SessionStart` hook runs `scripts/session-start.sh` automatically. If you need
to check or run it manually:

```bash
# Already bootstrapped? (written only after a fully successful run)
test -f /projects/sandbox/SuperBrain/.bootstrapped

# Bootstrap — idempotent, returns in <1s when already done
bash /projects/sandbox/SuperBrain/scripts/bootstrap.sh
```

The sentinel is **removed before installing** and **written only on success**, so
its presence means the last run genuinely succeeded. Never treat a missing
sentinel as harmless — it means bootstrap failed or never completed.

## Reading Failures

`bootstrap.sh`, `verify.sh` and `repair.sh` exit with the number of errors, and
**every failure prints its captured output**. Nothing is discarded to
`/dev/null`. If something breaks, the cause is already on screen — read it
instead of re-running blindly.

## Environment

```bash
source /projects/sandbox/SuperBrain/.env
```

Generated from the manifest's `environment` block. Regenerate with
`bootstrap.sh --force`.

## Quick Reference

```bash
# Health check — changes nothing, reports lock drift, collisions, orphans
bash /projects/sandbox/SuperBrain/scripts/verify.sh

# Repair
bash /projects/sandbox/SuperBrain/scripts/repair.sh list
bash /projects/sandbox/SuperBrain/scripts/repair.sh <repo|skills|packages|self>

# Reproducibility
bash /projects/sandbox/SuperBrain/scripts/bootstrap.sh --update-lock
bash /projects/sandbox/SuperBrain/scripts/bootstrap.sh --frozen

# AIBrain
bash /projects/sandbox/AIBrain/scripts/brain.sh status
bash /projects/sandbox/AIBrain/scripts/brain.sh recall "topic"

# Tooling
scrapetool fetch https://example.com
gsa doctor
```

## Adding a Repo

Edit `manifest.json` only. Never add per-repo install logic to the shell
scripts — CI rejects it. Every repo needs a non-empty `verify` array.

## 🔒 Security

SuperBrain and AIBrain are both **public** repositories. Never write
credentials, API keys, tokens or application passwords into either one. Use a
private vault and reference secrets by name.

## The Contract

1. Missing repos → clone them automatically
2. Missing packages → install them automatically
3. Missing skills → install them automatically
4. AIBrain unwired → wire it automatically
5. Never ask the user to run manual setup — but never claim success you have not
   verified either. The sentinel and the exit code are the proof.
