#!/usr/bin/env python3

import json
from pathlib import Path
from datetime import datetime, timedelta, time

RUNTIME = Path.home() / ".clipfactory"
QUEUE_FILE = RUNTIME / "queue.json"
SCHEDULE_FILE = RUNTIME / "schedule.json"

# 3 créneaux de départ.
POSTING_SLOTS = [
    (12, 0),
    (18, 0),
    (21, 0),
]


def now():
    return datetime.now()


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


def next_times(count):

    current = now()

    result = []

    day = current.date()

    while len(result) < count:

        for hour, minute in POSTING_SLOTS:

            dt = datetime.combine(
                day,
                time(
                    hour=hour,
                    minute=minute
                )
            )

            if dt <= current:
                continue

            result.append(
                dt
            )

            if len(result) >= count:
                break

        day += timedelta(
            days=1
        )

    return result


def build():

    queue = load_json(
        QUEUE_FILE,
        {
            "items":[]
        }
    )

    schedule = load_json(
        SCHEDULE_FILE,
        {
            "items":[]
        }
    )

    scheduled_ids = {
        x.get("queue_id")
        for x in schedule.get(
            "items",
            []
        )
    }

    waiting = [
        x
        for x in queue.get(
            "items",
            []
        )
        if (
            x.get("state")
            in {
                "PREPARED",
                "RETRY"
            }
            and
            x.get("id")
            not in scheduled_ids
        )
    ]

    times = next_times(
        len(waiting)
    )

    for item, dt in zip(
        waiting,
        times
    ):

        schedule[
            "items"
        ].append(
            {
                "queue_id":
                    item["id"],

                "file":
                    item["file"],

                "title":
                    item.get(
                        "title",
                        ""
                    ),

                "hashtags":
                    item.get(
                        "hashtags",
                        ""
                    ),

                "scheduled_at":
                    dt.isoformat(
                        timespec="minutes"
                    ),

                "state":
                    "SCHEDULED",

                "created_at":
                    now().isoformat(
                        timespec="seconds"
                    )
            }
        )

    save_json(
        SCHEDULE_FILE,
        schedule
    )

    return schedule


def refresh():

    schedule = build()

    current = now()

    for item in schedule.get(
        "items",
        []
    ):

        if item.get(
            "state"
        ) != "SCHEDULED":
            continue

        try:

            scheduled = (
                datetime.fromisoformat(
                    item["scheduled_at"]
                )
            )

        except Exception:
            continue

        if scheduled <= current:

            item["state"] = "DUE"

    save_json(
        SCHEDULE_FILE,
        schedule
    )

    return schedule


def due():

    schedule = refresh()

    candidates = [
        x
        for x in schedule.get(
            "items",
            []
        )
        if x.get(
            "state"
        ) == "DUE"
    ]

    candidates.sort(
        key=lambda x:
            x.get(
                "scheduled_at",
                ""
            )
    )

    return (
        candidates[0]
        if candidates
        else None
    )


def mark(
    queue_id,
    state
):

    schedule = load_json(
        SCHEDULE_FILE,
        {
            "items":[]
        }
    )

    for item in schedule.get(
        "items",
        []
    ):

        if (
            item.get(
                "queue_id"
            )
            ==
            queue_id
        ):

            item[
                "state"
            ] = state

            item[
                "updated_at"
            ] = (
                now()
                .isoformat(
                    timespec="seconds"
                )
            )

            break

    save_json(
        SCHEDULE_FILE,
        schedule
    )


def summary():

    schedule = refresh()

    counts = {}

    for item in schedule.get(
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

    ordered = sorted(
        schedule.get(
            "items",
            []
        ),
        key=lambda x:
            x.get(
                "scheduled_at",
                ""
            )
    )

    return {
        "counts":
            counts,

        "due":
            due(),

        "items":
            ordered[:30]
    }


if __name__ == "__main__":

    print(
        json.dumps(
            summary(),
            indent=2,
            ensure_ascii=False
        )
    )
