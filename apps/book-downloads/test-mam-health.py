import importlib.util
import io
import os
import json
from pathlib import Path
import tempfile
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("mam_health", Path(__file__).with_name("mam-health.py"))
health = importlib.util.module_from_spec(spec)
spec.loader.exec_module(health)


class AccountHealthTests(unittest.TestCase):
    def account(self, **changes):
        return {"uploaded_bytes": 30 * health.GIB, "downloaded_bytes": 10 * health.GIB,
                "seedbonus": 9000, "wedges": 43, "classname": "User", **changes}

    def test_credit_and_low_buffer_are_checked_independently(self):
        self.assertEqual(health.evaluate(self.account())["actions"], [])
        low_ratio = health.evaluate(self.account(downloaded_bytes=16 * health.GIB))
        self.assertTrue(any("2.0" in a for a in low_ratio["actions"]))
        low_buffer = health.evaluate(self.account(uploaded_bytes=4 * health.GIB, downloaded_bytes=health.GIB))
        self.assertEqual(low_buffer["ratio"], 4)
        self.assertTrue(any("10 GiB" in a for a in low_buffer["actions"]))

    def test_missing_or_invalid_stats_are_not_treated_as_healthy(self):
        for value in (None, -1, float("nan"), float("inf"), True, "100"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                health.evaluate(self.account(uploaded_bytes=value))

    def test_bonus_and_wedge_reviews_do_not_spend_anything(self):
        result = health.evaluate(self.account(seedbonus=27500, wedges=5))
        self.assertEqual(len(result["actions"]), 2)
        self.assertEqual(result["seedbonus"], 27500)
        self.assertEqual(result["wedges"], 5)

    def test_rotated_cookie_is_saved_privately_and_omitted_from_snapshot(self):
        with tempfile.TemporaryDirectory() as temporary:
            cookie = Path(temporary) / "cookie"
            snapshot = Path(temporary) / "health.json"
            cookie.write_text("old-cookie")
            cookie.chmod(0o600)
            response = SimpleNamespace(returncode=0, stdout=json.dumps({"cookie": "rotated-cookie", "account": self.account()}))
            with patch.object(health, "COOKIE", cookie), patch.object(health, "SNAPSHOT", snapshot), patch.object(health.subprocess, "run", return_value=response), patch("builtins.print"):
                self.assertEqual(health.main(), 0)
            self.assertEqual(cookie.read_text(), "rotated-cookie\n")
            self.assertEqual(cookie.stat().st_mode & 0o777, 0o600)
            self.assertNotIn("cookie", snapshot.read_text())
            self.assertEqual(json.loads(snapshot.read_text())["status"], "ok")

    def test_failed_check_preserves_last_good_account_and_does_not_expose_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            cookie = Path(temporary) / "cookie"
            snapshot = Path(temporary) / "health.json"
            cookie.write_text("private-cookie")
            cookie.chmod(0o600)
            snapshot.write_text(json.dumps({"status": "ok", "ratio": 3,
                                            "checkedAt": "2020-01-01T00:00:00+00:00"}))
            response = SimpleNamespace(returncode=1, stdout="private-cookie", stderr="private-cookie")
            with patch.object(health, "COOKIE", cookie), patch.object(health, "SNAPSHOT", snapshot), patch.object(health.subprocess, "run", return_value=response), patch("builtins.print"):
                self.assertEqual(health.main(), 1)
            saved = json.loads(snapshot.read_text())
            self.assertEqual(saved["status"], "error")
            self.assertEqual(saved["lastSuccessfulCheck"]["ratio"], 3)
            self.assertNotIn("private-cookie", snapshot.read_text())

    def test_daily_limit_survives_failure_and_does_not_overwrite_snapshot(self):
        with tempfile.TemporaryDirectory() as temporary:
            cookie = Path(temporary) / "cookie"
            snapshot = Path(temporary) / "health.json"
            cookie.write_text("private-cookie")
            cookie.chmod(0o600)
            response = SimpleNamespace(returncode=1, stdout="", stderr="")
            with patch.object(health, "COOKIE", cookie), patch.object(health, "SNAPSHOT", snapshot), patch.object(health.subprocess, "run", return_value=response) as request, patch("builtins.print"):
                self.assertEqual(health.main(), 1)
                saved = snapshot.read_text()
                self.assertEqual(health.main(), 0)
                self.assertEqual(snapshot.read_text(), saved)
                self.assertEqual(request.call_count, 1)
            self.assertEqual(snapshot.with_name("mam-health-attempt.json").stat().st_mode & 0o777, 0o600)

    def test_upgrade_and_restart_keep_a_full_day_between_attempts(self):
        now = datetime(2026, 10, 7, 20, 0, tzinfo=timezone.utc)
        with tempfile.TemporaryDirectory() as temporary:
            snapshot = Path(temporary) / "health.json"
            snapshot.write_text(json.dumps({"checkedAt": now.isoformat()}))
            with patch.object(health, "SNAPSHOT", snapshot):
                self.assertFalse(health.reserve_attempt(now + timedelta(hours=23, minutes=59)))
                self.assertTrue(health.reserve_attempt(now + timedelta(hours=24)))
                self.assertFalse(health.reserve_attempt(now + timedelta(hours=30)))
                self.assertFalse(health.reserve_attempt(now - timedelta(hours=1)))
                self.assertTrue(health.reserve_attempt(now + timedelta(hours=48)))

    def test_invalid_timestamp_does_not_allow_a_request(self):
        with tempfile.TemporaryDirectory() as temporary:
            snapshot = Path(temporary) / "health.json"
            snapshot.write_text('{"checkedAt":"invalid"}')
            with patch.object(health, "SNAPSHOT", snapshot), patch.object(health.subprocess, "run") as request, patch("builtins.print"):
                self.assertEqual(health.main(), 1)
                request.assert_not_called()

    def test_suggestions_exit_successfully(self):
        with tempfile.TemporaryDirectory() as temporary:
            cookie = Path(temporary) / "cookie"
            snapshot = Path(temporary) / "health.json"
            cookie.write_text("old-cookie")
            cookie.chmod(0o600)
            response = SimpleNamespace(returncode=0, stdout=json.dumps({"cookie": "rotated", "account": self.account(seedbonus=27500)}))
            with patch.dict(os.environ, {}, clear=False), patch.object(health, "COOKIE", cookie), patch.object(health, "SNAPSHOT", snapshot), patch.object(health.subprocess, "run", return_value=response), patch("builtins.print"):
                os.environ.pop("MAM_BOOKS_QBT_URL", None)
                self.assertEqual(health.main(), 0)
            self.assertEqual(json.loads(snapshot.read_text())["status"], "action-required")

    def test_upload_change_time_only_moves_when_upload_grows(self):
        now = datetime(2026, 11, 11, tzinfo=timezone.utc)
        previous = {"uploaded_bytes": 100, "checkedAt": "2026-11-01T00:00:00+00:00", "uploadedChangedAt": "2026-10-24T00:00:00+00:00"}
        self.assertEqual(health.upload_changed_at(100, now, previous), "2026-10-24T00:00:00+00:00")
        self.assertEqual(health.upload_changed_at(101, now, previous), now.isoformat())
        self.assertEqual(health.upload_changed_at(100, now, None), now.isoformat())
        self.assertEqual(health.upload_changed_at(100, now, {"uploaded_bytes": 100, "checkedAt": "2026-11-01T00:00:00+00:00"}), "2026-11-01T00:00:00+00:00")

    def test_rejected_tracker_and_stalled_upload_are_reported(self):
        now = datetime(2026, 11, 11, tzinfo=timezone.utc)
        account = {"uploadedChangedAt": (now - timedelta(days=8)).isoformat()}
        books = {"torrents": 20, "notWorking": 20, "message": "client not allowed"}
        actions = health.seeding_actions(account, books, now)
        self.assertTrue(any("rejecting 20 of 20" in a for a in actions))
        self.assertTrue(any("has not grown" in a for a in actions))
        account["uploadedChangedAt"] = (now - timedelta(days=2)).isoformat()
        self.assertEqual(health.seeding_actions(account, {"torrents": 20, "notWorking": 0, "message": None}, now), [])

    def test_books_trackers_counts_rejected_mam_torrents_without_urls(self):
        replies = {
            "torrents/info": [{"hash": "a"}, {"hash": "b"}],
            "torrents/trackers?hash=a": [{"url": "** [DHT] **", "status": 2}, {"url": "https://t.myanonamouse.net/tracker.php/secret/announce.php", "status": 4, "msg": "client not allowed"}],
            "torrents/trackers?hash=b": [{"url": "https://t.myanonamouse.net/tracker.php/secret/announce.php", "status": 2, "msg": ""}],
        }

        def urlopen(request, timeout):
            path = request.full_url.split("/api/v2/", 1)[1]
            return io.BytesIO(json.dumps(replies[path]).encode())

        with patch.dict(os.environ, {"MAM_BOOKS_QBT_URL": "http://books.invalid/books-qbt", "MAM_BOOKS_QBT_HOST": "arr.example"}), patch.object(health.urllib.request, "urlopen", urlopen):
            result = health.books_trackers()
        self.assertEqual(result, {"torrents": 2, "notWorking": 1, "message": "client not allowed"})
        self.assertNotIn("secret", json.dumps(result))


if __name__ == "__main__":
    unittest.main()
