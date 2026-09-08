#!/usr/bin/env python3
"""Read manifest.json and emit shell-consumable output.

This exists so bootstrap.sh / verify.sh / repair.sh never duplicate install
logic. manifest.json is the single source of truth; this module is the only
thing that parses it.

Stdlib-only by design (consistent with DEC-006), so it runs on any Python 3.9+
without an install step.

Usage:
    manifest.py repos                 -> TSV: name, github, branch, priority, skills_dir
    manifest.py steps <repo> install  -> one expanded shell command per line
    manifest.py steps <repo> verify   -> one expanded shell command per line
    manifest.py env                   -> KEY=VALUE per line (expanded)
    manifest.py post-install          -> one expanded shell command per line
    manifest.py field <dotted.path>   -> a single scalar value
    manifest.py skill-sources         -> TSV: repo_name, absolute_skills_dir
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any, Final

_SELF_DIR: Final[Path] = Path(__file__).resolve().parent
_REPO_ROOT: Final[Path] = _SELF_DIR.parent.parent
_MANIFEST: Final[Path] = _REPO_ROOT / "manifest.json"


def load() -> dict[str, Any]:
    """Parse manifest.json, failing loudly with a usable message."""
    try:
        with _MANIFEST.open(encoding="utf-8") as fh:
            return json.load(fh)
    except FileNotFoundError:
        sys.exit(f"manifest.py: manifest not found at {_MANIFEST}")
    except json.JSONDecodeError as exc:
        sys.exit(f"manifest.py: manifest.json is not valid JSON: {exc}")


def placeholders(data: dict[str, Any]) -> dict[str, str]:
    """Build the placeholder table used to expand manifest strings.

    Environment variables win over manifest defaults so tests can redirect
    WORKSPACE / KIRO_DIR to a scratch directory without editing the manifest.
    """
    workspace = os.environ.get("SB_WORKSPACE") or data.get("workspace", "/projects/sandbox")
    kiro_dir = os.environ.get("SB_KIRO_DIR") or data.get("kiro_dir", "/projects/.kiro")
    return {
        "WORKSPACE": workspace,
        "KIRO_DIR": kiro_dir,
        "KIRO_SKILLS": f"{kiro_dir}/skills",
    }


def expand(text: str, table: dict[str, str], repo_path: str = "") -> str:
    """Substitute ${NAME} placeholders. Unknown placeholders are left intact."""
    out = text
    for key, value in table.items():
        out = out.replace("${" + key + "}", value)
    if repo_path:
        out = out.replace("${REPO}", repo_path)
    return out


def _repo_entries(data: dict[str, Any]) -> list[dict[str, Any]]:
    repos = list(data.get("repositories", []))
    repos.sort(key=lambda r: r.get("priority", 999))
    return repos


def _find(data: dict[str, Any], name: str) -> dict[str, Any]:
    if name == "self":
        return data.get("self", {})
    for repo in _repo_entries(data):
        if repo.get("name") == name:
            return repo
    sys.exit(f"manifest.py: no repository named {name!r} in manifest.json")


def cmd_repos(data: dict[str, Any]) -> None:
    for repo in _repo_entries(data):
        branch = repo.get("branch") or "-"
        print(
            "\t".join(
                [
                    str(repo.get("name", "")),
                    str(repo.get("github", "")),
                    branch,
                    str(repo.get("priority", 999)),
                    str(repo.get("skills_dir") or "-"),
                ]
            )
        )


def cmd_steps(data: dict[str, Any], name: str, phase: str) -> None:
    if phase not in {"install", "verify"}:
        sys.exit("manifest.py: phase must be 'install' or 'verify'")
    repo = _find(data, name)
    table = placeholders(data)
    repo_path = f"{table['WORKSPACE']}/{repo.get('name', name)}"
    for step in repo.get(phase, []) or []:
        print(expand(str(step), table, repo_path))


def cmd_env(data: dict[str, Any]) -> None:
    table = placeholders(data)
    python_bin = data.get("python_bin")
    if python_bin:
        print(f'PATH={python_bin}:$PATH')
    for key, value in (data.get("environment") or {}).items():
        print(f"{key}={expand(str(value), table)}")


def cmd_post_install(data: dict[str, Any]) -> None:
    table = placeholders(data)
    for step in data.get("post_install") or []:
        print(expand(str(step), table))


def cmd_field(data: dict[str, Any], path: str) -> None:
    node: Any = data
    for part in path.split("."):
        if not isinstance(node, dict) or part not in node:
            sys.exit(f"manifest.py: no such field {path!r}")
        node = node[part]
    if isinstance(node, (dict, list)):
        sys.exit(f"manifest.py: field {path!r} is not a scalar")
    print(expand(str(node), placeholders(data)))


def cmd_skill_sources(data: dict[str, Any]) -> None:
    """Every directory that contributes skills, for collision + prune logic."""
    table = placeholders(data)
    entries = _repo_entries(data)
    self_entry = data.get("self")
    if self_entry:
        entries = entries + [self_entry]
    for repo in entries:
        skills_dir = repo.get("skills_dir")
        if not skills_dir:
            continue
        name = repo.get("name", "")
        print(f"{name}\t{table['WORKSPACE']}/{name}/{skills_dir}")


def main(argv: list[str]) -> None:
    if len(argv) < 2:
        sys.exit(__doc__)
    data = load()
    command = argv[1]
    if command == "repos":
        cmd_repos(data)
    elif command == "steps":
        if len(argv) < 4:
            sys.exit("usage: manifest.py steps <repo> <install|verify>")
        cmd_steps(data, argv[2], argv[3])
    elif command == "env":
        cmd_env(data)
    elif command == "post-install":
        cmd_post_install(data)
    elif command == "field":
        if len(argv) < 3:
            sys.exit("usage: manifest.py field <dotted.path>")
        cmd_field(data, argv[2])
    elif command == "skill-sources":
        cmd_skill_sources(data)
    else:
        sys.exit(f"manifest.py: unknown command {command!r}")


if __name__ == "__main__":
    main(sys.argv)
