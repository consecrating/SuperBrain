#!/usr/bin/env python3
"""
Predictive Bootstrap Engine - Hacker-Level SuperBrain Enhancement

This module analyzes prompts to predict which repos/skills are needed
and pre-clones them before the user even asks.

HACKER APPROACH:
- Don't wait for user to request - predict and pre-load
- Use keyword matching + heuristics for speed
- Cache predictions for recurring patterns
"""

import json
import os
import re
import subprocess
from pathlib import Path
from typing import Dict, List, Optional
from dataclasses import dataclass

# Repository definitions (from SuperBrain manifest)
REPOS = {
    "All-Skills": "consecrating/All-Skills",
    "Claude-Power": "consecrating/Claude-Power",
    "Claude-Opus5": "consecrating/Claude-Opus5",
    "AIBrain": "consecrating/AIBrain",
    "ScrapeToolAi": "consecrating/ScrapeToolAi",
    "goaaiseo-seo-adapter": "consecrating/goaaiseo-seo-adapter",
    "goaaiseo": "consecrating/goaaiseo",
}

# Keyword-to-repo mapping (hacker-style heuristics)
KEYWORD_MAP: Dict[str, List[str]] = {
    # Design/UX
    "design": ["All-Skills"],
    "ux": ["All-Skills"],
    "ui": ["All-Skills"],
    "wordpress": ["All-Skills"],
    "wp": ["All-Skills"],
    "block theme": ["All-Skills"],
    "plugin": ["All-Skills"],
    "grok": ["All-Skills"],
    
    # Engineering
    "python": ["Claude-Opus5", "Claude-Power"],
    "python3": ["Claude-Opus5", "Claude-Power"],
    "node": ["Claude-Power"],
    "javascript": ["Claude-Power"],
    "typescript": ["Claude-Power"],
    "react": ["Claude-Power"],
    "engineering": ["Claude-Power"],
    
    # Opus 5 optimization
    "opustoken": ["Claude-Opus5"],
    "token": ["Claude-Opus5"],
    "token-efficiency": ["Claude-Opus5"],
    "cache": ["Claude-Opus5"],
    "effort": ["Claude-Opus5"],
    "slim": ["Claude-Opus5"],
    
    # Scraping
    "scrape": ["ScrapeToolAi"],
    "scrapetool": ["ScrapeToolAi"],
    "web scrape": ["ScrapeToolAi"],
    "extract": ["ScrapeToolAi"],
    
    # SEO
    "seo": ["goaaiseo", "goaaiseo-seo-adapter"],
    "search engine": ["goaaiseo", "goaaiseo-seo-adapter"],
    "google": ["goaaiseo", "goaaiseo-seo-adapter"],
    "rank": ["goaaiseo", "goaaiseo-seo-adapter"],
    
    # Intelligence
    "memory": ["AIBrain"],
    "persist": ["AIBrain"],
    "learning": ["AIBrain"],
    "self-improve": ["AIBrain"],
    "self-heal": ["AIBrain"],
}

# Common patterns that indicate specific needs
PATTERN_MAP = {
    r"\b(browser|test|automate)\b.*\b(web|page|site)\b": ["playwright"],
    r"\b(git|github|pr|pull.*request)\b": ["Claude-Power"],
    r"\b(plugin|theme|wordpress)\b": ["All-Skills"],
    r"\b(scrape|extract|fetch|crawl)\b": ["ScrapeToolAi"],
    r"\b(seo|rank|search|traffic)\b": ["goaaiseo"],
}


def detect_keywords(prompt: str) -> List[str]:
    """Detect needed repos based on prompt keywords."""
    found = set()
    prompt_lower = prompt.lower()
    
    # Check keyword map
    for keyword, repos in KEYWORD_MAP.items():
        if keyword in prompt_lower:
            found.update(repos)
    
    # Check pattern map
    for pattern, repos in PATTERN_MAP.items():
        if re.search(pattern, prompt_lower):
            found.update(repos)
    
    return list(found)


def get_clone_path(repo_name: str) -> Path:
    """Get the clone path for a repo."""
    return Path("/projects/sandbox") / repo_name


def is_repo_cloned(repo_name: str) -> bool:
    """Check if a repo is already cloned."""
    path = get_clone_path(repo_name)
    return path.exists() and (path / ".git").is_dir()


def clone_repo(repo_name: str) -> bool:
    """Clone a repository."""
    github = REPOS.get(repo_name)
    if not github:
        print(f"Unknown repo: {repo_name}")
        return False
    
    path = get_clone_path(repo_name)
    
    if is_repo_cloned(repo_name):
        print(f"✓ {repo_name} already cloned")
        return True
    
    try:
        print(f"⏳ Cloning {repo_name}...")
        subprocess.run(
            ["git", "clone", f"https://github.com/{github}.git", str(path)],
            check=True,
            capture_output=True,
            text=True,
        )
        print(f"✓ {repo_name} cloned successfully")
        return True
    except subprocess.CalledProcessError as e:
        print(f"✗ Failed to clone {repo_name}: {e.stderr}")
        return False


def predict_bootstrap(prompt: str) -> Dict:
    """Predict what needs to be bootstrapped from a prompt."""
    keywords = detect_keywords(prompt)
    
    result = {
        "prompt": prompt,
        "detected_keywords": keywords,
        "needed_repos": [],
        "already_cloned": [],
        "to_clone": [],
    }
    
    for repo in keywords:
        if is_repo_cloned(repo):
            result["already_cloned"].append(repo)
        else:
            result["to_clone"].append(repo)
            result["needed_repos"].append(repo)
    
    return result


def bootstrap_needed_repos(prompt: str) -> Dict:
    """Predict and bootstrap needed repos from a prompt."""
    result = predict_bootstrap(prompt)
    
    cloned = []
    failed = []
    
    for repo in result["to_clone"]:
        if clone_repo(repo):
            cloned.append(repo)
        else:
            failed.append(repo)
    
    result["cloned"] = cloned
    result["failed"] = failed
    
    return result


def main():
    """Main entry point for CLI."""
    import sys
    
    if len(sys.argv) < 2:
        print("Usage: predictive-bootstrap <command> [args]")
        print("")
        print("Commands:")
        print("  detect <prompt>  - Detect needed repos")
        print("  clone <repo>     - Clone specific repo")
        print("  predict <prompt> - Predict and bootstrap")
        print("  status           - Show current clone status")
        sys.exit(0)
    
    command = sys.argv[1]
    
    if command == "detect":
        if len(sys.argv) < 3:
            print("Usage: predictive-bootstrap detect <prompt>")
            sys.exit(1)
        prompt = " ".join(sys.argv[2:])
        result = predict_bootstrap(prompt)
        print(json.dumps(result, indent=2))
    
    elif command == "clone":
        if len(sys.argv) < 3:
            print("Usage: predictive-bootstrap clone <repo_name>")
            sys.exit(1)
        repo = sys.argv[2]
        success = clone_repo(repo)
        sys.exit(0 if success else 1)
    
    elif command == "predict":
        if len(sys.argv) < 3:
            print("Usage: predictive-bootstrap predict <prompt>")
            sys.exit(1)
        prompt = " ".join(sys.argv[2:])
        result = bootstrap_needed_repos(prompt)
        print(json.dumps(result, indent=2))
    
    elif command == "status":
        print("Current repository status:")
        for repo in REPOS:
            status = "✓" if is_repo_cloned(repo) else "✗"
            print(f"  {status} {repo}")
    
    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == "__main__":
    main()
