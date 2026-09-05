#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# workspace-setup.sh — Lightweight env setup (no clone/install, just vars+paths)
#
# Source this in any command to get the full environment:
#   source /projects/sandbox/SuperBrain/scripts/workspace-setup.sh
#
# Or prefix commands:
#   eval "$(cat /projects/sandbox/SuperBrain/scripts/workspace-setup.sh)" && gsa doctor
# ═══════════════════════════════════════════════════════════════════════════════

# Python: prefer pinned 3.11.15, else newest pyenv 3.11.x, else any pyenv 3.1x,
# else whatever python3 is on PATH. Self-contained so `eval "$(cat ...)"` works.
_SB_PY="/root/.pyenv/versions/3.11.15/bin"
[ -x "$_SB_PY/python3" ] || _SB_PY="$(ls -1d /root/.pyenv/versions/3.11.*/bin 2>/dev/null | sort -V | tail -1)"
[ -n "$_SB_PY" ] && [ -x "$_SB_PY/python3" ] || _SB_PY="$(ls -1d /root/.pyenv/versions/3.1*/bin 2>/dev/null | sort -V | tail -1)"
[ -n "$_SB_PY" ] && [ -x "$_SB_PY/python3" ] || _SB_PY="$(dirname "$(command -v python3 2>/dev/null)" 2>/dev/null)"
[ -n "$_SB_PY" ] && export PATH="$_SB_PY:$PATH"
unset _SB_PY
export GOAAISEO_ROOT="/projects/sandbox/goaaiseo"
export GOAAISEO_BLUEPRINT="/projects/sandbox/goaaiseo/docs/blueprint"
export GSA_SINK="jsonfile"
export GSA_SINK_PATH="/projects/sandbox/goaaiseo-seo-adapter/out/site.graph.json"
export GSA_MIN_CONFIDENCE="0.7"
export SCRAPETOOL_OUTPUT="/projects/sandbox/ScrapeToolAi/output"
export SCRAPETOOL_IMPORTS="/projects/sandbox/ScrapeToolAi/imports"
export KIRO_SKILLS_DIR="/projects/.kiro/skills"
export AIBRAIN_ROOT="/projects/sandbox/AIBrain"
export SUPERBRAIN_ROOT="/projects/sandbox/SuperBrain"
