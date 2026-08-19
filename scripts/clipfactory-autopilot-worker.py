#!/usr/bin/env python3

import json
import subprocess
import time
import os
from pathlib import Path
from datetime import datetime

ROOT = Path.home() / "clipfactory-site"
RUNTIME = Path.home() / ".clipfactory"

AUTOPILOT_FILE = RUNTIME / "autopilot.json"
LOCK_FILE = RUNTIME / "autopilot.lock"
LOG_FILE = RUNTIME / "autopilot.log"

SCHEDULER = ROOT / "scripts" / "clipfactory-scheduler.py"
WORKER = ROOT / "scripts" / "clipfactory-scheduled-worker.sh"

CHECK_INTERVAL = 60


def now():
    return datetime.now().isoformat(
        timespec="seconds"
    )


def log(message):

    RUNTIME.mkdir(
        parents=True,
        exist_ok=True
    )

    line = f"[{now()}] {message}"

    print(line, flush=True)

    with LOG_FILE.open(
        "a",
        encoding="utf-8"
    ) as f:

        f.write(
            line + "\n"
        )


def read_json(
    path,
    default
):

    try:

        return json.loads(
            path.read_text(
                encoding="utf-8"
            )
        )

    except Exception:

        return default


def autopilot_enabled():

    data = read_json(
        AUTOPILOT_FILE,
        {
            "enabled":False
        }
    )

    return bool(
        data.get(
            "enabled",
            False
        )
    )


def scheduler_status():

    try:

        p = subprocess.run(
            [
                "python",
                str(SCHEDULER)
            ],
            capture_output=True,
            text=True,
            timeout=60
        )

        if p.returncode != 0:

            log(
                "Scheduler error: "
                +
                (
                    p.stderr
                    or p.stdout
                    or "unknown"
                )[-500:]
            )

            return {}

        return json.loads(
            p.stdout
            or "{}"
        )

    except Exception as exc:

        log(
            "Scheduler exception: "
            + str(exc)
        )

        return {}


def acquire_lock():

    try:

        fd = os.open(
            LOCK_FILE,
            os.O_CREAT
            |
            os.O_EXCL
            |
            os.O_WRONLY
        )

        os.write(
            fd,
            str(
                os.getpid()
            ).encode()
        )

        os.close(
            fd
        )

        return True

    except FileExistsError:

        return False


def release_lock():

    try:

        LOCK_FILE.unlink(
            missing_ok=True
        )

    except Exception:
        pass


def process_due():

    if not acquire_lock():

        log(
            "Another autopilot operation is already running"
        )

        return

    try:

        status = scheduler_status()

        due = status.get(
            "due"
        )

        if not due:

            log(
                "No DUE video"
            )

            return

        log(
            "DUE: "
            + str(
                due.get(
                    "file"
                )
            )
        )

        p = subprocess.run(
            [
                str(WORKER)
            ],
            capture_output=True,
            text=True,
            timeout=900
        )

        output = (
            (p.stdout or "")
            +
            (p.stderr or "")
        )

        if p.returncode == 0:

            log(
                "Scheduled worker SUCCESS"
            )

        else:

            log(
                "Scheduled worker FAILED: "
                + output[-1500:]
            )

    finally:

        release_lock()


def cycle():

    if not autopilot_enabled():

        log(
            "Autopilot OFF"
        )

        return

    log(
        "Autopilot ON"
    )

    process_due()


def loop():

    log(
        "ClipFactory Autopilot Worker started"
    )

    while True:

        try:

            cycle()

        except Exception as exc:

            log(
                "Worker exception: "
                + str(exc)
            )

        time.sleep(
            CHECK_INTERVAL
        )


if __name__ == "__main__":

    import sys

    if (
        len(sys.argv) > 1
        and sys.argv[1]
        == "once"
    ):

        cycle()

    else:

        loop()
