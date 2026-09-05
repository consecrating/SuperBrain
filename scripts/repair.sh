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

# ─── Shared library (manifest, python autodetect, path resolution) ───────────
SUPERBRAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "$SUPERBRAIN_DIR/scripts/lib.sh"

activate_python >/dev/null          # prepend detected python to PATH (this shell)
WORKSPACE="$(resolve_workspace)"
KIRO_DIR="$(resolve_kiro)"

echo "🔧 SuperBrain — Repair"
echo ""

# github_for <name>: look up a repo's github slug from the manifest (fallback list).
github_for() {
    local want="$1"
    manifest_repos | while IFS='|' read -r n g; do
        [ "$n" = "$want" ] && { printf '%s\n' "$g"; break; }
    done
}

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

TARGET="${1:-auto}"
case "$TARGET" in
    auto)
        echo "Auto-detecting issues and repairing..."
        echo ""
        repair_skills
        repair_packages
        repair_aibrain
        echo ""
        echo "✅ Auto-repair complete. Run verify.sh to confirm."
        ;;
    All-Skills)     repair_repo "All-Skills" "$(github_for All-Skills)" && repair_skills ;;
    Claude-Power)   repair_repo "Claude-Power" "$(github_for Claude-Power)" && repair_skills ;;
    AIBrain)        repair_repo "AIBrain" "$(github_for AIBrain)" && repair_aibrain ;;
    ScrapeToolAi)   repair_repo "ScrapeToolAi" "$(github_for ScrapeToolAi)" && repair_packages ;;
    goaaiseo-seo-adapter) repair_repo "goaaiseo-seo-adapter" "$(github_for goaaiseo-seo-adapter)" && repair_packages ;;
    goaaiseo)       repair_repo "goaaiseo" "$(github_for goaaiseo)" ;;
    Sanctify-Hivemind) repair_repo "Sanctify-Hivemind" "$(github_for Sanctify-Hivemind)" && repair_packages ;;
    skills)         repair_skills ;;
    packages)       repair_packages ;;
    aibrain)        repair_aibrain ;;
    *)
        # Generic: if TARGET is a manifest repo we don't special-case, re-clone it
        # and re-run package + skill installs to be safe.
        gh_slug="$(github_for "$TARGET")"
        if [ -n "$gh_slug" ]; then
            repair_repo "$TARGET" "$gh_slug"
            repair_packages
            repair_skills
        else
            echo "Usage: repair.sh [auto|<repo-name>|skills|packages|aibrain]"
            echo ""
            echo "Repos: $(manifest_repo_names | paste -sd, - | sed 's/,/, /g')"
            echo "Groups: skills, packages, aibrain, auto"
        fi
        ;;
esac
