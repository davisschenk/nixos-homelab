#!/usr/bin/env python3

import importlib.util
import io
import json
import os
import tempfile
import time
import unittest
import urllib.error
from pathlib import Path
from unittest import mock

MODULE_PATH = Path(os.environ.get("RECONCILER_PATH", Path(__file__).with_name("reconciler.py")))
SPEC = importlib.util.spec_from_file_location("pelican_reconciler", MODULE_PATH)
reconciler = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(reconciler)


NODE_UUID = "32011034-c138-4c4f-88be-d7c478faa405"
EGG_UUID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
SERVER_UUID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"


def manifest():
    return {
        "panel_url": "http://127.0.0.1:8000",
        "panel_host": "panel.example.test",
        "public_panel_url": "https://panel.example.test",
        "node_uuid": NODE_UUID,
        "default_owner": {"email": "owner@example.test", "external_id": None},
        "application_api_key_file": "/not-used",
        "client_api_key_file": None,
        "backup_marker": "/not-used",
        "backup_max_age_seconds": 129600,
        "state_file": "/not-used",
        "ingress": [
            {
                "name": "games-tcp",
                "protocol": "tcp",
                "from": 25565,
                "to": 25575,
                "target": "mangrove",
            },
            {
                "name": "games-udp",
                "protocol": "udp",
                "from": 25565,
                "to": 25575,
                "target": "mangrove",
            },
        ],
        "infrarust": {
            "enable": True,
            "public_ingress": "games-tcp",
            "domain_suffix": "mc.example.test",
            "listen_address": "0.0.0.0",
            "listen_port": 25565,
            "admin_address": "127.0.0.1",
            "admin_port": 8084,
            "admin_api_key_file": "/not-used",
            "external_url": "https://infrarust.example.test",
            "runtime_dir": "/not-used",
            "plugins_dir": "/not-used/plugins",
            "ban_file": "/not-used/bans.json",
        },
        "servers": {
            "survival": {
                "state": "present",
                "adopt_uuid": None,
                "delete_confirmation_uuid": None,
                "display_name": "Survival",
                "description": "",
                "owner": None,
                "egg_uuid": EGG_UUID,
                "image": "example/java:21",
                "startup": "java -jar server.jar",
                "environment": {"VERSION": "1.21"},
                "secret_environment_file": None,
                "limits": {
                    "memory": 4096,
                    "swap": 0,
                    "disk": 10240,
                    "io": 500,
                    "cpu": 200,
                    "threads": None,
                },
                "feature_limits": {
                    "databases": 0,
                    "allocations": 0,
                    "backups": 1,
                },
                "oom_killer": True,
                "allocations": {
                    "primary": {"ip": "127.0.0.1", "port": 25566, "primary": True}
                },
                "exposures": [],
                "minecraft": {
                    "infrarust": {
                        "enable": True,
                        "domains": ["survival.mc.example.test"],
                        "proxy_mode": "passthrough",
                        "send_proxy_protocol": False,
                        "wake_on_connect": False,
                        "start_timeout": "180s",
                        "poll_interval": "5s",
                        "shutdown_after": None,
                    }
                },
            }
        },
    }


def item(kind, values, relationships=None):
    result = {"object": kind, "attributes": values}
    if relationships:
        result["relationships"] = relationships
    return result


class FakeApplication:
    def __init__(self):
        self.nodes = [item("node", {"id": 1, "uuid": NODE_UUID})]
        self.users = [item("user", {"id": 2, "email": "owner@example.test"})]
        self.eggs = [item("egg", {"id": 3, "uuid": EGG_UUID})]
        self.servers = []
        self.allocations = []
        self.calls = []

    def paginate(self, path, query=None):
        if path == "/nodes":
            return self.nodes
        if path == "/users":
            return self.users
        if path == "/eggs":
            return self.eggs
        if path == "/servers":
            return self.servers
        if path.endswith("/allocations"):
            return self.allocations
        raise AssertionError(path)

    def request(self, method, path, query=None, payload=None, retry_read=True):
        self.calls.append((method, path, payload))
        if method == "POST" and path.endswith("/allocations"):
            allocation_id = len(self.allocations) + 10
            self.allocations.append(
                item(
                    "allocation",
                    {
                        "id": allocation_id,
                        "ip": payload["ip"],
                        "port": int(payload["ports"][0]),
                        "assigned": False,
                    },
                )
            )
            return None
        if method == "POST" and path == "/servers":
            allocation_id = payload["allocation"]["default"]
            allocation = next(
                value
                for value in self.allocations
                if reconciler.attributes(value)["id"] == allocation_id
            )
            reconciler.attributes(allocation)["assigned"] = True
            server_values = {
                "id": 20,
                "uuid": SERVER_UUID,
                "identifier": "bbbbbbbb",
                "external_id": payload["external_id"],
                "name": payload["name"],
                "description": payload["description"],
                "user": payload["user"],
                "node": 1,
                "allocation": allocation_id,
                "egg": payload["egg"],
                "oom_killer": payload["oom_killer"],
                "limits": payload["limits"],
                "feature_limits": payload["feature_limits"],
                "container": {
                    "image": payload["docker_image"],
                    "startup_command": payload["startup"],
                    "environment": payload["environment"],
                },
            }
            self.servers.append(
                item(
                    "server",
                    server_values,
                    {"allocations": {"data": [allocation]}},
                )
            )
            return {"data": self.servers[-1]}
        if method == "PATCH":
            return {"data": {}}
        if method == "DELETE":
            return None
        raise AssertionError((method, path))


class ManifestValidationTests(unittest.TestCase):
    def test_valid_manifest(self):
        reconciler.validate_manifest(manifest())

    def test_rejects_unreviewed_direct_port(self):
        value = manifest()
        server = value["servers"]["survival"]
        server["minecraft"]["infrarust"]["enable"] = False
        server["allocations"]["primary"]["ip"] = "0.0.0.0"
        server["allocations"]["primary"]["port"] = 25580
        server["exposures"] = [
            {"allocation": "primary", "ingress": "games-tcp", "protocol": "tcp"}
        ]
        with self.assertRaisesRegex(reconciler.ReconcileError, "does not cover"):
            reconciler.validate_manifest(value)

    def test_rejects_non_loopback_proxy_backend(self):
        value = manifest()
        value["servers"]["survival"]["allocations"]["primary"]["ip"] = "0.0.0.0"
        with self.assertRaisesRegex(reconciler.ReconcileError, "must bind 127.0.0.1"):
            reconciler.validate_manifest(value)

    def test_rejects_duplicate_domain(self):
        value = manifest()
        value["servers"]["creative"] = json.loads(
            json.dumps(value["servers"]["survival"])
        )
        value["servers"]["creative"]["allocations"]["primary"]["port"] = 25567
        with self.assertRaisesRegex(reconciler.ReconcileError, "duplicate Infrarust domain"):
            reconciler.validate_manifest(value)

    def test_rejects_duplicate_allocation_address(self):
        value = manifest()
        second = json.loads(json.dumps(value["servers"]["survival"]))
        second["minecraft"]["infrarust"]["enable"] = False
        second["minecraft"]["infrarust"]["domains"] = []
        value["servers"]["creative"] = second
        with self.assertRaisesRegex(reconciler.ReconcileError, "duplicate allocation"):
            reconciler.validate_manifest(value)

    def test_rejects_missing_primary_allocation(self):
        value = manifest()
        value["servers"]["survival"]["allocations"]["primary"]["primary"] = False
        with self.assertRaisesRegex(
            reconciler.ReconcileError, "exactly one primary allocation"
        ):
            reconciler.validate_manifest(value)

    def test_rejects_mismatched_ingress_protocol(self):
        value = manifest()
        server = value["servers"]["survival"]
        server["minecraft"]["infrarust"]["enable"] = False
        server["allocations"]["primary"]["ip"] = "0.0.0.0"
        server["allocations"]["primary"]["port"] = 25567
        server["exposures"] = [
            {"allocation": "primary", "ingress": "games-tcp", "protocol": "udp"}
        ]
        with self.assertRaisesRegex(reconciler.ReconcileError, "does not cover"):
            reconciler.validate_manifest(value)

    def test_rejects_invalid_domain_syntax(self):
        value = manifest()
        value["servers"]["survival"]["minecraft"]["infrarust"]["domains"] = [
            "survival_one.mc.example.test"
        ]
        with self.assertRaisesRegex(reconciler.ReconcileError, "is not below"):
            reconciler.validate_manifest(value)

    def test_rejects_malformed_deletion_uuid(self):
        value = manifest()
        server = value["servers"]["survival"]
        server["state"] = "absent"
        server["delete_confirmation_uuid"] = "not-a-uuid"
        with self.assertRaisesRegex(reconciler.ReconcileError, "is not a UUID"):
            reconciler.validate_manifest(value)


class ReconciliationTests(unittest.TestCase):
    def make_reconciler(self, apply):
        instance = reconciler.Reconciler(manifest(), apply=apply)
        instance.application = FakeApplication()
        instance.refresh()
        return instance

    def test_create_is_planned_without_mutation(self):
        instance = self.make_reconciler(False)
        instance.reconcile_present("survival", manifest()["servers"]["survival"])
        self.assertEqual(instance.application.calls, [])
        self.assertIn("create allocation 127.0.0.1:25566", instance.actions)
        self.assertIn("create server survival", instance.actions)

    def test_create_apply_does_not_start_server(self):
        instance = self.make_reconciler(True)
        instance.reconcile_present("survival", manifest()["servers"]["survival"])
        paths = [path for _, path, _ in instance.application.calls]
        self.assertIn("/servers", paths)
        self.assertFalse(any(path.endswith("/power") for path in paths))
        create_payload = next(
            payload
            for method, path, payload in instance.application.calls
            if method == "POST" and path == "/servers"
        )
        self.assertFalse(create_payload["start_on_completion"])

    def test_no_drift_reports_no_actions(self):
        value = manifest()
        spec = value["servers"]["survival"]
        instance = self.make_reconciler(True)
        allocation = item(
            "allocation",
            {"id": 10, "ip": "127.0.0.1", "port": 25566, "assigned": True},
            {
                "server": {
                    "data": item("server", {"id": 20, "uuid": SERVER_UUID})
                }
            },
        )
        server = item(
            "server",
            {
                "id": 20,
                "uuid": SERVER_UUID,
                "identifier": "bbbbbbbb",
                "external_id": "nix:survival",
                "name": "Survival",
                "description": "",
                "user": 2,
                "node": 1,
                "allocation": 10,
                "egg": 3,
                "oom_killer": True,
                "limits": spec["limits"],
                "feature_limits": spec["feature_limits"],
                "container": {
                    "image": spec["image"],
                    "startup_command": spec["startup"],
                    "environment": dict(spec["environment"]),
                },
            },
            {"allocations": {"data": [allocation]}},
        )
        instance.application.servers = [server]
        instance.application.allocations = [allocation]
        instance.servers = [server]
        instance.allocations = [allocation]
        instance.reconcile_present("survival", spec)
        self.assertEqual(instance.actions, [])
        self.assertEqual(instance.application.calls, [])

    def test_oom_killer_drift_is_patched(self):
        instance = self.make_reconciler(True)
        spec = manifest()["servers"]["survival"]
        instance.application.allocations = [
            item(
                "allocation",
                {
                    "id": 10,
                    "ip": "127.0.0.1",
                    "port": 25566,
                    "assigned": True,
                },
            )
        ]
        instance.application.servers = [
            item(
                "server",
                {
                    "id": 20,
                    "uuid": SERVER_UUID,
                    "external_id": "nix:survival",
                    "name": "Survival",
                    "description": "",
                    "user": 2,
                    "node": 1,
                    "allocation": 10,
                    "egg": 3,
                    "oom_killer": False,
                    "limits": spec["limits"],
                    "feature_limits": spec["feature_limits"],
                    "container": {
                        "image": spec["image"],
                        "startup_command": spec["startup"],
                        "environment": spec["environment"],
                    },
                },
                {"allocations": {"data": instance.application.allocations}},
            )
        ]
        instance.refresh()
        instance.reconcile_present("survival", spec)
        build_payload = next(
            payload
            for method, path, payload in instance.application.calls
            if method == "PATCH" and path.endswith("/build")
        )
        self.assertTrue(build_payload["oom_killer"])

    def test_occupied_allocation_is_rejected(self):
        instance = self.make_reconciler(False)
        instance.application.allocations = [
            item(
                "allocation",
                {"id": 10, "ip": "127.0.0.1", "port": 25566, "assigned": True},
                {
                    "server": {
                        "data": item("server", {"id": 99, "uuid": SERVER_UUID})
                    }
                },
            )
        ]
        instance.allocations = instance.application.allocations
        with self.assertRaisesRegex(reconciler.ReconcileError, "another server"):
            instance.reconcile_present("survival", manifest()["servers"]["survival"])

    def test_adoption_sets_external_id_without_create(self):
        value = manifest()
        value["servers"]["survival"]["adopt_uuid"] = SERVER_UUID
        instance = self.make_reconciler(False)
        instance.application.servers = [
            item(
                "server",
                {
                    "id": 20,
                    "uuid": SERVER_UUID,
                    "external_id": None,
                    "name": "Survival",
                    "description": "",
                    "user": 2,
                    "node": 1,
                    "allocation": 10,
                    "egg": 3,
                    "oom_killer": True,
                    "limits": value["servers"]["survival"]["limits"],
                    "feature_limits": value["servers"]["survival"]["feature_limits"],
                    "container": {
                        "image": "example/java:21",
                        "startup_command": "java -jar server.jar",
                        "environment": {"VERSION": "1.21"},
                    },
                },
            )
        ]
        instance.servers = instance.application.servers
        instance.application.allocations = [
            item(
                "allocation",
                {"id": 10, "ip": "127.0.0.1", "port": 25566, "assigned": True},
                {
                    "server": {
                        "data": item("server", {"id": 20, "uuid": SERVER_UUID})
                    }
                },
            )
        ]
        instance.allocations = instance.application.allocations
        instance.reconcile_present("survival", value["servers"]["survival"])
        self.assertIn("adopt server survival (external_id)", instance.actions)
        self.assertNotIn("create server survival", instance.actions)

    def test_declared_limit_drift_is_patched_without_power_action(self):
        value = manifest()
        instance = self.make_reconciler(True)
        allocation = item(
            "allocation",
            {"id": 10, "ip": "127.0.0.1", "port": 25566, "assigned": True},
            {
                "server": {
                    "data": item("server", {"id": 20, "uuid": SERVER_UUID})
                }
            },
        )
        actual_limits = dict(value["servers"]["survival"]["limits"])
        actual_limits["memory"] = 2048
        server = item(
            "server",
            {
                "id": 20,
                "uuid": SERVER_UUID,
                "identifier": "bbbbbbbb",
                "external_id": "nix:survival",
                "name": "Survival",
                "description": "",
                "user": 2,
                "node": 1,
                "allocation": 10,
                "egg": 3,
                "oom_killer": True,
                "limits": actual_limits,
                "feature_limits": value["servers"]["survival"]["feature_limits"],
                "container": {
                    "image": "example/java:21",
                    "startup_command": "java -jar server.jar",
                    "environment": {"VERSION": "1.21"},
                },
            },
            {"allocations": {"data": [allocation]}},
        )
        instance.application.servers = [server]
        instance.application.allocations = [allocation]
        instance.servers = [server]
        instance.allocations = [allocation]
        instance.reconcile_present("survival", value["servers"]["survival"])
        self.assertIn("update server build survival (limits)", instance.actions)
        calls = instance.application.calls
        self.assertTrue(
            any(method == "PATCH" and path == "/servers/20/build" for method, path, _ in calls)
        )
        self.assertFalse(any(path.endswith("/power") for _, path, _ in calls))


class FakeClient:
    def __init__(self, state="stopped"):
        self.state = state

    def request(self, method, path, query=None, payload=None, retry_read=True):
        return {"object": "stats", "attributes": {"current_state": self.state}}


class DeletionTests(unittest.TestCase):
    def deletion_reconciler(self, directory, state="stopped"):
        value = manifest()
        value["backup_marker"] = str(Path(directory) / "backup-success")
        Path(value["backup_marker"]).touch()
        spec = value["servers"]["survival"]
        spec["state"] = "absent"
        spec["delete_confirmation_uuid"] = SERVER_UUID
        instance = reconciler.Reconciler(value, apply=True)
        instance.application = FakeApplication()
        instance.client = FakeClient(state)
        allocation = item(
            "allocation",
            {"id": 10, "ip": "127.0.0.1", "port": 25566, "assigned": False},
        )
        server = item(
            "server",
            {
                "id": 20,
                "uuid": SERVER_UUID,
                "external_id": "nix:survival",
                "allocation": 10,
            },
            {"allocations": {"data": [allocation]}},
        )
        instance.servers = [server]
        instance.node = {"id": 1, "uuid": NODE_UUID}
        instance.application.allocations = [allocation]
        return instance, spec

    def test_delete_requires_offline_server_and_fresh_backup(self):
        with tempfile.TemporaryDirectory() as directory:
            instance, spec = self.deletion_reconciler(directory)
            instance.reconcile_absent("survival", spec)
            self.assertIn("delete server survival", instance.actions)
            self.assertTrue(
                any(
                    method == "DELETE" and path == "/servers/20"
                    for method, path, _ in instance.application.calls
                )
            )

    def test_delete_rejects_running_server(self):
        with tempfile.TemporaryDirectory() as directory:
            instance, spec = self.deletion_reconciler(directory, "running")
            with self.assertRaisesRegex(reconciler.ReconcileError, "while state is"):
                instance.reconcile_absent("survival", spec)

    def test_delete_rejects_stale_backup(self):
        with tempfile.TemporaryDirectory() as directory:
            instance, spec = self.deletion_reconciler(directory)
            old = time.time() - 200000
            os.utime(instance.manifest["backup_marker"], (old, old))
            with self.assertRaisesRegex(reconciler.ReconcileError, "hours old"):
                instance.reconcile_absent("survival", spec)


class ApiClientTests(unittest.TestCase):
    def test_pagination_reads_every_page(self):
        class PagedClient(reconciler.ApiClient):
            def __init__(self):
                pass

            def request(self, method, path, query=None, payload=None, retry_read=True):
                page = query["page"]
                return {
                    "data": [page],
                    "meta": {"pagination": {"total_pages": 3}},
                }

        self.assertEqual(PagedClient().paginate("/servers"), [1, 2, 3])

    def test_get_retries_then_raises_on_persistent_failure(self):
        client = reconciler.ApiClient("http://panel", "panel", "api-key")
        error = urllib.error.URLError("connection refused")
        with (
            mock.patch("urllib.request.urlopen", side_effect=error),
            mock.patch("time.sleep") as sleep_mock,
            self.assertRaisesRegex(reconciler.ReconcileError, "failed"),
        ):
            client.request("GET", "/servers")
        self.assertGreater(sleep_mock.call_count, 0)

    def test_api_errors_do_not_echo_server_detail(self):
        response = io.BytesIO(
            json.dumps(
                {"errors": [{"code": "ValidationException", "detail": "secret-value"}]}
            ).encode("utf-8")
        )
        error = urllib.error.HTTPError(
            "http://panel/api/application/servers",
            422,
            "unprocessable",
            {},
            response,
        )
        self.addCleanup(error.close)
        client = reconciler.ApiClient("http://panel", "panel", "api-key")
        with (
            mock.patch("urllib.request.urlopen", side_effect=error),
            self.assertRaises(reconciler.ReconcileError) as raised,
        ):
            client.request("POST", "/servers", payload={"value": "secret-value"})
        self.assertNotIn("secret-value", str(raised.exception))


class RendererTests(unittest.TestCase):
    def test_runtime_rendering_keeps_keys_out_of_manifest(self):
        value = manifest()
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            admin_key = directory / "admin-key"
            admin_key.write_text("admin-key-with-adequate-length", encoding="utf-8")
            runtime = directory / "run"
            value["infrarust"]["admin_api_key_file"] = str(admin_key)
            value["infrarust"]["runtime_dir"] = str(runtime)
            value["infrarust"]["plugins_dir"] = str(directory / "plugins")
            value["infrarust"]["ban_file"] = str(directory / "bans.json")
            value["state_file"] = str(directory / "state.json")
            reconciler.render_infrarust(value)
            global_config = (runtime / "infrarust.toml").read_text(encoding="utf-8")
            server_config = (runtime / "servers" / "survival.toml").read_text(
                encoding="utf-8"
            )
            self.assertIn("admin-key-with-adequate-length", global_config)
            self.assertIn('addresses = ["127.0.0.1:25566"]', server_config)
            self.assertNotIn("admin-key-with-adequate-length", json.dumps(value))
            self.assertEqual(os.stat(runtime / "infrarust.toml").st_mode & 0o222, 0)

    def test_send_proxy_protocol_is_rendered_when_enabled(self):
        value = manifest()
        value["servers"]["survival"]["minecraft"]["infrarust"]["send_proxy_protocol"] = True
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            (directory / "admin-key").write_text(
                "admin-key-with-adequate-length", encoding="utf-8"
            )
            value["infrarust"]["admin_api_key_file"] = str(directory / "admin-key")
            value["infrarust"]["runtime_dir"] = str(directory / "run")
            value["infrarust"]["plugins_dir"] = str(directory / "plugins")
            value["infrarust"]["ban_file"] = str(directory / "bans.json")
            value["state_file"] = str(directory / "state.json")
            reconciler.render_infrarust(value)
            server_config = (
                directory / "run" / "servers" / "survival.toml"
            ).read_text(encoding="utf-8")
            self.assertIn("send_proxy_protocol = true", server_config)

    def test_wake_on_connect_uses_runtime_identity(self):
        value = manifest()
        route = value["servers"]["survival"]["minecraft"]["infrarust"]
        route["wake_on_connect"] = True
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            (directory / "admin-key").write_text("admin-key-long-enough", encoding="utf-8")
            (directory / "client-key").write_text("client-key-secret", encoding="utf-8")
            (directory / "state.json").write_text(
                json.dumps({"survival": {"uuid": SERVER_UUID}}), encoding="utf-8"
            )
            value["client_api_key_file"] = str(directory / "client-key")
            value["state_file"] = str(directory / "state.json")
            value["infrarust"].update(
                {
                    "admin_api_key_file": str(directory / "admin-key"),
                    "runtime_dir": str(directory / "run"),
                    "plugins_dir": str(directory / "plugins"),
                    "ban_file": str(directory / "bans.json"),
                }
            )
            reconciler.render_infrarust(value)
            server_config = (
                directory / "run" / "servers" / "survival.toml"
            ).read_text(encoding="utf-8")
            self.assertIn("[server_manager]", server_config)
            self.assertIn(SERVER_UUID, server_config)
            self.assertIn("client-key-secret", server_config)


if __name__ == "__main__":
    unittest.main()
