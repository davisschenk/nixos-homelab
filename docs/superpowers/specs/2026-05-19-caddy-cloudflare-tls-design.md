# Caddy Cloudflare DNS Plugin + TLS Design

**Date:** 2026-05-19
**Status:** Approved

## Context

The Docker-based server setup (`/home/davis/server/caddy/`) uses a custom Caddy build with the `caddy-dns/cloudflare` plugin, enabling Let's Encrypt cert issuance via DNS-01 challenge. The NixOS setup currently uses stock Caddy with `auto_https off`, relying entirely on Cloudflare's edge TLS.

Access model: Cloudflare Zero Trust tunnel only — no local LAN HTTPS needed. The zone-level SSL mode does not directly govern tunnel-routed traffic (the tunnel connection is always fully encrypted by the tunnel protocol), so the primary motivation is parity with the server setup and future-proofing.

## Design

### 1. Package — Caddy with Cloudflare DNS plugin

```nix
services.caddy.package = pkgs.caddy.withPlugins {
  plugins = [ "github.com/caddy-dns/cloudflare@<pinned-version>" ];
  hash = "sha256-<vendor-hash>";
};
```

Hash is bootstrapped: build once with `lib.fakeHash`, capture the real hash from the Nix error, replace.

### 2. Secret — `secrets/cloudflare-dns.yaml`

New sops-encrypted file with one key:

```yaml
cloudflare_api_token: "<token>"
```

The Cloudflare API token requires **Zone:DNS:Edit** permission scoped to `schenkenberger.dev`. It is distinct from the tunnel token (which lives in `secrets/cloudflare-tunnel.yaml`).

A sops template produces the `KEY=value` format required by systemd `EnvironmentFile`:

```nix
sops.secrets."cloudflare_api_token" = {
  sopsFile = ../../secrets/cloudflare-dns.yaml;
};

sops.templates."caddy-env" = {
  content = "CF_API_TOKEN=${config.sops.placeholder."cloudflare_api_token"}";
  restartUnits = [ "caddy.service" ];
};

services.caddy.environmentFile = config.sops.templates."caddy-env".path;
```

### 3. Caddy global config

Replace `auto_https off` with ACME DNS-01 via Cloudflare:

```nix
services.caddy.globalConfig = ''
  email davisschenk@gmail.com
  acme_dns cloudflare {env.CF_API_TOKEN}
'';
```

Caddy automatically obtains Let's Encrypt certs for every named vhost using DNS-01. No changes needed to individual vhost `extraConfig` blocks.

### 4. Manual step — Cloudflare dashboard

Each public hostname route in **Zero Trust → Networks → Tunnels → [tunnel] → Public Hostnames** must be updated:

- Service URL: `http://127.0.0.1` → `https://127.0.0.1:443`
- Origin request setting: enable `No TLS Verify` (the cert is valid for `*.schenkenberger.dev`, not `127.0.0.1`, so hostname verification must be disabled for the localhost hop)

## Files Changed

| File | Change |
|------|--------|
| `modules/nixos/networking.nix` | Add plugin package, sops secret+template, env file, update globalConfig |
| `secrets/cloudflare-dns.yaml` | New — placeholder until encrypted with sops |

## Out of Scope

- Local LAN HTTPS (not needed; user confirmed tunnel-only)
- Per-vhost cert granularity (wildcard/per-domain is handled automatically by Caddy)
- Cloudflare zone SSL mode changes (irrelevant for tunnel-routed traffic)
