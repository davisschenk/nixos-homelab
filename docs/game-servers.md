# Declarative game servers

`mylab.gameServers` manages selected Pelican servers from Nix while leaving the
Pelican panel, console, file manager, and Wings SFTP available for day-to-day
operations. Servers not present in the catalog are never touched.

Public ports remain separately reviewed in `infra/ingress.json`. A catalog entry
can reference an ingress rule, but the reconciler cannot create or change edge
firewall, nftables, WireGuard, or Terraform resources.

## Initial setup

Create a Pelican Application API key with read/write access to nodes,
allocations, users, eggs, and servers. Create a Client API key for the account
that owns managed servers if deletion or wake-on-connect will be used. Add those
and an Infrarust dashboard key of at least 16 characters with:

```console
just edit pelican
```

The encrypted file must contain these keys before enabling the module:

```yaml
pelican_reconciler_api_key: papp_...
pelican_reconciler_client_key: pacc_...
infrarust_api_key: ...
```

The Client key is optional until deletion or wake-on-connect is declared. When
used, configure its path explicitly:

```nix
mylab.gameServers.clientApiKeyFile =
  config.sops.secrets.pelican_reconciler_client_key.path;
```

## Catalog example

```nix
{
  config,
  ...
}:
{
  mylab.gameServers = {
    enable = true;
    defaultOwner.email = "operator@example.com";

    applicationApiKeyFile =
      config.sops.secrets.pelican_reconciler_api_key.path;
    clientApiKeyFile = "/run/secrets/pelican_reconciler_client_key";

    infrarust = {
      enable = true;
      adminApiKeyFile = "/run/secrets/infrarust_api_key";
    };

    servers.survival = {
      adoptUuid = "<existing-pelican-server-uuid>";
      displayName = "Survival";
      eggUuid = "<minecraft-egg-uuid>";
      image = "<declared-image>";
      startup = "<declared-start-command>";

      environment.SERVER_VERSION = "1.21";
      limits = {
        memory = 8192;
        disk = 50000;
        cpu = 400;
      };

      allocations.primary = {
        ip = "127.0.0.1";
        port = 25566;
        primary = true;
      };

      minecraft.infrarust = {
        enable = true;
        domains = [ "survival.mc.schenkenberger.dev" ];
      };
    };

    servers.factorio = {
      eggUuid = "<factorio-egg-uuid>";
      allocations.game = {
        ip = "0.0.0.0";
        port = 25570;
        primary = true;
      };
      exposures = [
        {
          allocation = "game";
          ingress = "games-udp";
          protocol = "udp";
        }
      ];
    };
  };
}
```

Public environment values are managed key-by-key. Undeclared egg variables are
preserved. `secretEnvironmentFile` accepts a SOPS-rendered flat JSON object or
`KEY=VALUE` file; its contents are sent to Pelican without appearing in the Nix
store or reconcile output.

## Reconciliation

The system applies the catalog on boot and after each NixOS activation. It can
also be inspected or applied manually:

```console
sudo game-server-reconcile check
sudo game-server-reconcile plan
sudo systemctl start pelican-reconcile.service
sudo journalctl -u pelican-reconcile.service
```

The manifest store path is shown in the unit's `ExecStart` property:

```console
systemctl show pelican-reconcile.service --property=ExecStart
```

The reconciler patches declared metadata and runtime configuration but never
starts, stops, or reinstalls a server. A reported `operator action required`
must be handled through Pelican during a maintenance window.

## Infrarust backend addressing

Wings does not literally bind a published container port to a `127.0.0.1`
allocation -- it substitutes its own configured `docker.network.interface`
(the node's Docker bridge gateway) instead. The Pelican-declared allocation
IP should still be `127.0.0.1` (that's what tells Wings to keep it off public
interfaces), but Infrarust needs to connect to whatever Wings actually
publishes to. Check `docker.network.interface` in
`/var/lib/pelican-wings/config.yml` on the node and set
`mylab.gameServers.infrarust.backendAddress` to match -- otherwise Infrarust
will report `backend unreachable` / `Connection refused` for every join
attempt even though the server itself is running fine.

## Adoption and cutover

1. Deploy the module with `enable = true`, an empty `servers` set, and
   `infrarust.enable = false`.
2. Stop the Pelican-managed Infrarust server before enabling the native proxy;
   both use TCP port 25565.
3. Enable native Infrarust and verify
   `https://infrarust.schenkenberger.dev` through Authentik.
4. Declare one existing Minecraft server with `adoptUuid`, a loopback backend
   allocation, and its `*.mc.schenkenberger.dev` hostname.
5. Inspect the reconcile plan, apply it, and manually restart the server so its
   changed allocation is effective.
6. Verify panel files, SFTP, the console, hostname routing, and client source
   preservation before adopting more servers.

After adoption, the stable identity is `external_id = nix:<catalog-name>` and
`adoptUuid` may be removed.

## Deletion

Omission is never deletion. To remove a managed server, declare:

```nix
servers.old-world = {
  state = "absent";
  deleteConfirmationUuid = "<current-full-pelican-uuid>";
};
```

Deletion proceeds only when the UUID matches, the Client API reports the server
as stopped, and the `/persist` restic backup completed successfully in the last
36 hours. The reconciler never stops a server to satisfy this guard.
