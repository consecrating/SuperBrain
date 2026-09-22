#!/usr/bin/env python3
"""
AI-Powered Repo Recommendation Engine for SuperBrain

Analyzes your workflow and suggests new repos to install
based on what you're actually doing.

HACKER APPROACH:
- Analyze actual usage patterns
- Suggest complementary tools
- Flag redundant installations
- Predict future needs
"""

import json
import os
import subprocess
from pathlib import Path
from typing import Dict, List, Optional
from dataclasses import dataclass


# Known repos with capabilities
KNOWN_REPOS = {
    "All-Skills": {
        "github": "consecrating/All-Skills",
        "purpose": "44 design/UX/WordPress Kiro skills",
        "keywords": ["design", "ux", "ui", "wordpress", "wp", "block", "theme", "plugin"],
        "depends_on": [],
    },
    "Claude-Power": {
        "github": "consecrating/Claude-Power",
        "purpose": "17 engineering Kiro skills + MCP server",
        "keywords": ["engineering", "python", "js", "react", "git", "security", "refactor"],
        "depends_on": [],
    },
    "Claude-Opus5": {
        "github": "consecrating/Claude-Opus5",
        "purpose": "Real Opus 5 power - MCP server (effort control, cache)",
        "keywords": ["opustoken", "token", "cache", "effort", "slim"],
        "depends_on": [],
    },
    "AIBrain": {
        "github": "consecrating/AIBrain",
        "purpose": "Persistent intelligence layer",
        "keywords": ["memory", "persist", "learning", "self-improve", "self-heal"],
        "depends_on": [],
    },
    "ScrapeToolAi": {
        "github": "consecrating/ScrapeToolAi",
        "purpose": "Stealth web scraping framework",
        "keywords": ["scrape", "extract", "fetch", "crawl", "web"],
        "depends_on": [],
    },
    "goaaiseo-seo-adapter": {
        "github": "consecrating/goaaiseo-seo-adapter",
        "purpose": "SEO integration adapter",
        "keywords": ["seo", "search", "rank", "traffic", "google"],
        "depends_on": ["goaaiseo"],
    },
    "goaaiseo": {
        "github": "consecrating/goaaiseo",
        "purpose": "Autonomous SEO OS blueprint",
        "keywords": ["seo", "search", "rank", "traffic"],
        "depends_on": [],
    },
    # Additional useful repos
    "serenity-mcp": {
        "github": "oraios/serena",
        "purpose": "Token-saving symbol-level code retrieval",
        "keywords": ["token", "serenity", "symbol", "code", "retrieve"],
        "depends_on": [],
        "install": "uvx --from git+https://github.com/oraios/serena serenity start-mcp-server",
    },
    "playwright-mcp": {
        "github": "microsoft/playwright",
        "purpose": "Browser automation MCP",
        "keywords": ["browser", "automation", "test", "screenshot", "playwright"],
        "depends_on": [],
        "install": "npx -y @playwright/mcp@latest",
    },
    "github-power": {
        "github": "modelcontextprotocol/server-github",
        "purpose": "GitHub integration MCP",
        "keywords": ["github", "git", "repo", "pr", "issue"],
        "depends_on": [],
        "install": "npx -y @modelcontextprotocol/server-github",
    },
    "agent-browser": {
        "github": "vercel-labs/agent-browser",
        "purpose": "Browser automation agent",
        "keywords": ["browser", "agent", "navigate", "click"],
        "depends_on": [],
        "install": "npx -y @agent-browser/mcp@latest",
    },
}


def get_installed_repos() -> List[str]:
    """Get list of currently installed repos."""
    installed = []
    for repo_name in KNOWN_REPOS:
        path = Path(f"/projects/sandbox/{repo_name}")
        if path.exists() and (path / ".git" if repo_name != "serenity-mcp" else path).exists():
            installed.append(repo_name)
    return installed


def analyze_prompt(prompt: str) -> Dict[str, float]:
    """Analyze prompt to find needed capabilities."""
    scores = {}
    prompt_lower = prompt.lower()
    
    for repo_name, repo_info in KNOWN_REPOS.items():
        score = 0
        for keyword in repo_info.get("keywords", []):
            if keyword in prompt_lower:
                score += 1
        
        if score > 0:
            scores[repo_name] = score / len(repo_info.get("keywords", 1))
    
    return dict(sorted(scores.items(), key=lambda x: x[1], reverse=True))


def recommend_repos(prompt: str) -> Dict:
    """Recommend repos based on prompt."""
    prompt_scores = analyze_prompt(prompt)
    installed = set(get_installed_repos())
    
    recommendations = []
    
    for repo_name, score in prompt_scores.items():
        if repo_name not in installed:
            repo_info = KNOWN_REPOS[repo_name]
            recommendations.append({
                "name": repo_name,
                "score": round(score * 100, 1),
                "purpose": repo_info["purpose"],
                "keywords_matched": [k for k in repo_info.get("keywords", []) if k in prompt.lower()],
                "install_command": repo_info.get("install", f"pip install {repo_name}"),
            })
    
    # Add high-priority defaults if nothing matches
    if not recommendations:
        recommendations = [
            {
                "name": "serenity-mcp",
                "score": 80,
                "purpose": "Token-saving symbol-level code retrieval",
                "keywords_matched": ["efficiency", "token"],
                "install_command": "uvx --from git+https://github.com/oraios/serena serenity start-mcp-server",
            },
            {
                "name": "playwright-mcp",
                "score": 70,
                "purpose": "Browser automation",
                "keywords_matched": ["test", "browser"],
                "install_command": "npx -y @playwright/mcp@latest",
            },
        ]
    
    return {
        "prompt": prompt,
        "installed": list(installed),
        "recommendations": recommendations,
        "total_matched": len(prompt_scores),
    }


def analyze_setup() -> Dict:
    """Analyze current setup for improvements."""
    installed = get_installed_repos()
    
    analysis = {
        "installed_count": len(installed),
        "coverage": [],
        "gaps": [],
        "redundancies": [],
        "suggestions": [],
    }
    
    # Check for coverage gaps
    capabilities = {
        "design": ["All-Skills"],
        "engineering": ["Claude-Power"],
        "token_optimization": ["Claude-Opus5"],
        "memory": ["AIBrain"],
        "scraping": ["ScrapeToolAi"],
        "seo": ["goaaiseo", "goaaiseo-seo-adapter"],
        "browser_automation": ["playwright-mcp", "agent-browser"],
        "token_saving": ["serenity-mcp"],
    }
    
    for capability, repos in capabilities.items():
        found = any(r in installed for r in repos)
        if found:
            analysis["coverage"].append(capability)
        else:
            analysis["gaps"].append(capability)
    
    # Check for redundancies
    if "Claude-Power" in installed and "AIBrain" in installed:
        analysis["suggestions"].append("Claude-Power and AIBrain have overlapping skills. Consider merging.")
    
    # Add default suggestions
    if len(installed) < 5:
        analysis["suggestions"].append("Consider adding serenity-mcp for token savings (45% reduction).")
    
    if "playwright-mcp" not in installed:
        analysis["suggestions"].append("Add playwright-mcp for browser automation (test, screenshot).")
    
    if "serenity-mcp" not in installed:
        analysis["suggestions"].append("Add serenity-mcp for token-efficient code reads.")
    
    return analysis


def install_recommendation(repo_name: str) -> Dict:
    """Install a recommended repo."""
    repo_info = KNOWN_REPOS.get(repo_name)
    if not repo_info:
        return {"error": f"Unknown repo: {repo_name}"}
    
    install_cmd = repo_info.get("install")
    if not install_cmd:
        return {"error": f"No install command for {repo_name}"}
    
    try:
        result = subprocess.run(
            install_cmd,
            shell=True,
            capture_output=True,
            text=True,
            cwd="/projects/sandbox"
        )
        
        return {
            "installed": repo_name,
            "success": result.returncode == 0,
            "output": result.stdout[:500] if result.stdout else "",
            "error": result.stderr[:500] if result.stderr else "",
        }
    except Exception as e:
        return {
            "installed": repo_name,
            "success": False,
            "error": str(e),
        }


def main():
    """Main entry point for CLI."""
    import sys
    
    if len(sys.argv) < 2:
        print("Recommend - AI-Powered Repo Recommendations")
        print("")
        print("Usage: recommend <command> [args]")
        print("")
        print("Commands:")
        print("  status       - Analyze current setup")
        print("  suggest \"prompt\" - Get recommendations")
        print("  install <repo> - Install recommended repo")
        sys.exit(0)
    
    command = sys.argv[1]
    
    if command == "status":
        analysis = analyze_setup()
        print(json.dumps(analysis, indent=2))
    
    elif command == "suggest":
        if len(sys.argv) < 3:
            print("Usage: recommend suggest \"your prompt or task\"")
            sys.exit(1)
        prompt = " ".join(sys.argv[2:])
        recommendations = recommend_repos(prompt)
        print(json.dumps(recommendations, indent=2))
    
    elif command == "install":
        if len(sys.argv) < 3:
            print("Usage: recommend install <repo_name>")
            sys.exit(1)
        repo_name = sys.argv[2]
        result = install_recommendation(repo_name)
        print(json.dumps(result, indent=2))
    
    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == "__main__":
    main()
