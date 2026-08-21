#!/usr/bin/env python3

import argparse
import json
import os
import re
import stat
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

UUID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
    re.IGNORECASE,
)
NAME_RE = re.compile(r"^[a-z0-9_-]+$")
DOMAIN_RE = re.compile(r"^(?:\*\.)?[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$")


class ReconcileError(RuntimeError):
    pass


def read_json(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, json.JSONDecodeError) as exc:
        raise ReconcileError(f"cannot read {path}: {exc}") from exc


def read_secret(path, label):
    try:
        value = Path(path).read_text(encoding="utf-8").strip()
    except OSError as exc:
        raise ReconcileError(f"cannot read {label} file: {exc}") from exc
    if not value:
        raise ReconcileError(f"{label} file is empty")
    return value


def parse_environment_file(path):
    if not path:
        return {}
    try:
        content = Path(path).read_text(encoding="utf-8")
    except OSError as exc:
        raise ReconcileError(f"cannot read secret environment file: {exc}") from exc
    if content.lstrip().startswith("{"):
        try:
            values = json.loads(content)
        except json.JSONDecodeError as exc:
            raise ReconcileError(f"invalid secret environment JSON: {exc}") from exc
        if not isinstance(values, dict) or not all(
            isinstance(key, str) and isinstance(value, (str, int, float, bool))
            for key, value in values.items()
        ):
            raise ReconcileError("secret environment JSON must be a flat object")
        return {key: str(value) for key, value in values.items()}

    values = {}
    for line_number, raw_line in enumerate(content.splitlines(), 1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[7:].lstrip()
        if "=" not in line:
            raise ReconcileError(
                f"invalid secret environment line {line_number}: expected KEY=VALUE"
            )
        key, value = line.split("=", 1)
        key = key.strip()
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key):
            raise ReconcileError(
                f"invalid secret environment key on line {line_number}"
            )
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        values[key] = value
    return values


def validate_manifest(manifest):
    errors = []
    ingress = {entry.get("name"): entry for entry in manifest.get("ingress", [])}
    servers = manifest.get("servers", {})
    infrarust = manifest.get("infrarust", {})
    allocation_keys = set()
    domains = set()

    if not isinstance(servers, dict):
        errors.append("servers must be an object")
        servers = {}

    owner = manifest.get("default_owner", {})
    if bool(owner.get("email")) == bool(owner.get("external_id")):
        errors.append("default_owner must set exactly one of email or external_id")

    for name, server in servers.items():
        prefix = f"servers.{name}"
        if not NAME_RE.fullmatch(name):
            errors.append(f"{prefix}: name must match [a-z0-9_-]+")
        state_value = server.get("state")
        if state_value not in ("present", "absent"):
            errors.append(f"{prefix}.state must be present or absent")
            continue

        for field in ("adopt_uuid", "delete_confirmation_uuid"):
            value = server.get(field)
            if value and not UUID_RE.fullmatch(value):
                errors.append(f"{prefix}.{field} is not a UUID")

        if state_value == "absent":
            if not server.get("delete_confirmation_uuid"):
                errors.append(
                    f"{prefix}: absent servers require delete_confirmation_uuid"
                )
            continue

        if not UUID_RE.fullmatch(server.get("egg_uuid", "")):
            errors.append(f"{prefix}.egg_uuid is required and must be a UUID")

        server_owner = server.get("owner") or owner
        if bool(server_owner.get("email")) == bool(server_owner.get("external_id")):
            errors.append(
                f"{prefix}.owner must resolve to exactly one of email or external_id"
            )

        allocations = server.get("allocations", {})
        primary_names = [
            alloc_name
            for alloc_name, allocation in allocations.items()
            if allocation.get("primary")
        ]
        if len(primary_names) != 1:
            errors.append(f"{prefix} must have exactly one primary allocation")

        for allocation_name, allocation in allocations.items():
            allocation_prefix = f"{prefix}.allocations.{allocation_name}"
            ip = allocation.get("ip")
            port = allocation.get("port")
            if not isinstance(port, int) or isinstance(port, bool) or not 1 <= port <= 65535:
                errors.append(f"{allocation_prefix}.port must be between 1 and 65535")
                continue
            key = (ip, port)
            if key in allocation_keys:
                errors.append(f"{allocation_prefix}: duplicate allocation {ip}:{port}")
            allocation_keys.add(key)

        for exposure in server.get("exposures", []):
            allocation_name = exposure.get("allocation")
            allocation = allocations.get(allocation_name)
            gate = ingress.get(exposure.get("ingress"))
            if allocation is None:
                errors.append(
                    f"{prefix}: exposure references unknown allocation {allocation_name}"
                )
                continue
            if gate is None:
                errors.append(
                    f"{prefix}: exposure references unknown ingress {exposure.get('ingress')}"
                )
                continue
            port = allocation.get("port", 0)
            if (
                gate.get("target") != "mangrove"
                or gate.get("protocol") != exposure.get("protocol")
                or not gate.get("from", 0) <= port <= gate.get("to", -1)
            ):
                errors.append(
                    f"{prefix}: {exposure.get('ingress')} does not cover "
                    f"{exposure.get('protocol')}/{port} on mangrove"
                )

        route = server.get("minecraft", {}).get("infrarust", {})
        if route.get("enable"):
            if not infrarust.get("enable"):
                errors.append(f"{prefix}: Infrarust routing requires infrarust.enable")
            for allocation in allocations.values():
                if allocation.get("ip") != "127.0.0.1":
                    errors.append(
                        f"{prefix}: Infrarust backend allocations must bind 127.0.0.1"
                    )
            suffix = infrarust.get("domain_suffix", "").lower()
            for domain in route.get("domains", []):
                normalized = domain.lower()
                if (
                    not DOMAIN_RE.fullmatch(normalized)
                    or normalized == suffix
                    or not normalized.endswith(f".{suffix}")
                ):
                    errors.append(
                        f"{prefix}: Infrarust domain {domain!r} is not below {suffix}"
                    )
                if normalized in domains:
                    errors.append(f"{prefix}: duplicate Infrarust domain {domain!r}")
                domains.add(normalized)

    if infrarust.get("enable"):
        gate = ingress.get(infrarust.get("public_ingress"))
        port = infrarust.get("listen_port")
        if (
            gate is None
            or gate.get("target") != "mangrove"
            or gate.get("protocol") != "tcp"
            or not gate.get("from", 0) <= port <= gate.get("to", -1)
        ):
            errors.append(
                "Infrarust listener is not covered by its declared TCP ingress gate"
            )
        if any(
            allocation.get("ip") == "0.0.0.0"
            and allocation.get("port") == port
            for server in servers.values()
            if server.get("state") == "present"
            for allocation in server.get("allocations", {}).values()
        ):
            errors.append("an all-interface Pelican allocation conflicts with Infrarust")

    if errors:
        raise ReconcileError("manifest validation failed:\n- " + "\n- ".join(errors))


def attributes(item):
    if not isinstance(item, dict):
        return {}
    return item.get("attributes", item)


def relationship_items(item, name):
    relationship = item.get("relationships", {}).get(name, {})
    data = relationship.get("data", [])
    if data is None:
        return []
    if isinstance(data, list):
        return data
    return [data]


class ApiClient:
    def __init__(self, panel_url, panel_host, token, api_kind="application", timeout=15):
        self.base_url = panel_url.rstrip("/") + f"/api/{api_kind}"
        self.panel_host = panel_host
        self.token = token
        self.timeout = timeout

    def request(self, method, path, query=None, payload=None, retry_read=True):
        url = self.base_url + path
        if query:
            url += "?" + urllib.parse.urlencode(query, doseq=True)
        body = None if payload is None else json.dumps(payload).encode("utf-8")
        headers = {
            "Accept": "Application/vnd.pterodactyl.v1+json",
            "Authorization": f"Bearer {self.token}",
            "Host": self.panel_host,
        }
        if body is not None:
            headers["Content-Type"] = "application/json"

        attempts = 5 if method == "GET" and retry_read else 1
        last_error = None
        for attempt in range(attempts):
            request = urllib.request.Request(url, body, headers, method=method)
            try:
                with urllib.request.urlopen(request, timeout=self.timeout) as response:
                    content = response.read()
                    return json.loads(content) if content else None
            except urllib.error.HTTPError as exc:
                if exc.code >= 500 and attempt + 1 < attempts:
                    last_error = exc
                    time.sleep(min(2**attempt, 5))
                    continue
                try:
                    response = json.loads(exc.read().decode("utf-8"))
                    messages = [
                        error.get("code") or "API error"
                        for error in response.get("errors", [])[:3]
                    ]
                except (UnicodeDecodeError, json.JSONDecodeError):
                    messages = []
                detail = "; ".join(messages) if messages else "request rejected"
                raise ReconcileError(
                    f"Pelican {method} {path} failed with HTTP {exc.code}: {detail}"
                ) from exc
            except urllib.error.URLError as exc:
                last_error = exc
                if attempt + 1 < attempts:
                    time.sleep(min(2**attempt, 5))
                    continue
                break
        raise ReconcileError(f"Pelican {method} {path} failed: {last_error}")

    def paginate(self, path, query=None):
        page = 1
        result = []
        while True:
            page_query = dict(query or {})
            page_query.update({"page": page, "per_page": 100})
            response = self.request("GET", path, page_query)
            result.extend(response.get("data", []))
            pagination = response.get("meta", {}).get("pagination", {})
            total_pages = pagination.get("total_pages", page)
            if page >= total_pages:
                return result
            page += 1


class Reconciler:
    def __init__(self, manifest, apply=False):
        self.manifest = manifest
        self.apply = apply
        self.actions = []
        self.application = None
        self.client = None
        self.node = None
        self.eggs = {}
        self.users = []
        self.servers = []
        self.allocations = []

    def action(self, resource, name, fields=None):
        suffix = f" ({', '.join(fields)})" if fields else ""
        self.actions.append(f"{resource} {name}{suffix}")

    def connect(self):
        app_key = read_secret(
            self.manifest["application_api_key_file"], "Application API key"
        )
        self.application = ApiClient(
            self.manifest["panel_url"],
            self.manifest["panel_host"],
            app_key,
        )
        client_path = self.manifest.get("client_api_key_file")
        if client_path:
            client_key = read_secret(client_path, "Client API key")
            self.client = ApiClient(
                self.manifest["panel_url"],
                self.manifest["panel_host"],
                client_key,
                api_kind="client",
            )

    def refresh(self):
        nodes = self.application.paginate("/nodes")
        matching_nodes = [
            item
            for item in nodes
            if attributes(item).get("uuid") == self.manifest["node_uuid"]
        ]
        if len(matching_nodes) != 1:
            raise ReconcileError(
                f"expected one Pelican node with UUID {self.manifest['node_uuid']}"
            )
        self.node = attributes(matching_nodes[0])
        self.users = self.application.paginate("/users")
        egg_response = self.application.paginate("/eggs")
        self.eggs = {
            attributes(item).get("uuid"): attributes(item)
            for item in egg_response
        }
        self.servers = self.application.paginate(
            "/servers", {"include": "allocations"}
        )
        self.allocations = self.application.paginate(
            f"/nodes/{self.node['id']}/allocations", {"include": "server"}
        )

    def resolve_owner(self, selector):
        field = "email" if selector.get("email") else "external_id"
        value = selector[field]
        matches = [item for item in self.users if attributes(item).get(field) == value]
        if len(matches) != 1:
            raise ReconcileError(f"expected one Pelican user with {field}={value!r}")
        return attributes(matches[0])

    def find_server(self, name):
        external_id = f"nix:{name}"
        matches = [
            item
            for item in self.servers
            if attributes(item).get("external_id") == external_id
        ]
        if len(matches) > 1:
            raise ReconcileError(f"multiple Pelican servers use {external_id}")
        return matches[0] if matches else None

    def find_adoption(self, uuid):
        matches = [
            item for item in self.servers if attributes(item).get("uuid") == uuid
        ]
        if len(matches) != 1:
            raise ReconcileError(f"expected one Pelican server with UUID {uuid}")
        return matches[0]

    def allocation_owner(self, allocation_item):
        servers = relationship_items(allocation_item, "server")
        return attributes(servers[0]).get("id") if servers else None

    def ensure_allocations(self, name, desired, current_server_id=None):
        resolved = {}
        for allocation_name, spec in desired.items():
            matches = [
                item
                for item in self.allocations
                if attributes(item).get("ip") == spec["ip"]
                and attributes(item).get("port") == spec["port"]
            ]
            if len(matches) > 1:
                raise ReconcileError(
                    f"multiple allocations exist for {spec['ip']}:{spec['port']}"
                )
            if not matches:
                self.action("create allocation", f"{spec['ip']}:{spec['port']}")
                if not self.apply:
                    continue
                self.application.request(
                    "POST",
                    f"/nodes/{self.node['id']}/allocations",
                    payload={"ip": spec["ip"], "ports": [str(spec["port"])]},
                )
                self.allocations = self.application.paginate(
                    f"/nodes/{self.node['id']}/allocations", {"include": "server"}
                )
                matches = [
                    item
                    for item in self.allocations
                    if attributes(item).get("ip") == spec["ip"]
                    and attributes(item).get("port") == spec["port"]
                ]
            if not matches:
                continue
            allocation = matches[0]
            owner = self.allocation_owner(allocation)
            if owner is not None and owner != current_server_id:
                raise ReconcileError(
                    f"allocation {spec['ip']}:{spec['port']} belongs to another server"
                )
            resolved[allocation_name] = attributes(allocation)
        return resolved

    def desired_environment(self, spec, current=None):
        declared = {
            key: str(value) for key, value in spec.get("environment", {}).items()
        }
        declared.update(parse_environment_file(spec.get("secret_environment_file")))
        merged = dict(current or {})
        merged.update(declared)
        return merged, set(declared)

    def create_server(self, name, spec, owner, egg, allocations):
        primary = next(
            allocations[key]
            for key, allocation in spec["allocations"].items()
            if allocation["primary"]
        )
        additional = [
            allocations[key]["id"]
            for key, allocation in spec["allocations"].items()
            if not allocation["primary"]
        ]
        environment, _ = self.desired_environment(spec)
        payload = {
            "external_id": f"nix:{name}",
            "name": spec["display_name"],
            "description": spec["description"],
            "user": owner["id"],
            "egg": egg["id"],
            "environment": environment,
            "limits": spec["limits"],
            "feature_limits": spec["feature_limits"],
            "allocation": {
                "default": primary["id"],
                "additional": additional,
            },
            "skip_scripts": False,
            "start_on_completion": False,
            "oom_killer": spec["oom_killer"],
        }
        if spec.get("image") is not None:
            payload["docker_image"] = spec["image"]
        if spec.get("startup") is not None:
            payload["startup"] = spec["startup"]
        self.application.request("POST", "/servers", payload=payload)

    def reconcile_present(self, name, spec):
        owner = self.resolve_owner(spec.get("owner") or self.manifest["default_owner"])
        egg = self.eggs.get(spec["egg_uuid"])
        if egg is None:
            raise ReconcileError(f"Pelican egg {spec['egg_uuid']} does not exist")

        server_item = self.find_server(name)
        adopting = False
        if server_item is None and spec.get("adopt_uuid"):
            server_item = self.find_adoption(spec["adopt_uuid"])
            adopting = True
            actual = attributes(server_item)
            if actual.get("external_id") not in (None, "", f"nix:{name}"):
                raise ReconcileError(
                    f"server {spec['adopt_uuid']} already has external ID "
                    f"{actual.get('external_id')!r}"
                )
            if actual.get("node") != self.node["id"]:
                raise ReconcileError("adopted server is assigned to another node")

        server_id = attributes(server_item).get("id") if server_item else None
        allocations = self.ensure_allocations(name, spec["allocations"], server_id)
        if not self.apply and len(allocations) != len(spec["allocations"]):
            allocations = {}

        if server_item is None:
            self.action("create server", name)
            if self.apply:
                self.create_server(name, spec, owner, egg, allocations)
            return

        actual = attributes(server_item)
        if adopting:
            self.action("adopt server", name, ["external_id"])

        detail_fields = []
        if actual.get("external_id") != f"nix:{name}":
            detail_fields.append("external_id")
        if actual.get("name") != spec["display_name"]:
            detail_fields.append("name")
        if (actual.get("description") or "") != spec["description"]:
            detail_fields.append("description")
        if actual.get("user") != owner["id"]:
            detail_fields.append("owner")
        if detail_fields:
            if not adopting:
                self.action("update server details", name, detail_fields)
            if self.apply:
                self.application.request(
                    "PATCH",
                    f"/servers/{actual['id']}/details",
                    payload={
                        "external_id": f"nix:{name}",
                        "name": spec["display_name"],
                        "description": spec["description"],
                        "user": owner["id"],
                    },
                )

        current_allocation_ids = {
            attributes(item).get("id")
            for item in relationship_items(server_item, "allocations")
        }
        current_allocation_ids.add(actual.get("allocation"))
        current_allocation_ids.discard(None)
        desired_ids = {allocation["id"] for allocation in allocations.values()}
        primary_id = next(
            allocations[key]["id"]
            for key, allocation in spec["allocations"].items()
            if allocation["primary"]
        ) if allocations else actual.get("allocation")

        build_fields = []
        if actual.get("allocation") != primary_id:
            build_fields.append("primary allocation")
        if current_allocation_ids != desired_ids and allocations:
            build_fields.append("additional allocations")
        if actual.get("limits", {}) != spec["limits"]:
            build_fields.append("limits")
        if actual.get("feature_limits", {}) != spec["feature_limits"]:
            build_fields.append("feature limits")
        if actual.get("oom_killer") != spec["oom_killer"]:
            build_fields.append("OOM killer")
        if build_fields:
            self.action("update server build", name, build_fields)
            if self.apply:
                self.application.request(
                    "PATCH",
                    f"/servers/{actual['id']}/build",
                    payload={
                        "allocation": primary_id,
                        "oom_killer": spec["oom_killer"],
                        "limits": spec["limits"],
                        "feature_limits": spec["feature_limits"],
                        "add_allocations": sorted(desired_ids - current_allocation_ids),
                        "remove_allocations": sorted(current_allocation_ids - desired_ids),
                    },
                )

        container = actual.get("container", {})
        environment, managed_keys = self.desired_environment(
            spec, container.get("environment", {})
        )
        startup_fields = []
        if actual.get("egg") != egg["id"]:
            startup_fields.append("egg")
        if spec.get("image") is not None and container.get("image") != spec["image"]:
            startup_fields.append("image")
        if (
            spec.get("startup") is not None
            and container.get("startup_command") != spec["startup"]
        ):
            startup_fields.append("startup")
        if any(
            str(container.get("environment", {}).get(key)) != environment[key]
            for key in managed_keys
        ):
            startup_fields.append("environment")
        if startup_fields:
            self.action("update server startup", name, startup_fields)
            self.action("operator action required", name, ["restart or reinstall"])
            if self.apply:
                payload = {
                    "egg": egg["id"],
                    "environment": environment,
                }
                if spec.get("image") is not None:
                    payload["image"] = spec["image"]
                if spec.get("startup") is not None:
                    payload["startup"] = spec["startup"]
                # skip_scripts=True keeps this patch from silently triggering
                # a reinstall on its own. Pelican persists the flag on the
                # server rather than scoping it to this request, so clear it
                # again immediately -- otherwise a later operator-initiated
                # "Reinstall Server" click in the panel would silently no-op.
                self.application.request(
                    "PATCH",
                    f"/servers/{actual['id']}/startup",
                    payload={**payload, "skip_scripts": True},
                )
                self.application.request(
                    "PATCH",
                    f"/servers/{actual['id']}/startup",
                    payload={**payload, "skip_scripts": False},
                )

    def check_backup(self):
        marker = Path(self.manifest["backup_marker"])
        try:
            age = time.time() - marker.stat().st_mtime
        except OSError as exc:
            raise ReconcileError(f"backup success marker is unavailable: {exc}") from exc
        if age < -300 or age > self.manifest["backup_max_age_seconds"]:
            raise ReconcileError(
                f"last successful persist backup is {int(age / 3600)} hours old"
            )

    def reconcile_absent(self, name, spec):
        server_item = self.find_server(name)
        if server_item is None:
            return
        actual = attributes(server_item)
        if actual.get("uuid") != spec.get("delete_confirmation_uuid"):
            raise ReconcileError(f"delete confirmation UUID does not match servers.{name}")
        if self.client is None:
            raise ReconcileError("guarded deletion requires a Client API key")
        self.check_backup()
        resources = self.client.request(
            "GET", f"/servers/{actual['uuid']}/resources", retry_read=False
        )
        state_value = attributes(resources.get("data", resources)).get("current_state")
        if state_value not in ("offline", "stopped"):
            raise ReconcileError(
                f"refusing to delete servers.{name} while state is {state_value!r}"
            )
        allocation_ids = {
            attributes(item).get("id")
            for item in relationship_items(server_item, "allocations")
        }
        allocation_ids.add(actual.get("allocation"))
        allocation_ids.discard(None)
        self.action("delete server", name)
        if not self.apply:
            return
        self.application.request("DELETE", f"/servers/{actual['id']}")
        remaining = self.application.paginate(
            f"/nodes/{self.node['id']}/allocations", {"include": "server"}
        )
        for item in remaining:
            allocation = attributes(item)
            if allocation.get("id") in allocation_ids and not allocation.get("assigned"):
                self.application.request(
                    "DELETE",
                    f"/nodes/{self.node['id']}/allocations/{allocation['id']}",
                )
                self.action(
                    "delete allocation", f"{allocation['ip']}:{allocation['port']}"
                )

    def write_state(self):
        state_path = Path(self.manifest["state_file"])
        state_path.parent.mkdir(mode=0o750, parents=True, exist_ok=True)
        managed = {}
        for name in self.manifest["servers"]:
            item = self.find_server(name)
            if item:
                actual = attributes(item)
                managed[name] = {
                    "uuid": actual.get("uuid"),
                    "identifier": actual.get("identifier"),
                }
        temporary = state_path.with_suffix(".tmp")
        temporary.write_text(json.dumps(managed, sort_keys=True) + "\n", encoding="utf-8")
        os.chmod(temporary, 0o640)
        os.replace(temporary, state_path)

    def run(self):
        self.connect()
        self.refresh()
        for name, spec in sorted(self.manifest["servers"].items()):
            if spec["state"] == "present":
                self.reconcile_present(name, spec)
            else:
                self.reconcile_absent(name, spec)
            if self.apply:
                self.refresh()
        if self.apply:
            self.write_state()
        return self.actions


def toml_string(value):
    return json.dumps(value, ensure_ascii=True)


def toml_array(values):
    return "[" + ", ".join(toml_string(value) for value in values) + "]"


def render_infrarust(manifest):
    infrarust = manifest["infrarust"]
    if not infrarust.get("enable"):
        raise ReconcileError("Infrarust is disabled")
    admin_key = read_secret(infrarust["admin_api_key_file"], "Infrarust API key")
    if len(admin_key) < 16:
        raise ReconcileError("Infrarust API key must contain at least 16 characters")
    client_key = None
    if any(
        spec.get("minecraft", {}).get("infrarust", {}).get("wake_on_connect")
        for spec in manifest["servers"].values()
        if spec.get("state") == "present"
    ):
        client_key = read_secret(
            manifest["client_api_key_file"], "Pelican Client API key"
        )

    runtime_dir = Path(infrarust["runtime_dir"])
    servers_dir = runtime_dir / "servers"
    servers_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    for existing in servers_dir.glob("*.toml"):
        existing.unlink()

    global_lines = [
        f"bind = {toml_string(infrarust['listen_address'] + ':' + str(infrarust['listen_port']))}",
        f"servers_dir = {toml_string(str(servers_dir))}",
        f"plugins_dir = {toml_string(infrarust['plugins_dir'])}",
        "unknown_domain_behavior = \"drop\"",
        "",
        "[ban]",
        f"file = {toml_string(infrarust['ban_file'])}",
        'purge_interval = "5m"',
        "enable_audit_log = true",
        "",
        "[web]",
        "enable_api = true",
        "enable_webui = true",
        f"bind = {toml_string(infrarust['admin_address'] + ':' + str(infrarust['admin_port']))}",
        f"api_key = {toml_string(admin_key)}",
        f"cors_origins = {toml_array([infrarust['external_url']])}",
        "",
        "[web.rate_limit]",
        "requests_per_minute = 60",
    ]
    config_path = runtime_dir / "infrarust.toml"
    config_path.write_text("\n".join(global_lines) + "\n", encoding="utf-8")
    os.chmod(config_path, stat.S_IRUSR)

    state = {}
    state_file = Path(manifest["state_file"])
    if state_file.exists():
        state = read_json(state_file)

    for name, spec in sorted(manifest["servers"].items()):
        route = spec.get("minecraft", {}).get("infrarust", {})
        if spec.get("state") != "present" or not route.get("enable"):
            continue
        primary_name = next(
            allocation_name
            for allocation_name, allocation in spec["allocations"].items()
            if allocation["primary"]
        )
        primary = spec["allocations"][primary_name]
        lines = [
            f"name = {toml_string(name)}",
            f"domains = {toml_array(route['domains'])}",
            f"addresses = {toml_array([primary['ip'] + ':' + str(primary['port'])])}",
            f"proxy_mode = {toml_string(route['proxy_mode'])}",
            f"send_proxy_protocol = {'true' if route['send_proxy_protocol'] else 'false'}",
        ]
        if route.get("wake_on_connect"):
            identity = state.get(name, {})
            server_id = identity.get("uuid") or spec.get("adopt_uuid")
            if not server_id:
                raise ReconcileError(
                    f"servers.{name} needs a reconciled UUID before wake-on-connect"
                )
            lines.extend(
                [
                    "",
                    "[server_manager]",
                    'type = "pterodactyl"',
                    f"api_url = {toml_string(manifest['public_panel_url'])}",
                    f"api_key = {toml_string(client_key)}",
                    f"server_id = {toml_string(server_id)}",
                    f"start_timeout = {toml_string(route['start_timeout'])}",
                    f"poll_interval = {toml_string(route['poll_interval'])}",
                ]
            )
            if route.get("shutdown_after"):
                lines.append(
                    f"shutdown_after = {toml_string(route['shutdown_after'])}"
                )
        server_path = servers_dir / f"{name}.toml"
        server_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        os.chmod(server_path, stat.S_IRUSR)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Reconcile Nix-defined Pelican servers")
    parser.add_argument("--manifest", required=True)
    subcommands = parser.add_subparsers(dest="command", required=True)
    subcommands.add_parser("check")
    subcommands.add_parser("plan")
    subcommands.add_parser("apply")
    subcommands.add_parser("render-infrarust")
    args = parser.parse_args(argv)

    try:
        manifest = read_json(args.manifest)
        validate_manifest(manifest)
        if args.command == "check":
            print("manifest is valid")
            return 0
        if args.command == "render-infrarust":
            render_infrarust(manifest)
            return 0
        reconciler = Reconciler(manifest, apply=args.command == "apply")
        actions = reconciler.run()
        if not actions:
            print("no changes")
        else:
            for action in actions:
                print(action)
        return 0
    except ReconcileError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
