#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# smoke.sh — Tests that run without touching the real workspace.
#
# Everything is redirected into a scratch dir via SB_WORKSPACE / SB_KIRO_DIR, so
# this is safe to run anywhere, including CI with no network.
#
#   bash tests/smoke.sh
# ═══════════════════════════════════════════════════════════════════════════════
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

ok()   { printf '  \033[32mPASS\033[0m %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n'  "$1"; FAIL=$((FAIL + 1)); [ -n "${2:-}" ] && printf '       %s\n' "$2"; }

assert_ok()     { if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1" "expected success: $2"; fi; }
assert_fails()  { if eval "$2" >/dev/null 2>&1; then bad "$1" "expected failure: $2"; else ok "$1"; fi; }
assert_has()    { if eval "$2" 2>/dev/null | grep -qF "$3"; then ok "$1"; else bad "$1" "expected output containing '$3'"; fi; }

echo ""
echo "SuperBrain smoke tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

PY="$(command -v python3 || command -v python)"
M="$PY $ROOT/scripts/lib/manifest.py"

echo "manifest.json"
assert_ok    "valid JSON"                      "$PY -c 'import json;json.load(open(\"$ROOT/manifest.json\"))'"
assert_ok    "manifest.py runs"                "$M repos"
assert_has   "declares All-Skills"             "$M repos" "All-Skills"
assert_has   "declares 6 repos"                "$M repos | wc -l" "6"
assert_has   "version is a scalar"             "$M field version" "2."
assert_fails "unknown field errors"            "$M field nope.nope"
assert_fails "unknown repo errors"             "$M steps NoSuchRepo install"
assert_fails "bad phase errors"                "$M steps All-Skills explode"

echo ""
echo "placeholder expansion"
assert_has   "WORKSPACE expands"               "SB_WORKSPACE=/tmp/ws $M env" "/tmp/ws"
assert_has   "KIRO_SKILLS expands in steps"    "SB_KIRO_DIR=/tmp/k $M steps All-Skills install" "/tmp/k/skills"
assert_fails "no unexpanded placeholders left" "$M env | grep -q '\${'"
assert_fails "steps leave no placeholders"     "for r in All-Skills Claude-Power AIBrain ScrapeToolAi goaaiseo-seo-adapter goaaiseo self; do $M steps \$r install; $M steps \$r verify; done | grep -q '\${'"

echo ""
echo "skill sources"
assert_has   "reports skill-providing repos"   "$M skill-sources" "All-Skills"
assert_has   "includes self"                   "$M skill-sources" "SuperBrain"

echo ""
echo "scripts"
for s in bootstrap.sh verify.sh repair.sh session-start.sh; do
    assert_ok "$s parses"                      "bash -n $ROOT/scripts/$s"
done
assert_ok     "common.sh parses"               "bash -n $ROOT/scripts/lib/common.sh"
assert_ok     "bootstrap --help works"         "bash $ROOT/scripts/bootstrap.sh --help"
assert_fails  "bootstrap rejects bad flag"     "bash $ROOT/scripts/bootstrap.sh --nonsense"
assert_ok     "repair list works"              "bash $ROOT/scripts/repair.sh list"
assert_fails  "repair rejects bad target"      "bash $ROOT/scripts/repair.sh no-such-repo"

echo ""
echo "hook"
assert_ok    "hook is valid JSON"              "$PY -c 'import json;json.load(open(\"$ROOT/.kiro/hooks/auto-bootstrap.json\"))'"
assert_fails "hook does not pipe to tail (would mask exit status)" \
             "grep -q 'tail' $ROOT/.kiro/hooks/auto-bootstrap.json"

echo ""
echo "error surfacing"
# run_step must print captured output when a command fails, not swallow it.
assert_has   "run_step surfaces failure output" \
             "bash -c 'source $ROOT/scripts/lib/common.sh; run_step lbl / \"echo boom-marker >&2; exit 3\" || true'" \
             "boom-marker"
assert_fails "no blanket 2>/dev/null on install steps in bootstrap" \
             "grep -nE 'pip install.*2>/dev/null|git clone.*2>/dev/null' $ROOT/scripts/bootstrap.sh"

echo ""
echo "lockfile helpers"
assert_has   "lock round-trips a sha" \
             "bash -c 'export SB_ROOT=$ROOT; source $ROOT/scripts/lib/common.sh; SB_LOCKFILE=\$(mktemp); sb_lock_write_entry Foo abc123; sb_lock_read Foo'" \
             "abc123"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf 'passed %d, failed %d\n' "$PASS" "$FAIL"
echo ""
[ "$FAIL" -eq 0 ] || exit 1


# ─── Regression: sentinel must not survive a failed run ─────────────────────
# Found during development: bootstrap only WROTE the sentinel on success but
# never removed it, so success-then-failed-force left a stale sentinel and the
# next session skipped bootstrap on a broken workspace.
echo ""
echo "sentinel invalidation"
assert_ok "bootstrap invalidates sentinel before installing" \
          "grep -q 'rm -f \"\$SB_SENTINEL\"' $ROOT/scripts/bootstrap.sh"
assert_ok "sentinel is only written when SB_ERRORS is zero" \
          "grep -A2 'if \[ \"\$SB_ERRORS\" -eq 0 \]' $ROOT/scripts/bootstrap.sh | grep -q SB_SENTINEL"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf 'FINAL: passed %d, failed %d\n' "$PASS" "$FAIL"
echo ""
[ "$FAIL" -eq 0 ] || exit 1
