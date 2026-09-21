---
inclusion: always
description: "Recognizes 'Install Every Skills' and routes to the cross-agent installer. Also defines web-engine routing between keyless Firecrawl (fcless) and ScrapeToolAi."
---

# Install Everything — Trigger Phrases

When the user says any of:

- "Install Every Skills" / "Install every skill"
- "install everything"
- "set up the workspace" / "install all skills"
- "wire up Codex" / "install for Codex"

Run **one command**:

```bash
bash /projects/sandbox/SuperBrain/scripts/install-everything.sh
```

Then report the skill count and the agents wired. Do not ask for confirmation
first — this is the explicit request, it is idempotent, and it is safe to re-run.

## Which installer

| Script | When |
|---|---|
| `scripts/install-everything.sh` | **Default.** Portable; wires every agent found, including Codex. Works without `/projects`. |
| `scripts/bootstrap.sh` | Kiro Web only. Installs to `/projects/.kiro/skills`; does **not** wire Codex. |

Prefer `install-everything.sh` unless you specifically need the legacy Kiro-only
path. It installs **96 skills** from 7 repos into a canonical hub at
`~/.agents/skills`, then symlinks that hub into every agent directory.

## Repo #7 — FirecrawlPower (keyless web layer)

Provides what nothing else in the stack could do: **web search**.

```bash
fcless search "<query>" -n 10   # discover URLs        (no API key)
fcless fetch <url>              # read, auto-escalating
fcless papers "<query>"         # ~43M paper abstracts
fcless gh "<query>"             # GitHub issue/PR history
fcless doctor                   # health check
```

No API key, no credits. The keyless tier is **throttled**, so batch queries and
lean on the 24h cache rather than retrying.

## Web Engine Routing (important)

Two engines with opposite strengths:

| Task | Engine |
|---|---|
| Find URLs / search the web | `fcless` — **only option** |
| Papers, GitHub issue history | `fcless` — only option |
| Read a public docs/blog page | `fcless fetch` |
| Cloudflare / WAF / bot-defended | `scrapetool` — Firecrawl loses here |
| Crawl or map a whole site | `scrapetool crawl` — keyless `/map` + `/crawl` are **401** |
| Hundreds of pages | `scrapetool` spider — `fcless` is throttled |

> **Firecrawl discovers. ScrapeToolAi fights.**

Use `fcless fetch` when unsure; it tries the fast path and escalates to
`scrapetool` automatically. Never retry a `401` — it means the endpoint is not on
the keyless tier, so switch engines instead. See the `fc-hybrid-router` skill.

## Verification

```bash
bash /projects/sandbox/SuperBrain/scripts/verify.sh
fcless doctor
```
