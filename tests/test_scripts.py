import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ScriptTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / "scripts").mkdir()
        for script in ("env.sh", "cleanup.sh"):
            shutil.copyfile(ROOT / "scripts" / script, self.root / "scripts" / script)
        (self.root / ".lab-env").write_text("LAB_SUFFIX=cleanup42\n")
        (self.root / ".azure-sp").mkdir()
        (self.root / ".azure-sp" / "cache").write_text("test cache")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.env = {**os.environ, "PATH": f"{self.bin}:{os.environ['PATH']}"}

    def executable(self, name, body):
        path = self.bin / name
        path.write_text("#!/usr/bin/env bash\n" + body)
        path.chmod(0o700)

    def cleanup(self, scenario):
        self.executable(
            "az",
            """
case "$1 $2" in
  "group exists")
    if [ "$TEST_SCENARIO" = delete-failure ]; then echo true; else echo false; fi ;;
  "group delete") echo "ERROR: deletion denied" >&2; exit 2 ;;
  "keyvault list-deleted")
    if [ "$TEST_SCENARIO" = purge-failure ]; then echo kv-paaslab-cleanup42; fi ;;
  "keyvault purge") echo "ERROR: purge denied" >&2; exit 3 ;;
  "ad app"|"role definition") exit 0 ;;
  *) echo "ERROR: unexpected command: $*" >&2; exit 9 ;;
esac
""",
        )
        return subprocess.run(
            ["bash", "scripts/cleanup.sh", "-y"],
            cwd=self.root,
            env={**self.env, "TEST_SCENARIO": scenario},
            capture_output=True,
            text=True,
        )

    def test_cleanup_does_not_claim_success_when_deletion_or_purge_fails(self):
        for scenario in ("delete-failure", "purge-failure"):
            with self.subTest(scenario=scenario):
                result = self.cleanup(scenario)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("Cleanup complete", result.stdout)
                self.assertIn("ERROR:", result.stderr)
                self.assertFalse((self.root / ".azure-sp").exists())

    def test_cleanup_succeeds_when_lab_resources_are_already_absent(self):
        result = self.cleanup("absent")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Cleanup complete", result.stdout)
        self.assertFalse((self.root / ".azure-sp").exists())

    def test_cleanup_refuses_to_generate_new_state(self):
        (self.root / ".lab-env").unlink()
        result = self.cleanup("absent")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / ".lab-env").exists())

    def test_retry_handles_only_rbac_propagation_errors(self):
        self.executable("sleep", "exit 0\n")
        self.executable(
            "az",
            """
count=0
if [ -f attempts ]; then read -r count < attempts; fi
count=$((count + 1))
echo "$count" > attempts
if [ "$TEST_SCENARIO" = propagate ] && [ "$count" -ge 2 ]; then exit 0; fi
if [ "$TEST_SCENARIO" = network ]; then
  echo "ERROR: ForbiddenByConnection" >&2
else
  echo "ERROR: ForbiddenByRbac" >&2
fi
exit 7
""",
        )
        for scenario, expected_code, attempts in (("propagate", 0, 2), ("network", 7, 1), ("timeout", 7, 10)):
            with self.subTest(scenario=scenario):
                (self.root / "attempts").unlink(missing_ok=True)
                result = subprocess.run(
                    ["bash", str(ROOT / "scripts" / "retry.sh"), "az", "test"],
                    cwd=self.root,
                    env={**self.env, "TEST_SCENARIO": scenario},
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(result.returncode, expected_code, result.stderr)
                self.assertEqual(int((self.root / "attempts").read_text()), attempts)
                if expected_code:
                    self.assertIn("ERROR:", result.stderr)


if __name__ == "__main__":
    unittest.main()
