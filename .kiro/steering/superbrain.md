---
inclusion: always
description: "SuperBrain — auto-bootstrap orchestrator. On EVERY session start, ensures all repos are cloned, installed, and connected. This is the ONLY repo you need to connect."
---

# SuperBrain Protocol

SuperBrain is the master orchestrator. When this repo is connected to a Kiro session,
ALL other repos must be present and operational.

## At Session Start — AUTO-BOOTSTRAP

**IMMEDIATELY** on session start, before doing anything else:

1. Check if bootstrap has already run: `test -f /projects/sandbox/SuperBrain/.bootstrapped`
2. If NOT bootstrapped, run:
   ```bash
   bash /projects/sandbox/SuperBrain/scripts/bootstrap.sh
   ```
3. This automatically:
   - Clones All-Skills, Claude-Power, AIBrain, ScrapeToolAi, goaaiseo-seo-adapter, goaaiseo
   - Installs 61 Kiro skills (44 design + 16 engineering + superbrain)
   - Installs Python packages (scrapetoolai, gsa)
   - Activates AIBrain persistent intelligence
   - Sets all environment variables
   - Verifies everything works

## After Bootstrap — Full Power Available

Once bootstrapped, you have:
- **61 Kiro skills** active
- **AIBrain** persistent intelligence (memory, patterns, stack registry, banned list)
- **ScrapeToolAi** for stealth web scraping (`scrapetool` CLI)
- **gsa** for SEO analysis normalization (`gsa` CLI)
- **GOAAISEO** blueprint for architecture reference
- All environment variables set

## Environment (always prefix commands with)

```bash
export PATH="/root/.pyenv/versions/3.11.15/bin:$PATH"
```

Or source the generated env file:
```bash
source /projects/sandbox/SuperBrain/.env
```

## Quick Reference

```bash
# Re-bootstrap if anything breaks
bash /projects/sandbox/SuperBrain/scripts/bootstrap.sh

# Check status
bash /projects/sandbox/SuperBrain/scripts/verify.sh

# AIBrain commands
bash /projects/sandbox/AIBrain/scripts/brain.sh status
bash /projects/sandbox/AIBrain/scripts/brain.sh recall "topic"

# Scraping
scrapetool fetch https://example.com
scrapetool extract https://example.com --what "data"

# SEO adapter
gsa ingest report.json --site https://example.com --site-id tenant-1
gsa doctor
```

## The Contract

1. If repos are missing → clone them automatically
2. If packages aren't installed → install them automatically
3. If skills aren't active → install them automatically
4. If AIBrain isn't wired → wire it automatically
5. NEVER ask the user to manually set up anything — just do it
