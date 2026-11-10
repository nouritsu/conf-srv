"""Run Immich's machine-learning queues one at a time, and only while the machine-learning server answers."""

import argparse
import json
import logging
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

log = logging.getLogger("immich-ml-sequencer")

# the queues whose jobs call machine learning, in the order they take turns
ML_QUEUES = ["smartSearch", "faceDetection", "ocr"]
# a paused queue still finishes its active jobs; past this, switch anyway
DRAIN_TIMEOUT = 10 * 60


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
            with urllib.request.urlopen(req, timeout=30) as r:
                data = r.read()
        except urllib.error.HTTPError as e:
            if e.code in (401, 403):
                raise Fatal(f"immich refused the api key ({e.code}); it needs an admin's key with queue.read and queue.update") from e
            raise
        return json.loads(data) if data else None

    def queues(self):
        return {q["name"]: q for q in self.call("GET", "/queues")}

    def pause(self, name, paused):
        self.call("PUT", f"/queues/{name}", {"isPaused": paused})


def ml_up(url):
    try:
        with urllib.request.urlopen(f"{url.rstrip('/')}/ping", timeout=5) as r:
            return r.status == 200
    except (OSError, urllib.error.URLError):
        return False


def pending(queue):
    s = queue["statistics"]
    return s["active"] + s["waiting"] + s["delayed"] + s["paused"]


def drain(immich, names):
    deadline = time.monotonic() + DRAIN_TIMEOUT
    while time.monotonic() < deadline:
        queues = immich.queues()
        if all(queues[n]["statistics"]["active"] == 0 for n in names):
            return
        time.sleep(5)
    log.warning("%s still had active jobs after %d s", ", ".join(names), DRAIN_TIMEOUT)


def step(immich, ml_url, settle):
    queues = immich.queues()
    running = [n for n in ML_QUEUES if not queues[n]["isPaused"]]

    if not ml_up(ml_url):
        if running:
            log.info("%s is down, pausing %s", ml_url, ", ".join(running))
            for n in running:
                immich.pause(n, True)
        return

    current = running[0] if len(running) == 1 else None
    if current and pending(queues[current]):
        return

    # the next queue with work, starting after the one that just drained
    start = ML_QUEUES.index(current) + 1 if current else 0
    order = ML_QUEUES[start:] + ML_QUEUES[:start]
    target = next((n for n in order if pending(queues[n])), current or ML_QUEUES[0])
    if running == [target]:
        return

    others = [n for n in running if n != target]
    for n in others:
        immich.pause(n, True)
    if others:
        drain(immich, others)
        # the machine-learning server unloads a model once it's been idle for its MACHINE_LEARNING_MODEL_TTL
        time.sleep(settle)
    log.info("running %s (%d jobs)", target, pending(queues[target]))
    immich.pause(target, False)


def credential(name):
    directory = os.environ.get("CREDENTIALS_DIRECTORY")
    if not directory or not (Path(directory) / name).is_file():
        raise Fatal(f"no credential {name} (systemd LoadCredential)")
    return (Path(directory) / name).read_text().strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--immich", required=True, help="immich's url, e.g. http://127.0.0.1:2283")
    parser.add_argument("--ml", required=True, help="the machine-learning server's url, e.g. http://pc:3003")
    parser.add_argument("--interval", type=int, default=15, help="seconds between checks")
    parser.add_argument("--settle", type=int, default=60, help="seconds between one queue stopping and the next starting")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    try:
        immich = Immich(args.immich, credential("api-key"))
        log.info("sequencing %s against %s", ", ".join(ML_QUEUES), args.ml)
        failing = False
        while True:
            try:
                step(immich, args.ml, args.settle)
                failing = False
            except (OSError, urllib.error.URLError, json.JSONDecodeError, KeyError) as e:
                # immich restarting; say so once, not every interval
                if not failing:
                    log.warning("immich call failed: %s", e)
                failing = True
            time.sleep(args.interval)
    except Fatal as e:
        log.error("%s", e)
        sys.exit(1)


if __name__ == "__main__":
    main()
