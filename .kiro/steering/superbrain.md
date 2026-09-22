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
   - Clones All-Skills, Claude-Power, Claude-Opus5, Prompt-Sweeper, AIBrain,
     ScrapeToolAi, goaaiseo-seo-adapter, goaaiseo
   - Installs 63 Kiro skills (45 design + 16 engineering + aibrain + prompt-sweeper)
   - Installs Python packages (scrapetoolai, gsa, opus5lean, promptsweeper)
   - Installs MCP servers (opus5-lean, prompt-sweeper)
   - Activates AIBrain persistent intelligence
   - Sets all environment variables
   - Verifies everything works

## After Bootstrap — Full Power Available

Once bootstrapped, you have:
- **63 Kiro skills** active
- **AIBrain** persistent intelligence (memory, patterns, stack registry, banned list)
- **opus5-lean** for Opus 5 token accounting and cache planning (`opus5-lean` CLI)
- **prompt-sweeper** for measured prompt selection (`prompt-sweep` CLI)
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

# Token accounting for Opus 5 (offline, free)
opus5-lean count prompt.md
opus5-lean cache segments.json --rpd 5000

# Prompt selection (generate/recall are free; run is billed)
prompt-sweep generate "<task>"
prompt-sweep recall "<task>"
prompt-sweep run "<task>" --python-code --trials 3 --save
```

## Before hand-writing a prompt

Check whether a sweep already settled it:

```bash
prompt-sweep recall "<the task>"
```

A recorded strategy is evidence; overriding it by intuition discards the
measurement that produced it.

## The Contract

1. If repos are missing → clone them automatically
2. If packages aren't installed → install them automatically
3. If skills aren't active → install them automatically
4. If AIBrain isn't wired → wire it automatically
5. NEVER ask the user to manually set up anything — just do it
