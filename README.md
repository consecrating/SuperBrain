# ⚡ SuperBrain

**The ONLY repo you need to connect.** SuperBrain auto-installs and wires your entire workspace — all 6 repos, 61 skills, 2 Python packages, 2 CLIs, and persistent intelligence — in a single bootstrap.

> Connect `consecrating/SuperBrain` → start a session → everything is ready.

---

## What It Does

When SuperBrain is the only repo connected to a Kiro session:

1. **Detects** that other repos are missing
2. **Clones** all 6 repositories automatically
3. **Installs** 61 Kiro skills (design + engineering + AI brain)
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

### 61 Kiro Skills

| Source | Count | Focus |
|--------|-------|-------|
| All-Skills | 44 | Design, UX, WordPress, SEO, motion |
| Claude-Power | 16 | Engineering, debugging, security, refactoring |
| AIBrain | 1 | Persistent intelligence layer |

### 2 Python Packages

| Package | CLI | Purpose |
|---------|-----|---------|
| scrapetoolai 1.0 | `scrapetool` | Stealth web scraping + AI extraction |
| goaaiseo-seo-adapter 0.1 | `gsa` | SEO report normalization |

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

---

## Self-Healing

SuperBrain can repair itself:

```bash
# Everything broke? Full re-bootstrap (idempotent)
bash scripts/bootstrap.sh

# Just check health
bash scripts/verify.sh

# Fix specific thing
bash scripts/repair.sh All-Skills    # re-install skills
bash scripts/repair.sh packages      # re-install pip packages
bash scripts/repair.sh aibrain       # re-wire intelligence
bash scripts/repair.sh auto          # detect and fix all issues
```

---

## File Structure

```
SuperBrain/
├── README.md                           # This file
├── manifest.json                       # Declarative repo + install spec
├── .env                                # Generated env vars (after bootstrap)
├── .gitignore
├── LICENSE
├── scripts/
│   ├── bootstrap.sh                   # THE master installer
│   ├── verify.sh                      # Health check
│   ├── repair.sh                      # Fix broken things
│   └── workspace-setup.sh            # Env vars only (source-able)
└── .kiro/
    ├── steering/
    │   └── superbrain.md              # Always-on: "run bootstrap at session start"
    ├── skills/
    │   └── superbrain/
    │       └── SKILL.md               # Orchestration skill
    └── hooks/
        └── auto-bootstrap.json        # SessionStart hook (auto-trigger)
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
| Claude-Power | consecrating/Claude-Power | 17 Kiro skills (engineering) + real Opus 5 MCP power |
| Claude-Opus5 | consecrating/Claude-Opus5 | Token-efficiency tools (opus5-lean CLI) |
| Prompt-Sweeper | consecrating/Prompt-Sweeper | Measured prompt selection (prompt-sweep CLI + MCP) |
| AIBrain | consecrating/AIBrain | Persistent intelligence layer |
| ScrapeToolAi | consecrating/ScrapeToolAi | Web scraping framework |
| goaaiseo-seo-adapter | consecrating/goaaiseo-seo-adapter | SEO adapter (gsa) |
| goaaiseo | consecrating/goaaiseo | Autonomous SEO OS blueprint |

---

## License

MIT
