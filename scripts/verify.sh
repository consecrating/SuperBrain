#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# verify.sh — Health check. Changes nothing.
#
# Every check comes from manifest.json, so this cannot drift out of sync with
# what bootstrap.sh actually installs.
#
# Exit 0 = healthy, non-zero = number of errors.
# ═══════════════════════════════════════════════════════════════════════════════
set -uo pipefail

# shellcheck source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

PYTHON_BIN="$(sb_manifest field python_bin 2>/dev/null || true)"
[ -n "$PYTHON_BIN" ] && [ -d "$PYTHON_BIN" ] && export PATH="$PYTHON_BIN:$PATH"

WORKSPACE="$(sb_workspace)"
KIRO_DIR="$(sb_kiro_dir)"
KIRO_SKILLS="$(sb_skills_dir)"

echo ""
echo "🔍 SuperBrain — Verification (manifest v$(sb_manifest field version))"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ─── Repositories, incl. lock drift ─────────────────────────────────────────

sb_head "📦 Repositories"
while IFS=$'\t' read -r name _github _branch _priority _skills_dir; do
    [ -n "$name" ] || continue
    path="$WORKSPACE/$name"
    if [ ! -d "$path/.git" ]; then
        sb_fail "$(printf '%-24s' "$name") MISSING"
        continue
    fi
    head_sha="$(sb_git_head "$path")"
    detail="${head_sha:0:8}"
    if locked="$(sb_lock_read "$name")"; then
        if [ "$head_sha" != "$locked" ]; then
            detail="$detail (lock says ${locked:0:8} — DRIFTED)"
        fi
    else
        detail="$detail (unlocked)"
    fi
    sb_git_dirty "$path" && detail="$detail [dirty]"
    sb_ok "$(printf '%-24s' "$name") $detail"
done < <(sb_manifest repos)

# ─── Declared verify steps ──────────────────────────────────────────────────

sb_head "🔧 Declared checks"
check_target() {
    local label="$1" path="$2" steps ok=1
    steps="$(sb_manifest steps "$label" verify)"
    [ -n "$steps" ] || return 0
    while IFS= read -r step; do
        [ -n "$step" ] || continue
        if ! run_quiet "$path" "$step"; then
            sb_fail "$(printf '%-24s' "$label") failed: $step"
            ok=0
        fi
    done <<< "$steps"
    [ "$ok" -eq 1 ] && sb_ok "$(printf '%-24s' "$label") all checks pass"
}
while IFS=$'\t' read -r name _github _branch _priority _skills_dir; do
    [ -n "$name" ] || continue
    check_target "$name" "$WORKSPACE/$name"
done < <(sb_manifest repos)
check_target "self" "$SB_ROOT"

# ─── Skills: count, collisions, orphans ─────────────────────────────────────

sb_head "🎯 Skills"
SOURCES="$(
    while IFS=$'\t' read -r repo dir; do
        [ -d "$dir" ] || continue
        for skill in "$dir"/*/; do
            [ -d "$skill" ] || continue
            printf '%s\t%s\n' "$(basename "$skill")" "$repo"
        done
    done < <(sb_manifest skill-sources) | sort
)"
declared="$(printf '%s\n' "$SOURCES" | cut -f1 | sort -u | grep -c . || true)"
installed="$(find "$KIRO_SKILLS" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"

if [ "$declared" -eq "$installed" ]; then
    sb_ok "$installed installed, $declared declared — in sync"
else
    sb_warn "$installed installed but $declared declared"
fi

while IFS= read -r dupe; do
    [ -n "$dupe" ] || continue
    owners="$(printf '%s\n' "$SOURCES" | awk -F'\t' -v s="$dupe" '$1 == s { printf "%s ", $2 }')"
    sb_warn "collision: '$dupe' from [ ${owners}]"
done < <(printf '%s\n' "$SOURCES" | cut -f1 | sort | uniq -d)

for installed_dir in "$KIRO_SKILLS"/*/; do
    [ -d "$installed_dir" ] || continue
    skill="$(basename "$installed_dir")"
    printf '%s\n' "$SOURCES" | cut -f1 | grep -qxF "$skill" \
        || sb_warn "orphan (declared by no repo): $skill"
done

# ─── Steering ───────────────────────────────────────────────────────────────

sb_head "📋 Steering"
for steer in "$KIRO_DIR"/steering/*.md; do
    [ -f "$steer" ] || { sb_warn "no steering files found"; break; }
    sb_ok "$(basename "$steer")"
done

# ─── Sentinel ───────────────────────────────────────────────────────────────

sb_head "🔖 Bootstrap state"
if [ -f "$SB_SENTINEL" ]; then
    sb_ok "sentinel: $(head -1 "$SB_SENTINEL")"
else
    sb_warn "no sentinel — bootstrap has not completed successfully"
fi
if [ -f "$SB_LOCKFILE" ]; then
    sb_ok "lockfile: $(wc -l < "$SB_LOCKFILE" | tr -d ' ') pinned repo(s)"
else
    sb_warn "no superbrain.lock — versions are unpinned (bootstrap.sh --update-lock)"
fi

# ─── Summary ────────────────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$SB_ERRORS" -eq 0 ] && [ "$SB_WARNINGS" -eq 0 ]; then
    echo "✅ HEALTHY — $installed skills, no warnings"
elif [ "$SB_ERRORS" -eq 0 ]; then
    echo "⚠️  OK — $SB_WARNINGS warning(s), no errors"
else
    echo "❌ UNHEALTHY — $SB_ERRORS error(s), $SB_WARNINGS warning(s)"
    echo "   Run: bash $SB_ROOT/scripts/bootstrap.sh --force"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
exit "$SB_ERRORS"
