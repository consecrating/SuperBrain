# ⚡ SuperBrain

**The only repo you need to connect.** SuperBrain clones and wires your entire workspace — 6 repos, 62 skills, 2 Python packages, 2 CLIs, and persistent intelligence — from one declarative manifest.

> Connect `consecrating/SuperBrain` → start a session → everything is ready.

---

## How it works

`manifest.json` is the **single source of truth**. It declares every repo, its install steps, and its verification checks. The shell scripts contain no per-repo knowledge — add a repo to the manifest and it is picked up automatically. CI enforces this.

```
.kiro/hooks/auto-bootstrap.json   (SessionStart)
    └─> scripts/session-start.sh  (preserves exit status)
            └─> scripts/bootstrap.sh
                    ├─ reads manifest.json via scripts/lib/manifest.py
                    ├─ clones/pins each repo        (superbrain.lock)
                    ├─ detects skill-name collisions
                    ├─ runs each repo's declared install steps
                    ├─ prunes skills no repo declares any more
                    ├─ writes .env from manifest environment
                    ├─ runs each repo's declared verify steps
                    └─ writes .bootstrapped only on success
```

---

## Quick start

```bash
# Full install (safe to re-run — idempotent)
bash scripts/bootstrap.sh

# Health check, changes nothing
bash scripts/verify.sh

# Fix something specific
bash scripts/repair.sh list
bash scripts/repair.sh AIBrain
```

### bootstrap.sh flags

| Flag | Effect |
|---|---|
| *(none)* | Install. Skips instantly if `.bootstrapped` matches the manifest version, verifying instead. |
| `--force` | Reinstall even if already bootstrapped. |
| `--frozen` | Check out the exact commits recorded in `superbrain.lock`. |
| `--update-lock` | Record current HEADs into `superbrain.lock`. |
| `--no-prune` | Keep skills that no repo declares any more. |
| `--quiet` | Only warnings, errors and the summary. |

Exit code is the number of errors. **Failures print their captured output** — nothing is sent to `/dev/null`.

---

## What you get

### 62 Kiro skills

| Source | Count | Focus |
|---|---|---|
| All-Skills | 45 | Design, UX, WordPress, SEO, motion |
| Claude-Power | 16 | Engineering, debugging, security, refactoring |
| AIBrain | 1 | Persistent intelligence layer |
| SuperBrain | 1 | Workspace orchestration |

62 rather than 63 because `token-efficiency` ships in **both** All-Skills and Claude-Power. Bootstrap now reports this collision and names the winner instead of silently overwriting.

### 2 Python packages

| Package | CLI | Purpose |
|---|---|---|
| scrapetoolai | `scrapetool` | Stealth web scraping + AI extraction |
| goaaiseo-seo-adapter | `gsa` | SEO report normalization |

### Environment

```bash
source /projects/sandbox/SuperBrain/.env
```

---

## Reproducibility

`superbrain.lock` pins every repo to a commit:

```bash
bash scripts/bootstrap.sh --update-lock   # record current state
bash scripts/bootstrap.sh --frozen        # reproduce it exactly
bash scripts/verify.sh                    # reports DRIFTED if HEAD != lock
```

`--frozen` refuses to check out over a dirty working tree.

---

## Repos managed

| Repo | What |
|---|---|
| [All-Skills](https://github.com/consecrating/All-Skills) | 45 Kiro skills (design/UX/WP) |
| [Claude-Power](https://github.com/consecrating/Claude-Power) | 16 Kiro skills (engineering) |
| [AIBrain](https://github.com/consecrating/AIBrain) | Persistent intelligence layer |
| [ScrapeToolAi](https://github.com/consecrating/ScrapeToolAi) | Web scraping framework |
| [goaaiseo-seo-adapter](https://github.com/consecrating/goaaiseo-seo-adapter) | SEO adapter (`gsa`) |
| [goaaiseo](https://github.com/consecrating/goaaiseo) | Autonomous SEO OS blueprint |

---

## Adding a repo

Edit `manifest.json` only:

```json
{
  "name": "My-Repo",
  "github": "consecrating/My-Repo",
  "branch": null,
  "purpose": "What it does",
  "priority": 7,
  "skills_dir": ".kiro/skills",
  "install": ["pip install -e . --quiet"],
  "verify": ["python3 -c 'import my_repo'"]
}
```

Placeholders `${WORKSPACE}`, `${KIRO_DIR}`, `${KIRO_SKILLS}`, `${REPO}` are expanded before execution. `install` steps run with the repo as working directory. `verify` must be non-empty — CI rejects a repo without checks.

---

## Development

```bash
bash tests/smoke.sh    # 30 tests, no network, no workspace mutation
shellcheck --severity=warning scripts/*.sh scripts/lib/*.sh tests/*.sh
```

CI runs shellcheck, the smoke suite, manifest schema validation, and a check that no per-repo install logic has leaked back into `scripts/`.

---

## Security

Credentials never belong in this repo or in AIBrain — **both are public**. Use a private vault. AIBrain ships `scripts/scan-secrets.sh` as a pre-commit hook.

---

## License

MIT
