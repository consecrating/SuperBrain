#!/usr/bin/env python3
"""
Self-Healing Engine - Automated Dependency Resolution for SuperBrain

Automatically fixes broken installations, resolves conflicts, and
recovers from failures without user intervention.

HACKER APPROACH:
- Detect failures immediately
- Apply multiple fallback strategies
- Revert gracefully when needed
- Learn from failures to prevent recurrence
"""

import json
import os
import subprocess
import time
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass, field


# Component definitions
COMPONENTS = {
    "skills": {
        "path": "/projects/.kiro/skills",
        "verify": lambda: len(list(Path("/projects/.kiro/skills").glob("*/SKILL.md"))) > 40,
        "install": lambda: subprocess.run([
            "bash", "/projects/sandbox/SuperBrain/scripts/bootstrap.sh"
        ], capture_output=True).returncode == 0,
    },
    "mcp": {
        "path": "/projects/.kiro/mcp-servers",
        "verify": lambda: Path("/projects/.kiro/mcp-servers").exists(),
        "install": lambda: subprocess.run([
            "bash", "/projects/sandbox/SuperBrain/scripts/bootstrap.sh"
        ], capture_output=True).returncode == 0,
    },
    "aibrain": {
        "path": "/projects/sandbox/AIBrain",
        "verify": lambda: (
            Path("/projects/.kiro/steering/aibrain.md").exists() and
            Path("/projects/.kiro/skills/aibrain/SKILL.md").exists()
        ),
        "install": lambda: subprocess.run([
            "bash", "/projects/sandbox/AIBrain/scripts/install.sh"
        ], capture_output=True).returncode == 0,
    },
    "packages": {
        "path": None,
        "verify": lambda: (
            subprocess.run(["python3", "-c", "import scrapetoolai"], capture_output=True).returncode == 0 and
            subprocess.run(["python3", "-c", "from gsa import models"], capture_output=True).returncode == 0
        ),
        "install": lambda: subprocess.run([
            "pip", "install", "-e", "/projects/sandbox/ScrapeToolAi",
            "-e", "/projects/sandbox/goaaiseo-seo-adapter",
            "-e", "/projects/sandbox/Claude-Opus5"
        ], capture_output=True).returncode == 0,
    },
    "skills-all": {
        "path": "/projects/sandbox/All-Skills",
        "verify": lambda: Path("/projects/sandbox/All-Skills/install.sh").exists(),
        "install": lambda: subprocess.run([
            "git", "clone", "https://github.com/consecrating/All-Skills.git",
            "/projects/sandbox/All-Skills"
        ], capture_output=True).returncode == 0,
    },
    "skills-power": {
        "path": "/projects/sandbox/Claude-Power",
        "verify": lambda: Path("/projects/sandbox/Claude-Power/README.md").exists(),
        "install": lambda: subprocess.run([
            "git", "clone", "https://github.com/consecrating/Claude-Power.git",
            "/projects/sandbox/Claude-Power"
        ], capture_output=True).returncode == 0,
    },
    "skills-opus5": {
        "path": "/projects/sandbox/Claude-Opus5",
        "verify": lambda: Path("/projects/sandbox/Claude-Opus5/pyproject.toml").exists(),
        "install": lambda: subprocess.run([
            "git", "clone", "https://github.com/consecrating/Claude-Opus5.git",
            "/projects/sandbox/Claude-Opus5"
        ], capture_output=True).returncode == 0,
    },
}


def check_component(name: str) -> Tuple[bool, str]:
    """Check if a component is working."""
    component = COMPONENTS.get(name)
    if not component:
        return False, f"Unknown component: {name}"
    
    if not component["path"] or Path(component["path"]).exists():
        if component["verify"]():
            return True, f"{name}: healthy"
        return False, f"{name}: verification failed"
    
    return False, f"{name}: directory missing"


def fix_component(name: str, force: bool = False) -> Tuple[bool, str]:
    """Try to fix a broken component with multiple strategies."""
    component = COMPONENTS.get(name)
    if not component:
        return False, f"Unknown component: {name}"
    
    # Strategy 1: Re-run install
    if component["install"]():
        if component["verify"]():
            return True, f"{name}: fixed on first attempt"
    
    # Strategy 2: Force re-install (delete and reinstall)
    if not force and component["path"]:
        path = Path(component["path"])
        if path.exists():
            shutil.rmtree(path)
            if component["install"]() and component["verify"]():
                return True, f"{name}: fixed after force re-install"
    
    # Strategy 3: Manual fallback (if available)
    if name == "packages":
        # Try installing individual packages
        packages = [
            "/projects/sandbox/ScrapeToolAi",
            "/projects/sandbox/goaaiseo-seo-adapter",
            "/projects/sandbox/Claude-Opus5",
        ]
        for pkg in packages:
            if Path(pkg).exists():
                subprocess.run([
                    "pip", "install", "-e", pkg
                ], capture_output=True)
        
        if component["verify"]():
            return True, f"{name}: fixed by installing individual packages"
    
    return False, f"{name}: could not fix after all strategies"


def heal_all(force: bool = False) -> Dict:
    """Heal all components."""
    results = {}
    
    for name in COMPONENTS:
        healthy, message = check_component(name)
        
        if not healthy:
            success, fix_message = fix_component(name, force)
            results[name] = {
                "healthy_before": healthy,
                "message": message,
                "fixed": success,
                "fix_message": fix_message,
            }
        else:
            results[name] = {
                "healthy_before": True,
                "message": message,
                "skipped": True,
            }
    
    return {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "results": results,
        "summary": {
            "total": len(results),
            "healthy": sum(1 for r in results.values() if r.get("skipped") or r["fixed"]),
            "still_broken": sum(1 for r in results.values() if not r.get("skipped") and not r["fixed"]),
        },
    }


def heal_specific(components: List[str], force: bool = False) -> Dict:
    """Heal specific components."""
    results = {}
    
    for name in components:
        if name not in COMPONENTS:
            results[name] = {
                "error": f"Unknown component: {name}",
                "skipped": True,
            }
            continue
        
        healthy, message = check_component(name)
        
        if not healthy:
            success, fix_message = fix_component(name, force)
            results[name] = {
                "healthy_before": healthy,
                "message": message,
                "fixed": success,
                "fix_message": fix_message,
            }
        else:
            results[name] = {
                "healthy_before": True,
                "message": message,
                "skipped": True,
            }
    
    return {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "components": components,
        "results": results,
    }


def main():
    """Main entry point for CLI."""
    import sys
    
    if len(sys.argv) < 2:
        print("Self-Heal - Automated Dependency Resolution")
        print("")
        print("Usage: self-heal <command> [args]")
        print("")
        print("Commands:")
        print("  all          - Heal all components")
        print("  force        - Heal all with force re-install")
        print("  <component>  - Heal specific component")
        print("  list         - List all components")
        print("  status       - Show component status")
        sys.exit(0)
    
    command = sys.argv[1]
    
    if command == "list":
        print("Components:")
        for name, component in COMPONENTS.items():
            healthy, _ = check_component(name)
            status = "✓" if healthy else "✗"
            print(f"  {status} {name}")
    
    elif command == "status":
        for name in COMPONENTS:
            healthy, message = check_component(name)
            status = "HEALTHY" if healthy else "BROKEN"
            print(f"  [{status}] {name}: {message}")
    
    elif command == "all":
        result = heal_all()
        print(json.dumps(result, indent=2))
    
    elif command == "force":
        result = heal_all(force=True)
        print(json.dumps(result, indent=2))
    
    elif command in COMPONENTS:
        result = heal_specific([command])
        print(json.dumps(result, indent=2))
    
    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == "__main__":
    main()
