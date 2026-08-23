#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# repair.sh — Fix a specific broken component
#
# Usage:
#   ./scripts/repair.sh                    # auto-detect and fix all issues
#   ./scripts/repair.sh All-Skills         # re-install specific repo
#   ./scripts/repair.sh skills             # re-install all skills
#   ./scripts/repair.sh packages           # re-install Python packages
#   ./scripts/repair.sh aibrain            # re-wire AIBrain
# ═══════════════════════════════════════════════════════════════════════════════
set -uo pipefail

export PATH="/root/.pyenv/versions/3.11.15/bin:$PATH"
WORKSPACE="/projects/sandbox"
KIRO_DIR="/projects/.kiro"

echo "🔧 SuperBrain — Repair"
echo ""

repair_repo() {
    local name="$1"
    local github="$2"
    local path="$WORKSPACE/$name"
    
    if [ -d "$path/.git" ]; then
        echo "  ↻ Pulling latest for $name..."
        cd "$path" && git pull --quiet 2>/dev/null || true
        echo "  ✓ $name updated"
    else
        echo "  ⏳ Re-cloning $name..."
        rm -rf "$path"
        git clone "https://github.com/$github.git" "$path" --quiet 2>/dev/null
        echo "  ✓ $name re-cloned"
    fi
}

repair_skills() {
    echo "  ↻ Re-installing all skills..."
    mkdir -p "$KIRO_DIR/skills"
    
    # All-Skills
    if [ -x "$WORKSPACE/All-Skills/install.sh" ]; then
        KIRO_SKILLS_DIR="$KIRO_DIR/skills" bash "$WORKSPACE/All-Skills/install.sh" 2>&1 | tail -1
    fi
    
    # Claude-Power
    if [ -d "$WORKSPACE/Claude-Power/.kiro/skills" ]; then
        cp -r "$WORKSPACE/Claude-Power/.kiro/skills/"* "$KIRO_DIR/skills/" 2>/dev/null || true
    fi
    
    # AIBrain skill
    if [ -d "$WORKSPACE/AIBrain/.kiro/skills/aibrain" ]; then
        cp -r "$WORKSPACE/AIBrain/.kiro/skills/aibrain" "$KIRO_DIR/skills/" 2>/dev/null || true
    fi
    
    # SuperBrain skill
    if [ -d "$WORKSPACE/SuperBrain/.kiro/skills/superbrain" ]; then
        cp -r "$WORKSPACE/SuperBrain/.kiro/skills/superbrain" "$KIRO_DIR/skills/" 2>/dev/null || true
    fi
    
    local count=$(ls "$KIRO_DIR/skills" | wc -l)
    echo "  ✓ $count skills installed"
}

repair_packages() {
    echo "  ↻ Re-installing Python packages..."
    pip install -e "$WORKSPACE/ScrapeToolAi" --quiet 2>/dev/null
    pip install -e "$WORKSPACE/goaaiseo-seo-adapter" --quiet 2>/dev/null
    echo "  ✓ Packages re-installed"
}

repair_aibrain() {
    echo "  ↻ Re-wiring AIBrain..."
    if [ -x "$WORKSPACE/AIBrain/scripts/install.sh" ]; then
        bash "$WORKSPACE/AIBrain/scripts/install.sh" 2>&1 | grep -E "^(✓|✅)" || true
    else
        cp "$WORKSPACE/AIBrain/.kiro/steering/aibrain.md" "$KIRO_DIR/steering/" 2>/dev/null || true
        cp -r "$WORKSPACE/AIBrain/.kiro/skills/aibrain" "$KIRO_DIR/skills/" 2>/dev/null || true
    fi
    echo "  ✓ AIBrain wired"
}

case "${1:-auto}" in
    auto)
        echo "Auto-detecting issues and repairing..."
        echo ""
        repair_skills
        repair_packages
        repair_aibrain
        echo ""
        echo "✅ Auto-repair complete. Run verify.sh to confirm."
        ;;
    All-Skills)     repair_repo "All-Skills" "consecrating/All-Skills" && repair_skills ;;
    Claude-Power)   repair_repo "Claude-Power" "consecrating/Claude-Power" && repair_skills ;;
    AIBrain)        repair_repo "AIBrain" "consecrating/AIBrain" && repair_aibrain ;;
    ScrapeToolAi)   repair_repo "ScrapeToolAi" "consecrating/ScrapeToolAi" && repair_packages ;;
    goaaiseo-seo-adapter) repair_repo "goaaiseo-seo-adapter" "consecrating/goaaiseo-seo-adapter" && repair_packages ;;
    goaaiseo)       repair_repo "goaaiseo" "consecrating/goaaiseo" ;;
    skills)         repair_skills ;;
    packages)       repair_packages ;;
    aibrain)        repair_aibrain ;;
    *)
        echo "Usage: repair.sh [auto|<repo-name>|skills|packages|aibrain]"
        echo ""
        echo "Repos: All-Skills, Claude-Power, AIBrain, ScrapeToolAi, goaaiseo-seo-adapter, goaaiseo"
        echo "Groups: skills, packages, aibrain, auto"
        ;;
esac
