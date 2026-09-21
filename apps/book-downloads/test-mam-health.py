import importlib.util
import json
from pathlib import Path
import tempfile
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
            snapshot.write_text(json.dumps({"status": "ok", "ratio": 3}))
            response = SimpleNamespace(returncode=1, stdout="private-cookie", stderr="private-cookie")
            with patch.object(health, "COOKIE", cookie), patch.object(health, "SNAPSHOT", snapshot), patch.object(health.subprocess, "run", return_value=response), patch("builtins.print"):
                self.assertEqual(health.main(), 1)
            saved = json.loads(snapshot.read_text())
            self.assertEqual(saved["status"], "error")
            self.assertEqual(saved["lastSuccessfulCheck"]["ratio"], 3)
            self.assertNotIn("private-cookie", snapshot.read_text())


if __name__ == "__main__":
    unittest.main()
