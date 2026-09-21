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
WORKSPACE="/projects/sandbox"
KIRO_DIR="/projects/.kiro"

# ─── Python 3.11 ─────────────────────────────────────────────────────────────
export PATH="/root/.pyenv/versions/3.11.15/bin:$PATH"

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  🧠 SuperBrain — Full Workspace Bootstrap                       ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""
echo "  Python: $(python3 --version 2>&1)"
echo "  Workspace: $WORKSPACE"
echo ""

# ─── 1. Clone Repositories ──────────────────────────────────────────────────

clone_repo() {
    local name="$1"
    local github="$2"
    local path="$WORKSPACE/$name"
    
    if [ -d "$path/.git" ]; then
        echo "  ✓ $name (already cloned)"
    else
        echo "  ⏳ Cloning $name..."
        git clone "https://github.com/$github.git" "$path" --quiet 2>/dev/null || {
            echo "  ✗ Failed to clone $github"
            return 1
        }
        echo "  ✓ $name (cloned)"
    fi
}

echo "── 1/6 Cloning repositories ──"
clone_repo "All-Skills"              "consecrating/All-Skills"
clone_repo "Claude-Power"            "consecrating/Claude-Power"
clone_repo "AIBrain"                 "consecrating/AIBrain"
clone_repo "ScrapeToolAi"           "consecrating/ScrapeToolAi"
clone_repo "goaaiseo-seo-adapter"   "consecrating/goaaiseo-seo-adapter"
clone_repo "goaaiseo"               "consecrating/goaaiseo"
# Repo #7 — tolerated if absent so a failed clone cannot abort bootstrap
# (clone_repo returns 1 on failure, and `set -e` would otherwise exit here).
clone_repo "FirecrawlPower"         "consecrating/FirecrawlPower" || true
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
cp "$SUPERBRAIN_DIR/.kiro/steering/install-everything.md" "$KIRO_DIR/steering/" 2>/dev/null || true
cp -r "$SUPERBRAIN_DIR/.kiro/skills/superbrain" "$KIRO_DIR/skills/" 2>/dev/null || true
echo "  ✓ SuperBrain steering + skill installed"
echo ""

# ─── 7b. Install FirecrawlPower (repo #7 — keyless web layer) ────────────────

echo "── FirecrawlPower (keyless web layer) ──"
if [ -f "$WORKSPACE/FirecrawlPower/install.sh" ]; then
    KIRO_SKILLS_DIR="$KIRO_DIR/skills" \
      bash "$WORKSPACE/FirecrawlPower/install.sh" 2>&1 | grep -E '✓|⚠|✗' | tail -6 || true
    echo "  ✓ 6 keyless skills + fcless CLI"
else
    echo "  ⚠ FirecrawlPower not present — skipped (no API-key-free web layer)"
    echo "    for full cross-agent install use: bash scripts/install-everything.sh"
fi
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

# Check repos exist
for repo in All-Skills Claude-Power AIBrain ScrapeToolAi goaaiseo-seo-adapter goaaiseo; do
    if [ -d "$WORKSPACE/$repo/.git" ]; then
        printf "  ✓ %-25s cloned\n" "$repo"
    else
        printf "  ✗ %-25s MISSING\n" "$repo"
        ERRORS=$((ERRORS + 1))
    fi
done

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

# ─── Summary ─────────────────────────────────────────────────────────────────

if [ "$ERRORS" -eq 0 ]; then
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║  ✅ SUPERBRAIN BOOTSTRAP COMPLETE                               ║"
    echo "╠══════════════════════════════════════════════════════════════════╣"
    echo "║                                                                  ║"
    echo "║  Repos:    6 cloned & connected                                  ║"
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
