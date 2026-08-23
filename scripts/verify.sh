#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# verify.sh — Quick health check for the entire workspace
#
# Checks all repos, packages, skills, and wiring without reinstalling anything.
# Exit 0 = all good, Exit 1 = issues found.
# ═══════════════════════════════════════════════════════════════════════════════
set -uo pipefail

export PATH="/root/.pyenv/versions/3.11.15/bin:$PATH"
WORKSPACE="/projects/sandbox"
KIRO_DIR="/projects/.kiro"

echo ""
echo "🔍 SuperBrain — Workspace Verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

ERRORS=0
WARNINGS=0

# ─── Repositories ────────────────────────────────────────────────────────────

echo "📦 Repositories:"
for repo in All-Skills Claude-Power AIBrain ScrapeToolAi goaaiseo-seo-adapter goaaiseo SuperBrain; do
    if [ -d "$WORKSPACE/$repo/.git" ]; then
        printf "  ✓ %-25s present\n" "$repo"
    else
        printf "  ✗ %-25s MISSING\n" "$repo"
        ERRORS=$((ERRORS + 1))
    fi
done
echo ""

# ─── Python Packages ────────────────────────────────────────────────────────

echo "🐍 Python Packages:"
if python3 -c "import scrapetoolai" 2>/dev/null; then
    echo "  ✓ scrapetoolai              installed"
else
    echo "  ✗ scrapetoolai              NOT INSTALLED"
    ERRORS=$((ERRORS + 1))
fi
if python3 -c "from gsa import models, normalize, sinks" 2>/dev/null; then
    echo "  ✓ goaaiseo-seo-adapter      installed"
else
    echo "  ✗ goaaiseo-seo-adapter      NOT INSTALLED"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# ─── CLIs ────────────────────────────────────────────────────────────────────

echo "⚡ CLI Tools:"
if command -v gsa >/dev/null 2>&1; then
    echo "  ✓ gsa                       $(gsa --version 2>&1 | head -1)"
else
    echo "  ✗ gsa                       NOT FOUND"
    ERRORS=$((ERRORS + 1))
fi
if command -v scrapetool >/dev/null 2>&1; then
    echo "  ✓ scrapetool                available"
else
    echo "  ✗ scrapetool                NOT FOUND"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# ─── Kiro Skills ─────────────────────────────────────────────────────────────

echo "🎯 Kiro Skills:"
SKILL_COUNT=$(ls "$KIRO_DIR/skills" 2>/dev/null | wc -l)
echo "  Total: $SKILL_COUNT skills"

# Check critical skills
for skill in aibrain superbrain token-efficiency seo-optimization ui-ux-pro-max; do
    if [ -f "$KIRO_DIR/skills/$skill/SKILL.md" ]; then
        printf "  ✓ %-25s active\n" "$skill"
    else
        printf "  ✗ %-25s MISSING\n" "$skill"
        ERRORS=$((ERRORS + 1))
    fi
done
echo ""

# ─── Steering Files ──────────────────────────────────────────────────────────

echo "📋 Steering Files:"
for steer in superbrain.md aibrain.md verification-discipline.md; do
    if [ -f "$KIRO_DIR/steering/$steer" ]; then
        printf "  ✓ %-30s active\n" "$steer"
    else
        printf "  ⚠ %-30s missing\n" "$steer"
        WARNINGS=$((WARNINGS + 1))
    fi
done
echo ""

# ─── AIBrain ─────────────────────────────────────────────────────────────────

echo "🧠 AIBrain:"
if [ -f "$WORKSPACE/AIBrain/brain/identity.md" ]; then
    echo "  ✓ Brain knowledge graph     present"
else
    echo "  ✗ Brain knowledge graph     MISSING"
    ERRORS=$((ERRORS + 1))
fi
if [ -f "$WORKSPACE/AIBrain/memory/active-task.md" ]; then
    echo "  ✓ Memory system             present"
else
    echo "  ✗ Memory system             MISSING"
    ERRORS=$((ERRORS + 1))
fi
if [ -x "$WORKSPACE/AIBrain/scripts/brain.sh" ]; then
    echo "  ✓ brain.sh                  executable"
else
    echo "  ✗ brain.sh                  NOT EXECUTABLE"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# ─── Environment ─────────────────────────────────────────────────────────────

echo "🌍 Environment:"
if [ -f "$WORKSPACE/SuperBrain/.env" ]; then
    echo "  ✓ .env file                 present (source it for vars)"
else
    echo "  ⚠ .env file                 not generated (run bootstrap)"
    WARNINGS=$((WARNINGS + 1))
fi
echo ""

# ─── Summary ─────────────────────────────────────────────────────────────────

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
    echo "✅ Workspace HEALTHY — all systems operational"
    echo "   $SKILL_COUNT skills | 2 packages | 2 CLIs | AIBrain active"
elif [ "$ERRORS" -eq 0 ]; then
    echo "⚠️  Workspace OK — $WARNINGS warning(s), no errors"
    echo "   Run bootstrap.sh to fix warnings"
else
    echo "❌ Workspace UNHEALTHY — $ERRORS error(s), $WARNINGS warning(s)"
    echo "   Run: bash /projects/sandbox/SuperBrain/scripts/bootstrap.sh"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit $ERRORS
