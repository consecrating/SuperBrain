---
name: superbrain
description: "Master workspace orchestrator — bootstraps, exactly verifies, and repairs All-Skills/Claude-Power ownership plus AIBrain, ScrapeToolAi, gsa, and GOAAISEO wiring. Activate at session start or when connected-workspace health drifts."
metadata:
  version: "1.1"
  author: consecrating
---

# SuperBrain — Workspace Orchestrator

Use SuperBrain to install and verify the connected workspace without relying on directory counts or copy order.

## Bootstrap and health

```bash
export PATH="/root/.pyenv/versions/3.11.15/bin:$PATH"
bash /projects/sandbox/SuperBrain/scripts/bootstrap.sh
bash /projects/sandbox/SuperBrain/scripts/verify.sh
```

Bootstrap is idempotent. Its `.bootstrapped` marker is atomically published only after final verification succeeds.

## Deterministic skills

| Source | Informational package count | Combined rule |
|---|---:|---|
| All-Skills | 45 | v2 receipt owns exactly 44 |
| Claude-Power | 16 | owns the one overlap, `token-efficiency` |
| Unique between packs | 60 | verified by identities, not directory totals |
| AIBrain / SuperBrain | +1 each when installed | separate workspace skills |

Run the shared helper directly when diagnosing ownership:

```bash
python3 /projects/sandbox/SuperBrain/scripts/skills_integration.py install
python3 /projects/sandbox/SuperBrain/scripts/skills_integration.py verify
```

The helper validates the public All-Skills bundle/catalog and source validator, uses public `install.sh` lifecycle commands, checks the exact receipt folder set and public check health, and proves complete Claude-Power source/destination tree equality. Foreign unrelated skill directories are permitted.

All-Skills standalone installation remains unchanged and includes all 45. Combined migration relinquishes All-Skills' `token-efficiency` receipt entry through its public uninstall selection before Claude-Power publication.

## Optional intelligence synchronization

If AIBrain is available, successful combined installation best-effort ingests the current All-Skills catalog and compact integration report with explicit kinds/scopes. Missing or unhealthy AIBrain synchronization is a warning, never a connected-skill health failure.

## Repair

```bash
bash /projects/sandbox/SuperBrain/scripts/repair.sh skills
bash /projects/sandbox/SuperBrain/scripts/repair.sh packages
bash /projects/sandbox/SuperBrain/scripts/repair.sh aibrain
bash /projects/sandbox/SuperBrain/scripts/repair.sh auto
```

## Available services

- `scrapetool fetch|extract|crawl|import|search|mcp-server`
- `gsa ingest|analyze|doctor|serve`
- `bash /projects/sandbox/AIBrain/scripts/brain.sh status|recall|decide|correct`
- GOAAISEO blueprint under `/projects/sandbox/goaaiseo/docs/blueprint`

`/projects/sandbox/connect-all.sh` is a legacy bypass and is not health evidence.
