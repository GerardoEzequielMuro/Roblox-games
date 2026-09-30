"""Uploads assets/icons/*.png to Roblox (Open Cloud Assets API) and writes the IDs into every game.

Setup (once):
  1. https://create.roblox.com/dashboard/credentials -> Create API key
     - Access: "Assets" API -> Read + Write
     - Accepted IP: your IP (or 0.0.0.0/0 while testing)
  2. Your numeric Roblox user id (profile URL: roblox.com/users/<ID>/profile)
  3. PowerShell:
       $env:ROBLOX_API_KEY = "<key>"          # never commit it, never put it in a file of the repo
       $env:ROBLOX_USER_ID = "<id>"           # or ROBLOX_GROUP_ID if the games belong to a group
       python tools/icons/upload_assets.py

Already uploaded icons are skipped (assets/asset_ids.json keeps name -> id), so it is safe to re-run
after adding new icons. --dry-run only rewrites the Icons.luau files from the JSON.
"""

from __future__ import annotations

import json
import os
import pathlib
import re
import sys
import time
import urllib.error
import urllib.request
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[2]
ICONS = ROOT / "assets" / "icons"
IDS_FILE = ROOT / "assets" / "asset_ids.json"
GAMES = ["anime-planet-clicker", "huerta-tycoon", "ki-warriors", "obby-sky-tower", "pet-tap-simulator", "ruleta-pvp"]
API = "https://apis.roblox.com/assets/v1"


def _request(method: str, url: str, key: str, body: bytes | None = None, ctype: str | None = None) -> dict:
    req = urllib.request.Request(url, data=body, method=method, headers={"x-api-key": key})
    if ctype:
        req.add_header("Content-Type", ctype)
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read() or b"{}")


def upload(png: pathlib.Path, key: str, creator: dict) -> str:
    meta = {"assetType": "Decal", "displayName": f"icon_{png.stem}", "description": "HUD icon",
            "creationContext": {"creator": creator}}
    boundary = uuid.uuid4().hex
    body = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"request\"\r\n\r\n{json.dumps(meta)}\r\n"
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"fileContent\"; filename=\"{png.name}\"\r\n"
            f"Content-Type: image/png\r\n\r\n").encode() + png.read_bytes() + f"\r\n--{boundary}--\r\n".encode()
    op = _request("POST", f"{API}/assets", key, body, f"multipart/form-data; boundary={boundary}")
    # upload is async: poll the operation until moderation/processing hands back the asset id
    for _ in range(30):
        if op.get("done") and op.get("response", {}).get("assetId"):
            return str(op["response"]["assetId"])
        time.sleep(2)
        op = _request("GET", f"{API}/operations/{op['operationId'] if 'operationId' in op else op['path'].split('/')[-1]}", key)
    raise RuntimeError(f"{png.name}: operation did not finish ({op})")


def write_luau(ids: dict[str, str]) -> None:
    names = sorted(p.stem for p in ICONS.glob("*.png"))
    block = "\n".join(f'\t{n} = "{ids.get(n, "")}",' for n in names)
    for game in GAMES:
        f = ROOT / game / "src" / "shared" / "Icons.luau"
        if not f.exists():
            continue
        src = f.read_text(encoding="utf-8")
        new = re.sub(r"(-- BEGIN GENERATED\n).*?(\n\s*-- END GENERATED)", lambda m: m.group(1) + block + m.group(2), src, flags=re.S)
        f.write_text(new, encoding="utf-8", newline="\n")
        print(f"updated {f.relative_to(ROOT)}")


def main() -> None:
    ids: dict[str, str] = json.loads(IDS_FILE.read_text()) if IDS_FILE.exists() else {}
    if "--dry-run" not in sys.argv:
        key = os.environ.get("ROBLOX_API_KEY")
        user, group = os.environ.get("ROBLOX_USER_ID"), os.environ.get("ROBLOX_GROUP_ID")
        if not key or not (user or group):
            sys.exit("Set ROBLOX_API_KEY and ROBLOX_USER_ID (or ROBLOX_GROUP_ID). See the header of this file.")
        creator = {"groupId": group} if group else {"userId": user}
        for png in sorted(ICONS.glob("*.png")):
            if ids.get(png.stem):
                continue
            try:
                ids[png.stem] = upload(png, key, creator)
                print(f"{png.stem}: {ids[png.stem]}")
            except urllib.error.HTTPError as e:
                print(f"{png.stem}: HTTP {e.code} {e.read()[:300]!r}")
            IDS_FILE.write_text(json.dumps(ids, indent=2, sort_keys=True))
            time.sleep(1)  # stay far below the per-key rate limit
    write_luau(ids)


if __name__ == "__main__":
    main()
