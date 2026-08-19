#!/usr/bin/env python3

import json
import hashlib
import subprocess
from pathlib import Path
from datetime import datetime

ROOT = Path.home() / "tiktok_factory"
RUNTIME = Path.home() / ".clipfactory"

QUEUE_FILE = RUNTIME / "queue.json"
REGISTRY_FILE = RUNTIME / "published_registry.json"

RUNTIME.mkdir(
    parents=True,
    exist_ok=True
)


def now():
    return datetime.now().isoformat(
        timespec="seconds"
    )


def load_json(path, default):
    try:
        return json.loads(
            path.read_text(
                encoding="utf-8"
            )
        )
    except Exception:
        return default


def save_json(path, data):
    path.write_text(
        json.dumps(
            data,
            indent=2,
            ensure_ascii=False
        ),
        encoding="utf-8"
    )


def fingerprint(path):

    h = hashlib.sha256()

    with open(path, "rb") as f:
        while True:
            chunk = f.read(
                1024 * 1024
            )

            if not chunk:
                break

            h.update(chunk)

    return h.hexdigest()


def published_fingerprints():

    data = load_json(
        REGISTRY_FILE,
        {}
    )

    return {
        x.get("fingerprint")
        for x in data.get(
            "published",
            []
        )
        if (
            x.get("result")
            == "success"
            and x.get("fingerprint")
        )
    }


def video_info(path):

    cmd = [
        "ffprobe",
        "-v",
        "error",

        "-select_streams",
        "v:0",

        "-show_entries",
        "stream=codec_name,width,height",

        "-show_entries",
        "format=duration,size",

        "-of",
        "json",

        str(path)
    ]

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30
        )

        data = json.loads(
            result.stdout
            or "{}"
        )

        streams = data.get(
            "streams",
            []
        )

        fmt = data.get(
            "format",
            {}
        )

        stream = (
            streams[0]
            if streams
            else {}
        )

        return {
            "codec":
                stream.get(
                    "codec_name"
                ),

            "width":
                int(
                    stream.get(
                        "width",
                        0
                    )
                    or 0
                ),

            "height":
                int(
                    stream.get(
                        "height",
                        0
                    )
                    or 0
                ),

            "duration":
                float(
                    fmt.get(
                        "duration",
                        0
                    )
                    or 0
                ),

            "size":
                int(
                    fmt.get(
                        "size",
                        0
                    )
                    or 0
                )
        }

    except Exception:

        return {
            "codec":None,
            "width":0,
            "height":0,
            "duration":0,
            "size":0
        }


def title_and_tags(path):

    project = (
        path.parent.parent.name
        if len(path.parents) >= 2
        else "ClipFactory"
    )

    title = (
        project
        .replace("_", " ")
        .replace("-", " ")
    )

    low = project.lower()

    if "travel" in low:

        tags = (
            "#travel #voyage "
            "#tiktok #clipfactory"
        )

    elif (
        "cinema" in low
        or "emotion" in low
    ):

        tags = (
            "#cinema #emotion "
            "#story #clipfactory"
        )

    elif (
        "karaoke" in low
        or "music" in low
    ):

        tags = (
            "#music #karaoke "
            "#tiktok #clipfactory"
        )

    else:

        tags = (
            "#tiktok #viral "
            "#video #clipfactory"
        )

    return title, tags


def discover():

    queue = load_json(
        QUEUE_FILE,
        {
            "items":[]
        }
    )

    existing = {
        x.get("fingerprint")
        for x in queue.get(
            "items",
            []
        )
    }

    published = (
        published_fingerprints()
    )

    names = {
        "joined.mp4",
        "final.mp4",
        "output.mp4",
        "result.mp4"
    }

    candidates = []

    if ROOT.exists():

        for path in ROOT.rglob("*.mp4"):

            if (
                path.name.lower()
                in names
            ):
                candidates.append(
                    path
                )

    candidates.sort(
        key=lambda x:
            x.stat().st_mtime,
        reverse=True
    )

    added = 0

    for path in candidates:

        fp = fingerprint(
            path
        )

        if fp in existing:
            continue

        if fp in published:
            continue

        info = video_info(
            path
        )

        title, hashtags = (
            title_and_tags(
                path
            )
        )

        queue[
            "items"
        ].append(
            {
                "id":
                    fp[:12],

                "file":
                    str(path),

                "fingerprint":
                    fp,

                "title":
                    title,

                "hashtags":
                    hashtags,

                "codec":
                    info["codec"],

                "width":
                    info["width"],

                "height":
                    info["height"],

                "duration":
                    info["duration"],

                "size":
                    info["size"],

                "state":
                    "PREPARED",

                "attempts":
                    0,

                "last_error":
                    None,

                "created_at":
                    now(),

                "updated_at":
                    now()
            }
        )

        existing.add(
            fp
        )

        added += 1

    save_json(
        QUEUE_FILE,
        queue
    )

    return added


def next_item():

    queue = load_json(
        QUEUE_FILE,
        {
            "items":[]
        }
    )

    priority = [
        "NEXT",
        "RETRY",
        "PREPARED"
    ]

    for state in priority:

        for item in queue.get(
            "items",
            []
        ):

            if item.get(
                "state"
            ) == state:

                return item

    return None


def mark(
    item_id,
    state,
    error=None
):

    queue = load_json(
        QUEUE_FILE,
        {
            "items":[]
        }
    )

    for item in queue.get(
        "items",
        []
    ):

        if item.get(
            "id"
        ) == item_id:

            item[
                "state"
            ] = state

            item[
                "updated_at"
            ] = now()

            if error is not None:

                item[
                    "last_error"
                ] = str(
                    error
                )

            if state == "SENDING":

                item[
                    "attempts"
                ] = (
                    int(
                        item.get(
                            "attempts",
                            0
                        )
                    )
                    + 1
                )

            break

    save_json(
        QUEUE_FILE,
        queue
    )


def retry_failed():

    queue = load_json(
        QUEUE_FILE,
        {
            "items":[]
        }
    )

    n = 0

    for item in queue.get(
        "items",
        []
    ):

        if item.get(
            "state"
        ) == "FAILED":

            item[
                "state"
            ] = "RETRY"

            item[
                "updated_at"
            ] = now()

            n += 1

    save_json(
        QUEUE_FILE,
        queue
    )

    return n


def summary():

    queue = load_json(
        QUEUE_FILE,
        {
            "items":[]
        }
    )

    counts = {}

    for item in queue.get(
        "items",
        []
    ):

        state = item.get(
            "state",
            "UNKNOWN"
        )

        counts[state] = (
            counts.get(
                state,
                0
            )
            + 1
        )

    items = queue.get(
        "items",
        []
    )

    # newest/relevant first
    ordered = sorted(
        items,
        key=lambda x: (
            {
                "NEXT":0,
                "RETRY":1,
                "PREPARED":2,
                "SENDING":3,
                "FAILED":4,
                "SENT":5
            }.get(
                x.get("state"),
                9
            ),
            x.get(
                "created_at",
                ""
            )
        )
    )

    return {
        "total":
            len(items),

        "counts":
            counts,

        "next":
            next_item(),

        "items":
            ordered[:30]
    }


if __name__ == "__main__":

    import sys

    command = (
        sys.argv[1]
        if len(sys.argv) > 1
        else "status"
    )

    if command == "discover":

        n = discover()

        print(
            json.dumps(
                {
                    "added":n,
                    **summary()
                },
                indent=2,
                ensure_ascii=False
            )
        )

    elif command == "retry":

        n = retry_failed()

        print(
            json.dumps(
                {
                    "retried":n,
                    **summary()
                },
                indent=2,
                ensure_ascii=False
            )
        )

    else:

        discover()

        print(
            json.dumps(
                summary(),
                indent=2,
                ensure_ascii=False
            )
        )
