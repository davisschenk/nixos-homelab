# Service-Based NixOS Modules

**Date:** 2026-05-19  
**Status:** Approved

## Goal

Refactor `modules/nixos/` so each file owns the full vertical slice of a single service (or cohesive group): its SOPS secrets, Caddy virtualHost, and impermanence persist directories. Eliminate catch-all files (`apps.nix`, `containers.nix`).

## File Layout

Before → After:

| Old | New | Change |
|-----|-----|--------|
| `apps.nix` | *(deleted)* | Split into `mealie.nix`, `actual.nix`, `copyparty.nix` |
| `containers.nix` | *(deleted)* | Becomes `romm.nix` |
| — | `mealie.nix` | *new* |
| — | `actual.nix` | *new* |
| — | `copyparty.nix` | *new* |
| — | `romm.nix` | *new* |
| `base.nix` | `base.nix` | Remove service-specific secrets + persist dirs |
| `networking.nix` | `networking.nix` | Remove all virtualHosts; keep global Caddy config only |
| `auth.nix` | `auth.nix` | Already clean; add Caddy vhost + auth persist |
| `media.nix` | `media.nix` | Add Caddy vhost + jellyfin persist |
| `monitoring.nix` | `monitoring.nix` | Add Caddy vhosts + persist dirs |
| `arr.nix` | `arr.nix` | Move vpn secret here; add persist |
| `pelican.nix` | `pelican.nix` | Move 2 secrets from base; add persist |
| `gaming-vm.nix` | `gaming-vm.nix` | Untouched |

Final `default.nix` imports (13 files):

```
base.nix, networking.nix, auth.nix, media.nix, monitoring.nix,
arr.nix, mealie.nix, actual.nix, copyparty.nix, romm.nix,
pelican.nix, gaming-vm.nix
```

## Internal Structure Convention

Each service file follows this block ordering (omit blocks that don't apply — no empty stubs):

```nix
{ config, ... }:
{
  # 1. SOPS secrets
  sops.secrets."service_secret" = {
    sopsFile = ../../secrets/service.yaml;
  };

  # 2. Service configuration
  services.foo = { enable = true; ... };

  # 3. Caddy virtualHost
  services.caddy.virtualHosts."foo.schenkenberger.dev" = {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      import authentik_forward_auth
      reverse_proxy localhost:PORT
    '';
  };

  # 4. Persist directories
  environment.persistence."/persist" = {
    directories = [ "/var/lib/foo" ];
  };
}
```

OCI container services (romm) additionally include `systemd.tmpfiles.rules` and `systemd.services` mount dependencies in block 2.

## Migration Details

### Secrets moves

| Secret | From | To |
|--------|------|----|
| `cloudflare_tunnel_token` | `base.nix` (implicit default) | `networking.nix` with explicit `sopsFile` |
| `vpn_wg_conf` | `base.nix` | `arr.nix` |
| `pelican_token_id` | `base.nix` | `pelican.nix` |
| `pelican_token` | `base.nix` | `pelican.nix` |

`sops.defaultSopsFile` remains in `base.nix` pointing at `cloudflare-tunnel.yaml`. The `cloudflare_tunnel_token` declaration in `networking.nix` sets `sopsFile` explicitly since it can no longer rely on the default.

The encrypted `secrets/*.yaml` files are **not changed**.

### Persist directory moves

`base.nix` retains only host-level persist entries:
- `/etc/ssh`
- `/etc/sops/age`
- `/etc/machine-id`

All service-specific directories move to the module that owns the service:

| Directory | Moves to |
|-----------|----------|
| `/var/lib/jellyfin` | `media.nix` |
| `/var/lib/authentik` | `auth.nix` |
| `/var/lib/postgresql` | `auth.nix` (Authentik's DB) |
| `/var/lib/prometheus2` | `monitoring.nix` |
| `/var/lib/grafana` | `monitoring.nix` |
| `/var/lib/pelican` | `pelican.nix` |
| `/var/lib/pelican-wings` | `pelican.nix` |
| `/var/lib/mysql` | `pelican.nix` (Pelican's MariaDB — nix-pelican hardcodes MariaDB, not PostgreSQL) |
| `/var/lib/libvirt` | `gaming-vm.nix` |
| `/var/lib/nixarr` | `arr.nix` |
| `/containers/romm` | `romm.nix` |

NixOS merges `environment.persistence."/persist".directories` lists across modules — no extra wiring required.

### Caddy virtualHost moves

All `services.caddy.virtualHosts` declarations move out of `networking.nix` into their owning service files. `networking.nix` retains only:

```nix
services.caddy = {
  enable = true;
  globalConfig = ''auto_https off'';
  extraConfig = ''
    (authentik_forward_auth) {
      forward_auth localhost:9000 { ... }
    }
  '';
};
```

NixOS merges the `virtualHosts` attrset across modules.

### virtualHost → service mapping

| Domain | Service file |
|--------|-------------|
| `jellyfin.schenkenberger.dev` | `media.nix` |
| `auth.schenkenberger.dev` | `auth.nix` |
| `files.schenkenberger.dev` | `copyparty.nix` |
| `panel.schenkenberger.dev` | `pelican.nix` |
| `grafana.schenkenberger.dev` | `monitoring.nix` |
| `mealie.schenkenberger.dev` | `mealie.nix` |
| `actual.schenkenberger.dev` | `actual.nix` |
| `romm.schenkenberger.dev` | `romm.nix` |
| `sonarr.schenkenberger.dev` | `arr.nix` |
| `radarr.schenkenberger.dev` | `arr.nix` |
| `prowlarr.schenkenberger.dev` | `arr.nix` |
| `qbit.schenkenberger.dev` | `arr.nix` |
