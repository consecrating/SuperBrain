# ⚡ SuperBrain

**The ONLY repo you need to connect.** SuperBrain auto-installs and wires your entire workspace — all 7 repos, 62 skills, 2 Python packages, 2 CLIs, and persistent intelligence — in a single bootstrap.

> Connect `consecrating/SuperBrain` → start a session → everything is ready.

The bootstrap is **manifest-driven** (`manifest.json` is the single source of truth), **idempotent** (`--fast` skips re-work when nothing changed), **resilient** (clones retry with backoff), and **observable** (writes a run log + a structured state snapshot + an AIBrain journal entry) — with hardcoded fallbacks so the connect-and-go contract never breaks.

---

## What It Does

When SuperBrain is the only repo connected to a Kiro session:

1. **Detects** that other repos are missing
2. **Clones** all 7 repositories automatically (retry + backoff, in parallel)
3. **Installs** 62 Kiro skills (design + engineering + AI brain)
4. **Installs** Python packages (ScrapeToolAi, goaaiseo-seo-adapter)
5. **Wires** environment variables, CLIs, and steering files
6. **Activates** AIBrain persistent intelligence
7. **Verifies** everything works
8. **Self-heals** if anything breaks

All in ~30 seconds. No manual setup. No copy-pasting. No "install X first."

---

## How It Works

```
┌─────────────────────────────────────────────────────────────────────────┐
│  SESSION START — SuperBrain is the only connected repo                  │
│                                                                          │
│  .kiro/steering/superbrain.md (always-on) instructs Kiro:               │
│  "Run bootstrap.sh immediately"                                          │
│                                                                          │
│  .kiro/hooks/auto-bootstrap.json (SessionStart trigger):                │
│  Automatically runs bootstrap.sh before any user interaction             │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  bootstrap.sh executes:                                                  │
│                                                                          │
│  1. git clone consecrating/All-Skills         → 44 design skills         │
│  2. git clone consecrating/Claude-Power       → 16 engineering skills    │
│  3. git clone consecrating/AIBrain            → persistent intelligence  │
│  4. git clone consecrating/ScrapeToolAi       → scraping framework       │
│  5. git clone consecrating/goaaiseo-seo-adapter → SEO adapter            │
│  6. git clone consecrating/goaaiseo           → SEO OS blueprint         │
│  7. git clone consecrating/Sanctify-Hivemind  → multi-agent framework    │
│                                                                          │
│  (repo list, install order & optional ref pins all come from            │
│   manifest.json — edit the manifest, not the scripts)                    │
│                                                                          │
│  7. Install All-Skills (45 skills → /projects/.kiro/skills/)             │
│  8. Install Claude-Power (16 skills + steering + scripts)                │
│  9. Install AIBrain (brain skill + steering)                             │
│  10. pip install -e ScrapeToolAi (scrapetool CLI)                        │
│  11. pip install -e goaaiseo-seo-adapter (gsa CLI)                       │
│  12. Set environment variables + write .env                              │
│  13. Verify everything → report status                                   │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Quick Start

### Option A: Just connect this repo (recommended)

In Kiro Web, connect `consecrating/SuperBrain` to your session.
The steering file instructs Kiro to run bootstrap automatically.

### Option B: Manual trigger

```bash
bash /projects/sandbox/SuperBrain/scripts/bootstrap.sh
```

### Option C: From scratch (new machine)

```bash
git clone https://github.com/consecrating/SuperBrain.git
cd SuperBrain
bash scripts/bootstrap.sh
```

---

## What You Get After Bootstrap

### 62 Kiro Skills

| Source | Count | Focus |
|--------|-------|-------|
| All-Skills | 44 | Design, UX, WordPress, SEO, motion |
| Claude-Power | 16 | Engineering, debugging, security, refactoring |
| AIBrain | 1 | Persistent intelligence layer |
| SuperBrain | 1 | Workspace orchestration |

### Python Packages

| Package | CLI | Purpose |
|---------|-----|---------|
| scrapetoolai 1.0 | `scrapetool` | Stealth web scraping + AI extraction |
| goaaiseo-seo-adapter 0.1 | `gsa` | SEO report normalization |
| Sanctify-Hivemind | — | Multi-agent orchestration framework (importable as `hivemind`) |

### Persistent Intelligence (AIBrain)

- **Memory** — never forgets decisions, corrections, or context
- **Stack registry** — never suggests outdated packages
- **Pattern library** — uses YOUR proven code patterns
- **Self-healing** — learns from mistakes, never repeats them

### Environment Variables

All set automatically. Available via `source /projects/sandbox/SuperBrain/.env`

---

## Scripts

| Script | Purpose | When to Use |
|--------|---------|-------------|
| `scripts/bootstrap.sh` | Full install + verify | Session start, fresh workspace |
| `scripts/verify.sh` | Health check (no changes) | "Is everything working?" |
| `scripts/repair.sh` | Fix broken components | Something stopped working |
| `scripts/workspace-setup.sh` | Load env vars only | Prefix commands with env |
| `scripts/lib.sh` | Shared library (manifest parse, python autodetect, resilient clone, logging) | Sourced by the others |
| `scripts/selftest.sh` | Fast offline test harness | CI + before committing script changes |

### bootstrap.sh flags

```bash
bash scripts/bootstrap.sh            # full bootstrap (idempotent, safe to re-run)
bash scripts/bootstrap.sh --fast     # skip if manifest unchanged AND workspace healthy
bash scripts/bootstrap.sh --force    # force a full rebuild
bash scripts/bootstrap.sh --help     # usage
```

The SessionStart hook uses `--fast`, so a healthy session with an unchanged
`manifest.json` re-bootstraps in ~0.1s instead of re-running the full install.

### How the manifest drives everything

`manifest.json` is the single source of truth for the repo list, install order,
and optional per-repo pinning. To add or pin a repo, edit the manifest — no
script changes needed:

```jsonc
{
  "repositories": [
    { "name": "MyRepo", "github": "owner/MyRepo", "ref": "v1.2.0" }  // ref is optional
  ]
}
```

`bootstrap.sh`, `verify.sh`, and `repair.sh` all read the repo list from the
manifest via `lib.sh`. If the manifest is missing or malformed, they fall back
to a hardcoded list of the 7 known repos — the bootstrap never breaks.

### Observability

Every full run writes:

| Artifact | Contents |
|----------|----------|
| `bootstrap.log` | Full text log of the latest run |
| `.superbrain-state.json` | Structured snapshot: repos present, skills, packages, CLIs, python version, duration, healthy/errors |
| AIBrain journal entry | One-line record appended to `AIBrain/memory/journal.md` |

(All are gitignored.)

### Python runtime

The interpreter is **autodetected**, not hardcoded: it prefers `manifest.python`,
then a pinned pyenv 3.11.15, then the newest available pyenv 3.11.x / 3.1x, then
whatever `python3` is on `PATH`.

### Testing & CI

```bash
bash scripts/selftest.sh   # 20 offline checks: syntax, manifest, lib.sh, fallbacks, clone_one, CLI
```

GitHub Actions (`.github/workflows/selftest.yml`) runs the selftest and a
ShellCheck pass on every push and PR.

---

## Self-Healing

SuperBrain can repair itself:

```bash
# Everything broke? Full re-bootstrap (idempotent)
bash scripts/bootstrap.sh --force

# Just check health
bash scripts/verify.sh

# Fix specific thing
bash scripts/repair.sh All-Skills          # re-install skills
bash scripts/repair.sh Sanctify-Hivemind   # re-clone + re-install a repo
bash scripts/repair.sh packages            # re-install pip packages
bash scripts/repair.sh aibrain             # re-wire intelligence
bash scripts/repair.sh auto                # detect and fix all issues
```

---

## File Structure

```
SuperBrain/
├── README.md                           # This file
├── manifest.json                       # Declarative repo + install spec (source of truth)
├── .env                                # Generated env vars (after bootstrap, gitignored)
├── .bootstrapped                       # Idempotency state, gates --fast (gitignored)
├── .superbrain-state.json              # Structured run snapshot (gitignored)
├── bootstrap.log                       # Latest run log (gitignored)
├── .gitignore
├── LICENSE
├── scripts/
│   ├── lib.sh                         # Shared library (manifest, python, clone, logging)
│   ├── bootstrap.sh                   # THE master installer (--fast / --force / --help)
│   ├── verify.sh                      # Health check
│   ├── repair.sh                      # Fix broken things
│   ├── selftest.sh                    # Offline test harness (CI)
│   └── workspace-setup.sh            # Env vars only (source-able)
├── .github/
│   └── workflows/
│       └── selftest.yml               # CI: selftest + shellcheck on push/PR
└── .kiro/
    ├── steering/
    │   └── superbrain.md              # Always-on: "run bootstrap at session start"
    ├── skills/
    │   └── superbrain/
    │       └── SKILL.md               # Orchestration skill
    └── hooks/
        └── auto-bootstrap.json        # SessionStart hook (runs bootstrap.sh --fast)
```

---

## The Promise

**One repo. One connection. Full power.**

No more:
- "Install X first"
- "Set up Y manually"  
- "Run these 15 commands"
- "I forgot what was set up last time"

Connect SuperBrain → start working.

---

## Repos Managed

| Repo | GitHub | What |
|------|--------|------|
| All-Skills | consecrating/All-Skills | 44 Kiro skills (design/UX/WP) |
| Claude-Power | consecrating/Claude-Power | 16 Kiro skills (engineering) |
| AIBrain | consecrating/AIBrain | Persistent intelligence layer |
| ScrapeToolAi | consecrating/ScrapeToolAi | Web scraping framework |
| goaaiseo-seo-adapter | consecrating/goaaiseo-seo-adapter | SEO adapter (gsa) |
| goaaiseo | consecrating/goaaiseo | Autonomous SEO OS blueprint |
| Sanctify-Hivemind | consecrating/Sanctify-Hivemind | Multi-agent orchestration framework |

---

## License

MIT
