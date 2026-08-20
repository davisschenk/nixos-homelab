#!/usr/bin/env python3

import hashlib
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request


ENDPOINTS = {
    "ovh-us": "https://api.us.ovhcloud.com/1.0",
    "ovh-eu": "https://eu.api.ovh.com/1.0",
}


def request(method: str, path: str, payload: object | None = None) -> object:
    endpoint = ENDPOINTS.get(os.environ.get("OVH_ENDPOINT", "ovh-us"))
    if endpoint is None:
        raise RuntimeError("OVH_ENDPOINT must be ovh-us or ovh-eu")

    url = f"{endpoint}{path}"
    body = "" if payload is None else json.dumps(payload, separators=(",", ":"))
    timestamp = str(int(time.time()))
    application_key = os.environ["OVH_APPLICATION_KEY"]
    application_secret = os.environ["OVH_APPLICATION_SECRET"]
    consumer_key = os.environ["OVH_CONSUMER_KEY"]
    signature_source = "+".join(
        [application_secret, consumer_key, method, url, body, timestamp]
    )
    signature = "$1$" + hashlib.sha1(signature_source.encode()).hexdigest()
    headers = {
        "Content-Type": "application/json",
        "X-Ovh-Application": application_key,
        "X-Ovh-Consumer": consumer_key,
        "X-Ovh-Signature": signature,
        "X-Ovh-Timestamp": timestamp,
    }
    raw_body = body.encode() if body else None
    api_request = urllib.request.Request(
        url, data=raw_body, headers=headers, method=method
    )
    try:
        with urllib.request.urlopen(api_request, timeout=30) as response:
            response_body = response.read()
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        raise RuntimeError(f"OVH API {method} {path} failed: {error.code} {detail}") from error
    return json.loads(response_body) if response_body else None


def wait_until_absent(path: str, sequences: set[int], timeout: int = 60) -> None:
    deadline = time.monotonic() + timeout
    while sequences & {int(sequence) for sequence in request("GET", path)}:
        if time.monotonic() >= deadline:
            raise RuntimeError(
                f"OVH firewall rules were not deleted within {timeout} seconds"
            )
        time.sleep(1)


def main() -> None:
    firewall_cidr = urllib.parse.quote(os.environ["OVH_FIREWALL_CIDR"], safe="")
    firewall_ip = urllib.parse.quote(os.environ["OVH_FIREWALL_IP"], safe="")
    rules = json.loads(os.environ["OVH_FIREWALL_RULES"])
    rules_path = f"/ip/{firewall_cidr}/firewall/{firewall_ip}/rule"
    deny_rule = next(rule for rule in rules if rule["action"] == "deny")

    deleted_sequences = set()
    for sequence in request("GET", rules_path):
        if sequence != deny_rule["sequence"]:
            request("DELETE", f"{rules_path}/{sequence}")
            deleted_sequences.add(sequence)
    wait_until_absent(rules_path, deleted_sequences)

    for rule in sorted(
        (rule for rule in rules if rule["action"] != "deny"),
        key=lambda item: item["sequence"],
    ):
        request("POST", rules_path, rule)

    existing = request("GET", rules_path)
    if deny_rule["sequence"] in existing:
        request("DELETE", f"{rules_path}/{deny_rule['sequence']}")
        wait_until_absent(rules_path, {deny_rule["sequence"]})
    request("POST", rules_path, deny_rule)


if __name__ == "__main__":
    main()
