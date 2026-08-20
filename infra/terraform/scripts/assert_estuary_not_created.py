#!/usr/bin/env python3

import json
import sys


plan = json.load(sys.stdin)
estuary_changes = [
    change
    for change in plan.get("resource_changes", [])
    if change.get("address") == "ovh_vps.estuary"
]

if any("create" in change["change"]["actions"] for change in estuary_changes):
    raise SystemExit(
        "refusing to apply a plan that would order another estuary VPS; import the existing VPS into state"
    )
