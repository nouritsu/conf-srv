"""Whether I am about, for nouritsu.com/status.json, from the beszel hub on this host:
online while the PC is up, away while only the laptop is, offline while neither is.

Only that word leaves this host - no machine names, times, addresses or metrics - and a
new word is published only once it has held for --hold seconds, so the page follows by
about ten minutes rather than to the minute.

Run by a timer. The hub not answering is not news every few minutes: the first run that
gets no answer fails (and so mails root), later ones log and carry on. Until the hub has
been silent for --stale seconds the page keeps what it said; after that, offline.
"""

import argparse
import json
import os
import sys
import time
import urllib.request
from pathlib import Path


def credential(name: str) -> str:
    return (Path(os.environ["CREDENTIALS_DIRECTORY"]) / name).read_text().strip()


def systems(hub: str, email: str, password: str) -> dict[str, str]:
    """Each system the hub shows this user, by name, with its status: up, down, paused or
    pending. The user is read-only and shown only the machines that matter here."""

    def call(path: str, body: dict | None = None, token: str | None = None) -> dict:
        headers = {"Content-Type": "application/json"}
        if token:
            headers["Authorization"] = token
        request = urllib.request.Request(
            hub + path,
            data=None if body is None else json.dumps(body).encode(),
            headers=headers,
        )
        with urllib.request.urlopen(request, timeout=10) as response:
            return json.load(response)

    auth = call("/api/collections/users/auth-with-password", {"identity": email, "password": password})
    listing = call("/api/collections/systems/records?perPage=200&fields=name,status", token=auth["token"])
    return {item["name"]: item["status"] for item in listing["items"]}


def word(found: dict[str, str], online: str, away: str) -> str:
    if found.get(online) == "up":
        return "online"
    if found.get(away) == "up":
        return "away"
    return "offline"


def write(path: Path, data: dict, mode: int) -> None:
    """Replaces the file whole, so a reader never sees half of it."""
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(data) + "\n")
    temporary.chmod(mode)
    temporary.replace(path)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hub", required=True, help="the beszel hub's address")
    parser.add_argument("--online", required=True, help="the system whose being up means online")
    parser.add_argument("--away", required=True, help="the system whose being up alone means away")
    parser.add_argument("--hold", type=int, default=600, help="seconds a new word must hold before it shows")
    parser.add_argument("--stale", type=int, default=1800, help="seconds of silence from the hub before offline")
    parser.add_argument("--state", type=Path, required=True, help="this script's own memory, private")
    parser.add_argument("--out", type=Path, required=True, help="the published file")
    args = parser.parse_args()

    now = time.time()
    try:
        state = json.loads(args.state.read_text())
    except (OSError, ValueError):
        state = {}
    failing_before = state.get("failing", False)

    try:
        seen = word(systems(args.hub, credential("email"), credential("password")), args.online, args.away)
        state["failing"] = False
        state["answered"] = now
    except Exception as error:  # any failure means no answer from the hub
        print(f"presence: no answer from the hub: {error}", file=sys.stderr)
        state["failing"] = True
        # until the hub has been quiet a while, the page keeps what it last said
        silent = now - state.get("answered", 0) >= args.stale
        seen = "offline" if silent or "shown" not in state else state["shown"]

    # a new word starts its hold; it shows once it has held long enough
    if seen != state.get("seen"):
        state["seen"] = seen
        state["since"] = now
    if "shown" not in state or now - state["since"] >= args.hold:
        state["shown"] = state["seen"]

    write(args.state, state, 0o600)
    write(args.out, {"status": state["shown"]}, 0o644)

    # one mail as the hub goes quiet, not one every run while it stays so
    return 1 if state["failing"] and not failing_before else 0


if __name__ == "__main__":
    sys.exit(main())
