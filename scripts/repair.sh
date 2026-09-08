#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# repair.sh — Fix a broken component.
#
# Usage:
#   repair.sh                 # re-run install steps for every repo
#   repair.sh <repo-name>     # sync + reinstall one repo from the manifest
#   repair.sh skills          # reinstall every skill-providing repo
#   repair.sh packages        # reinstall every pip-installing repo
#   repair.sh list            # show repairable targets
#
# Two things the previous version got wrong, both fixed here:
#   1. `git pull ... || true` reported success even when the pull was refused.
#      AIBrain mutates tracked files constantly, so its tree is almost always
#      dirty and the pull ALWAYS failed silently while printing "✓ updated".
#   2. `cd "$path"` without a subshell leaked the working directory into later
#      functions in the same invocation.
# ═══════════════════════════════════════════════════════════════════════════════
set -uo pipefail

# shellcheck source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

PYTHON_BIN="$(sb_manifest field python_bin 2>/dev/null || true)"
[ -n "$PYTHON_BIN" ] && [ -d "$PYTHON_BIN" ] && export PATH="$PYTHON_BIN:$PATH"

WORKSPACE="$(sb_workspace)"

echo "🔧 SuperBrain — Repair"

# sync_repo <name> <github> <branch>
# Honest about failure. Never claims success it did not achieve, and never
# destroys a dirty working tree.
sync_repo() {
    local name="$1" github="$2" branch="$3"
    local path="$WORKSPACE/$name"

    if [ ! -d "$path/.git" ]; then
        if [ -e "$path" ]; then
            sb_warn "$name exists but is not a git repo — leaving it alone."
            sb_info "Move or delete '$path' yourself, then re-run. Refusing to rm -rf a directory that may hold your work."
            return 1
        fi
        local clone_args=()
        [ "$branch" != "-" ] && clone_args+=(--branch "$branch" --single-branch)
        run_step "$name — clone failed" "$WORKSPACE" \
            "git clone --quiet ${clone_args[*]:-} https://github.com/$github.git '$path'" \
            && sb_ok "$name cloned"
        return
    fi

    if sb_git_dirty "$path"; then
        sb_warn "$name has uncommitted changes — skipping pull (this is not a failure)"
        sb_info "$(git -C "$path" status --porcelain | wc -l | tr -d ' ') modified path(s); commit or stash to allow updates"
        return 0
    fi

    local before after
    before="$(sb_git_head "$path")"
    if run_step "$name — pull failed" "$path" "git pull --quiet --ff-only"; then
        after="$(sb_git_head "$path")"
        if [ "$before" = "$after" ]; then
            sb_ok "$name already up to date (${after:0:8})"
        else
            sb_ok "$name updated ${before:0:8} -> ${after:0:8}"
        fi
    fi
}

reinstall() {
    local name="$1"
    local path="$WORKSPACE/$name"
    [ "$name" = "self" ] && path="$SB_ROOT"
    if [ ! -d "$path" ]; then
        sb_fail "$name — directory missing"
        return 1
    fi
    local steps
    steps="$(sb_manifest steps "$name" install)"
    if [ -z "$steps" ]; then
        sb_info "$name (no install steps)"
        return 0
    fi
    local failed=0
    while IFS= read -r step; do
        [ -n "$step" ] || continue
        run_step "$name — step failed" "$path" "$step" || failed=1
    done <<< "$steps"
    [ "$failed" -eq 0 ] && sb_ok "$name reinstalled"
    return $failed
}

repos_tsv="$(sb_manifest repos)"

target="${1:-all}"
case "$target" in
    list)
        echo ""
        echo "Repairable targets:"
        printf '%s\n' "$repos_tsv" | awk -F'\t' '{ printf "  %-24s %s\n", $1, $2 }'
        echo "  self                     (SuperBrain steering + skill)"
        echo ""
        echo "Groups: all, skills, packages"
        exit 0
        ;;
    all)
        echo ""
        while IFS=$'\t' read -r name _g _b _p _s; do
            [ -n "$name" ] || continue
            reinstall "$name"
        done <<< "$repos_tsv"
        reinstall "self"
        ;;
    skills)
        echo ""
        while IFS=$'\t' read -r name _g _b _p skills_dir; do
            [ -n "$name" ] || continue
            [ "$skills_dir" = "-" ] && continue
            reinstall "$name"
        done <<< "$repos_tsv"
        reinstall "self"
        ;;
    packages)
        echo ""
        while IFS=$'\t' read -r name _g _b _p _s; do
            [ -n "$name" ] || continue
            if sb_manifest steps "$name" install | grep -q '^pip install'; then
                reinstall "$name"
            fi
        done <<< "$repos_tsv"
        ;;
    self)
        echo ""
        reinstall "self"
        ;;
    *)
        line="$(printf '%s\n' "$repos_tsv" | awk -F'\t' -v n="$target" '$1 == n')"
        if [ -z "$line" ]; then
            echo "repair.sh: unknown target '$target'. Try: repair.sh list" >&2
            exit 2
        fi
        echo ""
        IFS=$'\t' read -r name github branch _p _s <<< "$line"
        sync_repo "$name" "$github" "$branch"
        reinstall "$name"
        ;;
esac

echo ""
if [ "$SB_ERRORS" -eq 0 ]; then
    echo "✅ Repair complete — $SB_WARNINGS warning(s). Run verify.sh to confirm."
else
    echo "❌ Repair finished with $SB_ERRORS error(s) — output above."
fi
exit "$SB_ERRORS"
