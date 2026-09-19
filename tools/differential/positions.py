#!/usr/bin/env python3
"""Print `<path>:<line>:<col>:` for every `parse/` diagnostic in a
hefermotor `--json` document, one per line, as ponyc prints the head of
its error lines. A diagnostic located at a file rather than a span
(`parse/limit`) prints nothing. Line and column are 1-based and counted
in bytes, as ponyc counts them."""

import json
import sys


def main(path):
    with open(path, encoding="utf-8") as f:
        document = json.load(f)
    contents = {}
    for d in document["diagnostics"]:
        if not d["code"].startswith("parse/"):
            continue
        location = d["location"]
        if "start" not in location:
            continue
        file = location["file"]
        if file not in contents:
            with open(file, "rb") as f:
                contents[file] = f.read()
        head = contents[file][: location["start"]]
        line = head.count(b"\n") + 1
        col = location["start"] - (head.rfind(b"\n") + 1) + 1
        print(f"{file}:{line}:{col}:")


if __name__ == "__main__":
    main(sys.argv[1])
