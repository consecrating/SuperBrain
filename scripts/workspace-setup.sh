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

export PATH="/root/.pyenv/versions/3.11.15/bin:$PATH"
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
