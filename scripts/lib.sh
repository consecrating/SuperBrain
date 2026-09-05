#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# SuperBrain — lib.sh
#
# Shared library sourced by bootstrap.sh, verify.sh, repair.sh, selftest.sh.
# Provides:
#   • manifest parsing (jq → python3 → hardcoded fallback) — single source of truth
#   • python runtime autodetection (manifest → pyenv → system) — no hardcoded version
#   • path resolution (workspace / kiro dir)
#   • logging helpers (stdout + optional logfile)
#
# NOTHING here uses `set -e`; it is meant to be sourced. Callers own their own
# error handling. Every lookup has a hardcoded fallback so the bootstrap contract
# ("connect and everything just works") never breaks even if manifest.json is
# missing, malformed, or the environment lacks jq/python3.
# ═══════════════════════════════════════════════════════════════════════════════

# ─── Locate ourselves & the manifest ────────────────────────────────────────
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SUPERBRAIN_DIR="${SUPERBRAIN_DIR:-$(cd "$_LIB_DIR/.." && pwd)}"
MANIFEST="${MANIFEST:-$SUPERBRAIN_DIR/manifest.json}"

# ─── Hardcoded fallbacks (last line of defense) ──────────────────────────────
# Order matters: this is the install/verify order. Format: "name|github"
_FALLBACK_REPOS=(
    "All-Skills|consecrating/All-Skills"
    "Claude-Power|consecrating/Claude-Power"
    "AIBrain|consecrating/AIBrain"
    "ScrapeToolAi|consecrating/ScrapeToolAi"
    "goaaiseo-seo-adapter|consecrating/goaaiseo-seo-adapter"
    "goaaiseo|consecrating/goaaiseo"
    "Sanctify-Hivemind|consecrating/Sanctify-Hivemind"
)
_FALLBACK_WORKSPACE="/projects/sandbox"
_FALLBACK_KIRO="/projects/.kiro"
_FALLBACK_PYENV="/root/.pyenv/versions/3.11.15/bin"

# ─── Logging ─────────────────────────────────────────────────────────────────
# Set SUPERBRAIN_LOG to a file path to also capture output there.
SUPERBRAIN_LOG="${SUPERBRAIN_LOG:-}"

_log_raw() {
    # $1 = full line already formatted
    printf '%s\n' "$1"
    if [ -n "$SUPERBRAIN_LOG" ]; then
        printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$SUPERBRAIN_LOG" 2>/dev/null || true
    fi
}
log()      { _log_raw "$*"; }
log_ok()   { _log_raw "  ✓ $*"; }
log_warn() { _log_raw "  ⚠ $*"; }
log_err()  { _log_raw "  ✗ $*"; }
log_step() { _log_raw "$*"; }

# ─── Manifest helpers ────────────────────────────────────────────────────────

# manifest_available: 0 (true) if the manifest exists and is parseable.
manifest_available() {
    [ -f "$MANIFEST" ] || return 1
    if command -v jq >/dev/null 2>&1; then
        jq -e . "$MANIFEST" >/dev/null 2>&1 && return 0 || return 1
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$MANIFEST" >/dev/null 2>&1 && return 0 || return 1
    fi
    return 1
}

# manifest_repos: emit "name|github" per line, preserving manifest order.
# Falls back to the hardcoded list if the manifest can't be read.
manifest_repos() {
    if manifest_available; then
        if command -v jq >/dev/null 2>&1; then
            jq -r '.repositories[] | "\(.name)|\(.github)"' "$MANIFEST" 2>/dev/null && return 0
        elif command -v python3 >/dev/null 2>&1; then
            python3 - "$MANIFEST" <<'PY' 2>/dev/null && return 0
import json,sys
d=json.load(open(sys.argv[1]))
for r in d.get("repositories",[]):
    print(f"{r['name']}|{r['github']}")
PY
        fi
    fi
    # Fallback
    printf '%s\n' "${_FALLBACK_REPOS[@]}"
}

# manifest_repos_full: emit "name|github|ref" per line. ref is the optional
# git ref (branch/tag/sha) to pin a repo to; empty when unspecified.
manifest_repos_full() {
    if manifest_available; then
        if command -v jq >/dev/null 2>&1; then
            jq -r '.repositories[] | "\(.name)|\(.github)|\(.ref // "")"' "$MANIFEST" 2>/dev/null && return 0
        elif command -v python3 >/dev/null 2>&1; then
            python3 - "$MANIFEST" <<'PY' 2>/dev/null && return 0
import json,sys
d=json.load(open(sys.argv[1]))
for r in d.get("repositories",[]):
    print(f"{r['name']}|{r['github']}|{r.get('ref','') or ''}")
PY
        fi
    fi
    # Fallback: hardcoded list has no refs
    local line
    for line in "${_FALLBACK_REPOS[@]}"; do
        printf '%s|\n' "$line"
    done
}

# manifest_repo_names: just the names, one per line.
manifest_repo_names() {
    manifest_repos | cut -d'|' -f1
}

# manifest_repo_count: how many repos are declared.
manifest_repo_count() {
    manifest_repos | grep -c '|'
}

# manifest_top <key>: read a top-level scalar string from the manifest.
# Returns empty (non-zero) if absent/unreadable.
manifest_top() {
    local key="$1"
    manifest_available || return 1
    if command -v jq >/dev/null 2>&1; then
        local v
        v="$(jq -r --arg k "$key" '.[$k] // empty' "$MANIFEST" 2>/dev/null)"
        [ -n "$v" ] && { printf '%s\n' "$v"; return 0; }
        return 1
    elif command -v python3 >/dev/null 2>&1; then
        python3 - "$MANIFEST" "$key" <<'PY' 2>/dev/null
import json,sys
d=json.load(open(sys.argv[1]))
v=d.get(sys.argv[2])
if v: print(v)
PY
        return $?
    fi
    return 1
}

# ─── Path resolution ─────────────────────────────────────────────────────────

# resolve_workspace: manifest.workspace → $WORKSPACE env → hardcoded default.
# Only trusts a value that actually exists on disk; otherwise falls through.
resolve_workspace() {
    local w
    w="$(manifest_top workspace 2>/dev/null)"
    if [ -n "$w" ] && [ -d "$w" ]; then printf '%s\n' "$w"; return 0; fi
    if [ -n "${WORKSPACE:-}" ] && [ -d "${WORKSPACE}" ]; then printf '%s\n' "$WORKSPACE"; return 0; fi
    # Derive from our own location: SuperBrain lives inside the workspace.
    local guess; guess="$(cd "$SUPERBRAIN_DIR/.." && pwd)"
    if [ -d "$guess" ]; then printf '%s\n' "$guess"; return 0; fi
    printf '%s\n' "$_FALLBACK_WORKSPACE"
}

# resolve_kiro: $KIRO_DIR env → <workspace>/../.kiro if present → hardcoded default.
resolve_kiro() {
    if [ -n "${KIRO_DIR:-}" ]; then printf '%s\n' "$KIRO_DIR"; return 0; fi
    local ws; ws="$(resolve_workspace)"
    local guess; guess="$(cd "$ws/.." 2>/dev/null && pwd)/.kiro"
    if [ -d "$guess" ]; then printf '%s\n' "$guess"; return 0; fi
    printf '%s\n' "$_FALLBACK_KIRO"
}

# ─── Python autodetection ────────────────────────────────────────────────────
# detect_python_bin: print a directory to prepend to PATH that contains a usable
# python3. Preference order:
#   1. manifest.python (if it has a python3)
#   2. $_FALLBACK_PYENV (the known-good pinned interpreter)
#   3. newest pyenv 3.11.x, then any pyenv 3.1x
#   4. dir of whatever python3 is already on PATH (system)
detect_python_bin() {
    local cand

    # 1. Manifest-declared path
    cand="$(manifest_top python 2>/dev/null)"
    if [ -n "$cand" ] && [ -x "$cand/python3" ]; then printf '%s\n' "$cand"; return 0; fi

    # 2. Known-good pinned interpreter
    if [ -x "$_FALLBACK_PYENV/python3" ]; then printf '%s\n' "$_FALLBACK_PYENV"; return 0; fi

    # 3. Autodetect from pyenv — prefer 3.11.x, then highest 3.1x
    local pyenv_root="${PYENV_ROOT:-/root/.pyenv}/versions"
    if [ -d "$pyenv_root" ]; then
        cand="$(ls -1d "$pyenv_root"/3.11.*/bin 2>/dev/null | sort -V | tail -1)"
        if [ -n "$cand" ] && [ -x "$cand/python3" ]; then printf '%s\n' "$cand"; return 0; fi
        cand="$(ls -1d "$pyenv_root"/3.1*/bin 2>/dev/null | sort -V | tail -1)"
        if [ -n "$cand" ] && [ -x "$cand/python3" ]; then printf '%s\n' "$cand"; return 0; fi
    fi

    # 4. Whatever python3 is on PATH already
    if command -v python3 >/dev/null 2>&1; then
        dirname "$(command -v python3)"; return 0
    fi

    # Last resort: the pinned path even if unverified
    printf '%s\n' "$_FALLBACK_PYENV"
}

# activate_python: prepend the detected python bin dir to PATH (idempotent).
activate_python() {
    local bin; bin="$(detect_python_bin)"
    case ":$PATH:" in
        *":$bin:"*) : ;;             # already present
        *) export PATH="$bin:$PATH" ;;
    esac
    printf '%s\n' "$bin"
}

# ─── Resilient clone ─────────────────────────────────────────────────────────
# clone_one: resilient clone of a single repo into the workspace.
#   $1 name   $2 github-slug   $3 optional git ref (branch/tag/sha)
# Retries up to 3× with exponential backoff (2s → 4s → 8s), cleaning any partial
# clone between attempts. If the repo is already present and a ref is pinned, it
# fetches + checks out that ref. A bad ref warns but never fails the clone
# (the repo is still usable), preserving the bootstrap contract.
clone_one() {
    local name="$1" github="$2" ref="${3:-}"
    local ws="${WORKSPACE:-$(resolve_workspace)}"
    local path="$ws/$name"
    local attempt=1 max="${SUPERBRAIN_CLONE_RETRIES:-3}" delay=2

    if [ -d "$path/.git" ]; then
        if [ -n "$ref" ]; then
            git -C "$path" fetch --quiet --all 2>/dev/null || true
            if git -C "$path" checkout --quiet "$ref" 2>/dev/null; then
                log_ok "$name (already present, pinned @ $ref)"
            else
                log_warn "$name (present, but ref '$ref' checkout failed)"
            fi
        else
            log_ok "$name (already cloned)"
        fi
        return 0
    fi

    while [ "$attempt" -le "$max" ]; do
        if git clone "https://github.com/$github.git" "$path" --quiet 2>/dev/null; then
            if [ -n "$ref" ]; then
                if git -C "$path" checkout --quiet "$ref" 2>/dev/null; then
                    log_ok "$name (cloned @ $ref)"
                else
                    log_warn "$name (cloned, but ref '$ref' checkout failed)"
                fi
            else
                log_ok "$name (cloned)"
            fi
            return 0
        fi
        log_warn "$name clone attempt $attempt/$max failed; retry in ${delay}s..."
        rm -rf "$path" 2>/dev/null || true   # clean partial clone before retry
        sleep "$delay"
        delay=$((delay * 2))
        attempt=$((attempt + 1))
    done
    log_err "$name: clone failed after $max attempts ($github)"
    return 1
}

# ─── Manifest fingerprint (for --fast idempotency) ───────────────────────────
# manifest_hash: sha256 of manifest.json, or "no-manifest".
manifest_hash() {
    [ -f "$MANIFEST" ] || { printf 'no-manifest\n'; return 0; }
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$MANIFEST" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$MANIFEST" | awk '{print $1}'
    else
        # Fallback: size+mtime signature
        wc -c < "$MANIFEST" | tr -d ' '
    fi
}
