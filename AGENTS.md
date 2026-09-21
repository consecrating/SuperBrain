# SuperBrain — Agent Instructions

Master orchestrator for the `consecrating` workspace. Read by Codex, and by any
agent following the `AGENTS.md` convention. Kiro reads `.kiro/steering/` instead.

## Install Everything

When the user says **"Install Every Skills"**, "install everything", or "set up
the workspace", run:

```bash
bash scripts/install-everything.sh
```

That single command clones all 7 repos, installs **96 skills into every AI agent
on the machine** (Kiro, Codex, Claude, Cursor, Gemini, Roo, and any other agent
directory it finds), installs the Python packages, and wires the CLIs.

It is idempotent — safe to re-run at any time.

```bash
bash scripts/install-everything.sh --list          # show the plan, change nothing
bash scripts/install-everything.sh --agent codex   # one agent only
bash scripts/install-everything.sh --skip-python   # skills only, no pip
```

### Which installer should I use?

| Script | Scope |
|---|---|
| `scripts/install-everything.sh` | **Portable — any agent, any machine.** Use this by default. |
| `scripts/bootstrap.sh` | Kiro Web only; installs into `/projects/.kiro/skills`. |

On Codex, or anywhere `/projects` does not exist, **use
`install-everything.sh`** — `bootstrap.sh` hardcodes Kiro Web paths and will not
wire Codex.

## What You Get

| Repo | Provides |
|---|---|
| All-Skills | 45 skills — design, UX, WordPress, motion, SEO |
| Claude-Power | 16 skills — engineering, debugging, security, PRs |
| AIBrain | Persistent memory, decisions, patterns, stack registry |
| **FirecrawlPower** | **6 skills + `fcless` — web search & research, no API key** |
| ScrapeToolAi | `scrapetool` — stealth scraping, anti-bot, spider |
| goaaiseo-seo-adapter | `gsa` — SEO graph normalization |
| goaaiseo | Architecture blueprint |

## Commands After Install

```bash
fcless search "<query>"        # web discovery      (no API key)
fcless fetch <url>             # read a page        (auto-escalates)
fcless papers "<query>"        # ~43M paper abstracts
fcless gh "<query>"            # GitHub issue/PR history
scrapetool fetch <url>         # stealth fetch      (anti-bot)
gsa ingest <report>            # SEO normalization
bash AIBrain/scripts/brain.sh recall "<topic>"
```

## Web Engine Routing

Two engines, opposite strengths — picking wrong wastes time:

- **`fcless`** — the only thing that can *search*; clean markdown; rate-limited;
  loses to Cloudflare.
- **`scrapetool`** — cannot search; beats anti-bot defences; crawls whole sites;
  unthrottled.

> Firecrawl to find and read easy pages. ScrapeToolAi to fight for defended
> pages and to traverse sites.

Use `fcless fetch` when unsure — it escalates automatically. Full detail in the
`fc-hybrid-router` skill.

## AIBrain Protocol

Before suggesting a package, check `AIBrain/brain/stack/registry.md` and
`banned.md`. Before starting work, read `AIBrain/memory/active-task.md` and
`corrections.md`. Record decisions with `brain.sh decide`.

## Health Checks

```bash
bash scripts/verify.sh                      # workspace health
bash FirecrawlPower/scripts/verify.sh       # keyless layer health
fcless doctor                               # endpoint reachability
```
