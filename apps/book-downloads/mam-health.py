#!/usr/bin/env python3
"""Read MAM account health through its registered home IP; preserve cookie rotation."""

import json
import math
import os
from pathlib import Path
import shlex
import stat
import subprocess
import sys
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[2]
STATE = ROOT / "data/book-downloads"
COOKIE = STATE / "mam-account-cookie"
SNAPSHOT = STATE / "mam-health.json"
GIB = 1024**3

# A separate account-monitor session is required. Never borrow Prowlarr's cookie
# or Mousehole's dynamic-seedbox session: jsonLoad.php rotates mam_id on reads.
REMOTE = r'''
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
    # Current upstream client documents 500 points/GB and a 50 GB minimum.
    # This is a review trigger, not an automatic purchase or a price guarantee.
    if values["seedbonus"] >= 27_500:
        actions.append("Review a 50 GB upload-credit redemption; verify current store terms and retain 2,500 bonus points.")
    return {
        **values,
        "ratio": round(ratio, 3) if ratio is not None else None,
        "bufferGiB": round(buffer, 2),
        "class": account.get("classname"),
        "actions": actions,
    }


def main():
    os.umask(0o077)
    checked = datetime.now(timezone.utc).isoformat()
    try:
        info = COOKIE.lstat()
        if not stat.S_ISREG(info.st_mode) or info.st_mode & 0o077:
            raise ValueError("MAM account cookie must be a regular file with mode 600")
        cookie = COOKIE.read_text().strip()
        if not cookie or any(c.isspace() for c in cookie) or len(cookie) > 8192:
            raise ValueError("Invalid MAM account cookie file")
        result = subprocess.run(
            ["ssh", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
             "-o", "ConnectTimeout=10", "100.115.19.60", "python3", "-c", shlex.quote(REMOTE)],
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
        snapshot = {"checkedAt": checked, "status": "action-required" if account["actions"] else "ok", **account}
        atomic_write(SNAPSHOT, json.dumps(snapshot, indent=2) + "\n")
        print(json.dumps(snapshot))
        return 1 if account["actions"] else 0
    except Exception as error:
        # Never emit raw SSH/API output or credentials, including malformed JSON.
        message = str(error) if isinstance(error, ValueError) and not isinstance(error, json.JSONDecodeError) else "MAM account check failed"
        previous = None
        if SNAPSHOT.exists():
            try:
                previous = json.loads(SNAPSHOT.read_text())
                if previous.get("status") == "error":
                    previous = previous.get("lastSuccessfulCheck")
            except (OSError, ValueError):
                pass
        snapshot = {"checkedAt": checked, "status": "error", "error": message, "lastSuccessfulCheck": previous}
        atomic_write(SNAPSHOT, json.dumps(snapshot, indent=2) + "\n")
        print(message, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
