---
inclusion: always
description: "SuperBrain — deterministic connected-workspace bootstrap, verification, and repair orchestrator."
---

# SuperBrain Protocol

SuperBrain is the workspace orchestrator. When connected, required repositories and integrations must be present and verifiably healthy.

## Session start

1. Check `test -f /projects/sandbox/SuperBrain/.bootstrapped`.
2. If absent, run:
   ```bash
   bash /projects/sandbox/SuperBrain/scripts/bootstrap.sh
   ```
3. The marker is created atomically only after exact skill ownership and all required workspace checks pass.

## Skill ownership contract

- All-Skills packages 45 skills.
- In a combined workspace, its v2 receipt owns exactly 44.
- Claude-Power packages 16 and is the catalog-declared canonical owner of the one overlap, `token-efficiency`.
- The packs contain 60 unique identities; AIBrain and SuperBrain add one each when installed.
- Counts are informational only. Never use a total directory count as health evidence.
- Exact health is the catalog, receipt, public All-Skills check, and Claude-Power source-tree digest report produced by `scripts/skills_integration.py verify`.
- Unrelated foreign skill directories are allowed.

All-Skills' no-argument standalone installer still installs all 45. SuperBrain's combined helper selects the 44 non-external entries and uses the public All-Skills uninstall lifecycle when migrating a receipt that owns `token-efficiency`.

## Optional AIBrain synchronization

After successful skill integration, SuperBrain best-effort ingests the All-Skills catalog and compact health report when `AIBrain/scripts/brain.sh` exists. AIBrain absence or synchronization failure is a warning, not a skill-health failure. All-Skills remains independent of AIBrain.

## Commands

```bash
export PATH="/root/.pyenv/versions/3.11.15/bin:$PATH"

bash /projects/sandbox/SuperBrain/scripts/bootstrap.sh
bash /projects/sandbox/SuperBrain/scripts/verify.sh
bash /projects/sandbox/SuperBrain/scripts/repair.sh skills

python3 /projects/sandbox/SuperBrain/scripts/skills_integration.py verify

bash /projects/sandbox/AIBrain/scripts/brain.sh status
scrapetool fetch https://example.com
gsa doctor
```

`/projects/sandbox/connect-all.sh` is a legacy bypass and never defines health.

## Contract

1. Clone missing managed repositories automatically.
2. Install missing packages automatically.
3. Use public All-Skills v2 contracts and deterministic external ownership.
4. Propagate required installation and verification failures.
5. Never publish `.bootstrapped` after partial failure.
6. Never ask the user to perform setup that SuperBrain can safely perform itself.
