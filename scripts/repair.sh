#!/usr/bin/env bash
# Repair connected workspace components and propagate every required failure.
set -euo pipefail

SUPERBRAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="${SUPERBRAIN_WORKSPACE:-/projects/sandbox}"
KIRO_DIR="${KIRO_DIR:-/projects/.kiro}"
SKILLS_TARGET="$KIRO_DIR/skills"
INTEGRATION_REPORT="$KIRO_DIR/all-skills-integration.json"
export PATH="/root/.pyenv/versions/3.11.15/bin:$PATH"

absolute_path() { python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$1"; }
assert_safe_path() {
    local label="$1" path current="/" rest part
    path="$(absolute_path "$2")"; rest="${path#/}"
    IFS='/' read -r -a parts <<< "$rest"
    for part in "${parts[@]}"; do
        [ -n "$part" ] || continue; current="${current%/}/$part"
        if [ -L "$current" ]; then
            printf 'ERROR: refusing symlinked %s component: %s\n' "$label" "$current" >&2; return 1
        fi
    done
}
publish_artifacts() {
    python3 "$SUPERBRAIN_DIR/scripts/skills_integration.py" publish-artifacts \
        --lock-root "$KIRO_DIR" "$@"
}
WORKSPACE="$(absolute_path "$WORKSPACE")"; KIRO_DIR="$(absolute_path "$KIRO_DIR")"
SKILLS_TARGET="$KIRO_DIR/skills"; INTEGRATION_REPORT="$KIRO_DIR/all-skills-integration.json"
assert_safe_path "workspace" "$WORKSPACE"; assert_safe_path "Kiro directory" "$KIRO_DIR"

printf '🔧 SuperBrain — Repair\n\n'

repair_repo() {
    local name="$1"
    local github="$2"
    local path="$WORKSPACE/$name"
    if [ -d "$path/.git" ]; then
        printf '  ↻ Pulling latest for %s...\n' "$name"
        git -C "$path" pull --ff-only --quiet
        printf '  ✓ %s updated\n' "$name"
    else
        printf '  ⏳ Cloning %s...\n' "$name"
        git clone --quiet "https://github.com/$github.git" "$path"
        printf '  ✓ %s cloned\n' "$name"
    fi
}

repair_skills() {
    printf '  ↻ Repairing exact connected skill ownership...\n'
    mkdir -p "$SKILLS_TARGET" "$KIRO_DIR/steering" "$KIRO_DIR/scripts"
    python3 "$SUPERBRAIN_DIR/scripts/skills_integration.py" install \
        --workspace "$WORKSPACE" --target "$SKILLS_TARGET" --report "$INTEGRATION_REPORT"
    publish_artifacts \
        --contents "$WORKSPACE/Claude-Power/.kiro/steering" "$KIRO_DIR/steering" \
        --contents "$WORKSPACE/Claude-Power/.kiro/scripts" "$KIRO_DIR/scripts" \
        --tree "$SUPERBRAIN_DIR/.kiro/skills/superbrain" "$SKILLS_TARGET/superbrain" \
        --file "$SUPERBRAIN_DIR/.kiro/steering/superbrain.md" "$KIRO_DIR/steering/superbrain.md"
    python3 "$SUPERBRAIN_DIR/scripts/skills_integration.py" verify \
        --workspace "$WORKSPACE" --target "$SKILLS_TARGET" --report "$INTEGRATION_REPORT"
    printf '  ✓ Exact catalog, receipt, and owner-tree health restored\n'
}

repair_packages() {
    printf '  ↻ Re-installing Python packages...\n'
    python3 -m pip install --quiet -e "$WORKSPACE/ScrapeToolAi"
    python3 -m pip install --quiet -e "$WORKSPACE/goaaiseo-seo-adapter"
    printf '  ✓ Packages re-installed\n'
}

repair_aibrain() {
    printf '  ↻ Re-wiring AIBrain...\n'
    aibrain_installer="$WORKSPACE/AIBrain/scripts/install.sh"
    if ! python3 "$SUPERBRAIN_DIR/scripts/skills_integration.py" check-safe-file --path "$aibrain_installer" >/dev/null; then
        printf '  ✗ AIBrain installer is absent or unsafe\n' >&2
        return 1
    fi
    if KIRO_DIR="$KIRO_DIR" bash "$aibrain_installer"; then
        printf '  ✓ AIBrain wired\n'
    else
        printf '  ✗ AIBrain installer failed\n' >&2
        return 1
    fi
}

repair_aibrain_optional() {
    if ! repair_aibrain; then
        printf '  ⚠ Optional AIBrain repair skipped or failed; connected skill health is unaffected\n'
    fi
}

case "${1:-auto}" in
    auto)
        repair_skills
        repair_packages
        repair_aibrain_optional
        SUPERBRAIN_WORKSPACE="$WORKSPACE" KIRO_DIR="$KIRO_DIR" bash "$SUPERBRAIN_DIR/scripts/verify.sh"
        ;;
    All-Skills)
        repair_repo "All-Skills" "consecrating/All-Skills"
        repair_skills
        ;;
    Claude-Power)
        repair_repo "Claude-Power" "consecrating/Claude-Power"
        repair_skills
        ;;
    AIBrain)
        repair_repo "AIBrain" "consecrating/AIBrain"
        repair_aibrain
        ;;
    ScrapeToolAi)
        repair_repo "ScrapeToolAi" "consecrating/ScrapeToolAi"
        repair_packages
        ;;
    goaaiseo-seo-adapter)
        repair_repo "goaaiseo-seo-adapter" "consecrating/goaaiseo-seo-adapter"
        repair_packages
        ;;
    goaaiseo)
        repair_repo "goaaiseo" "consecrating/goaaiseo"
        ;;
    skills) repair_skills ;;
    packages) repair_packages ;;
    aibrain) repair_aibrain ;;
    *)
        printf 'Usage: repair.sh [auto|<repo-name>|skills|packages|aibrain]\n'
        printf 'Repos: All-Skills, Claude-Power, AIBrain, ScrapeToolAi, goaaiseo-seo-adapter, goaaiseo\n'
        exit 2
        ;;
esac
