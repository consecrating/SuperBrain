#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# SuperBrain — bootstrap.sh
#
# Clones every repo declared in manifest.json, runs its declared install steps,
# wires the environment, and verifies the result.
#
# manifest.json is the SOURCE OF TRUTH. This script contains no per-repo
# knowledge — add a repo to the manifest and it is picked up here automatically.
#
# Usage:
#   bootstrap.sh                 # install (skips if already bootstrapped)
#   bootstrap.sh --force         # re-run even if the sentinel exists
#   bootstrap.sh --frozen        # check out the exact commits in superbrain.lock
#   bootstrap.sh --update-lock   # record current HEADs into superbrain.lock
#   bootstrap.sh --no-prune      # keep skills no longer declared by any repo
#   bootstrap.sh --quiet         # only warnings, errors and the summary
#
# Exit 0 = success. Non-zero = the number of errors. Failures print their output.
# ═══════════════════════════════════════════════════════════════════════════════
set -uo pipefail

# shellcheck source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

FORCE=0 FROZEN=0 UPDATE_LOCK=0 PRUNE=1 QUIET=0
for arg in "$@"; do
    case "$arg" in
        --force)       FORCE=1 ;;
        --frozen)      FROZEN=1 ;;
        --update-lock) UPDATE_LOCK=1 ;;
        --no-prune)    PRUNE=0 ;;
        --quiet)       QUIET=1 ;;
        -h|--help)     sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "bootstrap.sh: unknown option '$arg' (try --help)" >&2; exit 2 ;;
    esac
done

say() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }

PYTHON="$(sb_python)"
if [ -z "$PYTHON" ]; then
    echo "bootstrap.sh: no python3 on PATH — cannot read manifest.json" >&2
    exit 1
fi

# Put the manifest's pinned interpreter first, if it exists. Never silently
# assume it does.
PYTHON_BIN="$(sb_manifest field python_bin 2>/dev/null || true)"
if [ -n "$PYTHON_BIN" ]; then
    if [ -d "$PYTHON_BIN" ]; then
        export PATH="$PYTHON_BIN:$PATH"
    else
        sb_warn "manifest python_bin does not exist: $PYTHON_BIN (falling back to PATH python3)"
    fi
fi

WORKSPACE="$(sb_workspace)"
KIRO_DIR="$(sb_kiro_dir)"
KIRO_SKILLS="$(sb_skills_dir)"
VERSION="$(sb_manifest field version)"

say ""
say "╔══════════════════════════════════════════════════════════════════╗"
say "║  🧠 SuperBrain v$VERSION — Workspace Bootstrap                       ║"
say "╚══════════════════════════════════════════════════════════════════╝"
say ""
say "  Python:    $(python3 --version 2>&1)"
say "  Workspace: $WORKSPACE"
say "  Kiro dir:  $KIRO_DIR"
[ "$FROZEN" -eq 1 ] && say "  Mode:      FROZEN (superbrain.lock)"
say ""

# ─── Idempotency sentinel ────────────────────────────────────────────────────
# The old version documented this check in steering but never wrote the file, so
# the full bootstrap re-ran on every single session.

SENTINEL_KEY="v${VERSION}"
if [ -f "$SB_SENTINEL" ] && [ "$FORCE" -eq 0 ] && [ "$UPDATE_LOCK" -eq 0 ]; then
    if grep -qF "$SENTINEL_KEY" "$SB_SENTINEL" 2>/dev/null; then
        say "Already bootstrapped ($(head -1 "$SB_SENTINEL"))."
        say "Verifying instead — use --force to reinstall."
        say ""
        exec bash "$SB_ROOT/scripts/verify.sh"
    fi
    sb_info "Sentinel exists but is for a different manifest version — re-installing."
fi

# From here on we are committing to an install. Invalidate the sentinel FIRST so
# that it only ever exists if the MOST RECENT run succeeded. Without this, a
# successful run followed by a failed --force would leave the stale sentinel in
# place and the next session would skip bootstrap on a broken workspace.
rm -f "$SB_SENTINEL"

mkdir -p "$KIRO_SKILLS" "$KIRO_DIR/steering" "$KIRO_DIR/scripts" "$KIRO_DIR/hooks"

# ─── 1. Clone / sync repositories ───────────────────────────────────────────

sb_head "── 1/5 Repositories ──"

while IFS=$'\t' read -r name github branch _priority _skills_dir; do
    [ -n "$name" ] || continue
    path="$WORKSPACE/$name"

    if [ -d "$path/.git" ]; then
        sb_ok "$name (present)"
    else
        clone_args=()
        [ "$branch" != "-" ] && clone_args+=(--branch "$branch" --single-branch)
        if run_step "$name — clone failed" "$WORKSPACE" \
            "git clone --quiet ${clone_args[*]:-} https://github.com/$github.git '$path'"; then
            sb_ok "$name (cloned)"
        else
            continue
        fi
    fi

    if [ "$FROZEN" -eq 1 ]; then
        if locked="$(sb_lock_read "$name")"; then
            if [ "$(sb_git_head "$path")" = "$locked" ]; then
                sb_info "$name pinned at ${locked:0:8}"
            elif sb_git_dirty "$path"; then
                sb_warn "$name has uncommitted changes — refusing to check out ${locked:0:8}"
            else
                run_step "$name — checkout $locked" "$path" \
                    "git fetch --quiet origin && git checkout --quiet '$locked'" \
                    && sb_info "$name -> ${locked:0:8}"
            fi
        else
            sb_warn "$name absent from superbrain.lock (run --update-lock)"
        fi
    fi
done < <(sb_manifest repos)

# ─── 2. Skill collision detection ───────────────────────────────────────────
# Two repos shipping a skill with the same name silently overwrote each other.
# Detect it and name the winner rather than pretending it cannot happen.

sb_head "── 2/5 Skill sources ──"

COLLISION_REPORT="$(
    while IFS=$'\t' read -r repo dir; do
        [ -d "$dir" ] || continue
        for skill in "$dir"/*/; do
            [ -d "$skill" ] || continue
            printf '%s\t%s\n' "$(basename "$skill")" "$repo"
        done
    done < <(sb_manifest skill-sources) | sort
)"

DECLARED_SKILLS="$(printf '%s\n' "$COLLISION_REPORT" | cut -f1 | sort -u | grep -c . || true)"
say "  Declared skills: $DECLARED_SKILLS"

while IFS= read -r dupe; do
    [ -n "$dupe" ] || continue
    owners="$(printf '%s\n' "$COLLISION_REPORT" | awk -F'\t' -v s="$dupe" '$1 == s { printf "%s ", $2 }')"
    winner="$(printf '%s\n' "$owners" | awk '{ print $NF }')"
    sb_warn "collision: '$dupe' shipped by [ ${owners}] — last install wins: $winner"
done < <(printf '%s\n' "$COLLISION_REPORT" | cut -f1 | sort | uniq -d)

# ─── 3. Run declared install steps ──────────────────────────────────────────

sb_head "── 3/5 Install ──"

install_target() {
    local label="$1" path="$2" steps
    steps="$(sb_manifest steps "$label" install)"
    [ -n "$steps" ] || { sb_info "$label (nothing to install)"; return 0; }
    local failed=0
    while IFS= read -r step; do
        [ -n "$step" ] || continue
        run_step "$label — step failed" "$path" "$step" || failed=1
    done <<< "$steps"
    [ "$failed" -eq 0 ] && sb_ok "$label installed"
    return $failed
}

while IFS=$'\t' read -r name _github _branch _priority _skills_dir; do
    [ -n "$name" ] || continue
    path="$WORKSPACE/$name"
    [ -d "$path" ] || { sb_fail "$name — directory missing, skipping install"; continue; }
    install_target "$name" "$path"
done < <(sb_manifest repos)

install_target "self" "$SB_ROOT"

# ─── 4. Prune orphaned skills ───────────────────────────────────────────────
# Nothing ever removed skills deleted upstream, so orphans accumulated forever
# and the old "count >= 50" check could not detect them.

sb_head "── 4/5 Prune ──"

if [ "$PRUNE" -eq 0 ]; then
    sb_info "pruning disabled (--no-prune)"
elif [ -z "$COLLISION_REPORT" ]; then
    sb_warn "no skill sources resolved — refusing to prune (would delete everything)"
else
    pruned=0
    for installed in "$KIRO_SKILLS"/*/; do
        [ -d "$installed" ] || continue
        skill="$(basename "$installed")"
        if ! printf '%s\n' "$COLLISION_REPORT" | cut -f1 | grep -qxF "$skill"; then
            rm -rf "$installed"
            sb_info "pruned orphan: $skill"
            pruned=$((pruned + 1))
        fi
    done
    if [ "$pruned" -eq 0 ]; then
        sb_ok "no orphans"
    else
        sb_ok "pruned $pruned orphan(s)"
    fi
fi

# ─── 5. Environment, post-install, lockfile ─────────────────────────────────

sb_head "── 5/5 Environment ──"

ENV_FILE="$SB_ROOT/.env"
{
    echo "# Generated by bootstrap.sh — do not edit by hand."
    echo "# Regenerate: bash scripts/bootstrap.sh --force"
    # Values are written inside double quotes so that a literal $PATH in the
    # PATH entry expands at source-time, not now. Verified by tests/smoke.sh.
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        printf 'export %s="%s"\n' "${line%%=*}" "${line#*=}"
    done < <(sb_manifest env)
} > "$ENV_FILE"
sb_ok ".env written ($(grep -c '^export' "$ENV_FILE") vars)"

while IFS= read -r step; do
    [ -n "$step" ] || continue
    run_step "post-install step failed" "$SB_ROOT" "$step" || true
done < <(sb_manifest post-install)
sb_ok "post-install complete"

if [ "$UPDATE_LOCK" -eq 1 ]; then
    : > "$SB_LOCKFILE"
    while IFS=$'\t' read -r name _github _branch _priority _skills_dir; do
        [ -n "$name" ] || continue
        sha="$(sb_git_head "$WORKSPACE/$name")"
        [ -n "$sha" ] && sb_lock_write_entry "$name" "$sha"
    done < <(sb_manifest repos)
    sb_ok "superbrain.lock updated ($(wc -l < "$SB_LOCKFILE" | tr -d ' ') entries)"
fi

# ─── Verify ─────────────────────────────────────────────────────────────────

sb_head "── Verification ──"

run_verify() {
    local label="$1" path="$2" steps ok=1
    steps="$(sb_manifest steps "$label" verify)"
    [ -n "$steps" ] || return 0
    while IFS= read -r step; do
        [ -n "$step" ] || continue
        if ! run_quiet "$path" "$step"; then
            sb_fail "$label — verify failed: $step"
            ok=0
        fi
    done <<< "$steps"
    [ "$ok" -eq 1 ] && sb_ok "$label verified"
}

while IFS=$'\t' read -r name _github _branch _priority _skills_dir; do
    [ -n "$name" ] || continue
    run_verify "$name" "$WORKSPACE/$name"
done < <(sb_manifest repos)
run_verify "self" "$SB_ROOT"

SKILL_COUNT="$(find "$KIRO_SKILLS" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
if [ "$SKILL_COUNT" -eq "$DECLARED_SKILLS" ]; then
    sb_ok "skills installed: $SKILL_COUNT (matches manifest)"
else
    sb_warn "skills installed: $SKILL_COUNT but manifest declares $DECLARED_SKILLS"
fi

# ─── Summary ────────────────────────────────────────────────────────────────

say ""
if [ "$SB_ERRORS" -eq 0 ]; then
    printf '%s\n' "  Bootstrap timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ) | manifest $SENTINEL_KEY" > "$SB_SENTINEL"
    say "╔══════════════════════════════════════════════════════════════════╗"
    printf "║  ✅ SUPERBRAIN READY — %-3s skills, %-2s warning(s)%*s║\n" \
        "$SKILL_COUNT" "$SB_WARNINGS" 18 ""
    say "╚══════════════════════════════════════════════════════════════════╝"
    say "  Sentinel written — subsequent sessions verify instead of reinstalling."
    say ""
    exit 0
fi

say "╔══════════════════════════════════════════════════════════════════╗"
printf "║  ❌ BOOTSTRAP FAILED — %-2s error(s), %-2s warning(s)%*s║\n" \
    "$SB_ERRORS" "$SB_WARNINGS" 16 ""
say "╚══════════════════════════════════════════════════════════════════╝"
say "  Output from each failure is printed above. Sentinel NOT written."
say ""
exit "$SB_ERRORS"
