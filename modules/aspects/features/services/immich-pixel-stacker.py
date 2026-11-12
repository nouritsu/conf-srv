"""Stack the files the Pixel camera saves for one shot in Immich, with the finished one on top."""

import argparse
import json
import logging
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

log = logging.getLogger("immich-pixel-stacker")

# PXL_20261112_124644518.RAW-01.COVER.jpg + .RAW-02.ORIGINAL.dng, PXL_20250208_185226175.VB-01.COVER.mp4 + .VB-02.MAIN.mp4
PART = re.compile(r"^(?P<shot>PXL_\d{8}_\d+\.[A-Z_.]+)-(?P<n>0\d)\.(?P<kind>[A-Z.]+?)(?P<copy>~\d+)?\.\w+$")
# the first kind present goes on top: video boost's processed video, else the camera's edited photo over its raw or unprocessed frame
TOP = ["MAIN", "COVER", "MP.COVER"]
# hidden is a motion photo's video, locked needs a pin
VISIBLE = {"timeline", "archive"}


class Fatal(Exception):
    """A failure retrying won't fix, such as a rejected API key."""


class Immich:
    def __init__(self, url, key):
        self.url = url.rstrip("/")
        self.key = key

    def call(self, method, path, body=None):
        req = urllib.request.Request(
            f"{self.url}/api{path}",
            data=None if body is None else json.dumps(body).encode(),
            headers={"x-api-key": self.key, "content-type": "application/json", "accept": "application/json"},
            method=method,
        )
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                data = r.read()
        except urllib.error.HTTPError as e:
            if e.code in (401, 403):
                raise Fatal(f"immich refused the api key ({e.code}); it needs user.read, asset.read and stack.create") from e
            raise
        return json.loads(data) if data else None

    def unstacked_parts(self):
        cursor = None
        while True:
            body = {"filter": {"originalFileName": {"startsWith": "PXL_", "like": "-0"}}, "withStacked": False, "size": 1000}
            if cursor:
                body["cursor"] = cursor
            page = self.call("POST", "/search/metadata", body)["assets"]
            yield from page["items"]
            cursor = page.get("nextCursor")
            if not cursor:
                return


def top(parts):
    for kind in TOP:
        found = [a for a, m in parts if m["kind"] == kind and not m["copy"]]
        if len(found) == 1:
            return found[0]
    return None


def run(immich):
    owner = immich.call("GET", "/users/me")["id"]
    shots = {}
    for a in immich.unstacked_parts():
        m = PART.match(a["originalFileName"])
        if m and a["ownerId"] == owner and a["visibility"] in VISIBLE and not a["isTrashed"]:
            shots.setdefault(m["shot"], []).append((a, m))

    stacked = 0
    for shot, parts in sorted(shots.items()):
        if len(parts) < 2:
            continue
        primary = top(parts)
        if primary is None:
            log.warning("%s has no single file to put on top, leaving it", shot)
            continue
        rest = [a["id"] for a, _ in sorted(parts, key=lambda p: p[0]["originalFileName"]) if a is not primary]
        immich.call("POST", "/stacks", {"assetIds": [primary["id"], *rest]})
        log.info("stacked %s under %s", shot, primary["originalFileName"])
        stacked += 1
    log.info("%d new stacks", stacked)


def credential(name):
    directory = os.environ.get("CREDENTIALS_DIRECTORY")
    if not directory or not (Path(directory) / name).is_file():
        raise Fatal(f"no credential {name} (systemd LoadCredential)")
    return (Path(directory) / name).read_text().strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--immich", required=True, help="immich's url, e.g. http://127.0.0.1:2283")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    try:
        run(Immich(args.immich, credential("api-key")))
    except Fatal as e:
        log.error("%s", e)
        sys.exit(1)


if __name__ == "__main__":
    main()
