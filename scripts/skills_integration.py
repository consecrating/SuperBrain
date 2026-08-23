#!/usr/bin/env python3
"""Deterministic All-Skills + Claude-Power connected-workspace integration.

This helper consumes only All-Skills' public JSON files and command-line
interfaces. It never imports All-Skills implementation modules.
"""

from __future__ import annotations

import argparse
import ctypes
import fcntl
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import uuid
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable, Iterator, Mapping, Sequence

SCHEMA_VERSION = "1.0"
ALL_SKILLS_SCHEMA_VERSION = "2.0"
EXPECTED_ALL_SKILLS_COUNT = 45
EXPECTED_ALL_SKILLS_OWNED = 44
EXPECTED_CLAUDE_POWER_COUNT = 16
EXPECTED_UNIQUE_IDENTITIES = 60
EXPECTED_EXTERNAL_OWNER = ("token-efficiency", "token-efficiency", "Claude-Power")
DEFAULT_WORKSPACE = Path("/projects/sandbox")
DEFAULT_TARGET = Path("/projects/.kiro/skills")
RECEIPT_RELATIVE = Path(".all-skills-receipts/all-skills.json")
OWNER_INVENTORY_RELATIVE = Path(".superbrain-owner-inventory.json")
PORTABLE_SKILL_PREFIX = "${CLAUDE_PLUGIN_ROOT}/.claude/skills/"
SAFE_COMPONENT = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
TRANSIENT_TREE_PARTS = frozenset({"__pycache__", ".pytest_cache", ".mypy_cache"})
TRANSIENT_TREE_SUFFIXES = frozenset({".pyc", ".pyo"})


class IntegrationError(RuntimeError):
    """A safe, actionable integration failure."""


@dataclass(frozen=True)
class TreeSnapshot:
    digest: str
    files: tuple[tuple[str, str, int], ...]


@dataclass(frozen=True)
class ExternalSkill:
    folder: str
    identity: str
    owner: str


@dataclass(frozen=True)
class Contract:
    workspace: Path
    all_skills_root: Path
    all_skills_source: Path
    manifest: Mapping[str, Any]
    catalog: Mapping[str, Any]
    bundle_id: str
    bundle_version: str
    manifest_digest: str
    catalog_entries: tuple[Mapping[str, Any], ...]
    all_skills_owned: tuple[str, ...]
    all_skills_snapshots: Mapping[str, TreeSnapshot]
    external: tuple[ExternalSkill, ...]
    owner_sources: Mapping[str, Mapping[str, Path]]
    owner_snapshots: Mapping[str, Mapping[str, TreeSnapshot]]


@dataclass
class OwnerTransaction:
    backup: Path
    moved: list[tuple[str, bool, bool]]
    previous_inventory: bytes | None
    inventory_path: Path


@dataclass(frozen=True)
class LifecycleTransaction:
    operation: str
    transaction_id: str
    skills: tuple[str, ...] = ()
    expected_receipt: Mapping[str, Any] | None = None


def _integration_lock_path(target: Path) -> Path:
    """Return All-Skills' exact per-target public lifecycle lock path."""

    return target.parent / f".{target.name}.all-skills.lock"


def _validate_report_destination(target: Path, report: Path) -> None:
    if report == _integration_lock_path(target) or report == target or report.is_relative_to(target):
        raise IntegrationError("report path must be outside the managed skills target and integration lock")


@contextmanager
def _integration_lock(target: Path) -> Iterator[int]:
    """Hold All-Skills' complete per-target transaction lock and yield its inheritable fd."""

    parent = _safe_absolute_path(target.parent, "integration lock directory")
    parent.mkdir(parents=True, exist_ok=True)
    lock_path = _integration_lock_path(target)
    flags = os.O_RDWR | os.O_CREAT
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        descriptor = os.open(lock_path, flags, 0o600)
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            os.close(descriptor)
            raise IntegrationError(f"integration lock is not a regular file: {lock_path}")
    except IntegrationError:
        raise
    except OSError as exc:
        raise IntegrationError(f"cannot open safe integration lock: {exc}") from exc
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield descriptor
    finally:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_UN)
        finally:
            os.close(descriptor)


def _canonical_json(data: Any) -> str:
    return json.dumps(data, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def _compact_json(data: Any) -> str:
    return json.dumps(data, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n"


def _sha256_bytes(content: bytes) -> str:
    return "sha256:" + hashlib.sha256(content).hexdigest()


def _safe_component(value: object, label: str) -> str:
    if not isinstance(value, str) or not SAFE_COMPONENT.fullmatch(value) or value in {".", ".."}:
        raise IntegrationError(f"unsafe {label}: {value!r}")
    return value


def _safe_absolute_path(path: Path, label: str) -> Path:
    """Normalize without following links, rejecting links in every existing component."""

    try:
        candidate = Path(os.path.abspath(os.fspath(path.expanduser())))
    except (OSError, RuntimeError, ValueError) as exc:
        raise IntegrationError(f"invalid {label}: {exc}") from exc
    current = Path(candidate.anchor)
    for part in candidate.parts[1:]:
        current /= part
        if current.is_symlink():
            raise IntegrationError(f"refusing symlinked {label} component: {current}")
        if current.exists() and current != candidate and not current.is_dir():
            raise IntegrationError(f"non-directory {label} ancestor: {current}")
    return candidate


def check_safe_file(path: Path) -> dict[str, Any]:
    candidate = _safe_absolute_path(path, "file")
    if candidate.is_symlink() or not candidate.is_file() or not stat.S_ISREG(candidate.stat().st_mode):
        raise IntegrationError(f"path is not a safe regular file: {candidate}")
    return {
        "schema_version": SCHEMA_VERSION,
        "operation": "check-safe-file",
        "health": "healthy",
        "path": str(candidate),
    }


def _load_json(path: Path, label: str) -> Any:
    if path.is_symlink() or not path.is_file():
        raise IntegrationError(f"missing safe {label}: {path}")
    try:
        with path.open(encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise IntegrationError(f"cannot read {label}: {exc}") from exc


def _atomic_write(path: Path, content: str) -> None:
    path = _safe_absolute_path(path, "output path")
    if path.exists() and path.is_symlink():
        raise IntegrationError(f"refusing symlinked output path: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    _safe_absolute_path(path.parent, "output directory")
    if path.parent.is_symlink():
        raise IntegrationError(f"refusing symlinked output directory: {path.parent}")
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise
    try:
        directory_fd = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    except OSError:
        pass


def _iter_tree_files(root: Path) -> Iterable[Path]:
    if root.is_symlink() or not root.is_dir():
        raise IntegrationError(f"missing safe source tree: {root}")
    paths: list[Path] = []
    try:
        for path in root.rglob("*"):
            relative = path.relative_to(root)
            if TRANSIENT_TREE_PARTS.intersection(relative.parts) or path.suffix in TRANSIENT_TREE_SUFFIXES:
                continue
            if path.is_symlink():
                raise IntegrationError(f"refusing symlink in tree: {path}")
            if path.is_file():
                paths.append(path)
            elif not path.is_dir():
                raise IntegrationError(f"refusing unsupported filesystem entry: {path}")
    except OSError as exc:
        raise IntegrationError(f"cannot inspect tree {root}: {exc}") from exc
    return sorted(paths, key=lambda item: item.relative_to(root).as_posix())


def _tree_snapshot(root: Path) -> TreeSnapshot:
    records: list[tuple[str, str, int]] = []
    digest = hashlib.sha256()
    for path in _iter_tree_files(root):
        relative = path.relative_to(root).as_posix()
        try:
            content = path.read_bytes()
        except OSError as exc:
            raise IntegrationError(f"cannot read tree file {path}: {exc}") from exc
        file_digest = _sha256_bytes(content)
        size = len(content)
        records.append((relative, file_digest, size))
        digest.update(relative.encode("utf-8"))
        digest.update(b"\0")
        digest.update(file_digest.encode("ascii"))
        digest.update(b"\0")
        digest.update(str(size).encode("ascii"))
        digest.update(b"\n")
    return TreeSnapshot("sha256:" + digest.hexdigest(), tuple(records))


def _aggregate_digest(snapshots: Mapping[str, TreeSnapshot]) -> str:
    digest = hashlib.sha256()
    for folder in sorted(snapshots):
        snapshot = snapshots[folder]
        digest.update(folder.encode("utf-8"))
        digest.update(b"\0")
        digest.update(snapshot.digest.encode("ascii"))
        digest.update(b"\n")
    return "sha256:" + digest.hexdigest()


def _projected_install_digest(source: Path, target: Path) -> str:
    records: list[tuple[str, str, int]] = []
    replacement = str(target).rstrip("/") + "/"
    for path in _iter_tree_files(source):
        content = path.read_bytes()
        if path.suffix in {".md", ".py"}:
            text = content.decode("utf-8", errors="ignore")
            if PORTABLE_SKILL_PREFIX in text:
                content = text.replace(PORTABLE_SKILL_PREFIX, replacement).encode("utf-8")
        records.append((path.relative_to(source).as_posix(), _sha256_bytes(content), len(content)))
    digest = hashlib.sha256()
    for relative, checksum, size in records:
        digest.update(relative.encode("utf-8"))
        digest.update(b"\0")
        digest.update(checksum.encode("ascii"))
        digest.update(b"\0")
        digest.update(str(size).encode("ascii"))
        digest.update(b"\n")
    return "sha256:" + digest.hexdigest()


def _run_json(
    command: Sequence[str],
    *,
    cwd: Path,
    allow_failure: bool = False,
    inherited_lock_fd: int | None = None,
) -> tuple[dict[str, Any], int]:
    environment = os.environ.copy()
    # The public CLI gives KIRO_SKILLS_DIR precedence over --target. Explicit
    # helper arguments must remain authoritative and deterministic.
    environment.pop("KIRO_SKILLS_DIR", None)
    pass_fds: tuple[int, ...] = ()
    if inherited_lock_fd is not None:
        if inherited_lock_fd < 0:
            raise IntegrationError("invalid inherited All-Skills lock descriptor")
        environment["ALL_SKILLS_LOCK_FD"] = str(inherited_lock_fd)
        pass_fds = (inherited_lock_fd,)
    else:
        environment.pop("ALL_SKILLS_LOCK_FD", None)
    try:
        process = subprocess.run(
            list(command),
            cwd=cwd,
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=300,
            check=False,
            pass_fds=pass_fds,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise IntegrationError(f"cannot run public command {Path(command[0]).name}: {exc}") from exc
    try:
        payload = json.loads(process.stdout)
    except json.JSONDecodeError as exc:
        detail = (process.stderr or process.stdout).strip()[-1200:]
        raise IntegrationError(f"public command returned invalid JSON ({process.returncode}): {detail}") from exc
    if not isinstance(payload, dict):
        raise IntegrationError("public command returned a non-object JSON payload")
    if process.returncode and not allow_failure:
        detail = payload.get("error") or "; ".join(
            str(item.get("code", "unknown")) for item in payload.get("issues", []) if isinstance(item, dict)
        )
        raise IntegrationError(f"public command failed ({process.returncode}): {detail or 'no safe detail'}")
    return payload, process.returncode


def _run_validator(all_skills_root: Path) -> dict[str, Any]:
    payload, returncode = _run_json(
        [sys.executable, "scripts/all_skills.py", "validate", "--json"], cwd=all_skills_root, allow_failure=True
    )
    errors = payload.get("errors")
    warnings = payload.get("warnings")
    if not isinstance(errors, int) or not isinstance(warnings, int):
        raise IntegrationError("All-Skills validator JSON is missing integer errors/warnings")
    if returncode or errors != 0:
        raise IntegrationError(f"All-Skills source validator reported {errors} error(s)")
    return {"errors": errors, "warnings": warnings, "status": str(payload.get("status", "unknown"))}


def _validate_catalog_tree(entry: Mapping[str, Any], source: Path) -> TreeSnapshot:
    snapshot = _tree_snapshot(source)
    checksums = entry.get("checksums")
    if not isinstance(checksums, dict) or checksums.get("content") != snapshot.digest:
        raise IntegrationError(f"catalog content digest mismatch for {entry.get('folder')}")
    declared_files = checksums.get("files")
    if not isinstance(declared_files, list):
        raise IntegrationError(f"catalog file checksums missing for {entry.get('folder')}")
    normalized: list[tuple[str, str, int]] = []
    for record in declared_files:
        if not isinstance(record, dict):
            raise IntegrationError(f"invalid catalog file record for {entry.get('folder')}")
        path = record.get("path")
        digest = record.get("sha256")
        size = record.get("size")
        if not isinstance(path, str) or Path(path).is_absolute() or ".." in Path(path).parts:
            raise IntegrationError(f"unsafe catalog file path for {entry.get('folder')}: {path!r}")
        if not isinstance(digest, str) or not isinstance(size, int):
            raise IntegrationError(f"invalid catalog file digest for {entry.get('folder')}")
        normalized.append((path, digest, size))
    if tuple(normalized) != snapshot.files:
        raise IntegrationError(f"catalog file path/digest set mismatch for {entry.get('folder')}")
    return snapshot


def _front_matter_name(skill_file: Path) -> str:
    if skill_file.is_symlink() or not skill_file.is_file():
        raise IntegrationError(f"missing safe SKILL.md: {skill_file}")
    try:
        text = skill_file.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        raise IntegrationError(f"cannot read skill identity {skill_file}: {exc}") from exc
    if not text.startswith("---\n"):
        raise IntegrationError(f"missing front matter in {skill_file}")
    end = text.find("\n---", 4)
    if end < 0:
        raise IntegrationError(f"unterminated front matter in {skill_file}")
    for line in text[4:end].splitlines():
        match = re.fullmatch(r"name:\s*['\"]?([^'\"#]+?)['\"]?\s*", line)
        if match:
            return match.group(1).strip()
    raise IntegrationError(f"missing front-matter name in {skill_file}")


def _load_contract(workspace_raw: Path) -> tuple[Contract, dict[str, Any]]:
    workspace = _safe_absolute_path(workspace_raw, "workspace")
    if not workspace.is_dir():
        raise IntegrationError(f"workspace is not a safe directory: {workspace_raw}")
    all_skills_root = workspace / "All-Skills"
    if all_skills_root.is_symlink() or not all_skills_root.is_dir():
        raise IntegrationError(f"All-Skills repository is missing or symlinked: {all_skills_root}")

    validator = _run_validator(all_skills_root)
    manifest = _load_json(all_skills_root / "bundle.json", "All-Skills bundle manifest")
    catalog = _load_json(all_skills_root / "catalog/skills.json", "All-Skills public catalog")
    if not isinstance(manifest, dict) or not isinstance(catalog, dict):
        raise IntegrationError("All-Skills bundle/catalog roots must be JSON objects")
    if manifest.get("schema_version") != ALL_SKILLS_SCHEMA_VERSION or catalog.get("schema_version") != ALL_SKILLS_SCHEMA_VERSION:
        raise IntegrationError("All-Skills bundle/catalog schema version mismatch")
    bundle = manifest.get("bundle")
    catalog_bundle = catalog.get("bundle")
    if not isinstance(bundle, dict) or not isinstance(catalog_bundle, dict):
        raise IntegrationError("All-Skills bundle identity is missing")
    for key in ("id", "name", "version", "skill_root"):
        if bundle.get(key) != catalog_bundle.get(key):
            raise IntegrationError(f"All-Skills bundle/catalog {key} mismatch")
    bundle_id = _safe_component(bundle.get("id"), "bundle id")
    bundle_version = str(bundle.get("version", ""))
    manifest_digest = _sha256_bytes(_canonical_json(manifest).encode("utf-8"))
    if catalog.get("manifest_sha256") != manifest_digest:
        raise IntegrationError("All-Skills catalog manifest digest is stale")

    manifest_entries_raw = manifest.get("skills")
    catalog_entries_raw = catalog.get("skills")
    if not isinstance(manifest_entries_raw, list) or not isinstance(catalog_entries_raw, list):
        raise IntegrationError("All-Skills bundle/catalog skills must be arrays")
    if len(manifest_entries_raw) != EXPECTED_ALL_SKILLS_COUNT:
        raise IntegrationError(
            f"All-Skills bundle must package exactly {EXPECTED_ALL_SKILLS_COUNT} skills; found {len(manifest_entries_raw)}"
        )
    if catalog.get("skill_count") != len(catalog_entries_raw) or len(catalog_entries_raw) != len(manifest_entries_raw):
        raise IntegrationError("All-Skills bundle/catalog skill counts are inconsistent")

    manifest_by_folder: dict[str, Mapping[str, Any]] = {}
    manifest_names: set[str] = set()
    for raw in manifest_entries_raw:
        if not isinstance(raw, dict):
            raise IntegrationError("All-Skills bundle contains a non-object skill")
        folder = _safe_component(raw.get("folder"), "manifest skill folder")
        name = _safe_component(raw.get("name"), "manifest activation identity")
        if folder in manifest_by_folder:
            raise IntegrationError(f"duplicate All-Skills manifest folder: {folder}")
        if name in manifest_names:
            raise IntegrationError(f"duplicate All-Skills activation identity: {name}")
        manifest_by_folder[folder] = raw
        manifest_names.add(name)

    catalog_entries: list[Mapping[str, Any]] = []
    catalog_folders: set[str] = set()
    catalog_names: set[str] = set()
    catalog_identities: dict[str, str] = {}
    all_skills_snapshots: dict[str, TreeSnapshot] = {}
    external: list[ExternalSkill] = []
    skill_root_raw = bundle.get("skill_root")
    if not isinstance(skill_root_raw, str) or Path(skill_root_raw).is_absolute() or ".." in Path(skill_root_raw).parts:
        raise IntegrationError("unsafe All-Skills bundle skill_root")
    all_skills_source = _safe_absolute_path(all_skills_root / skill_root_raw, "All-Skills source root")
    if not all_skills_source.is_dir():
        raise IntegrationError("All-Skills source root is missing or symlinked")

    for raw in catalog_entries_raw:
        if not isinstance(raw, dict):
            raise IntegrationError("All-Skills catalog contains a non-object skill")
        folder = _safe_component(raw.get("folder"), "catalog skill folder")
        name = _safe_component(raw.get("name"), "catalog activation identity")
        if folder in catalog_folders:
            raise IntegrationError(f"duplicate All-Skills catalog folder: {folder}")
        if name in catalog_names:
            raise IntegrationError(f"duplicate All-Skills catalog activation identity: {name}")
        aliases = raw.get("aliases", [])
        if not isinstance(aliases, list):
            raise IntegrationError(f"invalid All-Skills aliases for {folder}")
        local_identities: set[str] = set()
        for identity_raw in (folder, name, *aliases):
            identity = _safe_component(identity_raw, f"catalog identity for {folder}")
            if identity in local_identities:
                continue
            local_identities.add(identity)
            previous = catalog_identities.get(identity)
            if previous is not None and previous != folder:
                raise IntegrationError(f"ambiguous All-Skills catalog identity: {identity}")
            catalog_identities[identity] = folder
        declared = manifest_by_folder.get(folder)
        if declared is None or declared.get("name") != name:
            raise IntegrationError(f"All-Skills catalog identity does not match bundle for {folder}")
        for key in ("aliases", "conflicts", "supersession"):
            if raw.get(key) != declared.get(key):
                raise IntegrationError(f"All-Skills catalog {key} does not match bundle for {folder}")
        source = all_skills_source / folder
        if source.resolve() != source or source.parent.resolve() != all_skills_source:
            raise IntegrationError(f"All-Skills source escapes skill root: {folder}")
        all_skills_snapshots[folder] = _validate_catalog_tree(raw, source)
        conflicts = raw.get("conflicts", [])
        if not isinstance(conflicts, list):
            raise IntegrationError(f"invalid conflict metadata for {folder}")
        declarations: list[ExternalSkill] = []
        for conflict in conflicts:
            if not isinstance(conflict, dict):
                raise IntegrationError(f"invalid conflict declaration for {folder}")
            if conflict.get("resolution") == "external_canonical_owner":
                owner = _safe_component(conflict.get("owner"), "external owner")
                identity = _safe_component(conflict.get("identity"), "external owner identity")
                declarations.append(ExternalSkill(folder, identity, owner))
        if len(declarations) > 1:
            raise IntegrationError(f"multiple external canonical owners declared for {folder}")
        external.extend(declarations)
        catalog_entries.append(raw)
        catalog_folders.add(folder)
        catalog_names.add(name)

    if catalog_folders != set(manifest_by_folder):
        raise IntegrationError("All-Skills bundle/catalog folder sets differ")

    external_by_folder = {item.folder: item for item in external}
    if len(external_by_folder) != len(external):
        raise IntegrationError("duplicate external owner declarations")
    owned = tuple(sorted(catalog_folders - set(external_by_folder)))
    external_contract = {(item.folder, item.identity, item.owner) for item in external}
    if external_contract != {EXPECTED_EXTERNAL_OWNER}:
        raise IntegrationError(
            "combined ownership must declare exactly token-efficiency -> Claude-Power as external canonical owner"
        )
    if len(owned) != EXPECTED_ALL_SKILLS_OWNED:
        raise IntegrationError(
            f"combined All-Skills receipt must own exactly {EXPECTED_ALL_SKILLS_OWNED} skills; found {len(owned)}"
        )

    owner_sources: dict[str, dict[str, Path]] = {}
    owner_snapshots: dict[str, dict[str, TreeSnapshot]] = {}
    for owner in sorted({item.owner for item in external}):
        owner_root = _safe_absolute_path(workspace / owner, f"{owner} repository root")
        source_root = _safe_absolute_path(owner_root / ".kiro/skills", f"{owner} skill source")
        if not owner_root.is_dir() or not source_root.is_dir():
            raise IntegrationError(f"external owner source is missing or symlinked: {source_root}")
        sources: dict[str, Path] = {}
        snapshots: dict[str, TreeSnapshot] = {}
        identities: dict[str, str] = {}
        for source in sorted(source_root.iterdir(), key=lambda item: item.name):
            if source.is_symlink():
                raise IntegrationError(f"refusing symlink in external owner source: {source}")
            if not source.is_dir():
                continue
            folder = _safe_component(source.name, f"{owner} skill folder")
            identity = _safe_component(_front_matter_name(source / "SKILL.md"), f"{owner} activation identity")
            previous_identity_folder = identities.get(identity)
            if previous_identity_folder is not None:
                raise IntegrationError(
                    f"duplicate {owner} activation identity: {identity} ({previous_identity_folder}, {folder})"
                )
            identities[identity] = folder
            sources[folder] = source
            snapshots[folder] = _tree_snapshot(source)
        if not sources:
            raise IntegrationError(f"external owner has no skill trees: {owner}")
        if owner == "Claude-Power" and len(sources) != EXPECTED_CLAUDE_POWER_COUNT:
            raise IntegrationError(
                f"Claude-Power must package exactly {EXPECTED_CLAUDE_POWER_COUNT} skills; found {len(sources)}"
            )
        owner_sources[owner] = sources
        owner_snapshots[owner] = snapshots

    for item in external:
        source = owner_sources.get(item.owner, {}).get(item.folder)
        if source is None:
            raise IntegrationError(f"external owner {item.owner} does not provide {item.folder}")
        if _front_matter_name(source / "SKILL.md") != item.identity:
            raise IntegrationError(f"external owner identity mismatch for {item.folder}")
    for owner, sources in owner_sources.items():
        for folder in set(sources) & catalog_folders:
            declaration = external_by_folder.get(folder)
            if declaration is None or declaration.owner != owner:
                raise IntegrationError(f"undeclared combined-install collision: {folder}")

    owner_identity_records = {
        (owner, folder): _front_matter_name(source / "SKILL.md")
        for owner, sources in owner_sources.items()
        for folder, source in sources.items()
    }
    for (owner, folder), identity in owner_identity_records.items():
        catalog_folder = catalog_identities.get(identity)
        if catalog_folder is None:
            continue
        declaration = external_by_folder.get(catalog_folder)
        if (
            declaration is None
            or declaration.owner != owner
            or declaration.folder != folder
            or declaration.identity != identity
        ):
            raise IntegrationError(
                f"undeclared cross-pack activation identity collision: {identity} ({catalog_folder}, {owner}/{folder})"
            )
    unique_identities = catalog_names | set(owner_identity_records.values())
    if len(unique_identities) != EXPECTED_UNIQUE_IDENTITIES:
        raise IntegrationError(
            f"combined packs must expose exactly {EXPECTED_UNIQUE_IDENTITIES} unique activation identities; "
            f"found {len(unique_identities)}"
        )

    return (
        Contract(
            workspace=workspace,
            all_skills_root=all_skills_root,
            all_skills_source=all_skills_source,
            manifest=manifest,
            catalog=catalog,
            bundle_id=bundle_id,
            bundle_version=bundle_version,
            manifest_digest=manifest_digest,
            catalog_entries=tuple(catalog_entries),
            all_skills_owned=owned,
            all_skills_snapshots=dict(all_skills_snapshots),
            external=tuple(sorted(external, key=lambda item: (item.owner, item.folder))),
            owner_sources={owner: dict(sources) for owner, sources in owner_sources.items()},
            owner_snapshots={owner: dict(snapshots) for owner, snapshots in owner_snapshots.items()},
        ),
        validator,
    )


def _public_lifecycle(
    contract: Contract,
    command: str,
    target: Path,
    skills: Sequence[str] = (),
    *,
    lock_fd: int,
    transaction_id: str | None = None,
) -> tuple[dict[str, Any], LifecycleTransaction | None]:
    arguments = ["bash", "install.sh", command, "--target", str(target), "--json"]
    if transaction_id is not None:
        if command != "rollback":
            raise IntegrationError("explicit transaction selection is only valid for rollback")
        arguments.extend(("--transaction", transaction_id))
    for skill in skills:
        arguments.extend(("--skill", skill))
    payload, _ = _run_json(
        arguments, cwd=contract.all_skills_root, inherited_lock_fd=lock_fd
    )
    if (
        payload.get("schema_version") != ALL_SKILLS_SCHEMA_VERSION
        or payload.get("operation") != command
        or payload.get("target") != str(target)
    ):
        raise IntegrationError(f"All-Skills public {command} JSON does not match the requested operation/target")
    if command in {"install", "uninstall"}:
        if payload.get("status") != "healthy" or payload.get("dry_run") is not False:
            raise IntegrationError(f"All-Skills public {command} did not report a committed healthy mutation")
        if payload.get("bundle_id") != contract.bundle_id:
            raise IntegrationError(f"All-Skills public {command} bundle identity mismatch")
        if command == "install" and (
            payload.get("bundle_version") != contract.bundle_version
            or payload.get("manifest_sha256") != contract.manifest_digest
        ):
            raise IntegrationError("All-Skills public install bundle version/digest mismatch")
        records = payload.get("skills")
        if not isinstance(records, list) or {item.get("folder") for item in records if isinstance(item, dict)} != set(skills):
            raise IntegrationError(f"All-Skills public {command} selected skill set mismatch")
        receipt = payload.get("receipt")
        transaction_id = receipt.get("receipt_id") if isinstance(receipt, dict) else None
        if not isinstance(transaction_id, str) or not transaction_id:
            raise IntegrationError(f"All-Skills public {command} JSON omitted its transaction identity")
        return payload, LifecycleTransaction(
            command, transaction_id, tuple(skills), dict(receipt)
        )
    if command == "rollback":
        transaction_id = payload.get("transaction_id")
        transaction_operation = payload.get("transaction_operation")
        if payload.get("status") != "healthy" or not isinstance(transaction_id, str):
            raise IntegrationError("All-Skills public rollback JSON omitted its transaction identity")
        if transaction_operation not in {"install", "uninstall"}:
            raise IntegrationError("All-Skills public rollback JSON has an invalid transaction operation")
        return payload, LifecycleTransaction(str(transaction_operation), transaction_id)
    raise IntegrationError(f"unsupported public lifecycle command: {command}")


def _read_receipt_raw(target: Path) -> dict[str, Any] | None:
    path = target / RECEIPT_RELATIVE
    if not path.exists():
        return None
    payload = _load_json(path, "All-Skills receipt")
    if not isinstance(payload, dict):
        raise IntegrationError("All-Skills receipt must be a JSON object")
    return payload


def _receipt_folders(receipt: Mapping[str, Any] | None) -> set[str]:
    if receipt is None:
        return set()
    skills = receipt.get("skills")
    if not isinstance(skills, list):
        raise IntegrationError("All-Skills receipt skills must be an array")
    folders: set[str] = set()
    for item in skills:
        if not isinstance(item, dict):
            raise IntegrationError("All-Skills receipt contains a non-object skill")
        folder = _safe_component(item.get("folder"), "receipt skill folder")
        if folder in folders:
            raise IntegrationError(f"duplicate All-Skills receipt folder: {folder}")
        folders.add(folder)
    return folders


def _remove_path(path: Path) -> None:
    if path.is_symlink():
        path.unlink()
    elif path.is_dir():
        shutil.rmtree(path)
    else:
        path.unlink(missing_ok=True)


def _owner_inventory_payload(contract: Contract) -> dict[str, Any]:
    return {
        "schema_version": SCHEMA_VERSION,
        "owners": {
            owner: {
                "folders": {
                    folder: contract.owner_snapshots[owner][folder].digest
                    for folder in sorted(contract.owner_sources[owner])
                }
            }
            for owner in sorted(contract.owner_sources)
        },
    }


def _read_owner_inventory(target: Path) -> tuple[dict[str, tuple[str, str]], bytes | None]:
    path = target / OWNER_INVENTORY_RELATIVE
    if not path.exists():
        return {}, None
    raw = path.read_bytes()
    payload = _load_json(path, "external owner inventory")
    if not isinstance(payload, dict) or payload.get("schema_version") != SCHEMA_VERSION:
        raise IntegrationError("external owner inventory schema is invalid")
    owners = payload.get("owners")
    if not isinstance(owners, dict):
        raise IntegrationError("external owner inventory owners are invalid")
    inventory: dict[str, tuple[str, str]] = {}
    for owner_raw, owner_record in owners.items():
        owner = _safe_component(owner_raw, "inventory owner")
        if not isinstance(owner_record, dict) or not isinstance(owner_record.get("folders"), dict):
            raise IntegrationError(f"external owner inventory is invalid for {owner}")
        for folder_raw, digest in owner_record["folders"].items():
            folder = _safe_component(folder_raw, "inventory folder")
            if folder in inventory or not isinstance(digest, str) or not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
                raise IntegrationError(f"external owner inventory entry is invalid: {folder}")
            inventory[folder] = (owner, digest)
    return inventory, raw


def _publish_owner_trees(contract: Contract, target: Path) -> OwnerTransaction:
    if target.exists() and (target.is_symlink() or not target.is_dir()):
        raise IntegrationError(f"owner publication target is not a safe directory: {target}")
    target.mkdir(parents=True, exist_ok=True)
    if target.is_symlink():
        raise IntegrationError(f"owner publication target is symlinked: {target}")

    combined: dict[str, tuple[str, Path, TreeSnapshot]] = {}
    for owner in sorted(contract.owner_sources):
        for folder, source in contract.owner_sources[owner].items():
            if folder in combined:
                raise IntegrationError(f"multiple external owners publish the same folder: {folder}")
            combined[folder] = (owner, source, contract.owner_snapshots[owner][folder])

    previous, previous_raw = _read_owner_inventory(target)
    for folder, (_, _, expected) in combined.items():
        destination = target / folder
        if destination.is_symlink():
            raise IntegrationError(f"refusing symlinked owner destination: {destination}")
        if destination.exists() and folder not in previous:
            if not destination.is_dir() or _tree_snapshot(destination) != expected:
                raise IntegrationError(f"refusing unowned external owner destination collision: {folder}")

    transaction_root = target / f".superbrain-owner-transaction-{uuid.uuid4().hex}"
    stage = transaction_root / "stage"
    backup = transaction_root / "backup"
    stage.mkdir(parents=True, exist_ok=False)
    backup.mkdir()
    moved: list[tuple[str, bool, bool]] = []
    transaction = OwnerTransaction(backup, moved, previous_raw, target / OWNER_INVENTORY_RELATIVE)
    try:
        changed: list[str] = []
        for folder in sorted(combined):
            _, source, expected = combined[folder]
            staged = stage / folder
            shutil.copytree(source, staged, copy_function=shutil.copy2)
            if _tree_snapshot(staged) != expected:
                raise IntegrationError(f"staged external owner tree mismatch: {folder}")
            destination = target / folder
            if destination.is_dir() and _tree_snapshot(destination) == expected:
                continue
            changed.append(folder)
        retired = sorted(set(previous) - set(combined))
        for folder in retired:
            destination = target / folder
            if destination.is_symlink():
                raise IntegrationError(f"refusing symlinked retired owner destination: {folder}")
            if destination.exists():
                if not destination.is_dir() or _tree_snapshot(destination).digest != previous[folder][1]:
                    raise IntegrationError(
                        f"refusing to retire drifted or foreign replacement of owner folder: {folder}"
                    )
        published_count = 0
        for folder in retired + changed:
            destination = target / folder
            prior_present = destination.exists()
            if folder in combined:
                staged = stage / folder
                if prior_present:
                    _rename_exchange(staged, destination)
                    os.replace(staged, backup / folder)
                else:
                    os.replace(staged, destination)
                moved.append((folder, prior_present, True))
                published_count += 1
                raw_threshold = os.environ.get("SUPERBRAIN_TEST_FAIL_AFTER_OWNER_PUBLISH")
                if raw_threshold and int(raw_threshold) > 0 and published_count >= int(raw_threshold):
                    raise IntegrationError(f"simulated owner publication failure after {published_count} tree(s)")
            else:
                if prior_present:
                    os.replace(destination, backup / folder)
                moved.append((folder, prior_present, False))
        _atomic_write(transaction.inventory_path, _canonical_json(_owner_inventory_payload(contract)))
        shutil.rmtree(stage, ignore_errors=True)
        return transaction
    except BaseException as exc:
        rollback_errors = _rollback_owner_publication(transaction, target)
        if rollback_errors:
            raise IntegrationError(
                f"external owner publication failed ({exc}); rollback failed: {'; '.join(rollback_errors)}"
            ) from exc
        if isinstance(exc, IntegrationError):
            raise
        raise IntegrationError(f"external owner publication failed and was rolled back: {exc}") from exc


def _rollback_owner_publication(transaction: OwnerTransaction, target: Path) -> list[str]:
    # Rollback is all-or-nothing with respect to live owner trees. If commit
    # cleanup removed even one required backup, preserve every newly published
    # destination rather than deleting a version that can no longer be restored.
    missing_backups = [
        folder
        for folder, prior_present, _ in transaction.moved
        if prior_present
        and (
            not (transaction.backup / folder).exists()
            or (transaction.backup / folder).is_symlink()
            or not (transaction.backup / folder).is_dir()
        )
    ]
    if missing_backups:
        return [
            "refusing owner rollback because required backup(s) are missing: "
            + ", ".join(sorted(missing_backups))
        ]

    errors: list[str] = []
    for folder, prior_present, published in reversed(transaction.moved):
        destination = target / folder
        prior = transaction.backup / folder
        try:
            if published and prior_present:
                if destination.is_symlink() or not destination.is_dir():
                    raise IntegrationError(f"cannot atomically restore missing or unsafe owner destination: {folder}")
                _rename_exchange(prior, destination)
                _remove_path(prior)
            elif published and (destination.exists() or destination.is_symlink()):
                _remove_path(destination)
            elif prior_present:
                os.replace(prior, destination)
        except (OSError, IntegrationError) as exc:
            errors.append(f"{folder}: {exc}")
    try:
        if transaction.previous_inventory is None:
            transaction.inventory_path.unlink(missing_ok=True)
        else:
            _atomic_write(transaction.inventory_path, transaction.previous_inventory.decode("utf-8"))
    except (OSError, UnicodeError, IntegrationError) as exc:
        errors.append(f"inventory: {exc}")
    if not errors:
        shutil.rmtree(transaction.backup.parent, ignore_errors=True)
    return errors


def _cleanup_committed_owner_debris(
    contract: Contract, target: Path, *, exclude: Path | None = None
) -> None:
    """Retire stale owner transactions only after proving live committed state."""

    current, _ = _read_owner_inventory(target)
    expected = {
        folder: (owner, contract.owner_snapshots[owner][folder].digest)
        for owner in contract.owner_sources
        for folder in contract.owner_sources[owner]
    }
    if current != expected:
        return
    for folder, (_, digest) in expected.items():
        destination = target / folder
        if (
            destination.is_symlink()
            or not destination.is_dir()
            or _tree_snapshot(destination).digest != digest
        ):
            return
    excluded = exclude.resolve(strict=False) if exclude is not None else None
    for transaction in sorted(target.glob(".superbrain-owner-transaction-*")):
        if transaction.is_symlink() or not transaction.is_dir():
            continue
        if excluded is not None and transaction.resolve(strict=False) == excluded:
            continue
        shutil.rmtree(transaction, ignore_errors=True)


def _commit_owner_publication(transaction: OwnerTransaction) -> None:
    """Best-effort cleanup after the verified owner publication commit point."""

    try:
        shutil.rmtree(transaction.backup.parent, ignore_errors=False)
    except Exception:
        # Publication is already verified and committed. A cleanup failure may
        # leave recoverable transaction debris, but must never initiate rollback.
        pass


def _validate_receipt(contract: Contract, target: Path, receipt: Mapping[str, Any] | None) -> None:
    if receipt is None:
        raise IntegrationError("All-Skills receipt is missing")
    required = {
        "schema_version", "receipt_id", "bundle_id", "bundle_version", "installed_at", "target",
        "manifest_sha256", "skills",
    }
    if set(receipt) != required or receipt.get("schema_version") != ALL_SKILLS_SCHEMA_VERSION:
        raise IntegrationError("All-Skills receipt does not match the v2 schema")
    if receipt.get("bundle_id") != contract.bundle_id or receipt.get("bundle_version") != contract.bundle_version:
        raise IntegrationError("All-Skills receipt bundle identity/version is stale")
    if receipt.get("manifest_sha256") != contract.manifest_digest:
        raise IntegrationError("All-Skills receipt manifest digest is stale")
    try:
        receipt_target = Path(str(receipt.get("target", ""))).resolve(strict=False)
    except OSError as exc:
        raise IntegrationError(f"invalid All-Skills receipt target: {exc}") from exc
    if receipt_target != target.resolve(strict=False):
        raise IntegrationError("All-Skills receipt target does not match selected target")
    folders = _receipt_folders(receipt)
    expected = set(contract.all_skills_owned)
    if folders != expected:
        missing = sorted(expected - folders)
        extra = sorted(folders - expected)
        raise IntegrationError(f"All-Skills receipt folder set mismatch; missing={missing}, extra={extra}")
    catalog_names = {str(entry["folder"]): str(entry["name"]) for entry in contract.catalog_entries}
    allowed_skill_keys = {"folder", "name", "content_sha256", "ownership", "rollback_ref"}
    valid_ownership = {"owned", "adopted", "forced-replacement"}
    for record in receipt["skills"]:
        if not isinstance(record, dict):
            raise IntegrationError("All-Skills receipt contains a non-object skill record")
        if not {"folder", "name", "content_sha256", "ownership"}.issubset(record) or not set(record).issubset(allowed_skill_keys):
            raise IntegrationError("All-Skills receipt contains an invalid skill record schema")
        folder = str(record["folder"])
        if record.get("name") != catalog_names[folder]:
            raise IntegrationError(f"All-Skills receipt activation identity mismatch: {folder}")
        digest = record.get("content_sha256")
        if not isinstance(digest, str) or not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
            raise IntegrationError(f"All-Skills receipt content digest is invalid: {folder}")
        expected_source_digest = contract.all_skills_snapshots[folder].digest
        source = contract.all_skills_source / folder
        expected_installed_digest = _projected_install_digest(source, target)
        if digest != expected_installed_digest:
            raise IntegrationError(
                f"All-Skills receipt content digest differs from independently projected source expectation: {folder}"
            )
        rollback_ref = record.get("rollback_ref")
        source_reference = None
        if isinstance(rollback_ref, str):
            source_reference = dict(
                part.partition("=")[::2] for part in rollback_ref.split(";") if "=" in part
            ).get("source")
        if source_reference != expected_source_digest:
            raise IntegrationError(
                f"All-Skills receipt source digest differs from source-derived catalog expectation: {folder}"
            )
        if record.get("ownership") not in valid_ownership:
            raise IntegrationError(f"All-Skills receipt ownership is invalid: {folder}")


def _verify_owner_destinations(contract: Contract, target: Path) -> None:
    expected_inventory: dict[str, tuple[str, str]] = {}
    for owner, sources in contract.owner_sources.items():
        for folder in sorted(sources):
            destination = target / folder
            if destination.is_symlink() or not destination.is_dir():
                raise IntegrationError(f"external owner destination is missing or symlinked: {folder}")
            actual = _tree_snapshot(destination)
            expected = contract.owner_snapshots[owner][folder]
            if actual.files != expected.files or actual.digest != expected.digest:
                raise IntegrationError(f"external owner source/destination tree mismatch: {owner}/{folder}")
            expected_inventory[folder] = (owner, expected.digest)
    actual_inventory, _ = _read_owner_inventory(target)
    if actual_inventory != expected_inventory:
        raise IntegrationError("external owner inventory does not exactly match the complete current owner pack")


def _build_report(
    contract: Contract, validator: Mapping[str, Any], target: Path, public_check: Mapping[str, Any], operation: str
) -> dict[str, Any]:
    owner_counts = {owner: len(sources) for owner, sources in sorted(contract.owner_sources.items())}
    owner_digests = {
        owner: _aggregate_digest(contract.owner_snapshots[owner]) for owner in sorted(contract.owner_snapshots)
    }
    external_report = [
        {
            "folder": item.folder,
            "identity": item.identity,
            "owner": item.owner,
            "digest": contract.owner_snapshots[item.owner][item.folder].digest,
        }
        for item in contract.external
    ]
    unique_between_packs = len(
        set(str(entry["name"]) for entry in contract.catalog_entries)
        | {
            _front_matter_name(source / "SKILL.md")
            for sources in contract.owner_sources.values()
            for source in sources.values()
        }
    )
    return {
        "schema_version": SCHEMA_VERSION,
        "operation": operation,
        "health": "healthy",
        "target": str(target.resolve(strict=False)),
        "counts": {
            "all_skills_packaged": len(contract.catalog_entries),
            "all_skills_receipt_owned": len(contract.all_skills_owned),
            "external_owner_overlaps": len(contract.external),
            "owner_packaged": owner_counts,
            "unique_between_packs": unique_between_packs,
        },
        "all_skills": {
            "bundle_id": contract.bundle_id,
            "bundle_version": contract.bundle_version,
            "manifest_sha256": contract.manifest_digest,
            "validator": dict(validator),
            "check_health": public_check.get("health"),
        },
        "external_owners": {
            "pack_digests": owner_digests,
            "skills": external_report,
        },
    }


def _verify_unlocked(
    workspace: Path,
    target: Path,
    report_path: Path | None,
    *,
    operation: str = "verify",
    lock_fd: int,
) -> dict[str, Any]:
    contract, validator = _load_contract(workspace)
    target = _safe_absolute_path(target, "skills target")
    receipt = _read_receipt_raw(target)
    _validate_receipt(contract, target, receipt)
    public_check, returncode = _run_json(
        ["bash", "install.sh", "check", "--target", str(target), "--json"],
        cwd=contract.all_skills_root,
        allow_failure=True,
        inherited_lock_fd=lock_fd,
    )
    required_check_keys = {
        "schema_version", "operation", "health", "target", "bundle_id", "bundle_version",
        "manifest_sha256", "receipt", "counts", "skills", "issues",
    }
    if not required_check_keys.issubset(public_check):
        raise IntegrationError("All-Skills public check JSON is missing required fields")
    if (
        public_check.get("schema_version") != ALL_SKILLS_SCHEMA_VERSION
        or public_check.get("operation") != "check"
        or public_check.get("bundle_id") != contract.bundle_id
        or public_check.get("bundle_version") != contract.bundle_version
        or public_check.get("manifest_sha256") != contract.manifest_digest
        or public_check.get("target") != str(target)
        or public_check.get("receipt") != receipt
    ):
        raise IntegrationError("All-Skills public check JSON does not match the verified receipt/bundle")
    if returncode or public_check.get("health") != "healthy":
        codes = [str(item.get("code", "unknown")) for item in public_check.get("issues", []) if isinstance(item, dict)]
        raise IntegrationError(f"All-Skills public check is not healthy: {codes}")
    counts = public_check.get("counts")
    if not isinstance(counts, dict) or counts.get("selected") != len(contract.all_skills_owned) or counts.get("issues") != 0:
        raise IntegrationError("All-Skills public check counts do not match exact receipt ownership")
    _verify_owner_destinations(contract, target)
    report = _build_report(contract, validator, target, public_check, operation)
    destination = _safe_absolute_path(report_path or target.parent / "all-skills-integration.json", "report path")
    _atomic_write(destination, _canonical_json(report))
    return report


def verify(workspace: Path, target: Path, report_path: Path | None, *, operation: str = "verify") -> dict[str, Any]:
    safe_target = _safe_absolute_path(target, "skills target")
    destination = _safe_absolute_path(
        report_path or safe_target.parent / "all-skills-integration.json", "report path"
    )
    _validate_report_destination(safe_target, destination)
    with _integration_lock(safe_target) as lock_fd:
        try:
            return _verify_unlocked(
                workspace, safe_target, destination, operation=operation, lock_fd=lock_fd
            )
        except IntegrationError as exc:
            if not destination.is_symlink():
                blocked = {
                    "schema_version": SCHEMA_VERSION,
                    "operation": operation,
                    "health": "blocked",
                    "target": str(safe_target),
                    "error": str(exc),
                }
                _atomic_write(destination, _canonical_json(blocked))
            raise


def _rollback_public_lifecycle(
    contract: Contract,
    target: Path,
    transactions: Sequence[LifecycleTransaction],
    *,
    lock_fd: int,
) -> list[str]:
    failures: list[str] = []
    for expected in reversed(transactions):
        try:
            current_receipt = _read_receipt_raw(target)
            if expected.expected_receipt is None or current_receipt != expected.expected_receipt:
                current_id = current_receipt.get("receipt_id") if isinstance(current_receipt, dict) else None
                failures.append(
                    f"refusing exact rollback because current receipt is not captured transaction "
                    f"{expected.transaction_id} (found {current_id!r})"
                )
                break
            _, rolled_back = _public_lifecycle(
                contract,
                "rollback",
                target,
                lock_fd=lock_fd,
                transaction_id=expected.transaction_id,
            )
            if rolled_back is None or rolled_back.transaction_id != expected.transaction_id:
                actual = rolled_back.transaction_id if rolled_back is not None else "missing"
                failures.append(
                    f"rollback transaction mismatch: expected {expected.transaction_id}, public API returned {actual}"
                )
                break
            if rolled_back.operation != expected.operation:
                failures.append(
                    f"rollback operation mismatch for {expected.transaction_id}: "
                    f"expected {expected.operation}, got {rolled_back.operation}"
                )
                break
        except IntegrationError as exc:
            failures.append(str(exc))
            break
    return failures


def _sync_aibrain(workspace: Path, catalog_path: Path, report_path: Path) -> dict[str, Any]:
    try:
        safe_workspace = _safe_absolute_path(workspace, "AIBrain workspace")
        repository = _safe_absolute_path(safe_workspace / "AIBrain", "AIBrain repository")
        brain = _safe_absolute_path(repository / "scripts/brain.sh", "AIBrain brain.sh")
    except IntegrationError as exc:
        return {"status": "warning", "warnings": [f"AIBrain synchronization skipped: {exc}"]}
    if not repository.is_dir() or repository.is_symlink():
        return {"status": "absent", "warnings": ["AIBrain repository is not present; synchronization skipped"]}
    if brain.is_symlink() or not brain.is_file() or not stat.S_ISREG(brain.stat().st_mode):
        return {"status": "absent", "warnings": ["AIBrain brain.sh is not a safe regular file; synchronization skipped"]}
    warnings: list[str] = []
    commands = (
        ["bash", str(brain), "ingest", str(catalog_path), "--kind", "catalog", "--scope", "all-skills", "--tags", "catalog,skills-v2", "--json"],
        ["bash", str(brain), "ingest", str(report_path), "--kind", "integration-health", "--scope", "superbrain", "--tags", "all-skills,claude-power,receipt", "--json"],
    )
    for command in commands:
        try:
            process = subprocess.run(
                command,
                cwd=repository,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=120,
                check=False,
            )
            if process.returncode:
                warnings.append(f"AIBrain ingest failed for {Path(command[3]).name} (exit {process.returncode})")
        except (OSError, subprocess.SubprocessError) as exc:
            warnings.append(f"AIBrain ingest could not run: {exc}")
    try:
        status = subprocess.run(
            ["bash", str(brain), "status"], cwd=repository, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, timeout=120, check=False,
        )
        if status.returncode:
            warnings.append(f"AIBrain status failed (exit {status.returncode})")
        elif "Index: stale" in status.stdout:
            rebuild = subprocess.run(
                ["bash", str(brain), "index", "build"], cwd=repository, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, text=True, timeout=120, check=False,
            )
            if rebuild.returncode:
                warnings.append(f"AIBrain index rebuild failed (exit {rebuild.returncode})")
    except (OSError, subprocess.SubprocessError) as exc:
        warnings.append(f"AIBrain index synchronization could not run: {exc}")
    return {"status": "warning" if warnings else "synchronized", "warnings": warnings}


def install(workspace: Path, target: Path, report_path: Path | None, *, sync_aibrain: bool = True) -> dict[str, Any]:
    target = _safe_absolute_path(target, "skills target")
    effective_report = _safe_absolute_path(
        report_path or target.parent / "all-skills-integration.json", "report path"
    )
    _validate_report_destination(target, effective_report)
    with _integration_lock(target) as lock_fd:
        contract, _ = _load_contract(workspace)
        if effective_report.exists() and (effective_report.is_symlink() or not effective_report.is_file()):
            raise IntegrationError(f"refusing unsafe existing report path: {effective_report}")
        previous_report = effective_report.read_bytes() if effective_report.exists() else None
        initial_receipt = _read_receipt_raw(target)
        known_receipt_ids = {
            str(initial_receipt.get("receipt_id"))
            for _ in (0,)
            if isinstance(initial_receipt, dict) and isinstance(initial_receipt.get("receipt_id"), str)
        }
        external_folders = {item.folder for item in contract.external}
        currently_owned_external = sorted(_receipt_folders(initial_receipt) & external_folders)
        lifecycle_transactions: list[LifecycleTransaction] = []
        owner_transaction: OwnerTransaction | None = None
        committed_owner_transaction: OwnerTransaction | None = None
        try:
            if currently_owned_external:
                _, transaction = _public_lifecycle(
                    contract,
                    "uninstall",
                    target,
                    currently_owned_external,
                    lock_fd=lock_fd,
                )
                if transaction is not None:
                    lifecycle_transactions.append(transaction)
                    known_receipt_ids.add(transaction.transaction_id)
            _, transaction = _public_lifecycle(
                contract,
                "install",
                target,
                contract.all_skills_owned,
                lock_fd=lock_fd,
            )
            if transaction is not None:
                lifecycle_transactions.append(transaction)
                known_receipt_ids.add(transaction.transaction_id)
            owner_transaction = _publish_owner_trees(contract, target)
            result = _verify_unlocked(
                workspace,
                target,
                effective_report,
                operation="install",
                lock_fd=lock_fd,
            )
            result["aibrain_sync"] = (
                _sync_aibrain(
                    _safe_absolute_path(workspace, "workspace"),
                    contract.all_skills_root / "catalog/skills.json",
                    effective_report,
                )
                if sync_aibrain
                else {"status": "disabled", "warnings": []}
            )
            _atomic_write(effective_report, _canonical_json(result))
            # This is the commit point. Cleanup below is post-commit best effort
            # and can no longer enter transaction rollback.
            committed_owner_transaction = owner_transaction
            owner_transaction = None
        except BaseException as exc:
            receipt_failures: list[str] = []
            current_receipt: dict[str, Any] | None = None
            try:
                current_receipt = _read_receipt_raw(target)
            except IntegrationError as receipt_exc:
                receipt_failures.append(
                    f"refusing lifecycle rollback because current receipt is unreadable: {receipt_exc}"
                )
            if isinstance(current_receipt, dict):
                current_id = current_receipt.get("receipt_id")
                if not isinstance(current_id, str) or current_id not in known_receipt_ids:
                    receipt_failures.append(
                        f"refusing lifecycle rollback of unexplained current receipt {current_id!r}"
                    )
            owner_failures = (
                _rollback_owner_publication(owner_transaction, target) if owner_transaction is not None else []
            )
            lifecycle_failures = receipt_failures or _rollback_public_lifecycle(
                contract, target, lifecycle_transactions, lock_fd=lock_fd
            )
            report_failures: list[str] = []
            try:
                if previous_report is None:
                    effective_report.unlink(missing_ok=True)
                else:
                    _atomic_write(effective_report, previous_report.decode("utf-8"))
            except (OSError, UnicodeError, IntegrationError) as report_exc:
                report_failures.append(str(report_exc))
            rollback_failures = owner_failures + lifecycle_failures + report_failures
            if rollback_failures:
                raise IntegrationError(
                    f"{exc}; integration rollback failed: {'; '.join(rollback_failures)}"
                ) from exc
            raise IntegrationError(f"{exc}; integration transaction was rolled back") from exc

        if committed_owner_transaction is not None:
            _commit_owner_publication(committed_owner_transaction)
            _cleanup_committed_owner_debris(contract, target)

    return result


ARTIFACT_JOURNAL_NAME = ".superbrain-artifact-publication.json"
ARTIFACT_LOCK_NAME = ".superbrain-artifact-publication.lock"


def _fsync_directory(path: Path) -> None:
    flags = os.O_RDONLY
    if hasattr(os, "O_DIRECTORY"):
        flags |= os.O_DIRECTORY
    try:
        descriptor = os.open(path, flags)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
    except OSError as exc:
        raise IntegrationError(f"cannot durably synchronize directory {path}: {exc}") from exc


def _durable_write(path: Path, content: str) -> None:
    """Atomically write and fsync both a journal file and its directory entry."""

    path = _safe_absolute_path(path, "durable output path")
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and (path.is_symlink() or not path.is_file()):
        raise IntegrationError(f"refusing unsafe durable output path: {path}")
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=path.parent
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
        _fsync_directory(path.parent)
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise


def _remove_durable_file(path: Path) -> None:
    path.unlink(missing_ok=True)
    _fsync_directory(path.parent)


@contextmanager
def _artifact_publication_lock(lock_root: Path) -> Iterator[Path]:
    root = _safe_absolute_path(lock_root, "artifact publication lock root")
    root.mkdir(parents=True, exist_ok=True)
    root = _safe_absolute_path(root, "artifact publication lock root")
    lock_path = root / ARTIFACT_LOCK_NAME
    flags = os.O_RDWR | os.O_CREAT
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        descriptor = os.open(lock_path, flags, 0o600)
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            os.close(descriptor)
            raise IntegrationError(f"artifact publication lock is not a regular file: {lock_path}")
    except IntegrationError:
        raise
    except OSError as exc:
        raise IntegrationError(f"cannot open artifact publication lock: {exc}") from exc
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield root / ARTIFACT_JOURNAL_NAME
    finally:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_UN)
        finally:
            os.close(descriptor)


def _fsync_tree(root: Path) -> None:
    paths = list(_iter_tree_files(root))
    for path in paths:
        try:
            descriptor = os.open(path, os.O_RDONLY)
            try:
                os.fsync(descriptor)
            finally:
                os.close(descriptor)
        except OSError as exc:
            raise IntegrationError(f"cannot durably synchronize staged artifact {path}: {exc}") from exc
    directories = sorted(
        (path for path in root.rglob("*") if path.is_dir()),
        key=lambda path: len(path.parts),
        reverse=True,
    )
    for directory in directories:
        _fsync_directory(directory)
    _fsync_directory(root)


def _artifact_journal_payload(
    destination: Path,
    transaction: Path,
    stage: Path,
    backup: Path,
    prior_present: bool,
    state: str,
) -> dict[str, Any]:
    return {
        "schema_version": SCHEMA_VERSION,
        "operation": "artifact-publication",
        "state": state,
        "destination": str(destination),
        "transaction": str(transaction),
        "stage": str(stage),
        "backup": str(backup),
        "prior_present": prior_present,
    }


def _load_artifact_journal(path: Path) -> dict[str, Any] | None:
    if not path.exists():
        return None
    payload = _load_json(path, "artifact publication journal")
    required = {
        "schema_version", "operation", "state", "destination", "transaction",
        "stage", "backup", "prior_present",
    }
    if (
        not isinstance(payload, dict)
        or set(payload) != required
        or payload.get("schema_version") != SCHEMA_VERSION
        or payload.get("operation") != "artifact-publication"
        or payload.get("state") not in {"staging", "prepared", "committed"}
        or not isinstance(payload.get("prior_present"), bool)
    ):
        raise IntegrationError("artifact publication journal is invalid")
    return payload


def _cleanup_artifact_transaction(transaction: Path, journal_path: Path) -> None:
    try:
        if transaction.exists():
            if transaction.is_symlink() or not transaction.is_dir():
                raise IntegrationError(f"unsafe artifact transaction path: {transaction}")
            shutil.rmtree(transaction)
            _fsync_directory(transaction.parent)
        _remove_durable_file(journal_path)
    except OSError as exc:
        raise IntegrationError(f"cannot clean artifact publication transaction: {exc}") from exc


def _recover_artifact_publication(journal_path: Path) -> None:
    payload = _load_artifact_journal(journal_path)
    if payload is None:
        return
    lock_root = _safe_absolute_path(journal_path.parent, "artifact publication lock root")
    destination = _safe_absolute_path(Path(str(payload["destination"])), "journal destination")
    transaction = _safe_absolute_path(Path(str(payload["transaction"])), "journal transaction")
    stage = _safe_absolute_path(Path(str(payload["stage"])), "journal stage")
    backup = _safe_absolute_path(Path(str(payload["backup"])), "journal backup")
    prior_present = bool(payload["prior_present"])
    if destination == lock_root or not destination.is_relative_to(lock_root):
        raise IntegrationError("artifact publication journal destination escapes its lock root")
    if (
        transaction.parent != destination.parent
        or not transaction.name.startswith(".superbrain-artifact-publication-")
        or stage.parent != transaction
        or backup.parent != transaction
    ):
        raise IntegrationError("artifact publication journal paths are not confined to the destination filesystem")
    if destination.is_symlink() or stage.is_symlink() or backup.is_symlink() or transaction.is_symlink():
        raise IntegrationError("artifact publication recovery refuses symlinked state")

    destination_present = destination.exists()
    stage_present = stage.exists()
    backup_present = backup.exists()
    if payload["state"] == "staging":
        # The live destination has not been touched. A partial or complete
        # staged copy is untrusted scratch and can be retired under the lock.
        _cleanup_artifact_transaction(transaction, journal_path)
        return
    if payload["state"] == "committed":
        if destination_present:
            _cleanup_artifact_transaction(transaction, journal_path)
            return
        if prior_present and backup_present:
            os.replace(backup, destination)
            _fsync_directory(destination.parent)
            _cleanup_artifact_transaction(transaction, journal_path)
            return
        if not prior_present:
            # No old live tree can be lost. Clear the interrupted transaction;
            # the current call will republish from its validated source.
            _cleanup_artifact_transaction(transaction, journal_path)
            return
        raise IntegrationError("committed artifact publication has no recoverable live destination")

    if prior_present:
        if backup_present and stage_present and not destination_present:
            # Intent was durable but publication was interrupted after moving the
            # old live tree. Restore it before accepting new work.
            os.replace(backup, destination)
            _fsync_directory(destination.parent)
        elif backup_present and not stage_present and destination_present:
            # The stage reached the live name. Preserve the new live tree and
            # finish post-commit cleanup.
            pass
        elif backup_present and not stage_present and not destination_present:
            os.replace(backup, destination)
            _fsync_directory(destination.parent)
        elif not backup_present and stage_present and destination_present:
            # No live mutation occurred; discard the abandoned prepared stage.
            pass
        else:
            raise IntegrationError(
                "artifact publication journal has ambiguous or unrecoverable prior-destination state"
            )
    else:
        if backup_present:
            raise IntegrationError("artifact publication unexpectedly backed up an absent destination")
        if stage_present and not destination_present:
            pass
        elif not stage_present and destination_present:
            # First publication completed before the committed journal update.
            pass
        elif not stage_present and not destination_present:
            # Nothing previously existed and nothing live can be lost. Discard
            # the stale intent so this call can publish a fresh stage.
            pass
        else:
            raise IntegrationError(
                "artifact publication journal has ambiguous new-destination state"
            )
    _cleanup_artifact_transaction(transaction, journal_path)


def _validate_artifact_pair(kind: str, source: Path, destination: Path) -> tuple[str, Path, Path]:
    source = _safe_absolute_path(source, "artifact source")
    destination = _safe_absolute_path(destination, "artifact destination")
    destination.parent.mkdir(parents=True, exist_ok=True)
    _safe_absolute_path(destination.parent, "artifact destination parent")
    if source == destination or source.is_relative_to(destination) or destination.is_relative_to(source):
        raise IntegrationError("artifact source and destination must not overlap")
    if kind == "tree":
        _iter_tree_files(source)
        if destination.exists() and not destination.is_dir():
            raise IntegrationError(f"tree artifact destination is not a directory: {destination}")
    elif kind == "file":
        if source.is_symlink() or not source.is_file():
            raise IntegrationError(f"missing safe artifact source file: {source}")
        if destination.exists() and not destination.is_file():
            raise IntegrationError(f"file artifact destination is not a file: {destination}")
    else:
        raise IntegrationError(f"unsupported artifact kind: {kind}")
    return kind, source, destination


def _expand_artifact_operations(
    files: Sequence[Sequence[Path]],
    trees: Sequence[Sequence[Path]],
    contents: Sequence[Sequence[Path]],
) -> list[tuple[str, Path, Path]]:
    operations: list[tuple[str, Path, Path]] = []
    for source, destination in files:
        operations.append(_validate_artifact_pair("file", source, destination))
    for source, destination in trees:
        operations.append(_validate_artifact_pair("tree", source, destination))
    for source_raw, destination_raw in contents:
        source = _safe_absolute_path(source_raw, "artifact contents source")
        destination = _safe_absolute_path(destination_raw, "artifact contents destination")
        if source.is_symlink() or not source.is_dir():
            raise IntegrationError(f"missing safe artifact contents source: {source}")
        destination.mkdir(parents=True, exist_ok=True)
        for artifact in sorted(source.iterdir(), key=lambda item: item.name):
            kind = "tree" if artifact.is_dir() and not artifact.is_symlink() else "file"
            operations.append(
                _validate_artifact_pair(kind, artifact, destination / artifact.name)
            )
    return operations


def _publish_artifact_file(source: Path, destination: Path) -> None:
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{destination.name}.superbrain-file.", dir=destination.parent
    )
    temporary = Path(temporary_name)
    try:
        with source.open("rb") as reader, os.fdopen(descriptor, "wb") as writer:
            shutil.copyfileobj(reader, writer)
            os.fchmod(writer.fileno(), source.stat().st_mode & 0o777)
            writer.flush()
            os.fsync(writer.fileno())
        os.replace(temporary, destination)
        _fsync_directory(destination.parent)
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise


def _rename_exchange(first: Path, second: Path) -> None:
    """Atomically exchange two existing directory entries on Linux."""

    try:
        renameat2 = ctypes.CDLL(None, use_errno=True).renameat2
    except AttributeError as exc:
        raise IntegrationError(
            "atomic tree replacement requires renameat2(RENAME_EXCHANGE) on this platform"
        ) from exc
    renameat2.argtypes = [
        ctypes.c_int,
        ctypes.c_char_p,
        ctypes.c_int,
        ctypes.c_char_p,
        ctypes.c_uint,
    ]
    renameat2.restype = ctypes.c_int
    at_fdcwd = -100
    rename_exchange = 2
    result = renameat2(
        at_fdcwd,
        os.fsencode(first),
        at_fdcwd,
        os.fsencode(second),
        rename_exchange,
    )
    if result != 0:
        error = ctypes.get_errno()
        raise IntegrationError(
            f"atomic tree exchange failed for {first} and {second}: {os.strerror(error)}"
        )


def _publish_artifact_tree(source: Path, destination: Path, journal_path: Path) -> None:
    transaction = Path(
        tempfile.mkdtemp(prefix=".superbrain-artifact-publication-", dir=destination.parent)
    )
    stage = transaction / "stage"
    backup = transaction / "backup"
    prior_present = destination.exists()
    journal = _artifact_journal_payload(
        destination, transaction, stage, backup, prior_present, "staging"
    )
    try:
        _durable_write(journal_path, _canonical_json(journal))
        shutil.copytree(source, stage, copy_function=shutil.copy2)
        _iter_tree_files(stage)
        _fsync_tree(stage)
        if os.stat(stage).st_dev != os.stat(destination.parent).st_dev:
            raise IntegrationError("artifact stage is not on the destination filesystem")
        journal["state"] = "prepared"
        _durable_write(journal_path, _canonical_json(journal))
        if prior_present:
            # Exchange keeps a valid tree continuously visible to lock-free
            # readers. After the exchange, ``stage`` contains the prior live
            # tree and can be moved to the durable recovery name.
            _rename_exchange(stage, destination)
            _fsync_directory(destination.parent)
            os.replace(stage, backup)
            _fsync_directory(destination.parent)
            if os.environ.get("SUPERBRAIN_TEST_CRASH_AFTER_ARTIFACT_BACKUP") == "1":
                os._exit(91)
        else:
            os.replace(stage, destination)
            _fsync_directory(destination.parent)
        if os.environ.get("SUPERBRAIN_TEST_CRASH_AFTER_ARTIFACT_PUBLISH") == "1":
            os._exit(92)
        journal["state"] = "committed"
        _durable_write(journal_path, _canonical_json(journal))
    except BaseException:
        if journal_path.exists():
            _recover_artifact_publication(journal_path)
        elif transaction.exists():
            shutil.rmtree(transaction, ignore_errors=True)
        raise
    try:
        _cleanup_artifact_transaction(transaction, journal_path)
    except IntegrationError as exc:
        # The committed live artifact is authoritative. Stop this batch before
        # another tree can overwrite the retained recovery journal.
        raise IntegrationError(
            f"artifact published but durable transaction cleanup is pending: {exc}"
        ) from exc


def publish_artifacts(
    lock_root: Path,
    *,
    files: Sequence[Sequence[Path]] = (),
    trees: Sequence[Sequence[Path]] = (),
    contents: Sequence[Sequence[Path]] = (),
) -> dict[str, Any]:
    with _artifact_publication_lock(lock_root) as journal_path:
        _recover_artifact_publication(journal_path)
        operations = _expand_artifact_operations(files, trees, contents)
        safe_lock_root = _safe_absolute_path(journal_path.parent, "artifact publication lock root")
        for _, _, destination in operations:
            if destination == safe_lock_root or not destination.is_relative_to(safe_lock_root):
                raise IntegrationError(
                    f"artifact destination escapes publication lock root: {destination}"
                )
        for kind, source, destination in operations:
            if kind == "file":
                _publish_artifact_file(source, destination)
            else:
                _publish_artifact_tree(source, destination, journal_path)
    return {
        "schema_version": SCHEMA_VERSION,
        "operation": "publish-artifacts",
        "health": "healthy",
        "published": len(operations),
    }


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    for command in ("install", "verify"):
        sub = subparsers.add_parser(command)
        sub.add_argument("--workspace", type=Path, default=DEFAULT_WORKSPACE)
        sub.add_argument("--target", type=Path, default=DEFAULT_TARGET)
        sub.add_argument("--report", type=Path)
        if command == "install":
            sub.add_argument("--no-aibrain-sync", action="store_true", help="skip optional best-effort AIBrain ingestion")
    publication = subparsers.add_parser("publish-artifacts")
    publication.add_argument("--lock-root", type=Path, required=True)
    publication.add_argument("--file", nargs=2, action="append", type=Path, default=[])
    publication.add_argument("--tree", nargs=2, action="append", type=Path, default=[])
    publication.add_argument("--contents", nargs=2, action="append", type=Path, default=[])
    safe_file = subparsers.add_parser("check-safe-file")
    safe_file.add_argument("--path", type=Path, required=True)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    try:
        if args.command == "install":
            result = install(
                args.workspace, args.target, args.report, sync_aibrain=not args.no_aibrain_sync
            )
        elif args.command == "verify":
            result = verify(args.workspace, args.target, args.report)
        elif args.command == "check-safe-file":
            result = check_safe_file(args.path)
        else:
            result = publish_artifacts(
                args.lock_root,
                files=args.file,
                trees=args.tree,
                contents=args.contents,
            )
    except IntegrationError as exc:
        print(_compact_json({"schema_version": SCHEMA_VERSION, "operation": args.command, "health": "blocked", "error": str(exc)}), end="")
        return 1
    except (OSError, ValueError) as exc:
        print(_compact_json({"schema_version": SCHEMA_VERSION, "operation": args.command, "health": "blocked", "error": f"safe filesystem/input failure: {exc}"}), end="")
        return 1
    except Exception as exc:  # Defensive CLI boundary: never expose a traceback for malformed inputs.
        print(_compact_json({"schema_version": SCHEMA_VERSION, "operation": args.command, "health": "blocked", "error": f"unexpected integration failure: {type(exc).__name__}"}), end="")
        return 1
    print(_compact_json(result), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
