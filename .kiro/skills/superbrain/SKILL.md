---
name: superbrain
description: "Master workspace orchestrator — auto-bootstraps all repos (All-Skills, Claude-Power, AIBrain, ScrapeToolAi, goaaiseo-seo-adapter, goaaiseo) on session start. Activate when starting a session, when repos are missing, when packages fail to import, or when the workspace needs repair. Provides bootstrap, verify, and repair commands."
metadata:
  version: "1.0"
  author: consecrating
---

# SuperBrain — Workspace Orchestrator

You are running in a SuperBrain-powered workspace. This means ALL repos should
be present, installed, and connected. If they're not, fix it immediately.

## Auto-Bootstrap Protocol

At the START of every session:

```bash
export PATH="/root/.pyenv/versions/3.11.15/bin:$PATH"
bash /projects/sandbox/SuperBrain/scripts/bootstrap.sh
```

This is idempotent — safe to run even if everything is already installed.

## What Gets Installed

| Repo | What It Provides |
|------|-----------------|
| All-Skills | 44 Kiro skills (design, UX, WordPress, motion, SEO) |
| Claude-Power | 16 Kiro skills (engineering, debugging, security, PRs) |
| AIBrain | Persistent intelligence (memory, patterns, stack, decisions) |
| ScrapeToolAi | `scrapetool` CLI + Python scraping framework |
| goaaiseo-seo-adapter | `gsa` CLI + SEO normalization library |
| goaaiseo | GOAAISEO blueprint (architecture reference) |

## Self-Healing

If anything is broken mid-session:

```bash
# Quick fix — re-run bootstrap
bash /projects/sandbox/SuperBrain/scripts/bootstrap.sh

# Just verify without reinstalling
bash /projects/sandbox/SuperBrain/scripts/verify.sh

# Repair a specific repo
bash /projects/sandbox/SuperBrain/scripts/repair.sh <repo-name>
```

## Available After Bootstrap

### CLIs
- `scrapetool fetch|extract|crawl|import|search|mcp-server`
- `gsa ingest|analyze|doctor|serve`
- `bash /projects/sandbox/AIBrain/scripts/brain.sh status|recall|decide|correct`

### Python Libraries
```python
from scrapetoolai.fetchers.http_fetcher import http_fetch, SimplePage
from scrapetoolai.fetchers.escalation import auto_fetch
from scrapetoolai.organizer.search import search_collection

from gsa.models import GraphNode, IssueRecord, ActionCandidate, IngestResult
from gsa.normalize import ingest_seo_report
from gsa.sinks import get_sink
from gsa.config import Settings
```

### Environment Variables
All set automatically. Source them with:
```bash
source /projects/sandbox/SuperBrain/.env
```

## When to Activate This Skill

- ✅ Session start (bootstrap check)
- ✅ Import errors (package not installed)
- ✅ Command not found (CLI missing)
- ✅ Skill not recognized (not installed)
- ✅ "Workspace is broken" / repair needed
- ✅ Need to understand how repos connect
