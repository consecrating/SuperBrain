#!/usr/bin/env bash
# SuperBrain workspace bootstrap: clone, install, connect, and verify.
set -euo pipefail

SUPERBRAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="${SUPERBRAIN_WORKSPACE:-/projects/sandbox}"
KIRO_DIR="${KIRO_DIR:-/projects/.kiro}"
SKILLS_TARGET="$KIRO_DIR/skills"
INTEGRATION_REPORT="$KIRO_DIR/all-skills-integration.json"
MARKER="$SUPERBRAIN_DIR/.bootstrapped"
export PATH="/root/.pyenv/versions/3.11.15/bin:$PATH"

absolute_path() {
    python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$1"
}

assert_safe_path() {
    local label="$1"
    local path
    path="$(absolute_path "$2")"
    local current="/"
    local rest="${path#/}"
    local part
    IFS='/' read -r -a parts <<< "$rest"
    for part in "${parts[@]}"; do
        [ -n "$part" ] || continue
        current="${current%/}/$part"
        if [ -L "$current" ]; then
            printf 'ERROR: refusing symlinked %s component: %s\n' "$label" "$current" >&2
            return 1
        fi
    done
}

publish_artifacts() {
    python3 "$SUPERBRAIN_DIR/scripts/skills_integration.py" publish-artifacts \
        --lock-root "$KIRO_DIR" "$@"
}

WORKSPACE="$(absolute_path "$WORKSPACE")"
KIRO_DIR="$(absolute_path "$KIRO_DIR")"
SKILLS_TARGET="$KIRO_DIR/skills"
INTEGRATION_REPORT="$KIRO_DIR/all-skills-integration.json"
assert_safe_path "workspace" "$WORKSPACE"
assert_safe_path "Kiro directory" "$KIRO_DIR"
assert_safe_path "bootstrap marker" "$MARKER"

# Invalidate prior success before any workspace mutation. A failed rerun must
# never leave an old marker that can suppress the next bootstrap attempt.
if [ -L "$MARKER" ]; then
    printf 'ERROR: refusing symlinked bootstrap marker: %s\n' "$MARKER" >&2
    exit 1
fi
rm -f "$MARKER"

printf '\n╔══════════════════════════════════════════════════════════════════╗\n'
printf '║  🧠 SuperBrain — Full Workspace Bootstrap                       ║\n'
printf '╚══════════════════════════════════════════════════════════════════╝\n\n'
printf '  Python: %s\n  Workspace: %s\n\n' "$(python3 --version 2>&1)" "$WORKSPACE"

clone_repo() {
    local name="$1"
    local github="$2"
    local path="$WORKSPACE/$name"
    if [ -d "$path/.git" ]; then
        printf '  ✓ %s (already cloned)\n' "$name"
    else
        printf '  ⏳ Cloning %s...\n' "$name"
        if git clone --quiet "https://github.com/$github.git" "$path"; then
            printf '  ✓ %s (cloned)\n' "$name"
        else
            printf '  ✗ %s clone failed\n' "$name" >&2
            return 1
        fi
    fi
}

printf '%s\n' '── 1/6 Cloning repositories ──'
clone_repo "All-Skills" "consecrating/All-Skills"
clone_repo "Claude-Power" "consecrating/Claude-Power"
if ! clone_repo "AIBrain" "consecrating/AIBrain"; then
    printf '  ⚠ AIBrain unavailable; optional intelligence synchronization disabled\n'
fi
clone_repo "ScrapeToolAi" "consecrating/ScrapeToolAi"
clone_repo "goaaiseo-seo-adapter" "consecrating/goaaiseo-seo-adapter"
clone_repo "goaaiseo" "consecrating/goaaiseo"
printf '\n'

mkdir -p "$SKILLS_TARGET" "$KIRO_DIR/steering" "$KIRO_DIR/scripts" "$KIRO_DIR/hooks"

printf '%s\n' '── 2/6 Installing exact connected skill ownership ──'
python3 "$SUPERBRAIN_DIR/scripts/skills_integration.py" install \
    --workspace "$WORKSPACE" \
    --target "$SKILLS_TARGET" \
    --report "$INTEGRATION_REPORT"
printf '  ✓ All-Skills receipt owns 44; Claude-Power owns token-efficiency\n\n'

printf '%s\n' '── 3/6 Installing Claude-Power steering and scripts ──'
publish_artifacts --contents "$WORKSPACE/Claude-Power/.kiro/steering" "$KIRO_DIR/steering" \
    --contents "$WORKSPACE/Claude-Power/.kiro/scripts" "$KIRO_DIR/scripts"
printf '  ✓ Steering and scripts installed separately from skill ownership\n\n'

printf '%s\n' '── 4/6 Installing optional AIBrain integration ──'
AIBRAIN_INSTALLER="$WORKSPACE/AIBrain/scripts/install.sh"
if python3 "$SUPERBRAIN_DIR/scripts/skills_integration.py" check-safe-file --path "$AIBRAIN_INSTALLER" >/dev/null; then
    if KIRO_DIR="$KIRO_DIR" bash "$AIBRAIN_INSTALLER"; then
        printf '  ✓ Optional AIBrain integration installed\n'
    else
        printf '  ⚠ AIBrain installer failed; connected skill health remains valid\n'
    fi
else
    printf '  ⚠ AIBrain installer is absent; optional catalog synchronization was skipped\n'
fi
printf '\n'

printf '%s\n' '── 5/6 Installing Python packages ──'
if python3 -c "import scrapetoolai" >/dev/null 2>&1; then
    printf '  ✓ scrapetoolai (already installed)\n'
else
    python3 -m pip install --quiet -e "$WORKSPACE/ScrapeToolAi"
    printf '  ✓ scrapetoolai installed\n'
fi
if python3 -c "from gsa import models" >/dev/null 2>&1; then
    printf '  ✓ goaaiseo-seo-adapter (already installed)\n'
else
    python3 -m pip install --quiet -e "$WORKSPACE/goaaiseo-seo-adapter"
    printf '  ✓ goaaiseo-seo-adapter installed\n'
fi
printf '\n'

printf '%s\n' '── 6/6 Installing SuperBrain artifacts ──'
publish_artifacts \
    --file "$SUPERBRAIN_DIR/.kiro/steering/superbrain.md" "$KIRO_DIR/steering/superbrain.md" \
    --tree "$SUPERBRAIN_DIR/.kiro/skills/superbrain" "$KIRO_DIR/skills/superbrain"
chmod +x "$KIRO_DIR/scripts/"*.sh
find "$KIRO_DIR/skills" -type f -name '*.sh' -exec chmod +x {} +
if [ -d "$WORKSPACE/AIBrain/scripts" ]; then
    if ! find "$WORKSPACE/AIBrain/scripts" -maxdepth 1 -type f -name '*.sh' -exec chmod +x {} +; then
        printf '  ⚠ Optional AIBrain script permission refresh failed\n'
    fi
fi
mkdir -p "$WORKSPACE/goaaiseo-seo-adapter/out"
mkdir -p "$WORKSPACE/ScrapeToolAi/output" "$WORKSPACE/ScrapeToolAi/imports"
printf '  ✓ SuperBrain steering and skill installed\n\n'

export GOAAISEO_ROOT="$WORKSPACE/goaaiseo"
export GOAAISEO_BLUEPRINT="$WORKSPACE/goaaiseo/docs/blueprint"
export GSA_SINK="jsonfile"
export GSA_SINK_PATH="$WORKSPACE/goaaiseo-seo-adapter/out/site.graph.json"
export GSA_MIN_CONFIDENCE="0.7"
export SCRAPETOOL_OUTPUT="$WORKSPACE/ScrapeToolAi/output"
export SCRAPETOOL_IMPORTS="$WORKSPACE/ScrapeToolAi/imports"
export KIRO_SKILLS_DIR="$SKILLS_TARGET"
export AIBRAIN_ROOT="$WORKSPACE/AIBrain"

assert_safe_path "environment file" "$SUPERBRAIN_DIR/.env"
ENV_TMP="$(mktemp "$SUPERBRAIN_DIR/.env.XXXXXX")"
{
    printf 'export PATH=%q:$PATH\n' "/root/.pyenv/versions/3.11.15/bin"
    printf 'export GOAAISEO_ROOT=%q\n' "$WORKSPACE/goaaiseo"
    printf 'export GOAAISEO_BLUEPRINT=%q\n' "$WORKSPACE/goaaiseo/docs/blueprint"
    printf 'export GSA_SINK=%q\n' "jsonfile"
    printf 'export GSA_SINK_PATH=%q\n' "$WORKSPACE/goaaiseo-seo-adapter/out/site.graph.json"
    printf 'export GSA_MIN_CONFIDENCE=%q\n' "0.7"
    printf 'export SCRAPETOOL_OUTPUT=%q\n' "$WORKSPACE/ScrapeToolAi/output"
    printf 'export SCRAPETOOL_IMPORTS=%q\n' "$WORKSPACE/ScrapeToolAi/imports"
    printf 'export KIRO_SKILLS_DIR=%q\n' "$SKILLS_TARGET"
    printf 'export AIBRAIN_ROOT=%q\n' "$WORKSPACE/AIBrain"
} > "$ENV_TMP"
mv -f "$ENV_TMP" "$SUPERBRAIN_DIR/.env"

printf '%s\n' '── Final exact verification ──'
SUPERBRAIN_WORKSPACE="$WORKSPACE" KIRO_DIR="$KIRO_DIR" bash "$SUPERBRAIN_DIR/scripts/verify.sh"

# The marker is the final commit point. Any earlier failure exits under set -e,
# leaving no success marker. The same-filesystem rename makes publication atomic.
MARKER_TMP="$(mktemp "$SUPERBRAIN_DIR/.bootstrapped.XXXXXX")"
printf 'verified\n' > "$MARKER_TMP"
mv -f "$MARKER_TMP" "$MARKER"

printf '\n╔══════════════════════════════════════════════════════════════════╗\n'
printf '║  ✅ SUPERBRAIN BOOTSTRAP COMPLETE                               ║\n'
printf '╠══════════════════════════════════════════════════════════════════╣\n'
printf '║  Exact skill ownership, packages, CLIs, and workspace verified. ║\n'
printf '╚══════════════════════════════════════════════════════════════════╝\n'
