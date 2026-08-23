#!/usr/bin/env bash
# Verify the connected workspace without reinstalling or counting directories.
set -uo pipefail

SUPERBRAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="${SUPERBRAIN_WORKSPACE:-/projects/sandbox}"
KIRO_DIR="${KIRO_DIR:-/projects/.kiro}"
SKILLS_TARGET="$KIRO_DIR/skills"
INTEGRATION_REPORT="$KIRO_DIR/all-skills-integration.json"
export PATH="/root/.pyenv/versions/3.11.15/bin:$PATH"

printf '\n🔍 SuperBrain — Workspace Verification\n'
printf '%s\n\n' '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
ERRORS=0
WARNINGS=0

printf '📦 Repositories:\n'
for repo in All-Skills Claude-Power ScrapeToolAi goaaiseo-seo-adapter goaaiseo SuperBrain; do
    if [ -d "$WORKSPACE/$repo/.git" ]; then
        printf '  ✓ %-25s present\n' "$repo"
    else
        printf '  ✗ %-25s MISSING\n' "$repo"
        ERRORS=$((ERRORS + 1))
    fi
done
printf '\n'

printf '🐍 Python packages and CLIs:\n'
if python3 -c "import scrapetoolai" >/dev/null 2>&1; then
    printf '  ✓ scrapetoolai              importable\n'
else
    printf '  ✗ scrapetoolai              NOT IMPORTABLE\n'
    ERRORS=$((ERRORS + 1))
fi
if python3 -c "from gsa import models, normalize, sinks" >/dev/null 2>&1; then
    printf '  ✓ goaaiseo-seo-adapter      importable\n'
else
    printf '  ✗ goaaiseo-seo-adapter      NOT IMPORTABLE\n'
    ERRORS=$((ERRORS + 1))
fi
for cli in gsa scrapetool; do
    if command -v "$cli" >/dev/null 2>&1; then
        printf '  ✓ %-25s available\n' "$cli"
    else
        printf '  ✗ %-25s MISSING\n' "$cli"
        ERRORS=$((ERRORS + 1))
    fi
done
printf '\n'

printf '🎯 Connected skill ownership:\n'
if INTEGRATION_OUTPUT="$(python3 "$SUPERBRAIN_DIR/scripts/skills_integration.py" verify \
    --workspace "$WORKSPACE" --target "$SKILLS_TARGET" --report "$INTEGRATION_REPORT" 2>&1)"; then
    printf '  ✓ All-Skills catalog, 44-folder receipt, public check, and owner trees are exact\n'
    printf '  %s\n' "$INTEGRATION_OUTPUT"
else
    printf '  ✗ Exact connected-skill verification failed\n'
    printf '  %s\n' "$INTEGRATION_OUTPUT"
    ERRORS=$((ERRORS + 1))
fi
printf '\n'

printf '📋 Installed workspace artifacts:\n'
for artifact in \
    "$KIRO_DIR/steering/superbrain.md" \
    "$KIRO_DIR/steering/verification-discipline.md" \
    "$KIRO_DIR/skills/superbrain/SKILL.md"; do
    if [ -f "$artifact" ] && [ ! -L "$artifact" ]; then
        printf '  ✓ %s\n' "$artifact"
    else
        printf '  ✗ %s missing or unsafe\n' "$artifact"
        ERRORS=$((ERRORS + 1))
    fi
done
printf '\n'

printf '🧠 AIBrain (separate from skill ownership health):\n'
AIBRAIN_BRAIN="$WORKSPACE/AIBrain/scripts/brain.sh"
if python3 "$SUPERBRAIN_DIR/scripts/skills_integration.py" check-safe-file --path "$AIBRAIN_BRAIN" >/dev/null; then
    if bash "$AIBRAIN_BRAIN" doctor >/dev/null 2>&1; then
        printf '  ✓ AIBrain doctor            healthy\n'
    else
        printf '  ⚠ AIBrain doctor            reported issues\n'
        WARNINGS=$((WARNINGS + 1))
    fi
else
    printf '  ⚠ AIBrain brain.sh          absent; optional synchronization unavailable\n'
    WARNINGS=$((WARNINGS + 1))
fi
printf '\n'

if [ -f "$SUPERBRAIN_DIR/.env" ] && [ ! -L "$SUPERBRAIN_DIR/.env" ]; then
    printf '🌍 Environment: generated .env present\n\n'
elif [ -L "$SUPERBRAIN_DIR/.env" ]; then
    printf '🌍 Environment: .env is symlinked and unsafe\n\n'
    ERRORS=$((ERRORS + 1))
else
    printf '🌍 Environment: .env absent (run bootstrap to generate it)\n\n'
    WARNINGS=$((WARNINGS + 1))
fi

printf '%s\n' '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
    printf '✅ Workspace HEALTHY — exact connected ownership verified\n'
elif [ "$ERRORS" -eq 0 ]; then
    printf '⚠️  Workspace skill health is exact; %s optional warning(s)\n' "$WARNINGS"
else
    printf '❌ Workspace UNHEALTHY — %s error(s), %s warning(s)\n' "$ERRORS" "$WARNINGS"
fi
printf '%s\n' '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
exit "$ERRORS"
