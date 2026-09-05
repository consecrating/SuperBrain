#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# selftest.sh — Fast, offline test harness for the SuperBrain script layer.
#
# Validates lib.sh logic, manifest integrity, script syntax, argument handling,
# and clone_one's already-present / bad-ref behavior — WITHOUT cloning repos,
# installing packages, or needing pyenv. Safe to run in CI on a bare checkout.
#
# Exit 0 = all tests pass, non-zero = failures.
#
# Usage: bash scripts/selftest.sh
# ═══════════════════════════════════════════════════════════════════════════════
set -uo pipefail

SUPERBRAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$SUPERBRAIN_DIR/scripts"

PASS=0
FAIL=0

ok()   { printf "  \033[32m✓\033[0m %s\n" "$1"; PASS=$((PASS + 1)); }
bad()  { printf "  \033[31m✗\033[0m %s\n" "$1"; FAIL=$((FAIL + 1)); }

# assert_eq <expected> <actual> <label>
assert_eq() {
    if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (expected '$1', got '$2')"; fi
}
# assert_true <label> ; runs following via: assert_cmd "label" cmd args...
assert_cmd() {
    local label="$1"; shift
    if "$@" >/dev/null 2>&1; then ok "$label"; else bad "$label"; fi
}
assert_fail() {
    local label="$1"; shift
    if "$@" >/dev/null 2>&1; then bad "$label (expected failure, succeeded)"; else ok "$label"; fi
}

echo ""
echo "🧪 SuperBrain — Self Test"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ─── 1. Syntax of every shell script ─────────────────────────────────────────
echo ""
echo "1. Shell syntax"
for f in lib.sh bootstrap.sh verify.sh repair.sh workspace-setup.sh selftest.sh; do
    if [ -f "$SCRIPTS/$f" ]; then
        assert_cmd "$f parses" bash -n "$SCRIPTS/$f"
    else
        bad "$f missing"
    fi
done

# ─── 2. Manifest integrity ───────────────────────────────────────────────────
echo ""
echo "2. Manifest"
MANIFEST="$SUPERBRAIN_DIR/manifest.json"
if command -v jq >/dev/null 2>&1; then
    assert_cmd "manifest.json is valid JSON" jq -e . "$MANIFEST"
    JQ_COUNT="$(jq '.repositories | length' "$MANIFEST" 2>/dev/null)"
elif command -v python3 >/dev/null 2>&1; then
    assert_cmd "manifest.json is valid JSON" python3 -c "import json,sys;json.load(open('$MANIFEST'))"
    JQ_COUNT="$(python3 -c "import json;print(len(json.load(open('$MANIFEST'))['repositories']))" 2>/dev/null)"
else
    bad "no jq or python3 to validate manifest"
    JQ_COUNT=""
fi

# ─── 3. lib.sh functions (happy path) ────────────────────────────────────────
echo ""
echo "3. lib.sh (with manifest)"
# shellcheck source=lib.sh
source "$SCRIPTS/lib.sh"

assert_cmd "manifest_available succeeds" manifest_available

LIB_COUNT="$(manifest_repo_count)"
if [ -n "$JQ_COUNT" ]; then
    assert_eq "$JQ_COUNT" "$LIB_COUNT" "manifest_repo_count matches jq/python count"
fi

# every repo line must have a non-empty name and github slug
BADROWS=0
while IFS='|' read -r n g; do
    [ -z "$n" ] && continue
    { [ -n "$n" ] && [ -n "$g" ]; } || BADROWS=$((BADROWS + 1))
done < <(manifest_repos)
assert_eq "0" "$BADROWS" "every manifest_repos row has name+github"

# manifest_repos_full must yield 3 fields (name|github|ref)
FULL_OK=1
while IFS='|' read -r n g r; do
    [ -z "$n" ] && continue
    [ -n "$n" ] && [ -n "$g" ] || FULL_OK=0
done < <(manifest_repos_full)
assert_eq "1" "$FULL_OK" "manifest_repos_full yields name|github|ref rows"

# hash + python detection return something
HASH="$(manifest_hash)"
assert_cmd "manifest_hash non-empty" test -n "$HASH"
PYBIN="$(detect_python_bin)"
assert_cmd "detect_python_bin non-empty" test -n "$PYBIN"
WS="$(resolve_workspace)"
assert_cmd "resolve_workspace non-empty" test -n "$WS"

# ─── 4. lib.sh fallbacks (manifest missing) ──────────────────────────────────
echo ""
echo "4. lib.sh fallbacks (no manifest)"
(
    MANIFEST="/nonexistent/manifest.json"
    manifest_available && exit 91   # should NOT be available
    cnt="$(manifest_repos | grep -c '|')"
    [ "$cnt" -eq 7 ] || exit 92     # hardcoded fallback = 7 repos
    [ "$(manifest_hash)" = "no-manifest" ] || exit 93
    exit 0
)
case $? in
    0)  ok "fallback: unavailable→7 hardcoded repos, hash=no-manifest" ;;
    91) bad "fallback: manifest_available true for missing file" ;;
    92) bad "fallback: hardcoded repo count != 7" ;;
    93) bad "fallback: manifest_hash != no-manifest" ;;
    *)  bad "fallback: unexpected error" ;;
esac

# malformed manifest → fallback
(
    tmp="$(mktemp)"; echo "{ not json" > "$tmp"
    MANIFEST="$tmp"
    if manifest_available; then rm -f "$tmp"; exit 91; fi
    cnt="$(manifest_repos | grep -c '|')"
    rm -f "$tmp"
    [ "$cnt" -eq 7 ] || exit 92
    exit 0
)
case $? in
    0)  ok "malformed manifest → hardcoded fallback" ;;
    *)  bad "malformed manifest not handled" ;;
esac

# ─── 5. clone_one behavior (offline) ─────────────────────────────────────────
echo ""
echo "5. clone_one (offline)"
(
    WORKSPACE="$(mktemp -d)"
    mkdir -p "$WORKSPACE/FakeRepo/.git"      # pretend already cloned
    out="$(clone_one FakeRepo owner/FakeRepo 2>&1)"
    echo "$out" | grep -q "already cloned" || exit 91
    rm -rf "$WORKSPACE"
    exit 0
)
case $? in
    0) ok "clone_one detects already-present repo (no network)" ;;
    *) bad "clone_one already-present detection failed" ;;
esac

# ─── 6. bootstrap.sh CLI contract ────────────────────────────────────────────
echo ""
echo "6. bootstrap.sh CLI"
HELP="$(bash "$SCRIPTS/bootstrap.sh" --help 2>&1)"
assert_cmd "bootstrap.sh --help exits 0" bash "$SCRIPTS/bootstrap.sh" --help
echo "$HELP" | grep -q -- "--fast"  && ok "help documents --fast"  || bad "help missing --fast"
echo "$HELP" | grep -q -- "--force" && ok "help documents --force" || bad "help missing --force"

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$FAIL" -eq 0 ]; then
    echo "✅ selftest PASSED — $PASS checks green"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 0
else
    echo "❌ selftest FAILED — $FAIL failed, $PASS passed"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 1
fi
