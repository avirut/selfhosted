#!/usr/bin/env python3

import json
import math
import os
from pathlib import Path
import stat
import subprocess
import sys
import urllib.request
from datetime import datetime, timedelta, timezone

ROOT = Path(__file__).resolve().parents[2]
STATE = ROOT / "data/book-downloads"
COOKIE = STATE / "mam-account-cookie"
SNAPSHOT = STATE / "mam-health.json"
GIB = 1024**3
STALLED_UPLOAD = timedelta(days=7)

REQUEST = r'''
import http.cookies, json, sys, urllib.request
try:
    cookie = json.load(sys.stdin)["cookie"]
    request = urllib.request.Request(
        "https://www.myanonamouse.net/jsonLoad.php",
        headers={"Cookie": "mam_id=" + cookie},
    )
    with urllib.request.urlopen(request, timeout=25) as response:
        rotated = http.cookies.SimpleCookie()
        for header in response.headers.get_all("Set-Cookie", []):
            rotated.load(header)
        current = rotated["mam_id"].value if "mam_id" in rotated else cookie
        data = json.load(response)
    keys = ("uploaded_bytes", "downloaded_bytes", "ratio", "seedbonus", "wedges", "classname")
    print(json.dumps({"cookie": current, "account": {k: data.get(k) for k in keys}}))
except Exception:
    print("MAM account request failed", file=sys.stderr)
    sys.exit(1)
'''


def atomic_write(path, text):
    temporary = path.with_name(path.name + ".tmp")
    try:
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as stream:
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def reserve_attempt(now):
    attempt = SNAPSHOT.with_name("mam-health-attempt.json")
    source = attempt if attempt.exists() else SNAPSHOT
    if source.exists():
        try:
            last = datetime.fromisoformat(json.loads(source.read_text())["checkedAt"])
            if last.tzinfo is None:
                raise ValueError("Missing timezone")
        except (OSError, ValueError, KeyError, TypeError):
            raise ValueError("Invalid MAM check timestamp; inspect local state before polling") from None
        if (now - last).total_seconds() < 86400:
            return False
    atomic_write(attempt, json.dumps({"checkedAt": now.isoformat()}) + "\n")
    return True


def previous_account():
    try:
        previous = json.loads(SNAPSHOT.read_text())
    except (OSError, ValueError):
        return None
    if previous.get("status") == "error":
        previous = previous.get("lastSuccessfulCheck")
    return previous if isinstance(previous, dict) else None


def upload_changed_at(uploaded, now, previous):
    if previous and isinstance(previous.get("uploaded_bytes"), (int, float)):
        changed = previous.get("uploadedChangedAt") or previous.get("checkedAt")
        if uploaded <= previous["uploaded_bytes"] and isinstance(changed, str):
            return changed
    return now.isoformat()


def books_trackers():
    url = os.environ.get("MAM_BOOKS_QBT_URL")
    if not url:
        return None
    host = os.environ.get("MAM_BOOKS_QBT_HOST")
    headers = {"Host": host} if host else {}

    def get(path):
        request = urllib.request.Request(url.rstrip("/") + "/api/v2/" + path, headers=headers)
        with urllib.request.urlopen(request, timeout=15) as response:
            return json.load(response)

    try:
        torrents = get("torrents/info")
        rejected, message = 0, None
        for torrent in torrents:
            for tracker in get("torrents/trackers?hash=" + torrent["hash"]):
                if "myanonamouse" in tracker.get("url", "") and tracker.get("status") == 4:
                    rejected += 1
                    message = message or (tracker.get("msg") or "")[:200] or None
                    break
        return {"torrents": len(torrents), "notWorking": rejected, "message": message}
    except Exception:
        return {"error": "books client unreachable"}


def evaluate(account):
    values = {}
    for key in ("uploaded_bytes", "downloaded_bytes", "seedbonus", "wedges"):
        value = account.get(key)
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise ValueError("Incomplete MAM account response")
        if not math.isfinite(value) or value < 0:
            raise ValueError("Invalid MAM account response")
        values[key] = value
    uploaded, downloaded = values["uploaded_bytes"], values["downloaded_bytes"]
    ratio = uploaded / downloaded if downloaded else None
    buffer = (uploaded - downloaded) / GIB
    actions = []
    if ratio is not None and ratio < 2:
        actions.append("Hold charged downloads: account ratio is below the 2.0 reserve.")
    if buffer < 10:
        actions.append("Build upload credit: less than 10 GiB remains above ratio 1.0.")
    if values["wedges"] <= 5:
        actions.append("Replenish freeleech wedges before further charged acquisitions.")
    if values["seedbonus"] >= 27_500:
        actions.append("Review a 50 GB upload-credit redemption; verify current store terms and retain 2,500 bonus points.")
    return {
        **values,
        "ratio": round(ratio, 3) if ratio is not None else None,
        "bufferGiB": round(buffer, 2),
        "class": account.get("classname"),
        "actions": actions,
    }


def seeding_actions(account, books, now):
    actions = []
    if books and books.get("notWorking"):
        actions.append(f"MAM is rejecting {books['notWorking']} of {books['torrents']} books torrents: {books.get('message') or 'no tracker message'}")
    changed = datetime.fromisoformat(account["uploadedChangedAt"])
    if now - changed >= STALLED_UPLOAD:
        actions.append(f"MAM upload has not grown since {changed.date().isoformat()}.")
    return actions


def main():
    os.umask(0o077)
    now = datetime.now(timezone.utc)
    checked = now.isoformat()
    try:
        if not reserve_attempt(now):
            print("MAM account check skipped: the previous attempt was less than 24 hours ago.")
            return 0
        info = COOKIE.lstat()
        if not stat.S_ISREG(info.st_mode) or info.st_mode & 0o077:
            raise ValueError("MAM account cookie must be a regular file with mode 600")
        cookie = COOKIE.read_text().strip()
        if not cookie or any(c.isspace() for c in cookie) or len(cookie) > 8192:
            raise ValueError("Invalid MAM account cookie file")
        result = subprocess.run(
            [sys.executable, "-c", REQUEST],
            input=json.dumps({"cookie": cookie}), capture_output=True, text=True, timeout=45,
        )
        if result.returncode:
            raise ValueError("MAM account check failed; inspect connectivity/session before retrying")
        response = json.loads(result.stdout)
        rotated = response.get("cookie")
        if not isinstance(rotated, str) or not rotated or len(rotated) > 8192 or any(c.isspace() for c in rotated):
            raise ValueError("Invalid rotated MAM cookie")
        atomic_write(COOKIE, rotated + "\n")
        account = evaluate(response["account"])
        account["uploadedChangedAt"] = upload_changed_at(account["uploaded_bytes"], now, previous_account())
        books = books_trackers()
        account["books"] = books
        account["actions"] += seeding_actions(account, books, now)
        snapshot = {"checkedAt": checked, "status": "action-required" if account["actions"] else "ok", **account}
        atomic_write(SNAPSHOT, json.dumps(snapshot, indent=2) + "\n")
        print(json.dumps(snapshot))
        return 0
    except Exception as error:
        message = str(error) if isinstance(error, ValueError) and not isinstance(error, json.JSONDecodeError) else "MAM account check failed"
        previous = previous_account()
        snapshot = {"checkedAt": checked, "status": "error", "error": message, "lastSuccessfulCheck": previous}
        atomic_write(SNAPSHOT, json.dumps(snapshot, indent=2) + "\n")
        print(message, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
