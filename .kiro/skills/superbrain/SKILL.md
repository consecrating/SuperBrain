---
name: superbrain
description: "Master workspace orchestrator — bootstraps all repos (All-Skills, Claude-Power, AIBrain, ScrapeToolAi, goaaiseo-seo-adapter, goaaiseo) from a declarative manifest. Activate when starting a session, when repos are missing, when packages fail to import, when a CLI is not found, or when the workspace needs repair. Provides bootstrap, verify and repair commands."
metadata:
  version: "2.0"
  author: consecrating
---

# SuperBrain — Workspace Orchestrator

`manifest.json` is the single source of truth. The scripts hold no per-repo
knowledge, so trust the manifest over anything hardcoded.

## Bootstrap

```bash
bash /projects/sandbox/SuperBrain/scripts/bootstrap.sh
```

Idempotent. If `.bootstrapped` matches the current manifest version it skips
installing and verifies instead — this returns in well under a second, so there
is no reason to avoid running it.

| Flag | Effect |
|---|---|
| `--force` | Reinstall regardless of the sentinel |
| `--frozen` | Check out the commits pinned in `superbrain.lock` |
| `--update-lock` | Record current HEADs into `superbrain.lock` |
| `--no-prune` | Keep skills no repo declares any more |
| `--quiet` | Warnings, errors and summary only |

**Exit code is the error count, and every failure prints its captured output.**
If a step fails, the reason is already on screen — read it rather than guessing.

## Diagnose and repair

```bash
bash /projects/sandbox/SuperBrain/scripts/verify.sh        # changes nothing
bash /projects/sandbox/SuperBrain/scripts/repair.sh list   # show targets
bash /projects/sandbox/SuperBrain/scripts/repair.sh AIBrain
bash /projects/sandbox/SuperBrain/scripts/repair.sh skills
bash /projects/sandbox/SuperBrain/scripts/repair.sh packages
```

`repair.sh` will **not** pull over a dirty working tree, and reports that as a
warning rather than pretending it updated. It will never `rm -rf` a directory
that is not a git repo.

## What is installed

| Repo | Provides |
|---|---|
| All-Skills | 45 Kiro skills (design, UX, WordPress, motion, SEO) |
| Claude-Power | 16 Kiro skills (engineering, debugging, security, PRs) |
| AIBrain | Persistent intelligence (memory, patterns, stack, decisions) |
| ScrapeToolAi | `scrapetool` CLI + Python scraping framework |
| goaaiseo-seo-adapter | `gsa` CLI + SEO normalization library |
| goaaiseo | GOAAISEO blueprint (architecture reference) |

62 skills total, not 63 — `token-efficiency` ships in both All-Skills and
Claude-Power. Bootstrap reports the collision and names the winner.

## CLIs and libraries

```bash
source /projects/sandbox/SuperBrain/.env

scrapetool fetch|extract|crawl|import|search|mcp-server
gsa ingest|analyze|doctor|serve
bash /projects/sandbox/AIBrain/scripts/brain.sh status|recall|decide|correct
```

```python
from scrapetoolai.fetchers.escalation import auto_fetch
from gsa.models import GraphNode, IssueRecord, ActionCandidate, IngestResult
from gsa.normalize import ingest_seo_report
```

## Adding a repo

Edit `manifest.json` only — never add install logic to the shell scripts. CI
fails the build if per-repo logic leaks into `scripts/`.

## 🔒 Security

SuperBrain and AIBrain are both **public** repositories. Never write
credentials, tokens or app passwords into either. Use a private vault and
reference secrets by name only.

## When to activate

- Session start (bootstrap check)
- `ImportError` on `scrapetoolai` or `gsa`
- `command not found` for `scrapetool` or `gsa`
- A skill is not recognised
- Workspace repair, or understanding how the repos connect
