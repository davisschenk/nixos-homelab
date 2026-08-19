#!/usr/bin/env python3

import json
import sys
from pathlib import Path


def fail(message: str) -> None:
    raise ValueError(message)


def validate(path: Path) -> None:
    entries = json.loads(path.read_text())
    if not isinstance(entries, list) or not entries:
        fail("ingress must be a non-empty JSON array")
    if len(entries) > 13:
        fail("ingress exceeds the OVH Edge Network Firewall rule limit")

    names: set[str] = set()
    for index, entry in enumerate(entries):
        if not isinstance(entry, dict):
            fail(f"entry {index} must be an object")
        if set(entry) != {"name", "protocol", "from", "to", "target"}:
            fail(f"entry {index} has an unexpected shape")
        if not isinstance(entry["name"], str) or not entry["name"]:
            fail(f"entry {index} has an invalid name")
        if entry["name"] in names:
            fail(f"duplicate ingress name: {entry['name']}")
        names.add(entry["name"])
        if entry["protocol"] not in {"tcp", "udp"}:
            fail(f"{entry['name']} has an invalid protocol")
        if entry["target"] != "mangrove":
            fail(f"{entry['name']} has an unknown target")
        if type(entry["from"]) is not int or type(entry["to"]) is not int:
            fail(f"{entry['name']} ports must be integers")
        if not 1 <= entry["from"] <= entry["to"] <= 65535:
            fail(f"{entry['name']} has an invalid port range")

    for index, left in enumerate(entries):
        for right in entries[index + 1 :]:
            overlaps = left["from"] <= right["to"] and right["from"] <= left["to"]
            if left["protocol"] == right["protocol"] and overlaps:
                fail(f"{left['name']} overlaps {right['name']}")


if __name__ == "__main__":
    try:
        validate(Path(sys.argv[1] if len(sys.argv) > 1 else "infra/ingress.json"))
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print(f"invalid ingress: {error}", file=sys.stderr)
        raise SystemExit(1)
