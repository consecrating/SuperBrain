#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# SuperBrain — install-everything.sh
#
# THE CROSS-AGENT INSTALLER. Say "Install Every Skills" and this runs.
#
# Difference from bootstrap.sh:
#   bootstrap.sh          Kiro Web only — installs into /projects/.kiro/skills
#   install-everything.sh portable — installs into EVERY agent found on the
#                         machine (Kiro, Codex, Claude, Cursor, Gemini, Roo, …)
#                         and works when /projects does not exist
#
# Usage:
#   bash scripts/install-everything.sh              # everything, every agent
#   bash scripts/install-everything.sh --list       # show plan, change nothing
#   bash scripts/install-everything.sh --agent codex
#   bash scripts/install-everything.sh --skip-python
#
# Safe to re-run (idempotent).
# ═══════════════════════════════════════════════════════════════════════════════
set -uo pipefail          # deliberately NOT -e: one bad repo must not abort all

# ─── Config ──────────────────────────────────────────────────────────────────
HUB="$HOME/.agents/skills"                 # canonical agent-neutral skill store
BIN_DIR="${FP_BIN_DIR:-$HOME/.local/bin}"

# Workspace: prefer the Kiro Web location, fall back to a home dir elsewhere
if [ -d /projects/sandbox ] && [ -w /projects/sandbox ]; then
  WORKSPACE="/projects/sandbox"
else
  WORKSPACE="${SUPERBRAIN_WORKSPACE:-$HOME/superbrain-workspace}"
fi

# repo-name → github-slug
REPOS=(
  "All-Skills:consecrating/All-Skills"
  "Claude-Power:consecrating/Claude-Power"
  "AIBrain:consecrating/AIBrain"
  "ScrapeToolAi:consecrating/ScrapeToolAi"
  "goaaiseo-seo-adapter:consecrating/goaaiseo-seo-adapter"
  "goaaiseo:consecrating/goaaiseo"
  "FirecrawlPower:consecrating/FirecrawlPower"
)

# Agents always wired, plus any other agent dir already present
ALWAYS=(.kiro .codex .claude)
OPTIONAL=(.continue .copilot .cursor .factory .gemini .hermes .openclaw .openhands
          .roo .qwen .trae .windsurf .augment .zed .goose)

ONLY_AGENT=""; LIST_ONLY=0; SKIP_PYTHON=0
while [ $# -gt 0 ]; do
  case "$1" in
    --agent) ONLY_AGENT="${2:-}"; shift 2 ;;
    --list)  LIST_ONLY=1; shift ;;
    --skip-python) SKIP_PYTHON=1; shift ;;
    -h|--help) sed -n '3,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) shift ;;
  esac
done

# Python: use pyenv 3.11 when available
for p in /root/.pyenv/versions/3.11.15/bin "$HOME/.pyenv/versions/3.11.15/bin"; do
  [ -d "$p" ] && export PATH="$p:$PATH" && break
done

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  🧠 SuperBrain — INSTALL EVERY SKILL (all agents)               ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""
echo "  workspace : $WORKSPACE"
echo "  hub       : $HUB"
echo "  python    : $(python3 --version 2>&1)"
echo ""

# ─── Resolve agent targets ───────────────────────────────────────────────────
targets=()
if [ -n "$ONLY_AGENT" ]; then
  a="${ONLY_AGENT#.}"; a="${a%-cli}"
  targets+=("$HOME/.${a}/skills")
else
  for d in "${ALWAYS[@]}"; do targets+=("$HOME/$d/skills"); done
  for d in "${OPTIONAL[@]}"; do [ -d "$HOME/$d" ] && targets+=("$HOME/$d/skills"); done
fi
# Workspace-level Kiro dir, when this is a Kiro workspace
WS_SKILLS=""
if [ -d /projects/.kiro ] || [ -w /projects ] 2>/dev/null; then
  WS_SKILLS="${KIRO_SKILLS_DIR:-/projects/.kiro/skills}"
fi

if [ "$LIST_ONLY" = "1" ]; then
  echo "  Repos (${#REPOS[@]}):"
  for r in "${REPOS[@]}"; do echo "    • ${r%%:*}"; done
  echo ""
  echo "  Agent targets:"
  for t in "${targets[@]}"; do echo "    → ${t/#$HOME/~}"; done
  [ -n "$WS_SKILLS" ] && echo "    → $WS_SKILLS (workspace)"
  echo ""
  echo "  Nothing was changed (--list)."
  exit 0
fi

mkdir -p "$WORKSPACE" "$HUB"

# ─── 1. Clone ────────────────────────────────────────────────────────────────
echo "── 1/5 Cloning repositories ──"
MISSING=()
for entry in "${REPOS[@]}"; do
  name="${entry%%:*}"; slug="${entry#*:}"
  path="$WORKSPACE/$name"
  if [ -d "$path/.git" ]; then
    echo "  ✓ $name (present)"
  elif git clone --quiet "https://github.com/$slug.git" "$path" 2>/dev/null; then
    echo "  ✓ $name (cloned)"
  else
    # Tolerated on purpose — a repo that does not exist yet must not abort the run
    echo "  ⚠ $name — clone failed (skipping)"
    MISSING+=("$name")
  fi
done
echo ""

# ─── 2. Collect skills into the hub ──────────────────────────────────────────
echo "── 2/5 Collecting skills into hub ──"
declare -A ORIGIN=()
COLLISIONS=()
collect() {
  local repo="$1" dir="$2"
  [ -d "$dir" ] || return 0
  local n=0
  for s in "$dir"/*/; do
    [ -d "$s" ] || continue
    local nm; nm=$(basename "$s")
    [ -f "$s/SKILL.md" ] || continue
    if [ -n "${ORIGIN[$nm]:-}" ] && [ "${ORIGIN[$nm]}" != "$repo" ]; then
      COLLISIONS+=("$nm: ${ORIGIN[$nm]} → $repo")
    fi
    rm -rf "$HUB/$nm"
    cp -r "$s" "$HUB/$nm" 2>/dev/null && { ORIGIN[$nm]="$repo"; n=$((n+1)); }
  done
  printf "  %-22s %d skills\n" "$repo" "$n"
}

collect "All-Skills"      "$WORKSPACE/All-Skills/.kiro/skills"
collect "Claude-Power"    "$WORKSPACE/Claude-Power/.kiro/skills"
collect "AIBrain"         "$WORKSPACE/AIBrain/.kiro/skills"
collect "FirecrawlPower"  "$WORKSPACE/FirecrawlPower/.kiro/skills"
collect "SuperBrain"      "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.kiro/skills"

TOTAL=$(find "$HUB" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
echo "  ─────────────────────────────────"
printf "  %-22s %d skills\n" "HUB TOTAL" "$TOTAL"
if [ "${#COLLISIONS[@]}" -gt 0 ]; then
  echo ""
  echo "  ⚠ name collisions (last one wins):"
  for c in "${COLLISIONS[@]}"; do echo "      $c"; done
fi
echo ""

# ─── 3. Fan out to every agent ───────────────────────────────────────────────
echo "── 3/5 Wiring all agents ──"
for t in "${targets[@]}"; do
  mkdir -p "$t" 2>/dev/null || { echo "  ⚠ cannot create ${t/#$HOME/~}"; continue; }
  n=0
  for s in "$HUB"/*/; do
    [ -d "$s" ] || continue
    nm=$(basename "$s")
    rm -rf "$t/$nm"
    ln -s "${s%/}" "$t/$nm" 2>/dev/null || cp -r "$s" "$t/$nm" 2>/dev/null
    [ -e "$t/$nm" ] && n=$((n+1))
  done
  printf "  ✓ %-26s %d skills\n" "${t/#$HOME/~}" "$n"
done

if [ -n "$WS_SKILLS" ]; then
  mkdir -p "$WS_SKILLS" 2>/dev/null
  n=0
  for s in "$HUB"/*/; do
    [ -d "$s" ] || continue
    nm=$(basename "$s")
    rm -rf "$WS_SKILLS/$nm"
    cp -r "$s" "$WS_SKILLS/$nm" 2>/dev/null && n=$((n+1))
  done
  printf "  ✓ %-26s %d skills\n" "$WS_SKILLS" "$n"
fi

# Steering files (Kiro-specific, additive)
if [ -d /projects/.kiro ]; then
  mkdir -p /projects/.kiro/steering /projects/.kiro/scripts
  for f in "$WORKSPACE/Claude-Power/.kiro/steering"/* "$WORKSPACE/AIBrain/.kiro/steering"/*; do
    [ -f "$f" ] && cp "$f" /projects/.kiro/steering/ 2>/dev/null
  done
  cp -r "$WORKSPACE/Claude-Power/.kiro/scripts/"* /projects/.kiro/scripts/ 2>/dev/null
  echo "  ✓ steering + scripts installed"
fi
echo ""

# ─── 4. Python packages + CLIs ───────────────────────────────────────────────
if [ "$SKIP_PYTHON" = "1" ]; then
  echo "── 4/5 Python packages — skipped (--skip-python) ──"
else
  echo "── 4/5 Python packages ──"
  if python3 -c "import scrapetoolai" 2>/dev/null; then
    echo "  ✓ scrapetoolai (already installed)"
  elif [ -d "$WORKSPACE/ScrapeToolAi" ]; then
    pip install -e "$WORKSPACE/ScrapeToolAi" --quiet 2>/dev/null \
      && echo "  ✓ scrapetoolai installed" || echo "  ⚠ scrapetoolai install failed"
  fi
  if python3 -c "from gsa import models" 2>/dev/null; then
    echo "  ✓ gsa (already installed)"
  elif [ -d "$WORKSPACE/goaaiseo-seo-adapter" ]; then
    pip install -e "$WORKSPACE/goaaiseo-seo-adapter" --quiet 2>/dev/null \
      && echo "  ✓ gsa installed" || echo "  ⚠ gsa install failed"
  fi
fi

# fcless CLI (keyless Firecrawl — no API key)
if [ -f "$WORKSPACE/FirecrawlPower/bin/fcless" ]; then
  mkdir -p "$BIN_DIR"
  install -m 0755 "$WORKSPACE/FirecrawlPower/bin/fcless" "$BIN_DIR/fcless" 2>/dev/null \
    || { cp "$WORKSPACE/FirecrawlPower/bin/fcless" "$BIN_DIR/fcless"; chmod +x "$BIN_DIR/fcless"; }
  echo "  ✓ fcless → $BIN_DIR/fcless"
  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) echo "  ⚠ add to your profile: export PATH=\"$BIN_DIR:\$PATH\"" ;;
  esac
fi
echo ""

# ─── 5. Environment ──────────────────────────────────────────────────────────
echo "── 5/5 Environment ──"
SB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cat > "$SB_DIR/.env" << EOF
export PATH="$BIN_DIR:\$PATH"
export GOAAISEO_ROOT="$WORKSPACE/goaaiseo"
export GOAAISEO_BLUEPRINT="$WORKSPACE/goaaiseo/docs/blueprint"
export GSA_SINK="jsonfile"
export GSA_SINK_PATH="$WORKSPACE/goaaiseo-seo-adapter/out/site.graph.json"
export GSA_MIN_CONFIDENCE="0.7"
export SCRAPETOOL_OUTPUT="$WORKSPACE/ScrapeToolAi/output"
export SCRAPETOOL_IMPORTS="$WORKSPACE/ScrapeToolAi/imports"
export AIBRAIN_ROOT="$WORKSPACE/AIBrain"
export AGENT_SKILLS_HUB="$HUB"
EOF
[ -n "$WS_SKILLS" ] && echo "export KIRO_SKILLS_DIR=\"$WS_SKILLS\"" >> "$SB_DIR/.env"
mkdir -p "$WORKSPACE/goaaiseo-seo-adapter/out" \
         "$WORKSPACE/ScrapeToolAi/output" "$WORKSPACE/ScrapeToolAi/imports" 2>/dev/null
find "$HUB" -name '*.sh' -exec chmod +x {} \; 2>/dev/null
echo "  ✓ $SB_DIR/.env written"
echo ""

# ─── Summary ─────────────────────────────────────────────────────────────────
echo "╔══════════════════════════════════════════════════════════════════╗"
printf "║  ✅ INSTALLED — %-3s skills across %-2s agent(s)%*s║\n" \
       "$TOTAL" "${#targets[@]}" 15 ""
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║  fcless search \"<q>\"   web discovery      (no API key)          ║"
echo "║  fcless fetch <url>     read a page        (auto-escalates)     ║"
echo "║  scrapetool fetch <url> stealth fetch      (anti-bot)           ║"
echo "║  gsa ingest …           SEO normalization                        ║"
echo "║  brain.sh recall \"…\"    persistent memory                       ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
if [ "${#MISSING[@]}" -gt 0 ]; then
  echo ""
  echo "  ⚠ repos unavailable: ${MISSING[*]}"
  echo "    (create them on GitHub, then re-run — everything else installed fine)"
fi
echo ""
touch "$SB_DIR/.bootstrapped"
exit 0
