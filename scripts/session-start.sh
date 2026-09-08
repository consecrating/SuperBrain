#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# session-start.sh — SessionStart hook entrypoint.
#
# The hook used to be:
#   bootstrap.sh 2>&1 | tail -30
# A pipeline exits with the status of its LAST command, so that reported success
# no matter how badly bootstrap.sh failed. This wrapper keeps the output short
# without throwing away the exit status.
# ═══════════════════════════════════════════════════════════════════════════════
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$ROOT/.bootstrap.log"

if bash "$ROOT/scripts/bootstrap.sh" --quiet > "$LOG" 2>&1; then
    tail -20 "$LOG"
    exit 0
fi

status=$?
echo "SuperBrain bootstrap FAILED (exit $status). Last 40 lines:"
tail -40 "$LOG"
echo ""
echo "Full log: $LOG"
echo "Retry with: bash $ROOT/scripts/bootstrap.sh --force"
exit "$status"
