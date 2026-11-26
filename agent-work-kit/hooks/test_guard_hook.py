#!/usr/bin/env python3
"""Offline unittest suite for guard-hook.py.

Run from the kit root:
    python3 -m unittest hooks/test_guard_hook.py -v
No network, cloud, container, or repository mutation is required.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HOOK = Path(__file__).resolve().parent / "guard-hook.py"


class GuardHookTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="agent-work-hook-test-")
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.repo = root / "repo"
        self.work = root / "work"
        self.repo.mkdir()
        self.work.mkdir()
        (self.repo / "deploy").mkdir()
        (self.repo / "deploy" / "values.yaml").write_text("protected: true\n", encoding="utf-8")
        subprocess.run(["git", "init", "-q", "-b", "main", str(self.repo)], check=True)

        env = os.environ.copy()
        env.update(
            {
                "REPO_DIR": str(self.repo),
                "WORK_DIR": str(self.work),
                "PROTECTED_BRANCHES": "main master",
                "DEPLOY_CMD": "./deploy",
                "PROTECTED_FILES": "deploy/values.yaml",
                "ALLOWED_RM_ROOTS": f"{self.work} /tmp",
            }
        )
        self.env = env

    def run_hook(self, event: dict | str, cwd: str | None = None) -> subprocess.CompletedProcess[str]:
        if isinstance(event, dict):
            event.setdefault("cwd", cwd or str(self.repo))
            payload = json.dumps(event)
        else:
            payload = event
        return subprocess.run(
            [sys.executable, str(HOOK)],
            input=payload,
            text=True,
            capture_output=True,
            env=self.env,
            check=False,
            timeout=5,
        )

    def assert_allowed(self, event: dict | str, cwd: str | None = None) -> None:
        proc = self.run_hook(event, cwd)
        self.assertEqual(proc.returncode, 0, f"expected allow, got {proc.returncode}: {proc.stderr}")

    def assert_blocked(self, event: dict | str, cwd: str | None = None) -> None:
        proc = self.run_hook(event, cwd)
        self.assertEqual(proc.returncode, 2, f"expected block, got {proc.returncode}: {proc.stdout} {proc.stderr}")
        self.assertIn("BLOCKED by agent-work guard", proc.stderr)

    @staticmethod
    def exec_event(command: str) -> dict:
        return {"tool_name": "exec", "tool_input": {"command": command}}

    def test_read_only_git_commands_allowed(self) -> None:
        self.assert_allowed(self.exec_event("git status --short && git diff --check"))

    def test_git_push_denied(self) -> None:
        self.assert_blocked(self.exec_event("git push origin feature-branch"))

    def test_git_merge_on_protected_branch_denied(self) -> None:
        self.assert_blocked(self.exec_event("git merge feature-branch"), cwd=str(self.repo))

    def test_git_merge_on_feature_branch_allowed(self) -> None:
        subprocess.run(["git", "-C", str(self.repo), "symbolic-ref", "HEAD", "refs/heads/feature"], check=True)
        self.assert_allowed(self.exec_event("git merge topic-branch"), cwd=str(self.repo))

    def test_git_merge_tree_is_read_only_and_allowed(self) -> None:
        # merge-tree does not update HEAD, the index, or the working tree.
        self.assert_allowed(self.exec_event("git merge-tree --write-tree main feature"), cwd=str(self.repo))

    def test_git_rebase_involving_protected_branch_denied(self) -> None:
        subprocess.run(["git", "-C", str(self.repo), "symbolic-ref", "HEAD", "refs/heads/feature"], check=True)
        self.assert_blocked(self.exec_event("git rebase main"), cwd=str(self.repo))

    def test_git_commit_on_protected_branch_denied(self) -> None:
        self.assert_blocked(self.exec_event("git commit -m test"), cwd=str(self.repo))

    def test_deploy_command_denied(self) -> None:
        self.assert_blocked(self.exec_event("./deploy apply --yes"))
        self.assert_blocked(self.exec_event("cd /tmp && /opt/bin/deploy render"))

    def test_orchestration_mutations_denied(self) -> None:
        for command in (
            "helm upgrade app ./chart",
            "helm install app ./chart",
            "kubectl apply -f app.yaml",
            "kubectl delete pod x",
            "kubectl patch deployment x -p '{}'",
            "kubectl rollout restart deployment x",
            "terraform apply",
            "terraform destroy",
        ):
            with self.subTest(command=command):
                self.assert_blocked(self.exec_event(command))

    def test_docker_prune_denied_but_container_rm_allowed(self) -> None:
        for command in ("docker system prune", "docker image prune", "docker builder prune"):
            with self.subTest(command=command):
                self.assert_blocked(self.exec_event(command))
        self.assert_allowed(self.exec_event("docker rm -f -v temporary-test-container"))

    def test_recursive_rm_allowed_only_under_allowed_roots(self) -> None:
        self.assert_allowed(self.exec_event("rm -rf /tmp/agent-work-safe-delete-test"))
        self.assert_allowed(self.exec_event(f"rm -rf {self.work}/scratch"))
        self.assert_blocked(self.exec_event("rm -rf /var/log/agent-work-never"))

    def test_dynamic_recursive_rm_denied(self) -> None:
        self.assert_blocked(self.exec_event('rm -rf "$HOME/scratch"'))

    def test_edit_tool_protected_file_denied(self) -> None:
        protected = str(self.repo / "deploy" / "values.yaml")
        self.assert_blocked({"tool_name": "edit", "tool_input": {"file_path": protected}})

    def test_compact_redirect_to_protected_file_denied(self) -> None:
        protected = self.repo / "deploy" / "values.yaml"
        self.assert_blocked(self.exec_event(f"echo bad>{protected}"))

    def test_simple_command_substitution_forms_denied(self) -> None:
        for command in ("$(./deploy)", "$(rm -rf /opt/example)"):
            with self.subTest(command=command):
                self.assert_blocked(self.exec_event(command))

    def test_read_tool_protected_file_allowed(self) -> None:
        protected = str(self.repo / "deploy" / "values.yaml")
        self.assert_allowed({"tool_name": "read", "tool_input": {"file_path": protected}})

    def test_shell_write_to_protected_file_denied(self) -> None:
        protected = self.repo / "deploy" / "values.yaml"
        self.assert_blocked(self.exec_event(f"echo x >> {protected}"))
        self.assert_blocked(self.exec_event(f"sed -i 's/a/b/' {protected}"))
        self.assert_blocked(self.exec_event(f"cp /tmp/x {protected}"))

    def test_kiro_tool_input_shape_supported(self) -> None:
        self.assert_blocked({"tool_name": "shell", "toolInput": {"command": "terraform apply"}})

    def test_malformed_json_is_treated_as_raw_command(self) -> None:
        self.assert_blocked("git push origin feature")


if __name__ == "__main__":
    unittest.main()
