#!/usr/bin/env python3

import json
import hashlib
import subprocess
import urllib.request
from pathlib import Path
from datetime import datetime

HOME = Path.home()
SITE = HOME / "clipfactory-site"
FACTORY = HOME / "tiktok_factory"
RUNTIME = HOME / ".clipfactory"

REPORT = RUNTIME / "tests" / "stability_report.json"

QUEUE = RUNTIME / "queue.json"
SCHEDULE = RUNTIME / "schedule.json"

VIDEO_NAMES = {
    "joined.mp4",
    "final.mp4",
    "output.mp4",
    "result.mp4"
}


def sha(path):

    h = hashlib.sha256()

    with path.open("rb") as f:

        while True:

            chunk = f.read(
                1024 * 1024
            )

            if not chunk:
                break

            h.update(chunk)

    return h.hexdigest()


def ffprobe(path):

    cmd = [
        "ffprobe",
        "-v",
        "error",

        "-select_streams",
        "v:0",

        "-show_entries",
        "stream=codec_name,width,height,r_frame_rate",

        "-show_entries",
        "format=duration,size",

        "-of",
        "json",

        str(path)
    ]

    try:

        p = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30
        )

        if p.returncode != 0:

            return {
                "ok":False,
                "error":p.stderr[-500:]
            }

        d = json.loads(
            p.stdout
            or "{}"
        )

        stream = (
            d.get(
                "streams",
                [{}]
            )[0]
        )

        fmt = d.get(
            "format",
            {}
        )

        width = int(
            stream.get(
                "width",
                0
            )
            or 0
        )

        height = int(
            stream.get(
                "height",
                0
            )
            or 0
        )

        duration = float(
            fmt.get(
                "duration",
                0
            )
            or 0
        )

        size = int(
            fmt.get(
                "size",
                0
            )
            or 0
        )

        codec = stream.get(
            "codec_name"
        )

        return {
            "ok":
                (
                    codec == "h264"
                    and height > width
                    and duration >= 4
                    and size > 100000
                ),

            "codec":
                codec,

            "width":
                width,

            "height":
                height,

            "duration":
                round(
                    duration,
                    2
                ),

            "size":
                size,

            "fps":
                stream.get(
                    "r_frame_rate"
                )
        }

    except Exception as exc:

        return {
            "ok":False,
            "error":str(exc)
        }


def find_videos():

    videos = []

    if not FACTORY.exists():
        return videos

    candidates = []

    for p in FACTORY.rglob("*.mp4"):

        try:

            # Ignore fichiers minuscules / incomplets
            if p.stat().st_size < 500_000:
                continue

            candidates.append(p)

        except Exception:
            continue

    candidates.sort(
        key=lambda x: x.stat().st_mtime,
        reverse=True
    )

    unique = []
    seen = set()

    for p in candidates:

        fp = sha(p)

        if fp in seen:
            continue

        # Valide réellement la vidéo avant de la compter
        info = ffprobe(p)

        if not info.get("ok"):
            continue

        seen.add(fp)

        unique.append(
            (p, fp)
        )

        if len(unique) >= 3:
            break

    return unique


def api(path):

    try:

        with urllib.request.urlopen(
            "http://127.0.0.1:8787"
            + path,
            timeout=5
        ) as r:

            return {
                "ok":True,
                "data":
                    json.loads(
                        r.read().decode()
                    )
            }

    except Exception as exc:

        return {
            "ok":False,
            "error":str(exc)
        }


def check_git_secrets():

    p = subprocess.run(
        [
            "git",
            "ls-files"
        ],
        cwd=SITE,
        capture_output=True,
        text=True
    )

    tracked_sensitive = []

    for line in p.stdout.splitlines():

        low = line.lower()

        name = Path(line).name.lower()

        if (
            name == ".env"
            or name.startswith(".env.")
            or "tiktok_token" in low
            or "credentials" in low
            or "client_secret.json" in low
            or name.endswith(".pem")
            or name.endswith(".key")
        ):

            tracked_sensitive.append(line)


    # Recherche uniquement des secrets manifestement codés en dur.
    # Des expressions comme d.get("access_token") sont légitimes.
    suspicious = []

    patterns = [
        r'(?i)client_secret\s*=\s*["\'][A-Za-z0-9_\-]{20,}["\']',
        r'(?i)access_token\s*=\s*["\'][A-Za-z0-9_\-.*!]{30,}["\']',
        r'(?i)refresh_token\s*=\s*["\'][A-Za-z0-9_\-.*!]{30,}["\']',
    ]

    gp = subprocess.run(
        [
            "git",
            "grep",
            "-n",
            "-E",
            "client_secret|access_token|refresh_token"
        ],
        cwd=SITE,
        capture_output=True,
        text=True
    )

    import re

    for line in gp.stdout.splitlines():

        if any(
            re.search(pattern, line)
            for pattern in patterns
        ):
            suspicious.append(line)


    return {
        "ok":
            not tracked_sensitive
            and not suspicious,

        "tracked_sensitive":
            tracked_sensitive,

        "secret_matches":
            suspicious[:10]
    }


def json_file(path):

    try:

        return json.loads(
            path.read_text(
                encoding="utf8"
            )
        )

    except Exception:

        return {}


def main():

    tests = {}

    # ------------------------------------------------------
    # SERVICES
    # ------------------------------------------------------

    tests["bridge"] = api(
        "/health"
    )

    tests["queue_api"] = api(
        "/queue"
    )

    tests["schedule_api"] = api(
        "/schedule"
    )

    tests["autopilot_api"] = api(
        "/autopilot"
    )

    tests["diagnostics_api"] = api(
        "/diagnostics"
    )


    # ------------------------------------------------------
    # TOKENS
    # ------------------------------------------------------

    token_file = (
        HOME
        /
        "tiktok_token.json"
    )

    tests["token_file"] = {
        "exists":
            token_file.exists(),

        "private":
            (
                oct(
                    token_file.stat().st_mode
                    & 0o777
                )
                ==
                "0o600"
            )
            if token_file.exists()
            else False
    }


    # ------------------------------------------------------
    # GIT SECURITY
    # ------------------------------------------------------

    tests[
        "git_security"
    ] = check_git_secrets()


    # ------------------------------------------------------
    # THREE REAL VIDEOS
    # ------------------------------------------------------

    videos = []

    for path, fp in find_videos():

        info = ffprobe(
            path
        )

        videos.append(
            {
                "file":
                    str(path),

                "name":
                    path.name,

                "fingerprint":
                    fp,

                **info
            }
        )

    tests[
        "videos"
    ] = videos


    # ------------------------------------------------------
    # QUEUE / SCHEDULE CONSISTENCY
    # ------------------------------------------------------

    q = json_file(
        QUEUE
    )

    s = json_file(
        SCHEDULE
    )

    qitems = q.get(
        "items",
        []
    )

    sitems = s.get(
        "items",
        []
    )

    queue_ids = {
        x.get("id")
        for x in qitems
    }

    invalid_schedule = [
        x
        for x in sitems
        if x.get(
            "queue_id"
        )
        not in queue_ids
    ]

    fingerprints = [
        x.get(
            "fingerprint"
        )
        for x in qitems
        if x.get(
            "fingerprint"
        )
    ]

    duplicate_fingerprints = (
        len(
            fingerprints
        )
        !=
        len(
            set(
                fingerprints
            )
        )
    )

    tests[
        "queue_integrity"
    ] = {

        "queue_items":
            len(
                qitems
            ),

        "schedule_items":
            len(
                sitems
            ),

        "invalid_schedule":
            invalid_schedule,

        "duplicate_fingerprints":
            duplicate_fingerprints,

        "ok":
            (
                not invalid_schedule
                and
                not duplicate_fingerprints
            )
    }


    # ------------------------------------------------------
    # RESULT
    # ------------------------------------------------------

    critical = [

        tests[
            "bridge"
        ].get(
            "ok",
            False
        ),

        tests[
            "queue_api"
        ].get(
            "ok",
            False
        ),

        tests[
            "schedule_api"
        ].get(
            "ok",
            False
        ),

        tests[
            "git_security"
        ].get(
            "ok",
            False
        ),

        tests[
            "queue_integrity"
        ].get(
            "ok",
            False
        ),

        len(
            videos
        ) >= 3,

        all(
            v.get(
                "ok"
            )
            for v in videos
        )
        if videos
        else False
    ]

    passed = all(
        critical
    )

    report = {

        "timestamp":
            datetime.now()
            .isoformat(
                timespec="seconds"
            ),

        "status":
            (
                "PASS"
                if passed
                else "FAIL"
            ),

        "tests":
            tests
    }

    REPORT.parent.mkdir(
        parents=True,
        exist_ok=True
    )

    REPORT.write_text(
        json.dumps(
            report,
            indent=2,
            ensure_ascii=False
        ),
        encoding="utf8"
    )

    print()
    print("=" * 68)
    print(" CLIPFACTORY STABILITY GATE")
    print("=" * 68)

    print()

    print(
        "BRIDGE       :",
        "PASS"
        if tests["bridge"].get("ok")
        else "FAIL"
    )

    print(
        "QUEUE API    :",
        "PASS"
        if tests["queue_api"].get("ok")
        else "FAIL"
    )

    print(
        "SCHEDULE API :",
        "PASS"
        if tests["schedule_api"].get("ok")
        else "FAIL"
    )

    print(
        "GIT SECURITY :",
        "PASS"
        if tests["git_security"].get("ok")
        else "FAIL"
    )

    print(
        "QUEUE DATA   :",
        "PASS"
        if tests["queue_integrity"].get("ok")
        else "FAIL"
    )

    print()

    print(
        "REAL VIDEOS:",
        len(videos),
        "/ 3"
    )

    for i, video in enumerate(
        videos,
        1
    ):

        print()
        print(
            f"VIDEO {i}"
        )

        print(
            " ",
            video["name"]
        )

        print(
            " ",
            video.get("codec"),
            f'{video.get("width")}x{video.get("height")}',
            f'{video.get("duration")}s'
        )

        print(
            " ",
            "PASS"
            if video.get("ok")
            else "FAIL"
        )

    print()
    print("=" * 68)

    if passed:

        print(
            "✅ STABILITY GATE PASSED"
        )

        print(
            "ClipFactory is ready for controlled real-world testing."
        )

    else:

        print(
            "⚠️ STABILITY GATE FAILED"
        )

        print(
            "Do not add new features until failing checks are fixed."
        )

    print("=" * 68)

    print()
    print(
        "Report:",
        REPORT
    )


if __name__ == "__main__":
    main()
