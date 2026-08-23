from __future__ import annotations

import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


REPOSITORY = Path(__file__).resolve().parents[1]
HELPER = REPOSITORY / "scripts/skills_integration.py"
WORKSPACE = REPOSITORY.parent
ALL_SKILLS = WORKSPACE / "All-Skills"
CLAUDE_POWER = WORKSPACE / "Claude-Power"


class ConnectedSkillsIntegrationTests(unittest.TestCase):
    maxDiff = 2000

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.target = self.root / "kiro/skills"
        self.report = self.root / "health.json"

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def run_helper(
        self,
        command: str,
        *,
        expected: int = 0,
        environment: dict[str, str] | None = None,
        target: Path | None = None,
        report: Path | None = None,
    ) -> dict[str, object]:
        selected_target = target or self.target
        selected_report = report or self.report
        arguments = [
            sys.executable,
            str(HELPER),
            command,
            "--workspace",
            str(WORKSPACE),
            "--target",
            str(selected_target),
            "--report",
            str(selected_report),
        ]
        if command == "install":
            arguments.append("--no-aibrain-sync")
        run_environment = os.environ.copy()
        run_environment.pop("KIRO_SKILLS_DIR", None)
        if environment:
            run_environment.update(environment)
        process = subprocess.run(
            arguments,
            cwd=REPOSITORY,
            env=run_environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=300,
            check=False,
        )
        self.assertEqual(
            expected,
            process.returncode,
            msg=f"stdout={process.stdout[-2000:]}\nstderr={process.stderr[-2000:]}",
        )
        return json.loads(process.stdout)

    @property
    def receipt_path(self) -> Path:
        return self.target / ".all-skills-receipts/all-skills.json"

    def read_receipt(self) -> dict[str, object]:
        return json.loads(self.receipt_path.read_text(encoding="utf-8"))

    def install_combined(self) -> dict[str, object]:
        return self.run_helper("install")

    def load_helper_module(self):
        spec = importlib.util.spec_from_file_location("skills_integration_under_test", HELPER)
        self.assertIsNotNone(spec)
        self.assertIsNotNone(spec.loader)
        module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)
        return module

    def test_fresh_combined_install_has_exact_ownership_and_allows_foreign_skill(self) -> None:
        result = self.install_combined()
        receipt = self.read_receipt()
        folders = {item["folder"] for item in receipt["skills"]}

        self.assertEqual(45, result["counts"]["all_skills_packaged"])
        self.assertEqual(44, result["counts"]["all_skills_receipt_owned"])
        self.assertEqual(60, result["counts"]["unique_between_packs"])
        self.assertEqual(44, len(folders))
        self.assertNotIn("token-efficiency", folders)
        self.assertEqual(
            sorted(path.relative_to(CLAUDE_POWER / ".kiro/skills/token-efficiency").as_posix()
                   for path in (CLAUDE_POWER / ".kiro/skills/token-efficiency").rglob("*") if path.is_file()),
            sorted(path.relative_to(self.target / "token-efficiency").as_posix()
                   for path in (self.target / "token-efficiency").rglob("*") if path.is_file()),
        )

        foreign = self.target / "foreign-local-skill"
        foreign.mkdir()
        (foreign / "SKILL.md").write_text("foreign\n", encoding="utf-8")
        verified = self.run_helper("verify")
        self.assertEqual("healthy", verified["health"])
        self.assertTrue(foreign.is_dir())

    def test_install_is_idempotent_and_report_is_stable(self) -> None:
        first = self.install_combined()
        first_report = self.report.read_bytes()
        second = self.install_combined()
        self.assertEqual(first, second)
        self.assertEqual(first_report, self.report.read_bytes())
        self.assertEqual(44, len(self.read_receipt()["skills"]))

    def test_migrates_standalone_receipt_that_owns_token_efficiency(self) -> None:
        environment = os.environ.copy()
        environment.pop("KIRO_SKILLS_DIR", None)
        process = subprocess.run(
            ["bash", "install.sh", "install", "--target", str(self.target), "--json"],
            cwd=ALL_SKILLS,
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=300,
            check=False,
        )
        self.assertEqual(0, process.returncode, msg=process.stderr)
        self.assertEqual(45, len(self.read_receipt()["skills"]))
        self.assertIn("token-efficiency", {item["folder"] for item in self.read_receipt()["skills"]})

        self.install_combined()
        folders = {item["folder"] for item in self.read_receipt()["skills"]}
        self.assertEqual(44, len(folders))
        self.assertNotIn("token-efficiency", folders)
        self.assertIn("references/command-recipes.md", {
            path.relative_to(self.target / "token-efficiency").as_posix()
            for path in (self.target / "token-efficiency").rglob("*") if path.is_file()
        })

    def test_tampered_all_skills_tree_fails_exact_verification(self) -> None:
        self.install_combined()
        with (self.target / "banner-design/SKILL.md").open("a", encoding="utf-8") as handle:
            handle.write("\ntampered\n")
        result = self.run_helper("verify", expected=1)
        self.assertEqual("blocked", result["health"])
        self.assertIn("public check", result["error"])

    def test_tampered_external_owner_tree_fails_exact_verification(self) -> None:
        self.install_combined()
        with (self.target / "token-efficiency/SKILL.md").open("a", encoding="utf-8") as handle:
            handle.write("\ntampered\n")
        result = self.run_helper("verify", expected=1)
        self.assertEqual("blocked", result["health"])
        self.assertIn("external owner", result["error"])

    def test_missing_extra_and_stale_receipts_fail(self) -> None:
        self.install_combined()
        original = self.receipt_path.read_bytes()

        self.receipt_path.unlink()
        missing = self.run_helper("verify", expected=1)
        self.assertIn("receipt is missing", missing["error"])

        self.receipt_path.parent.mkdir(parents=True, exist_ok=True)
        self.receipt_path.write_bytes(original)
        extra_receipt = self.read_receipt()
        extra_receipt["skills"].append({
            "folder": "retired-skill",
            "name": "retired-skill",
            "content_sha256": "sha256:" + "0" * 64,
            "ownership": "owned",
            "rollback_ref": None,
        })
        self.receipt_path.write_text(json.dumps(extra_receipt), encoding="utf-8")
        extra = self.run_helper("verify", expected=1)
        self.assertIn("folder set mismatch", extra["error"])

        self.receipt_path.write_bytes(original)
        stale_receipt = self.read_receipt()
        stale_receipt["manifest_sha256"] = "sha256:" + "f" * 64
        self.receipt_path.write_text(json.dumps(stale_receipt), encoding="utf-8")
        stale = self.run_helper("verify", expected=1)
        self.assertIn("manifest digest is stale", stale["error"])

    def test_owner_publication_failure_rolls_back_all_lifecycle_changes(self) -> None:
        result = self.run_helper(
            "install",
            expected=1,
            environment={"SUPERBRAIN_TEST_FAIL_AFTER_OWNER_PUBLISH": "1"},
        )
        self.assertIn("rolled back", result["error"])
        self.assertFalse(self.receipt_path.exists())
        self.assertFalse((self.target / "banner-design").exists())
        self.assertFalse((self.target / "api-contract-design").exists())

    def test_symlinked_target_report_and_target_ancestor_are_rejected(self) -> None:
        install_report_referent = self.root / "install-report-referent.json"
        install_report_referent.write_text("unchanged\n", encoding="utf-8")
        linked_install_report = self.root / "linked-install-report.json"
        linked_install_report.symlink_to(install_report_referent)
        install_report_result = self.run_helper("install", expected=1, report=linked_install_report)
        self.assertIn("symlinked report path component", install_report_result["error"])
        self.assertFalse(self.receipt_path.exists())
        self.assertFalse((self.target / "banner-design").exists())
        self.assertEqual("unchanged\n", install_report_referent.read_text(encoding="utf-8"))

        real_target = self.root / "real-target"
        real_target.mkdir()
        linked_target = self.root / "linked-target"
        linked_target.symlink_to(real_target, target_is_directory=True)
        linked = self.run_helper("install", expected=1, target=linked_target)
        self.assertIn("symlinked skills target component", linked["error"])
        self.assertFalse((real_target / ".all-skills-receipts").exists())

        real_parent = self.root / "real-parent"
        real_parent.mkdir()
        linked_parent = self.root / "linked-parent"
        linked_parent.symlink_to(real_parent, target_is_directory=True)
        ancestor = self.run_helper("install", expected=1, target=linked_parent / "skills")
        self.assertIn("symlinked skills target component", ancestor["error"])
        self.assertFalse((real_parent / "skills").exists())

        self.install_combined()
        report_referent = self.root / "report-referent.json"
        report_referent.write_text("unchanged\n", encoding="utf-8")
        linked_report = self.root / "linked-report.json"
        linked_report.symlink_to(report_referent)
        report_result = self.run_helper("verify", expected=1, report=linked_report)
        self.assertIn("symlinked report path component", report_result["error"])
        self.assertEqual("unchanged\n", report_referent.read_text(encoding="utf-8"))

    def test_optional_aibrain_sync_uses_explicit_kinds_scopes_and_rebuilds_stale_index(self) -> None:
        module = self.load_helper_module()
        workspace = self.root / "workspace"
        brain = workspace / "AIBrain/scripts/brain.sh"
        brain.parent.mkdir(parents=True)
        brain.write_text(
            "#!/usr/bin/env bash\n"
            "printf '%s\\n' \"$*\" >> \"$AIBRAIN_TEST_LOG\"\n"
            "if [ \"${1:-}\" = status ]; then printf 'Index: stale\\n'; fi\n",
            encoding="utf-8",
        )
        catalog = self.root / "catalog.json"
        report = self.root / "report.json"
        catalog.write_text("{}\n", encoding="utf-8")
        report.write_text("{}\n", encoding="utf-8")
        log = self.root / "aibrain.log"
        with mock.patch.dict(os.environ, {"AIBRAIN_TEST_LOG": str(log)}):
            result = module._sync_aibrain(workspace, catalog, report)
        commands = log.read_text(encoding="utf-8").splitlines()
        self.assertEqual("synchronized", result["status"])
        self.assertTrue(any(f"ingest {catalog} --kind catalog --scope all-skills" in line for line in commands))
        self.assertTrue(any(f"ingest {report} --kind integration-health --scope superbrain" in line for line in commands))
        self.assertIn("index build", commands)

    def test_external_owner_intermediate_symlink_is_rejected(self) -> None:
        module = self.load_helper_module()

        owner = self.root / "Owner"
        owner.mkdir()
        referent = self.root / "owner-kiro"
        (referent / "skills").mkdir(parents=True)
        (owner / ".kiro").symlink_to(referent, target_is_directory=True)
        with self.assertRaises(module.IntegrationError):
            module._safe_absolute_path(owner / ".kiro/skills", "external owner source")

    def test_public_rollback_is_bound_to_captured_transaction_ids(self) -> None:
        module = self.load_helper_module()
        expected_receipt = {"receipt_id": "expected-transaction"}
        expected = module.LifecycleTransaction(
            "install", "expected-transaction", expected_receipt=expected_receipt
        )
        actual = module.LifecycleTransaction("install", "different-transaction")
        receipt_path = self.target / module.RECEIPT_RELATIVE
        receipt_path.parent.mkdir(parents=True)
        receipt_path.write_text(json.dumps(expected_receipt), encoding="utf-8")
        with mock.patch.object(module, "_public_lifecycle", return_value=({}, actual)):
            failures = module._rollback_public_lifecycle(
                mock.sentinel.contract, self.target, [expected], lock_fd=123
            )
        self.assertEqual(1, len(failures))
        self.assertIn("transaction mismatch", failures[0])
        self.assertIn("expected-transaction", failures[0])

    def test_owner_inventory_removes_retired_folders_transactionally(self) -> None:
        module = self.load_helper_module()
        source = self.root / "source/current-skill"
        source.mkdir(parents=True)
        (source / "SKILL.md").write_text("---\nname: current-skill\n---\n", encoding="utf-8")
        snapshot = module._tree_snapshot(source)
        retired = self.target / "retired-skill"
        retired.mkdir(parents=True)
        (retired / "SKILL.md").write_text("retired\n", encoding="utf-8")
        inventory = {
            "schema_version": module.SCHEMA_VERSION,
            "owners": {"Claude-Power": {"folders": {"retired-skill": module._tree_snapshot(retired).digest}}},
        }
        self.target.mkdir(parents=True, exist_ok=True)
        inventory_path = self.target / module.OWNER_INVENTORY_RELATIVE
        inventory_path.write_text(module._canonical_json(inventory), encoding="utf-8")
        contract = module.Contract(
            workspace=self.root,
            all_skills_root=self.root,
            all_skills_source=self.root,
            manifest={},
            catalog={},
            bundle_id="all-skills",
            bundle_version="2",
            manifest_digest="sha256:" + "0" * 64,
            catalog_entries=(),
            all_skills_owned=(),
            all_skills_snapshots={},
            external=(),
            owner_sources={"Claude-Power": {"current-skill": source}},
            owner_snapshots={"Claude-Power": {"current-skill": snapshot}},
        )
        transaction = module._publish_owner_trees(contract, self.target)
        self.assertFalse(retired.exists())
        self.assertTrue((self.target / "current-skill").is_dir())
        self.assertEqual([], module._rollback_owner_publication(transaction, self.target))
        self.assertTrue(retired.is_dir())
        self.assertFalse((self.target / "current-skill").exists())
        self.assertEqual(inventory, json.loads(inventory_path.read_text(encoding="utf-8")))

    def test_report_paths_cannot_alias_managed_target_or_lock(self) -> None:
        module = self.load_helper_module()
        target = module._safe_absolute_path(self.target, "target")
        with self.assertRaises(module.IntegrationError):
            module._validate_report_destination(target, target / "skill/SKILL.md")
        with self.assertRaises(module.IntegrationError):
            module._validate_report_destination(target, module._integration_lock_path(target))
        module._validate_report_destination(target, target.parent / "health.json")

    def test_drifted_retired_owner_folder_is_preserved(self) -> None:
        module = self.load_helper_module()
        self.target.mkdir(parents=True)
        retired = self.target / "retired-skill"
        retired.mkdir()
        (retired / "SKILL.md").write_text("owned\n", encoding="utf-8")
        original_digest = module._tree_snapshot(retired).digest
        inventory = {
            "schema_version": module.SCHEMA_VERSION,
            "owners": {"Claude-Power": {"folders": {"retired-skill": original_digest}}},
        }
        (self.target / module.OWNER_INVENTORY_RELATIVE).write_text(
            module._canonical_json(inventory), encoding="utf-8"
        )
        (retired / "SKILL.md").write_text("foreign replacement\n", encoding="utf-8")
        contract = module.Contract(
            workspace=self.root, all_skills_root=self.root, all_skills_source=self.root,
            manifest={}, catalog={}, bundle_id="all-skills", bundle_version="2",
            manifest_digest="sha256:" + "0" * 64, catalog_entries=(), all_skills_owned=(),
            all_skills_snapshots={}, external=(), owner_sources={"Claude-Power": {}},
            owner_snapshots={"Claude-Power": {}},
        )
        with self.assertRaisesRegex(module.IntegrationError, "drifted or foreign"):
            module._publish_owner_trees(contract, self.target)
        self.assertEqual("foreign replacement\n", (retired / "SKILL.md").read_text(encoding="utf-8"))

    def test_post_verification_failure_rolls_back_migration_uninstall_and_install(self) -> None:
        module = self.load_helper_module()
        self.target.mkdir(parents=True)
        receipt_path = self.target / module.RECEIPT_RELATIVE
        receipt_path.parent.mkdir(parents=True)
        original = {"receipt_id": "original", "skills": [{"folder": "token-efficiency"}]}
        receipt_path.write_text(json.dumps(original), encoding="utf-8")
        contract = mock.Mock()
        contract.external = (module.ExternalSkill("token-efficiency", "token-efficiency", "Claude-Power"),)
        contract.all_skills_owned = ("owned-skill",)
        contract.all_skills_root = self.root
        lifecycle_calls: list[str] = []

        uninstall_receipt = {"receipt_id": "uninstall-tx", "skills": []}

        def lifecycle(_contract, command, _target, _skills=(), **_kwargs):
            lifecycle_calls.append(command)
            if command == "uninstall":
                receipt_path.write_text(json.dumps(uninstall_receipt), encoding="utf-8")
                return {}, module.LifecycleTransaction(
                    "uninstall", "uninstall-tx", tuple(_skills), uninstall_receipt
                )
            if command == "install" and lifecycle_calls.count("install") == 1:
                install_receipt = {"receipt_id": "install-tx", "skills": []}
                receipt_path.write_text(json.dumps(install_receipt), encoding="utf-8")
                return {}, module.LifecycleTransaction(
                    "install", "install-tx", tuple(_skills), install_receipt
                )
            current = json.loads(receipt_path.read_text(encoding="utf-8"))["receipt_id"]
            if command == "rollback" and current == "install-tx":
                receipt_path.write_text(json.dumps(uninstall_receipt), encoding="utf-8")
                return {}, module.LifecycleTransaction("install", "install-tx")
            if command == "rollback" and current == "uninstall-tx":
                receipt_path.write_text(json.dumps(original), encoding="utf-8")
                return {}, module.LifecycleTransaction("uninstall", "uninstall-tx")
            raise AssertionError(f"unexpected {command} state: {current}")

        owner_transaction = mock.sentinel.owner_transaction
        with mock.patch.object(module, "_load_contract", return_value=(contract, {})), \
             mock.patch.object(module, "_public_lifecycle", side_effect=lifecycle), \
             mock.patch.object(module, "_publish_owner_trees", return_value=owner_transaction), \
             mock.patch.object(module, "_verify_unlocked", side_effect=module.IntegrationError("final verify failed")), \
             mock.patch.object(module, "_rollback_owner_publication", return_value=[]):
            with self.assertRaisesRegex(module.IntegrationError, "transaction was rolled back"):
                module.install(self.root, self.target, self.report, sync_aibrain=False)
        self.assertEqual(original, json.loads(receipt_path.read_text(encoding="utf-8")))
        self.assertEqual(["uninstall", "install", "rollback", "rollback"], lifecycle_calls)

    def test_partial_owner_cleanup_never_triggers_destructive_rollback(self) -> None:
        module = self.load_helper_module()
        self.target.mkdir(parents=True)
        destination = self.target / "owned-skill"
        destination.mkdir()
        (destination / "SKILL.md").write_text("new\n", encoding="utf-8")
        other_destination = self.target / "other-skill"
        other_destination.mkdir()
        (other_destination / "SKILL.md").write_text("other-new\n", encoding="utf-8")
        transaction_root = self.target / ".superbrain-owner-transaction-test"
        backup = transaction_root / "backup"
        prior = backup / "owned-skill"
        prior.mkdir(parents=True)
        (prior / "SKILL.md").write_text("old\n", encoding="utf-8")
        other_prior = backup / "other-skill"
        other_prior.mkdir()
        (other_prior / "SKILL.md").write_text("other-old\n", encoding="utf-8")
        transaction = module.OwnerTransaction(
            backup,
            [("owned-skill", True, True), ("other-skill", True, True)],
            None,
            self.target / module.OWNER_INVENTORY_RELATIVE,
        )

        real_rmtree = shutil.rmtree

        def partial_cleanup(_path, ignore_errors=False):
            self.assertFalse(ignore_errors)
            real_rmtree(prior)
            raise OSError("simulated partial cleanup failure")

        with mock.patch.object(module.shutil, "rmtree", side_effect=partial_cleanup):
            module._commit_owner_publication(transaction)
        failures = module._rollback_owner_publication(transaction, self.target)
        self.assertEqual("new\n", (destination / "SKILL.md").read_text(encoding="utf-8"))
        self.assertEqual(
            "other-new\n", (other_destination / "SKILL.md").read_text(encoding="utf-8")
        )
        self.assertEqual(1, len(failures))
        self.assertIn("required backup", failures[0])

    def test_exact_all_skills_lock_is_shared_and_descriptor_is_inherited(self) -> None:
        module = self.load_helper_module()
        lock_path = self.target.parent / f".{self.target.name}.all-skills.lock"
        self.assertEqual(lock_path, module._integration_lock_path(self.target))
        with module._integration_lock(self.target) as lock_fd:
            contender_code = (
                "import fcntl,json,os,sys; "
                "f=open(sys.argv[1],'a+'); "
                "blocked=False; "
                "\ntry: fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)"
                "\nexcept BlockingIOError: blocked=True"
                "\nprint(json.dumps({'blocked':blocked}))"
            )
            contender = subprocess.run(
                [sys.executable, "-c", contender_code, str(lock_path)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False,
            )
            self.assertEqual(0, contender.returncode, msg=contender.stderr)
            self.assertTrue(json.loads(contender.stdout)["blocked"])

            inherited_code = (
                "import json,os; "
                "fd=int(os.environ['ALL_SKILLS_LOCK_FD']); "
                "st=os.fstat(fd); "
                "print(json.dumps({'fd':fd,'inode':st.st_ino}))"
            )
            payload, returncode = module._run_json(
                [sys.executable, "-c", inherited_code],
                cwd=self.root,
                inherited_lock_fd=lock_fd,
            )
            self.assertEqual(0, returncode)
            self.assertEqual(os.fstat(lock_fd).st_ino, payload["inode"])

    def test_unknown_receipt_is_never_attributed_or_rolled_back(self) -> None:
        module = self.load_helper_module()
        self.target.mkdir(parents=True)
        receipt_path = self.target / module.RECEIPT_RELATIVE
        contract = mock.Mock()
        contract.external = ()
        contract.all_skills_owned = ("owned-skill",)
        contract.all_skills_root = self.root

        def unexplained_mutation(*_args, **_kwargs):
            receipt_path.parent.mkdir(parents=True, exist_ok=True)
            receipt_path.write_text(
                json.dumps({"receipt_id": "direct-writer", "skills": []}), encoding="utf-8"
            )
            raise module.IntegrationError("public response lost")

        with mock.patch.object(module, "_load_contract", return_value=(contract, {})), \
             mock.patch.object(module, "_public_lifecycle", side_effect=unexplained_mutation), \
             mock.patch.object(module, "_rollback_public_lifecycle") as rollback:
            with self.assertRaisesRegex(module.IntegrationError, "unexplained current receipt"):
                module.install(self.root, self.target, self.report, sync_aibrain=False)
        rollback.assert_not_called()
        self.assertEqual("direct-writer", json.loads(receipt_path.read_text())["receipt_id"])

    def test_uninstall_compensation_requires_exact_captured_receipt_state(self) -> None:
        module = self.load_helper_module()
        expected_receipt = {"receipt_id": "uninstall-tx", "skills": []}
        transaction = module.LifecycleTransaction(
            "uninstall", "uninstall-tx", ("token-efficiency",), expected_receipt
        )
        receipt_path = self.target / module.RECEIPT_RELATIVE
        receipt_path.parent.mkdir(parents=True)
        receipt_path.write_text(
            json.dumps({"receipt_id": "uninstall-tx", "skills": [], "foreign": True}),
            encoding="utf-8",
        )
        with mock.patch.object(module, "_public_lifecycle") as lifecycle:
            failures = module._rollback_public_lifecycle(
                mock.sentinel.contract, self.target, [transaction], lock_fd=123
            )
        lifecycle.assert_not_called()
        self.assertEqual(1, len(failures))
        self.assertIn("not captured transaction", failures[0])

    def test_interrupted_artifact_publication_is_recovered_on_next_call(self) -> None:
        source = self.root / "source-tree"
        lock_root = self.root / "kiro"
        destination = lock_root / "published/tree"
        source.mkdir()
        destination.mkdir(parents=True)
        (source / "value.txt").write_text("new\n", encoding="utf-8")
        (destination / "value.txt").write_text("old\n", encoding="utf-8")
        command = [
            sys.executable,
            str(HELPER),
            "publish-artifacts",
            "--lock-root",
            str(lock_root),
            "--tree",
            str(source),
            str(destination),
        ]
        environment = os.environ.copy()
        environment["SUPERBRAIN_TEST_CRASH_AFTER_ARTIFACT_BACKUP"] = "1"
        interrupted = subprocess.run(
            command,
            cwd=REPOSITORY,
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        self.assertEqual(91, interrupted.returncode)
        self.assertTrue(destination.exists())
        self.assertEqual("new\n", (destination / "value.txt").read_text(encoding="utf-8"))
        self.assertTrue((lock_root / ".superbrain-artifact-publication.json").is_file())

        recovered = subprocess.run(
            command,
            cwd=REPOSITORY,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        self.assertEqual(0, recovered.returncode, msg=recovered.stderr)
        self.assertEqual("new\n", (destination / "value.txt").read_text(encoding="utf-8"))
        self.assertFalse((lock_root / ".superbrain-artifact-publication.json").exists())
        self.assertEqual([], list(destination.parent.glob(".superbrain-artifact-publication-*")))

        (source / "value.txt").write_text("newer\n", encoding="utf-8")
        publish_crash_environment = os.environ.copy()
        publish_crash_environment["SUPERBRAIN_TEST_CRASH_AFTER_ARTIFACT_PUBLISH"] = "1"
        published_then_interrupted = subprocess.run(
            command,
            cwd=REPOSITORY,
            env=publish_crash_environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        self.assertEqual(92, published_then_interrupted.returncode)
        self.assertEqual("newer\n", (destination / "value.txt").read_text(encoding="utf-8"))
        recovered_after_publish = subprocess.run(
            command,
            cwd=REPOSITORY,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        self.assertEqual(0, recovered_after_publish.returncode, msg=recovered_after_publish.stderr)
        self.assertEqual("newer\n", (destination / "value.txt").read_text(encoding="utf-8"))
        self.assertFalse((lock_root / ".superbrain-artifact-publication.json").exists())

    def test_pending_artifact_cleanup_stops_batch_before_journal_overwrite(self) -> None:
        module = self.load_helper_module()
        lock_root = self.root / "kiro"
        first_source = self.root / "first-source"
        second_source = self.root / "second-source"
        first_destination = lock_root / "skills/first"
        second_destination = lock_root / "skills/second"
        for source, value in ((first_source, "first-new\n"), (second_source, "second-new\n")):
            source.mkdir(parents=True)
            (source / "value.txt").write_text(value, encoding="utf-8")
        for destination, value in (
            (first_destination, "first-old\n"),
            (second_destination, "second-old\n"),
        ):
            destination.mkdir(parents=True)
            (destination / "value.txt").write_text(value, encoding="utf-8")

        with mock.patch.object(
            module,
            "_cleanup_artifact_transaction",
            side_effect=module.IntegrationError("simulated cleanup failure"),
        ):
            with self.assertRaisesRegex(module.IntegrationError, "cleanup is pending"):
                module.publish_artifacts(
                    lock_root,
                    trees=((first_source, first_destination), (second_source, second_destination)),
                )
        self.assertEqual(
            "first-new\n", (first_destination / "value.txt").read_text(encoding="utf-8")
        )
        self.assertEqual(
            "second-old\n", (second_destination / "value.txt").read_text(encoding="utf-8")
        )
        journal_path = lock_root / module.ARTIFACT_JOURNAL_NAME
        journal = json.loads(journal_path.read_text(encoding="utf-8"))
        self.assertEqual(str(first_destination), journal["destination"])

        result = module.publish_artifacts(
            lock_root,
            trees=((first_source, first_destination), (second_source, second_destination)),
        )
        self.assertEqual(2, result["published"])
        self.assertEqual(
            "second-new\n", (second_destination / "value.txt").read_text(encoding="utf-8")
        )
        self.assertFalse(journal_path.exists())

    def test_artifact_publication_is_serialized_atomic_and_rejects_symlinks(self) -> None:
        module = self.load_helper_module()
        lock_root = self.root / "kiro"
        source_file = self.root / "source.sh"
        destination_file = lock_root / "scripts/tool.sh"
        source_file.write_text("new-file\n", encoding="utf-8")
        source_file.chmod(0o750)
        destination_file.parent.mkdir(parents=True)
        destination_file.write_text("old-file\n", encoding="utf-8")
        module.publish_artifacts(
            lock_root, files=((source_file, destination_file),)
        )
        self.assertEqual("new-file\n", destination_file.read_text(encoding="utf-8"))
        self.assertEqual(0o750, destination_file.stat().st_mode & 0o777)
        self.assertEqual([], list(destination_file.parent.glob(".*.superbrain-file.*")))

        unsafe_tree = self.root / "unsafe-tree"
        unsafe_tree.mkdir()
        (unsafe_tree / "outside-link").symlink_to(source_file)
        safe_destination = lock_root / "skills/safe"
        with self.assertRaisesRegex(module.IntegrationError, "symlink"):
            module.publish_artifacts(
                lock_root, trees=((unsafe_tree, safe_destination),)
            )
        self.assertFalse(safe_destination.exists())

        first_source = self.root / "concurrent-first"
        second_source = self.root / "concurrent-second"
        destination = lock_root / "skills/concurrent"
        for source, marker in ((first_source, "first"), (second_source, "second")):
            source.mkdir()
            for index in range(20):
                (source / f"{index}.txt").write_text(marker, encoding="utf-8")
        commands = [
            [
                sys.executable, str(HELPER), "publish-artifacts", "--lock-root", str(lock_root),
                "--tree", str(source), str(destination),
            ]
            for source in (first_source, second_source)
        ]
        processes = [
            subprocess.Popen(
                command, cwd=REPOSITORY, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
            )
            for command in commands
        ]
        results = [process.communicate(timeout=30) + (process.returncode,) for process in processes]
        self.assertTrue(all(returncode == 0 for _, _, returncode in results), msg=results)
        values = {path.read_text(encoding="utf-8") for path in destination.glob("*.txt")}
        self.assertIn(values, ({"first"}, {"second"}))
        self.assertEqual(20, len(list(destination.glob("*.txt"))))
        self.assertFalse((lock_root / module.ARTIFACT_JOURNAL_NAME).exists())

    def test_manifest_commands_are_executable_and_python_caches_are_ignored(self) -> None:
        manifest = json.loads((REPOSITORY / "manifest.json").read_text(encoding="utf-8"))
        for repository in manifest["repositories"]:
            for field in ("install", "verify"):
                command = repository[field]
                process = subprocess.run(
                    ["bash", "-n", "-c", command], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
                )
                self.assertEqual(0, process.returncode, msg=f"{repository['name']} {field}: {process.stderr}")
        ignored = (REPOSITORY / ".gitignore").read_text(encoding="utf-8")
        self.assertIn("__pycache__/", ignored)
        self.assertIn("*.py[cod]", ignored)
        for script_name in ("bootstrap.sh", "repair.sh"):
            script = (REPOSITORY / "scripts" / script_name).read_text(encoding="utf-8")
            self.assertNotIn("$RANDOM", script)
            self.assertIn("skills_integration.py\" publish-artifacts", script)
            self.assertNotIn("mv \"$destination\" \"$backup\"", script)
            self.assertNotIn("publish_tree()", script)

    def test_bootstrap_treats_aibrain_as_optional(self) -> None:
        bootstrap = (REPOSITORY / "scripts/bootstrap.sh").read_text(encoding="utf-8")
        verify = (REPOSITORY / "scripts/verify.sh").read_text(encoding="utf-8")
        repair = (REPOSITORY / "scripts/repair.sh").read_text(encoding="utf-8")
        self.assertIn('if ! clone_repo "AIBrain"', bootstrap)
        self.assertIn('check-safe-file --path "$AIBRAIN_INSTALLER"', bootstrap)
        self.assertIn('if KIRO_DIR="$KIRO_DIR" bash "$AIBRAIN_INSTALLER"; then', bootstrap)
        self.assertIn('if ! find "$WORKSPACE/AIBrain/scripts"', bootstrap)
        required_repositories = next(line for line in verify.splitlines() if line.startswith("for repo in "))
        self.assertNotIn("AIBrain", required_repositories)
        self.assertIn("repair_aibrain_optional", repair)

    def test_bootstrap_marker_is_invalidated_before_mutation_and_published_after_verify(self) -> None:
        script = (REPOSITORY / "scripts/bootstrap.sh").read_text(encoding="utf-8")
        invalidate_position = script.index('rm -f "$MARKER"')
        first_mutation_position = script.index('clone_repo "All-Skills"')
        verify_position = script.index('bash "$SUPERBRAIN_DIR/scripts/verify.sh"')
        marker_temp_position = script.index('MARKER_TMP="$(mktemp')
        marker_publish_position = script.index('mv -f "$MARKER_TMP" "$MARKER"')
        self.assertLess(invalidate_position, first_mutation_position)
        self.assertLess(verify_position, marker_temp_position)
        self.assertLess(marker_temp_position, marker_publish_position)
        self.assertEqual(1, script.count('mv -f "$MARKER_TMP" "$MARKER"'))
        self.assertIn('if [ -L "$MARKER" ]', script)
        self.assertIn("set -euo pipefail", script[:500])


if __name__ == "__main__":
    unittest.main()
