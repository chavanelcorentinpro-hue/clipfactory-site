#!/usr/bin/env python3

import json
from pathlib import Path
from datetime import datetime

FILE = (
    Path.home()
    / ".clipfactory"
    / "autopilot.json"
)


def load():

    try:
        return json.loads(
            FILE.read_text(
                encoding="utf-8"
            )
        )

    except Exception:
        return {
            "enabled":False
        }


def save(enabled):

    data = {
        "enabled":
            bool(enabled),

        "updated_at":
            datetime.now().isoformat(
                timespec="seconds"
            )
    }

    FILE.parent.mkdir(
        parents=True,
        exist_ok=True
    )

    FILE.write_text(
        json.dumps(
            data,
            indent=2
        ),
        encoding="utf-8"
    )

    return data


if __name__ == "__main__":

    import sys

    if (
        len(sys.argv) > 1
        and sys.argv[1]
        in {"on","off"}
    ):

        print(
            json.dumps(
                save(
                    sys.argv[1]
                    == "on"
                ),
                indent=2
            )
        )

    else:

        print(
            json.dumps(
                load(),
                indent=2
            )
        )
