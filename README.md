# ⚡ SuperBrain

SuperBrain bootstraps and verifies the connected SEO, scraping, skills, and intelligence workspace from one repository.

## Quick start

```bash
bash /projects/sandbox/SuperBrain/scripts/bootstrap.sh
```

Bootstrap clones missing repositories, installs the two Python packages and CLIs, publishes Kiro artifacts, performs exact connected-skill verification, and atomically creates `.bootstrapped` only after every required check succeeds.

## Deterministic skill ownership

All-Skills and Claude-Power overlap on `token-efficiency`. SuperBrain resolves that overlap from All-Skills' public catalog metadata rather than installation order:

| Source | Packaged | Combined ownership |
|---|---:|---|
| All-Skills | 45 | Its v2 receipt owns exactly 44 |
| Claude-Power | 16 | Owns its complete pack, including the one declared overlap, `token-efficiency` |
| Unique between both packs | 60 | 44 All-Skills-only + 16 Claude-Power |
| AIBrain and SuperBrain | 1 each when installed | Additional workspace skills |

These counts are informational, not health invariants. Health comes from `scripts/skills_integration.py verify`, which proves:

- `bundle.json` and `catalog/skills.json` identities, count, manifest digest, and packaged tree checksums;
- `python3 scripts/all_skills.py validate --json` reports zero errors (warnings are preserved);
- the All-Skills v2 receipt has the current schema, bundle/version/manifest, and exactly the 44 computed All-Skills-owned folders;
- public `install.sh check --json` reports `healthy`;
- Claude-Power source and installed trees have identical complete path sets and deterministic digests, including its canonical `token-efficiency` tree.

Unrelated foreign skill directories are allowed and never used to infer health. The compact current report is written atomically to `/projects/.kiro/all-skills-integration.json` by default.

All-Skills remains standalone-compatible: running its no-argument `install.sh` outside the combined SuperBrain flow installs all 45 skills, including its standalone `token-efficiency` copy. During migration from such an install, SuperBrain uses All-Skills' public uninstall selection to relinquish that one receipt entry before publishing Claude-Power's canonical tree.

## Integration commands

```bash
# Additive, idempotent combined install
python3 scripts/skills_integration.py install

# Exact read-only verification (apart from atomically refreshing the report)
python3 scripts/skills_integration.py verify

# Explicit paths for tests or alternate workspaces
python3 scripts/skills_integration.py verify \
  --workspace /path/to/workspace \
  --target /path/to/.kiro/skills \
  --report /path/to/health.json
```

The helper is Python-standard-library-only and consumes only All-Skills' public JSON and CLI contracts; it does not import All-Skills modules. Install and verify hold All-Skills' exact `.<target>.all-skills.lock` for the complete integration transaction and pass that descriptor to every public lifecycle/check subprocess through `ALL_SKILLS_LOCK_FD`. Rollback uses only captured receipt states; unexplained receipt identities fail closed.

Bootstrap and repair also delegate file/tree publication to the helper's internal `publish-artifacts` command. It serializes both scripts under one Kiro-root lock, stages trees on the destination filesystem, fsyncs a recovery journal before renaming a live tree, recovers interrupted prepared transactions on the next call, and keeps individual file replacement atomic.

## Optional AIBrain synchronization

After a successful combined install, the helper checks for `AIBrain/scripts/brain.sh`. When available, it best-effort ingests the current All-Skills catalog (`kind=catalog`, `scope=all-skills`) and compact integration report (`kind=integration-health`, `scope=superbrain`), then rebuilds a stale index. AIBrain absence or synchronization failure is reported as a warning and never changes exact skill health. All-Skills does not call or import AIBrain.

## Workspace scripts

| Script | Purpose |
|---|---|
| `scripts/bootstrap.sh` | Full install, exact final verification, atomic success marker |
| `scripts/skills_integration.py` | Deterministic All-Skills/Claude-Power install and verification |
| `scripts/verify.sh` | Whole-workspace health check without reinstalling |
| `scripts/repair.sh` | Repair exact skills, packages, repositories, or AIBrain wiring |
| `scripts/workspace-setup.sh` | Load environment variables |

```bash
bash scripts/verify.sh
bash scripts/repair.sh skills
bash scripts/repair.sh packages
bash scripts/repair.sh aibrain
bash scripts/repair.sh auto
```

`/projects/sandbox/connect-all.sh` is a legacy bypass outside this repository. It is not an ownership or verification contract and must not be used to determine connected-workspace health.

## Managed repositories

| Repository | Purpose |
|---|---|
| All-Skills | Versioned design/UX/WordPress skills bundle and public lifecycle |
| Claude-Power | Engineering skills, steering, and scripts |
| AIBrain | Optional persistent local intelligence |
| ScrapeToolAi | Web scraping framework and `scrapetool` CLI |
| goaaiseo-seo-adapter | SEO normalization and `gsa` CLI |
| goaaiseo | Autonomous SEO OS blueprint |

Environment variables are written to `/projects/sandbox/SuperBrain/.env` after bootstrap.

## License

MIT
