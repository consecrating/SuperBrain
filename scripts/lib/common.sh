#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# common.sh — shared helpers. Source this; do not execute it.
#
# The single most important thing here is run_step(): the previous scripts piped
# every install command through `2>/dev/null`, so a failure produced either a
# silent abort (under `set -e`) or a cheerful "✓ installed" that was a lie.
# run_step captures output and PRINTS IT ON FAILURE.
# ═══════════════════════════════════════════════════════════════════════════════

# Resolve paths relative to this library, not the caller's cwd.
SB_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SB_ROOT="$(cd "$SB_LIB_DIR/../.." && pwd)"
export SB_LIB_DIR SB_ROOT

SB_MANIFEST="$SB_ROOT/scripts/lib/manifest.py"
SB_LOCKFILE="$SB_ROOT/superbrain.lock"
SB_SENTINEL="$SB_ROOT/.bootstrapped"
export SB_MANIFEST SB_LOCKFILE SB_SENTINEL

# ─── Manifest-derived config (overridable for tests) ─────────────────────────

sb_python() {
    if [ -n "${SB_PYTHON:-}" ]; then echo "$SB_PYTHON"; return; fi
    command -v python3 || command -v python
}

sb_manifest() { "$(sb_python)" "$SB_MANIFEST" "$@"; }

sb_workspace() { echo "${SB_WORKSPACE:-$(sb_manifest field workspace)}"; }
sb_kiro_dir()  { echo "${SB_KIRO_DIR:-$(sb_manifest field kiro_dir)}"; }
sb_skills_dir() { echo "$(sb_kiro_dir)/skills"; }

# ─── Output ─────────────────────────────────────────────────────────────────

SB_ERRORS=0
SB_WARNINGS=0

sb_ok()    { printf '  \033[32m✓\033[0m %s\n' "$*"; }
sb_warn()  { printf '  \033[33m⚠\033[0m %s\n' "$*"; SB_WARNINGS=$((SB_WARNINGS + 1)); }
sb_fail()  { printf '  \033[31m✗\033[0m %s\n' "$*"; SB_ERRORS=$((SB_ERRORS + 1)); }
sb_info()  { printf '  · %s\n' "$*"; }
sb_head()  { printf '\n\033[1m%s\033[0m\n' "$*"; }

# ─── The important one ──────────────────────────────────────────────────────

# run_step <label> <cwd> <shell-command>
# Returns the command's exit status. On failure, prints the captured output so
# the operator can actually see what broke. Never swallows stderr.
run_step() {
    local label="$1" cwd="$2" cmd="$3"
    local out status
    out="$(cd "$cwd" 2>/dev/null && eval "$cmd" 2>&1)"
    status=$?
    if [ "$status" -ne 0 ]; then
        sb_fail "$label"
        printf '      \033[31m└ exit %d\033[0m — command: %s\n' "$status" "$cmd"
        if [ -n "$out" ]; then
            printf '%s\n' "$out" | tail -15 | sed 's/^/        /'
        else
            printf '        (no output — command produced nothing on stdout or stderr)\n'
        fi
    fi
    return $status
}

# run_quiet <cwd> <shell-command> — same capture, no reporting. For probes.
run_quiet() {
    local cwd="$1" cmd="$2"
    ( cd "$cwd" 2>/dev/null && eval "$cmd" ) >/dev/null 2>&1
}

# ─── Git helpers ────────────────────────────────────────────────────────────

# sb_git_dirty <path> — 0 if the tree has uncommitted changes.
sb_git_dirty() {
    local path="$1"
    [ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]
}

sb_git_head() { git -C "$1" rev-parse HEAD 2>/dev/null; }

# ─── Lockfile ───────────────────────────────────────────────────────────────
# Plain "name<TAB>sha" lines. Avoids a JSON dependency in the shell path.

sb_lock_read() {
    local name="$1"
    [ -f "$SB_LOCKFILE" ] || return 1
    awk -v n="$name" -F'\t' '$1 == n { print $2; found = 1 } END { exit !found }' "$SB_LOCKFILE"
}

sb_lock_write_entry() {
    local name="$1" sha="$2" tmp
    tmp="$(mktemp)"
    if [ -f "$SB_LOCKFILE" ]; then
        grep -v -P "^\Q$name\E\t" "$SB_LOCKFILE" 2>/dev/null > "$tmp" \
            || awk -v n="$name" -F'\t' '$1 != n' "$SB_LOCKFILE" > "$tmp" 2>/dev/null \
            || true
    fi
    printf '%s\t%s\n' "$name" "$sha" >> "$tmp"
    sort -o "$tmp" "$tmp"
    mv "$tmp" "$SB_LOCKFILE"
}
