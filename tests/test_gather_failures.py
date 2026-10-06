"""Failed gather prerequisites must not publish the completion signal."""

# Standard Python Libraries
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

# Stand-in commands record execution and write only tiny local fixtures. No
# external server, Redis instance, database or scanner is accessed.
STUB = r"""import json
import os
from pathlib import Path
import shutil
import sys
name = Path(sys.argv[0]).name
args = sys.argv[1:]
log = Path(os.environ["COMMAND_LOG"])
previous = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
with log.open("a") as stream:
    stream.write(json.dumps([name, args]) + "\n")
occurrence = 1 + sum(command[0] == name for command in previous)
if name == os.environ.get("FAIL_COMMAND") and occurrence == int(os.environ.get("FAIL_OCCURRENCE", "1")):
    sys.exit(17)
if name == "fed_hostnames.py":
    Path(args[0].split("=", 1)[1]).write_text("host.example,AGENCY\n")
elif name == "wget":
    Path(args[args.index("-O") + 1]).write_text("Domain Name,Owner\nexample.gov,AGENCY\n")
elif name == "gather":
    Path("results").mkdir(exist_ok=True)
    Path("results/gathered.csv").write_text("domain,owner\nexample.gov,AGENCY\n")
elif name == "mkdir":
    Path(args[0]).mkdir(parents=True, exist_ok=True)
elif name == "cp":
    shutil.copyfile(args[0], args[1])
elif name == "mv":
    shutil.move(args[0], args[1])
elif name in ("cut", "awk", "sort", "tr", "paste", "tail", "cat"):
    print("example.gov")
"""


class GatherFailureTest(unittest.TestCase):
    """Run the real script control flow with isolated command substitutes."""

    def run_pipeline(self, failure="", occurrence=1):
        """Relocate only hard-coded filesystem roots for a local shell run."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home"
            (home / "shared/artifacts").mkdir(parents=True)
            (home / "domain-scan").mkdir()
            commands = root / "bin"
            commands.mkdir()
            log = root / "commands.jsonl"
            body = "#!" + sys.executable + "\n" + STUB
            for name in [
                "mkdir",
                "wget",
                "tail",
                "cat",
                "sed",
                "cut",
                "awk",
                "sort",
                "tr",
                "paste",
                "cp",
                "mv",
                "redis-cli",
            ]:
                path = commands / name
                path.write_text(body)
                path.chmod(0o755)
            for path in [root / "fed_hostnames.py", home / "domain-scan/gather"]:
                path.write_text(body)
                path.chmod(0o755)
            source = (ROOT / "src/gather-domains.sh").read_text()
            self.assertEqual(source.count("HOME_DIR=/home/cisa"), 1)
            source = source.replace(
                "HOME_DIR=/home/cisa", "HOME_DIR=" + shlex.quote(str(home))
            )
            source = source.replace(
                "/tmp/current-federal-non-dotgov.csv", str(root / "non-dotgov.csv")
            )
            script = root / "gather-domains.sh"
            script.write_text(source)
            environment = dict(
                os.environ,
                PATH=str(commands),
                COMMAND_LOG=str(log),
                FAIL_COMMAND=failure,
                FAIL_OCCURRENCE=str(occurrence),
            )
            result = subprocess.run(
                ["/bin/sh", str(script)],
                cwd=root,
                env=environment,
                capture_output=True,
                text=True,
                timeout=20,
            )
            calls = (
                [json.loads(line) for line in log.read_text().splitlines()]
                if log.exists()
                else []
            )
            return result, calls

    def test_failed_prerequisites_cannot_reach_redis_completion(self):
        """Stop after extraction, source download, gathering or output failures."""
        for command, occurrence in [
            ("fed_hostnames.py", 1),
            ("wget", 1),
            ("wget", 2),
            ("gather", 1),
            ("cp", 1),
            ("mv", 1),
        ]:
            with self.subTest(command=command, occurrence=occurrence):
                result, calls = self.run_pipeline(command, occurrence)
                self.assertEqual(result.returncode, 17, result.stderr)
                self.assertNotIn("redis-cli", [call[0] for call in calls])
                self.assertEqual(calls[-1][0], command)

    def test_successful_run_signals_completion_once_at_the_end(self):
        """The successful command sequence retains its completion signal."""
        result, calls = self.run_pipeline()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            [call for call in calls if call[0] == "redis-cli"],
            [["redis-cli", ["-h", "redis", "set", "gathering_complete", "true"]]],
        )
        self.assertEqual(calls[-1][0], "redis-cli")

    def test_hostname_configuration_failures_exit_nonzero(self):
        """The direct Python CLI propagates main's handled failure result."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            invalid_yaml = root / "invalid.yml"
            invalid_yaml.write_text("database: [\n")
            missing_keys = root / "missing-keys.yml"
            missing_keys.write_text("other: value\n")
            for path in [root / "absent.yml", invalid_yaml, missing_keys]:
                with self.subTest(path=path.name):
                    output = root / "hosts.csv"
                    result = subprocess.run(
                        [
                            sys.executable,
                            str(ROOT / "src/fed_hostnames.py"),
                            "--db-creds-file=" + str(path),
                            "--output-file=" + str(output),
                        ],
                        capture_output=True,
                        text=True,
                        timeout=20,
                    )
                    self.assertEqual(result.returncode, 1, result.stderr)
                    self.assertFalse(output.exists())

    def test_successful_hostname_cli_writes_expected_csv(self):
        """Run the real CLI with a local in-memory database boundary."""
        launcher = """import runpy
import sys
from unittest.mock import Mock, patch
source, output = sys.argv[1:]
database = Mock()
database.requests.find_one.side_effect = lambda query: {
    "FEDERAL": {"_id": "FEDERAL", "children": ["AGENCY"]},
    "AGENCY": {"_id": "AGENCY", "children": [], "retired": False},
}[query["_id"]]
database.port_scans.find.return_value = [{"ip_int": 123}]
database.host_scans.find.return_value = [{"hostname": "host.example", "owner": "AGENCY"}]
sys.argv = [source, "--output-file=" + output]
with patch("mongo_db_from_config.db_from_config", return_value=database):
    runpy.run_path(source, run_name="__main__")
"""
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "hosts.csv"
            result = subprocess.run(
                [
                    sys.executable,
                    "-c",
                    launcher,
                    str(ROOT / "src/fed_hostnames.py"),
                    str(output),
                ],
                capture_output=True,
                text=True,
                timeout=20,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(output.read_text(), "host.example,AGENCY\n")

    def test_help_and_version_keep_successful_exit_codes(self):
        """Read-only informational CLI invocations continue to work."""
        for option in ["--help", "--version"]:
            with self.subTest(option=option):
                result = subprocess.run(
                    [sys.executable, str(ROOT / "src/fed_hostnames.py"), option],
                    capture_output=True,
                    text=True,
                    timeout=20,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue(result.stdout)


if __name__ == "__main__":
    unittest.main()
