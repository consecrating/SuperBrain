#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# SuperBrain — bootstrap.sh
#
# THE ONLY SCRIPT YOU NEED. Clones all repos, installs everything, wires
# environment, verifies integration. Run once per session.
#
# Usage:
#   bash /projects/sandbox/SuperBrain/scripts/bootstrap.sh
#
# What it does:
#   1. Sets up Python 3.11 runtime
#   2. Clones all 6 repos (skips if already present)
#   3. Installs All-Skills (44 design/UX/WP skills)
#   4. Installs Claude-Power (16 engineering skills + steering + scripts)
#   5. Installs AIBrain (intelligence layer + steering + skill)
#   6. Installs ScrapeToolAi (pip, CLI)
#   7. Installs goaaiseo-seo-adapter (pip, CLI)
#   8. Links goaaiseo blueprint
#   9. Sets all environment variables
#   10. Verifies everything works
#
# Safe to re-run (idempotent). Takes ~30s on a fresh session.
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

SUPERBRAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ─── Shared library (manifest parsing, python autodetect, logging) ───────────
# shellcheck source=lib.sh
source "$SUPERBRAIN_DIR/scripts/lib.sh"

WORKSPACE="$(resolve_workspace)"
KIRO_DIR="$(resolve_kiro)"

# ─── Python runtime (autodetected: manifest → pinned 3.11 → pyenv → system) ──
# NOTE: must mutate PATH in THIS shell, not a subshell — so detect, then export.
PYTHON_BIN="$(detect_python_bin)"
case ":$PATH:" in
    *":$PYTHON_BIN:"*) : ;;
    *) export PATH="$PYTHON_BIN:$PATH" ;;
esac

# ─── Argument parsing ────────────────────────────────────────────────────────
FAST=0
FORCE=0
for arg in "$@"; do
    case "$arg" in
        --fast)  FAST=1 ;;
        --force) FORCE=1 ;;
        -h|--help)
            cat <<'HELP'
SuperBrain bootstrap.sh — clone all repos, install skills+packages, wire env.

Usage:
  bootstrap.sh            Full bootstrap (idempotent; safe to re-run).
  bootstrap.sh --fast     Skip if manifest unchanged AND workspace already healthy.
                          (Used by the SessionStart hook to avoid re-work.)
  bootstrap.sh --force    Force a full bootstrap even if already bootstrapped.
  bootstrap.sh --help     Show this help.
HELP
            exit 0 ;;
        *) echo "  ⚠ Unknown argument: $arg (ignoring)" ;;
    esac
done

STATE_FILE="$SUPERBRAIN_DIR/.bootstrapped"
STATE_JSON="$SUPERBRAIN_DIR/.superbrain-state.json"
LOG_FILE="$SUPERBRAIN_DIR/bootstrap.log"
CURRENT_HASH="$(manifest_hash)"
START_TS="$(date +%s)"

# quick_health: lightweight check that the workspace is already wired.
# Returns 0 (healthy) only if every manifest repo is present and both Python
# packages import. Deliberately cheaper than verify.sh.
quick_health() {
    local r
    while read -r r; do
        [ -z "$r" ] && continue
        [ -d "$WORKSPACE/$r/.git" ] || return 1
    done < <(manifest_repo_names)
    python3 -c "import scrapetoolai" 2>/dev/null || return 1
    python3 -c "from gsa import models" 2>/dev/null || return 1
    return 0
}

# ─── Fast-path skip (hook-friendly) ──────────────────────────────────────────
# Only skips when NOT forced, --fast was requested, the recorded manifest hash
# matches the current one, and the workspace passes a quick health check.
if [ "$FORCE" -eq 0 ] && [ "$FAST" -eq 1 ] && [ -f "$STATE_FILE" ]; then
    PREV_HASH="$(grep -m1 '^manifest_sha256=' "$STATE_FILE" 2>/dev/null | cut -d= -f2)"
    if [ -n "$PREV_HASH" ] && [ "$PREV_HASH" = "$CURRENT_HASH" ] && quick_health; then
        echo "🧠 SuperBrain: already bootstrapped & healthy (manifest unchanged) — fast skip."
        echo "   Run 'bootstrap.sh --force' to rebuild, or 'verify.sh' for a full check."
        exit 0
    fi
fi

# ─── Observability: capture this full run to bootstrap.log ───────────────────
# We re-exec the script through a synchronous `| tee` pipeline (NOT process
# substitution). A real pipeline is awaited by the shell, so tee gets EOF when
# the run ends and never leaves a dangling reader that would hang `| tail` (or
# the SessionStart hook). Only full runs reach here, so --fast skips don't
# clobber the last full-run log.
if [ -z "${_SB_TEE:-}" ] && command -v tee >/dev/null 2>&1; then
    export _SB_TEE=1
    bash "$0" "$@" 2>&1 | tee "$LOG_FILE"
    exit "${PIPESTATUS[0]}"
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  🧠 SuperBrain — Full Workspace Bootstrap                       ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""
echo "  Python: $(python3 --version 2>&1)  ($PYTHON_BIN)"
echo "  Workspace: $WORKSPACE"
echo "  Started:   $(date -u +%Y-%m-%dT%H:%M:%SZ)"
[ "$FORCE" -eq 1 ] && echo "  Mode: --force (rebuilding)"
echo ""

# ─── 1. Clone Repositories ──────────────────────────────────────────────────
# clone_one() is provided by lib.sh (resilient: retry + backoff + ref pin).

REPO_COUNT="$(manifest_repo_count)"
# Parallel cloning speeds fresh sessions; set SUPERBRAIN_PARALLEL_CLONE=0 to serialize.
PARALLEL_CLONE="${SUPERBRAIN_PARALLEL_CLONE:-1}"
echo "── 1/6 Cloning repositories ($REPO_COUNT declared${PARALLEL_CLONE:+, parallel=$PARALLEL_CLONE}) ──"
CLONE_ERRORS=0

if [ "$PARALLEL_CLONE" = "1" ]; then
    _clone_tmp="$(mktemp -d)"
    _clone_order=()
    while IFS='|' read -r _name _github _ref; do
        [ -z "$_name" ] && continue
        _clone_order+=("$_name")
        (
            if clone_one "$_name" "$_github" "$_ref" > "$_clone_tmp/$_name.log" 2>&1; then
                echo ok > "$_clone_tmp/$_name.status"
            else
                echo fail > "$_clone_tmp/$_name.status"
            fi
        ) &
    done < <(manifest_repos_full)
    wait || true
    for _name in "${_clone_order[@]}"; do
        cat "$_clone_tmp/$_name.log" 2>/dev/null || true
        [ "$(cat "$_clone_tmp/$_name.status" 2>/dev/null)" = "ok" ] || CLONE_ERRORS=$((CLONE_ERRORS + 1))
    done
    rm -rf "$_clone_tmp" 2>/dev/null || true
else
    while IFS='|' read -r _name _github _ref; do
        [ -z "$_name" ] && continue
        clone_one "$_name" "$_github" "$_ref" || CLONE_ERRORS=$((CLONE_ERRORS + 1))
    done < <(manifest_repos_full)
fi
echo ""

# ─── 2. Create Kiro directories ─────────────────────────────────────────────

mkdir -p "$KIRO_DIR/skills" "$KIRO_DIR/steering" "$KIRO_DIR/scripts" "$KIRO_DIR/hooks"

# ─── 3. Install All-Skills (44 skills) ──────────────────────────────────────

echo "── 2/6 Installing All-Skills (44 design/UX/WP skills) ──"
if [ -x "$WORKSPACE/All-Skills/install.sh" ]; then
    KIRO_SKILLS_DIR="$KIRO_DIR/skills" bash "$WORKSPACE/All-Skills/install.sh" 2>&1 | tail -1
else
    chmod +x "$WORKSPACE/All-Skills/install.sh"
    KIRO_SKILLS_DIR="$KIRO_DIR/skills" bash "$WORKSPACE/All-Skills/install.sh" 2>&1 | tail -1
fi
echo ""

# ─── 4. Install Claude-Power (16 engineering skills + steering + scripts) ────

echo "── 3/6 Installing Claude-Power (16 engineering skills) ──"
if [ -d "$WORKSPACE/Claude-Power/.kiro/skills" ]; then
    cp -r "$WORKSPACE/Claude-Power/.kiro/skills/"* "$KIRO_DIR/skills/" 2>/dev/null || true
    echo "  ✓ Skills merged"
fi
if [ -d "$WORKSPACE/Claude-Power/.kiro/steering" ]; then
    cp -r "$WORKSPACE/Claude-Power/.kiro/steering/"* "$KIRO_DIR/steering/" 2>/dev/null || true
    echo "  ✓ Steering installed"
fi
if [ -d "$WORKSPACE/Claude-Power/.kiro/scripts" ]; then
    cp -r "$WORKSPACE/Claude-Power/.kiro/scripts/"* "$KIRO_DIR/scripts/" 2>/dev/null || true
    echo "  ✓ Scripts installed"
fi
echo ""

# ─── 5. Install AIBrain (intelligence layer) ─────────────────────────────────

echo "── 4/6 Installing AIBrain (intelligence layer) ──"
if [ -x "$WORKSPACE/AIBrain/scripts/install.sh" ]; then
    bash "$WORKSPACE/AIBrain/scripts/install.sh" 2>&1 | grep -E "^(✓|✅|⚠️)" || true
else
    # Manual install if script missing
    if [ -f "$WORKSPACE/AIBrain/.kiro/steering/aibrain.md" ]; then
        cp "$WORKSPACE/AIBrain/.kiro/steering/aibrain.md" "$KIRO_DIR/steering/"
    fi
    if [ -d "$WORKSPACE/AIBrain/.kiro/skills/aibrain" ]; then
        cp -r "$WORKSPACE/AIBrain/.kiro/skills/aibrain" "$KIRO_DIR/skills/"
    fi
    echo "  ✓ AIBrain installed (manual)"
fi
echo ""

# ─── 6. Install Python packages ──────────────────────────────────────────────

echo "── 5/6 Installing Python packages ──"
if python3 -c "import scrapetoolai" 2>/dev/null; then
    echo "  ✓ scrapetoolai (already installed)"
else
    pip install -e "$WORKSPACE/ScrapeToolAi" --quiet 2>/dev/null
    echo "  ✓ scrapetoolai installed"
fi

if python3 -c "from gsa import models" 2>/dev/null; then
    echo "  ✓ goaaiseo-seo-adapter (already installed)"
else
    pip install -e "$WORKSPACE/goaaiseo-seo-adapter" --quiet 2>/dev/null
    echo "  ✓ goaaiseo-seo-adapter installed"
fi
echo ""

# ─── 7. Install SuperBrain steering (overwrites workspace-repos) ─────────────

echo "── 6/6 Installing SuperBrain steering ──"
cp "$SUPERBRAIN_DIR/.kiro/steering/superbrain.md" "$KIRO_DIR/steering/" 2>/dev/null || true
cp -r "$SUPERBRAIN_DIR/.kiro/skills/superbrain" "$KIRO_DIR/skills/" 2>/dev/null || true
echo "  ✓ SuperBrain steering + skill installed"
echo ""

# ─── 8. Post-install setup ───────────────────────────────────────────────────

chmod +x "$KIRO_DIR/scripts/"*.sh 2>/dev/null || true
find "$KIRO_DIR/skills" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
chmod +x "$WORKSPACE/AIBrain/scripts/"*.sh 2>/dev/null || true
mkdir -p "$WORKSPACE/goaaiseo-seo-adapter/out"
mkdir -p "$WORKSPACE/ScrapeToolAi/output" "$WORKSPACE/ScrapeToolAi/imports"

# ─── 9. Environment Variables ────────────────────────────────────────────────

export GOAAISEO_ROOT="$WORKSPACE/goaaiseo"
export GOAAISEO_BLUEPRINT="$WORKSPACE/goaaiseo/docs/blueprint"
export GSA_SINK="jsonfile"
export GSA_SINK_PATH="$WORKSPACE/goaaiseo-seo-adapter/out/site.graph.json"
export GSA_MIN_CONFIDENCE="0.7"
export SCRAPETOOL_OUTPUT="$WORKSPACE/ScrapeToolAi/output"
export SCRAPETOOL_IMPORTS="$WORKSPACE/ScrapeToolAi/imports"
export KIRO_SKILLS_DIR="$KIRO_DIR/skills"
export AIBRAIN_ROOT="$WORKSPACE/AIBrain"

# Write env file for sourcing in future commands
cat > "$SUPERBRAIN_DIR/.env" << EOF
export PATH="/root/.pyenv/versions/3.11.15/bin:\$PATH"
export GOAAISEO_ROOT="$WORKSPACE/goaaiseo"
export GOAAISEO_BLUEPRINT="$WORKSPACE/goaaiseo/docs/blueprint"
export GSA_SINK="jsonfile"
export GSA_SINK_PATH="$WORKSPACE/goaaiseo-seo-adapter/out/site.graph.json"
export GSA_MIN_CONFIDENCE="0.7"
export SCRAPETOOL_OUTPUT="$WORKSPACE/ScrapeToolAi/output"
export SCRAPETOOL_IMPORTS="$WORKSPACE/ScrapeToolAi/imports"
export KIRO_SKILLS_DIR="$KIRO_DIR/skills"
export AIBRAIN_ROOT="$WORKSPACE/AIBrain"
EOF

# ─── 10. Verification ────────────────────────────────────────────────────────

echo "── Verifying installation ──"
ERRORS=0

# Check repos exist (driven by manifest)
while read -r repo; do
    [ -z "$repo" ] && continue
    if [ -d "$WORKSPACE/$repo/.git" ]; then
        printf "  ✓ %-25s cloned\n" "$repo"
    else
        printf "  ✗ %-25s MISSING\n" "$repo"
        ERRORS=$((ERRORS + 1))
    fi
done < <(manifest_repo_names)

# Check Python packages
if python3 -c "import scrapetoolai" 2>/dev/null; then
    echo "  ✓ scrapetoolai              importable"
else
    echo "  ✗ scrapetoolai              FAILED"
    ERRORS=$((ERRORS + 1))
fi
if python3 -c "from gsa import models" 2>/dev/null; then
    echo "  ✓ gsa                       importable"
else
    echo "  ✗ gsa                       FAILED"
    ERRORS=$((ERRORS + 1))
fi

# Check CLIs
if command -v gsa >/dev/null 2>&1; then
    echo "  ✓ gsa CLI                   available"
else
    echo "  ✗ gsa CLI                   MISSING"
    ERRORS=$((ERRORS + 1))
fi
if command -v scrapetool >/dev/null 2>&1; then
    echo "  ✓ scrapetool CLI            available"
else
    echo "  ✗ scrapetool CLI            MISSING"
    ERRORS=$((ERRORS + 1))
fi

# Check skills
SKILL_COUNT=$(ls "$KIRO_DIR/skills" 2>/dev/null | wc -l)
if [ "$SKILL_COUNT" -ge 50 ]; then
    echo "  ✓ Kiro skills               $SKILL_COUNT active"
else
    echo "  ⚠ Kiro skills               only $SKILL_COUNT (expected 60+)"
fi

# Check AIBrain
if [ -f "$KIRO_DIR/steering/aibrain.md" ] && [ -f "$KIRO_DIR/skills/aibrain/SKILL.md" ]; then
    echo "  ✓ AIBrain                   steering + skill active"
else
    echo "  ✗ AIBrain                   NOT WIRED"
    ERRORS=$((ERRORS + 1))
fi

# Check SuperBrain steering
if [ -f "$KIRO_DIR/steering/superbrain.md" ]; then
    echo "  ✓ SuperBrain                steering active"
else
    echo "  ⚠ SuperBrain                steering missing"
fi

echo ""

# ─── Record state (observability + --fast idempotency) ───────────────────────

END_TS="$(date +%s)"
DURATION=$((END_TS - START_TS))
GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if [ "$ERRORS" -eq 0 ]; then HEALTHY=true; else HEALTHY=false; fi

# .bootstrapped — key=value state that gates the --fast fast-path (success only).
if [ "$ERRORS" -eq 0 ]; then
    cat > "$STATE_FILE" <<EOF
# SuperBrain bootstrap state — auto-generated, gitignored. Do not edit.
manifest_sha256=$CURRENT_HASH
bootstrapped_at=$GENERATED_AT
python_bin=$PYTHON_BIN
repos=$REPO_COUNT
skills=$SKILL_COUNT
duration_seconds=$DURATION
EOF
fi

# .superbrain-state.json — structured snapshot, written every run (even on error).
if python3 -c "import scrapetoolai" 2>/dev/null; then PKG_SCRAPE=true; else PKG_SCRAPE=false; fi
if python3 -c "from gsa import models" 2>/dev/null; then PKG_GSA=true; else PKG_GSA=false; fi
if command -v scrapetool >/dev/null 2>&1; then CLI_SCRAPE=true; else CLI_SCRAPE=false; fi
if command -v gsa >/dev/null 2>&1; then CLI_GSA=true; else CLI_GSA=false; fi
PY_VER="$(python3 --version 2>&1 | awk '{print $2}')"
{
    echo "{"
    echo "  \"generated_at\": \"$GENERATED_AT\","
    echo "  \"healthy\": $HEALTHY,"
    echo "  \"errors\": $ERRORS,"
    echo "  \"duration_seconds\": $DURATION,"
    echo "  \"manifest_sha256\": \"$CURRENT_HASH\","
    echo "  \"workspace\": \"$WORKSPACE\","
    echo "  \"kiro_dir\": \"$KIRO_DIR\","
    echo "  \"python_bin\": \"$PYTHON_BIN\","
    echo "  \"python_version\": \"$PY_VER\","
    echo "  \"skills\": $SKILL_COUNT,"
    echo "  \"packages\": { \"scrapetoolai\": $PKG_SCRAPE, \"gsa\": $PKG_GSA },"
    echo "  \"clis\": { \"scrapetool\": $CLI_SCRAPE, \"gsa\": $CLI_GSA },"
    echo "  \"repos\": ["
    _first=1
    while read -r r; do
        [ -z "$r" ] && continue
        if [ -d "$WORKSPACE/$r/.git" ]; then _present=true; else _present=false; fi
        if [ "$_first" -eq 1 ]; then _first=0; else printf ",\n"; fi
        printf "    { \"name\": \"%s\", \"present\": %s }" "$r" "$_present"
    done < <(manifest_repo_names)
    printf "\n"
    echo "  ]"
    echo "}"
} > "$STATE_JSON"

# AIBrain journal — record the run in persistent memory (best-effort).
if [ -x "$WORKSPACE/AIBrain/scripts/brain.sh" ]; then
    bash "$WORKSPACE/AIBrain/scripts/brain.sh" journal \
        "SuperBrain bootstrap: $ERRORS error(s), $REPO_COUNT repos, $SKILL_COUNT skills, ${DURATION}s (py $PY_VER)" \
        >/dev/null 2>&1 || true
fi

# ─── Summary ─────────────────────────────────────────────────────────────────

if [ "$ERRORS" -eq 0 ]; then
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║  ✅ SUPERBRAIN BOOTSTRAP COMPLETE                               ║"
    echo "╠══════════════════════════════════════════════════════════════════╣"
    echo "║                                                                  ║"
    echo "║  Repos:    $REPO_COUNT cloned & connected                                  ║"
    echo "║  Skills:   $SKILL_COUNT active (design + engineering + brain)          ║"
    echo "║  Packages: scrapetoolai + gsa installed                          ║"
    echo "║  CLIs:     scrapetool, gsa                                       ║"
    echo "║  Brain:    AIBrain persistent intelligence active                ║"
    echo "║  Env:      All variables set (source .env to reload)             ║"
    echo "║                                                                  ║"
    echo "║  Everything is connected. Start working.                         ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
else
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║  ⚠️  BOOTSTRAP COMPLETED WITH $ERRORS ERROR(S)                     ║"
    echo "║  Re-run or check the failures above.                            ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
fi

exit $ERRORS
