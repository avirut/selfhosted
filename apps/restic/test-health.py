import datetime
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parent
UTC = datetime.timezone.utc
SUNDAY = datetime.datetime(2026, 11, 15, 11, 30, tzinfo=UTC)
SETS = (
    "skepsis/apps", "skepsis/embral", "sophon-media/apps",
    "sophon-gpu/apps", "sophon/apps", "sophon-agent/apps", "ambrosia.local/apps", "chrysaora/apps",
)


class BackupHealthTest(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.root = Path(folder.name)
        self.state = self.root / "state"
        self.state.mkdir()
        self.alert_state = self.state / "shared-monitor"
        self.alert_state.mkdir()
        self.env = dict(os.environ, PATH=f"{self.root}:{os.environ['PATH']}",
                        FIXTURE=str(self.root))
        for name in ("maintenance.sh", "monitor.sh"):
            path = self.root / name
            shutil.copy(SCRIPTS / name, path)
            path.write_text(path.read_text().replace("cd /home/avirut/qm", 'cd "$FIXTURE"'))
        script = (SCRIPTS / "health.sh").read_text().replace(
            "BACKUP_STATE=/var/lib/kroacnet-backup", 'BACKUP_STATE="$FIXTURE/state"')
        (self.root / "health.sh").write_text(script)
        self.stub("date", """#!/usr/bin/env bash
case "$*" in
    +%s) echo "$TEST_NOW";;
    +%s%N) printf '%s%s\\n' "$TEST_NOW" "$(/usr/bin/date +%N)";;
    '-u +%Y-%m-%dT%H:%M:%SZ') /usr/bin/date -u -d "@$TEST_NOW" +%Y-%m-%dT%H:%M:%SZ;;
    *) exec /usr/bin/date "$@";;
esac
""")
        self.stub("list-snapshots.sh", """#!/usr/bin/env bash
if [[ ${LIST_EXIT:-0} != 0 ]]; then exit "$LIST_EXIT"; fi
cat "$FIXTURE/catalogue"
""")
        self.stub("remove-old.sh", """#!/usr/bin/env bash
echo "$2" >> "$FIXTURE/restic.calls"
""")
        self.stub("restic", """#!/usr/bin/env bash
echo "$*" >> "$FIXTURE/restic.calls"
if [[ ${FAIL_PRECHECK:-0} == 1 && "$*" == *--read-data-subset* ]]; then exit 1; fi
""")
        self.stub("systemctl", """#!/usr/bin/env bash
[[ ${*: -1} == "${FAILED_UNIT:-}" ]]
""")
        self.stub("runuser", """#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

root = Path(os.environ["FIXTURE"])
request = json.load(sys.stdin)
command = sys.argv[-1]
path = root / request["requestKey"]
if command == "enqueue":
    if not path.exists():
        path.write_text("pending")
        with (root / "alerts").open("a") as log:
            log.write(json.dumps(request) + "\\n")
    if os.environ.get("FAIL_ENQUEUE") == "1":
        sys.exit(1)
elif command == "cancel":
    if path.exists() and path.read_text() == "pending":
        path.write_text("cancelled")
else:
    sys.exit(1)
print(json.dumps({"status": path.read_text() if path.exists() else "absent"}))
""")
        (self.root / "env").touch()
        self.at(SUNDAY)
        self.stamp("maintenance-success", SUNDAY - datetime.timedelta(days=7))
        self.stamp("restore-success", SUNDAY - datetime.timedelta(days=1))

    def stub(self, name, text):
        path = self.root / name
        path.write_text(text)
        path.chmod(0o755)

    def stamp(self, name, when):
        (self.state / name).write_text(when.isoformat() + "\n")

    def at(self, when, stale=None, missing=None):
        self.env["TEST_NOW"] = str(int(when.timestamp()))
        rows = [
            {
                "hostname": item.split("/")[0],
                "tags": [item.split("/")[1]],
                "time": (when - datetime.timedelta(hours=31 if item == stale else 3)).isoformat(),
            }
            for item in SETS if item != missing
        ]
        (self.root / "catalogue").write_text(json.dumps(rows))

    def run_job(self, name, expected=0, **env):
        result = subprocess.run(
            ("bash", str(self.root / f"{name}.sh"), str(self.root / "env")),
            env=dict(self.env, **env), text=True, capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, expected, (result.stdout, result.stderr))
        return result

    def alerts(self):
        log = self.root / "alerts"
        rows = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
        for row in rows:
            reason = row["text"].split(". ", 1)[1]
            self.assertIn(len(reason.split()), range(5, 11), row["text"])
        return rows

    def test_deferral_catch_up_and_recovery(self):
        self.at(SUNDAY, stale="chrysaora/apps")
        (self.alert_state / "maintenance.state").write_text("failed 1794713400\n")
        self.run_job("maintenance")
        self.assertIn("snapshot-stale chrysaora/apps", (self.state / "maintenance-result").read_text())
        self.assertFalse((self.root / "restic.calls").exists())
        self.run_job("monitor", FAILED_UNIT="restic-maintenance.service")
        initial = self.alerts()
        self.assertEqual(len(initial), 1)
        self.assertIn("chrysaora-apps is stale", initial[0]["text"])

        for days in (1, 2):
            self.at(SUNDAY + datetime.timedelta(days=days))
            self.run_job("maintenance")
            self.run_job("monitor")
        calls = (self.root / "restic.calls").read_text().splitlines()
        self.assertEqual(len(calls), 4)
        self.assertEqual(calls.count("--prune"), 1)
        alerts = self.alerts()
        self.assertEqual(len(alerts), 3)
        self.assertIn("chrysaora-apps is healthy", alerts[1]["text"])
        self.assertIn("maintenance is healthy", alerts[2]["text"])
        self.assertEqual((self.root / initial[0]["requestKey"]).read_text(), "cancelled")

    def test_actual_failure_alerts_once_and_stops_after_a_success(self):
        for days in (0, 1):
            self.at(SUNDAY + datetime.timedelta(days=days))
            self.run_job("maintenance", expected=1, FAIL_PRECHECK="1")
            self.run_job("monitor")
        first = self.alerts()
        self.assertEqual(len(first), 1)
        self.assertIn("maintenance is failed. Pre-prune", first[0]["text"])
        self.assertNotIn("--prune", (self.root / "restic.calls").read_text())

        self.at(SUNDAY + datetime.timedelta(days=1, hours=1))
        self.run_job("maintenance")
        self.run_job("monitor")
        self.assertEqual(len(self.alerts()), 2)
        self.assertIn("maintenance is healthy", self.alerts()[1]["text"])
        self.assertEqual((self.root / first[0]["requestKey"]).read_text(), "cancelled")

    def test_overdue_reports_current_blocker_and_waits_for_restore(self):
        self.at(SUNDAY + datetime.timedelta(days=3), missing="sophon-gpu/apps")
        self.run_job("maintenance")
        self.run_job("monitor")
        self.assertEqual(len(self.alerts()), 2)
        self.assertIn("maintenance is overdue. No current snapshot", self.alerts()[-1]["text"])
        self.assertIn("sophon-gpu-apps", self.alerts()[-1]["text"])
        self.assertFalse((self.root / "restic.calls").exists())
        self.at(SUNDAY + datetime.timedelta(days=4))
        self.stamp("restore-success", SUNDAY - datetime.timedelta(days=38))
        self.run_job("maintenance")
        self.assertIn("restore-stale", (self.state / "maintenance-result").read_text())
        self.run_job("monitor")
        self.assertIn("maintenance is overdue. The last verified restore", self.alerts()[-1]["text"])
        self.assertFalse((self.root / "restic.calls").exists())

    def test_obsolete_ambiguous_submission_is_cancelled(self):
        self.at(SUNDAY, stale="chrysaora/apps")
        self.run_job("monitor", expected=1, FAIL_ENQUEUE="1")
        old = self.alerts()[0]
        self.assertTrue((self.alert_state / "chrysaora-apps.pending.json").exists())
        self.at(SUNDAY + datetime.timedelta(minutes=15))
        self.run_job("monitor")
        self.assertEqual(len(self.alerts()), 1)
        self.assertEqual((self.root / old["requestKey"]).read_text(), "cancelled")
        self.assertFalse((self.alert_state / "chrysaora-apps.pending.json").exists())

    def test_current_backup_failure_and_repository_access_have_descriptions(self):
        profile = self.state / "apps"
        profile.mkdir()
        (profile / "result").write_text("failed 2026-11-15T10:00:00Z postgres\n")
        self.run_job("monitor", expected=1, LIST_EXIT="11")
        self.run_job("monitor")
        texts = [row["text"] for row in self.alerts()]
        self.assertIn("A repository lock blocked the snapshot listing.", texts[0])
        self.assertIn("skepsis-apps is failed. A running PostgreSQL", texts[-1])

    def test_week_starts_at_chicago_maintenance_window_after_dst_change(self):
        boundary = datetime.datetime(2026, 3, 8, 10, 30, tzinfo=UTC)
        self.stamp("maintenance-success", datetime.datetime(2026, 3, 1, 11, 30, tzinfo=UTC))
        self.stamp("restore-success", boundary - datetime.timedelta(days=1))
        self.at(boundary - datetime.timedelta(seconds=1))
        self.run_job("maintenance")
        self.assertFalse((self.root / "restic.calls").exists())
        self.at(boundary)
        self.run_job("maintenance")
        self.assertIn("--prune", (self.root / "restic.calls").read_text())


if __name__ == "__main__":
    unittest.main()
