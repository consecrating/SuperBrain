#!/usr/bin/env python3
"""
MCP Hub - One-Click Tool Orchestration for SuperBrain

A unified interface for managing all MCP servers in your workspace.
Enable/disable tools instantly without manual config edits.

HACKER APPROACH:
- Single source of truth for all MCP configs
- One-click enable/disable via simple commands
- Auto-generate configs from templates
"""

import json
import os
import shutil
from pathlib import Path
from typing import Dict, List, Optional
from dataclasses import dataclass, field

# Pre-configured MCP servers with defaults
SERVER_TEMPLATES = {
    "playwright": {
        "command": "npx",
        "args": ["-y", "@playwright/mcp@latest", "--headless", "--no-sandbox"],
        "disabled": False,
        "description": "Browser automation, screenshots, testing",
    },
    "serenity": {
        "command": "uvx",
        "args": ["--from", "git+https://github.com/oraios/serena", "serenity", "start-mcp-server", "--context", "ide-assistant", "--project", "/projects/sandbox"],
        "disabled": False,
        "description": "Token-saving symbol-level code retrieval",
    },
    "github": {
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-github"],
        "disabled": True,
        "env": {"GITHUB_PERSONAL_ACCESS_TOKEN": ""},
        "description": "GitHub API, git operations (requires PAT)",
    },
    "agent-browser": {
        "command": "npx",
        "args": ["-y", "@agent-browser/mcp@latest"],
        "disabled": False,
        "description": "Browser automation with isolated sessions",
    },
    "21st-magic": {
        "command": "npx",
        "args": ["-y", "@21st-dev/magic@latest"],
        "disabled": True,
        "env": {"API_KEY": ""},
        "description": "Premium component search/generation (requires API key)",
    },
    "shadcn-ui": {
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-shadcn-ui"],
        "disabled": True,
        "description": "shadcn/ui component source and blocks",
    },
    "unsplash": {
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-unsplash"],
        "disabled": True,
        "description": "Photo search/download",
    },
    "pinterest": {
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-pinterest"],
        "disabled": True,
        "description": "Image search/download",
    },
}


def get_mcp_config_path() -> Path:
    """Get the MCP config file path."""
    return Path("/projects/sandbox/.kiro/settings/mcp.json")


def load_mcp_config() -> Dict:
    """Load current MCP config or return empty config."""
    path = get_mcp_config_path()
    if path.exists():
        try:
            return json.loads(path.read_text())
        except json.JSONDecodeError:
            pass
    return {"mcpServers": {}}


def save_mcp_config(config: Dict) -> None:
    """Save MCP config to file."""
    path = get_mcp_config_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(config, indent=2) + "\n")


def get_all_servers() -> Dict[str, Dict]:
    """Get all configured servers with their templates."""
    config = load_mcp_config()
    configured = config.get("mcpServers", {})
    
    result = {}
    for name, template in SERVER_TEMPLATES.items():
        current = configured.get(name, {})
        result[name] = {
            "name": name,
            "enabled": not current.get("disabled", template.get("disabled", False)),
            "description": template.get("description", ""),
            "command": current.get("command", template.get("command")),
        }
    
    # Add any servers not in templates
    for name, config_data in configured.items():
        if name not in result:
            result[name] = {
                "name": name,
                "enabled": not config_data.get("disabled", False),
                "description": "Custom server",
                "command": config_data.get("command"),
            }
    
    return result


def enable_server(name: str) -> bool:
    """Enable an MCP server."""
    config = load_mcp_config()
    
    if name in SERVER_TEMPLATES:
        if name not in config["mcpServers"]:
            config["mcpServers"][name] = SERVER_TEMPLATES[name].copy()
        config["mcpServers"][name]["disabled"] = False
    elif name in config["mcpServers"]:
        config["mcpServers"][name]["disabled"] = False
    else:
        print(f"Unknown server: {name}")
        return False
    
    save_mcp_config(config)
    return True


def disable_server(name: str) -> bool:
    """Disable an MCP server."""
    config = load_mcp_config()
    
    if name not in config["mcpServers"]:
        print(f"Server not found: {name}")
        return False
    
    config["mcpServers"][name]["disabled"] = True
    save_mcp_config(config)
    return True


def list_servers() -> List[Dict]:
    """List all available servers."""
    return list(get_all_servers().values())


def get_server_status() -> Dict:
    """Get detailed server status."""
    servers = get_all_servers()
    
    enabled_count = sum(1 for s in servers.values() if s["enabled"])
    
    return {
        "total": len(servers),
        "enabled": enabled_count,
        "disabled": len(servers) - enabled_count,
        "servers": servers,
    }


def init_hub() -> Dict:
    """Initialize MCP hub with default servers."""
    config = {"mcpServers": {}}
    
    # Add default enabled servers
    defaults = ["playwright", "serenity", "agent-browser"]
    for name in defaults:
        if name in SERVER_TEMPLATES:
            config["mcpServers"][name] = SERVER_TEMPLATES[name].copy()
    
    save_mcp_config(config)
    return {"initialized": True, "servers": defaults}


def main():
    """Main entry point for CLI."""
    import sys
    
    if len(sys.argv) < 2:
        print("MCP Hub - One-Click Tool Orchestration")
        print("")
        print("Usage: mcp-hub <command> [args]")
        print("")
        print("Commands:")
        print("  list         - List all servers")
        print("  status       - Show detailed status")
        print("  enable <name> - Enable a server")
        print("  disable <name> - Disable a server")
        print("  init         - Initialize with defaults")
        sys.exit(0)
    
    command = sys.argv[1]
    
    if command == "list":
        servers = list_servers()
        print("Available servers:")
        for s in servers:
            status = "✓" if s["enabled"] else "✗"
            print(f"  {status} {s['name']}: {s['description']}")
    
    elif command == "status":
        status = get_server_status()
        print(f"Total: {status['total']} | Enabled: {status['enabled']} | Disabled: {status['disabled']}")
        print("")
        print("Servers:")
        for name, info in status["servers"].items():
            status = "enabled" if info["enabled"] else "disabled"
            print(f"  {name}: {status}")
    
    elif command == "enable":
        if len(sys.argv) < 3:
            print("Usage: mcp-hub enable <server_name>")
            sys.exit(1)
        name = sys.argv[2]
        if enable_server(name):
            print(f"✓ {name} enabled")
        else:
            print(f"✗ Failed to enable {name}")
            sys.exit(1)
    
    elif command == "disable":
        if len(sys.argv) < 3:
            print("Usage: mcp-hub disable <server_name>")
            sys.exit(1)
        name = sys.argv[2]
        if disable_server(name):
            print(f"✓ {name} disabled")
        else:
            print(f"✗ Failed to disable {name}")
            sys.exit(1)
    
    elif command == "init":
        result = init_hub()
        print(f"✓ MCP hub initialized with {len(result['servers'])} servers")
        print(f"  Enabled: {', '.join(result['servers'])}")
    
    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == "__main__":
    main()
