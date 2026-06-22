# Authentik IaC via Nix-driven Blueprints

## Context

Authentik is already deployed declaratively via `authentik-nix` (see `modules/nixos/auth.nix`). However, its internal objects — applications, OAuth2/OIDC providers, proxy providers, and outpost bindings — are configured only through the web UI and live only in the PostgreSQL database. They would be lost on a full rebuild and are not version-controlled.

This design adds a new NixOS module that declares all Authentik internal objects as Authentik Blueprints, generated from Nix and applied automatically whenever Authentik starts.

## Approach

### Why Blueprints (not OpenTofu/Terraform)

Authentik Blueprints are its native IaC format: YAML files placed in a `blueprints/` directory that Authentik reads and applies on startup. They are idempotent and auto-applied — no separate `apply` step. This fits the NixOS-rebuild-driven workflow perfectly.

OpenTofu with the Authentik provider was ruled out because it requires a running Authentik API at apply time and a persistent state file, making "automatic on nixos-rebuild" fragile.

### Why `pkgs.writeText` (not `pkgs.formats.yaml.generate`)

Blueprints for OIDC services need Authentik's `!env_var` custom YAML tag to reference client secrets at apply time. Nix's standard YAML serializer cannot produce custom YAML tags, so these blueprints are written as raw string files via `pkgs.writeText`. Pure-structure blueprints (forward-auth providers with no secrets) could use `pkgs.formats.yaml.generate`, but using `pkgs.writeText` uniformly keeps the authoring style consistent.

## Files

| File | Role |
|------|------|
| `modules/nixos/auth-blueprints.nix` | New module — all blueprint logic |
| `modules/nixos/default.nix` | Add `./auth-blueprints.nix` import |
| `modules/nixos/auth.nix` | Unchanged |

## Module Design (`auth-blueprints.nix`)

### 1. Blueprint YAML files

One `pkgs.writeText` file per service, placed in a `custom/` namespace within the combined blueprints dir. Each file is a complete Authentik Blueprint YAML.

**OIDC services** (Mealie, RomM): declare an `authentik_providers_oauth2.oauth2provider` + `authentik_core.application`. The `client_secret` attribute uses `!env_var <VAR>` to reference a runtime environment variable.

**Forward-auth services** (Grafana, Sonarr, Radarr, Prowlarr, qBittorrent): declare an `authentik_providers_proxy.proxyprovider` in `forward_auth_mode` with the service's external host URL, plus an `authentik_core.application`. A final entry binds all proxy providers to the embedded outpost (`authentik_outposts.outpost` with `identifiers.name = "authentik Embedded Outpost"`).

### 2. Combined blueprints directory

```nix
let
  defaultBlueprintsDir =
    "${config.services.authentik.authentikComponents.staticWorkdirDeps}/blueprints";

  customBlueprintsDir = pkgs.runCommand "authentik-blueprints" { } ''
    cp -rL ${defaultBlueprintsDir}/. $out/
    mkdir -p $out/custom
    cp ${mealieBlueprint}   $out/custom/mealie.yaml
    cp ${rommBlueprint}     $out/custom/romm.yaml
    cp ${grafanaBlueprint}  $out/custom/grafana.yaml
    cp ${arrBlueprint}      $out/custom/arr.yaml
  '';
in
{
  services.authentik.settings.blueprints_dir = customBlueprintsDir;
}
```

`pkgs.runCommand` runs at build time, so the Nix store path to default blueprints is valid. The merged directory includes all of Authentik's shipped default/system blueprints (default flows, etc.) and adds the custom files in `custom/`.

### 3. Secret injection for OIDC client secrets

OIDC client secrets already exist in SOPS (`mealie_oidc_client_secret` in `secrets/mealie.yaml`, `romm_oidc_client_secret` in `secrets/romm.yaml`). They need to be visible in Authentik's environment at blueprint-apply time.

A new sops template provides them:

```nix
sops.templates."authentik-blueprint-env" = {
  content = ''
    MEALIE_OIDC_CLIENT_SECRET=${config.sops.placeholder."mealie_oidc_client_secret"}
    ROMM_OIDC_CLIENT_SECRET=${config.sops.placeholder."romm_oidc_client_secret"}
  '';
  restartUnits = [ "authentik.service" "authentik-worker.service" ];
};
```

Then appended to both Authentik systemd units (the authentik-nix module sets `EnvironmentFile` as a list, so `lib.mkAfter` is safe):

```nix
systemd.services.authentik.serviceConfig.EnvironmentFile =
  lib.mkAfter [ config.sops.templates."authentik-blueprint-env".path ];
systemd.services.authentik-worker.serviceConfig.EnvironmentFile =
  lib.mkAfter [ config.sops.templates."authentik-blueprint-env".path ];
```

The secrets are already declared in `mealie.nix` and `romm.nix` respectively. `config.sops.placeholder` works across modules — no need to re-declare them in `auth-blueprints.nix`.

## Blueprint Schema Per Service

### Mealie (OIDC)
- Model: `authentik_providers_oauth2.oauth2provider` — `client_id = "mealie"`, `client_secret = !env_var MEALIE_OIDC_CLIENT_SECRET`, `redirect_uris = ["https://mealie.schenkenberger.dev/*"]`
- Model: `authentik_core.application` — `slug = "mealie"`, linked provider

### RomM (OIDC)
- Model: `authentik_providers_oauth2.oauth2provider` — `client_id = "romm"`, `client_secret = !env_var ROMM_OIDC_CLIENT_SECRET`, `redirect_uris = ["https://romm.schenkenberger.dev/api/oauth/openid"]`
- Model: `authentik_core.application` — `slug = "romm"`, linked provider

### Grafana (forward auth)
- Model: `authentik_providers_proxy.proxyprovider` — `external_host = "https://grafana.schenkenberger.dev"`, `mode = "forward_single"`
- Model: `authentik_core.application` — `slug = "grafana"`, linked provider

### Arr services (forward auth, single blueprint file)
One blueprint file covers all four services. Each gets:
- `authentik_providers_proxy.proxyprovider` — respective external host (`sonarr.schenkenberger.dev`, `radarr.schenkenberger.dev`, `prowlarr.schenkenberger.dev`, `qbit.schenkenberger.dev`), `mode = "forward_single"`
- `authentik_core.application` — respective slug, linked provider

### Embedded outpost binding
A final entry in the forward-auth blueprints binds all proxy providers to the embedded outpost:
```yaml
- model: authentik_outposts.outpost
  state: present
  identifiers:
    name: "authentik Embedded Outpost"
  attrs:
    providers:
      - !find [authentik_core.application, {slug: grafana}]
      - !find [authentik_core.application, {slug: sonarr}]
      # ... etc
```

## Verification

1. Run `nixos-rebuild switch` — build should succeed (Nix eval + build the merged blueprints dir)
2. Check Authentik admin UI → System → Blueprints: all custom blueprints should appear and show status "Successful"
3. Verify OIDC login works for Mealie and RomM
4. Verify Caddy forward auth works for Grafana, Sonarr, Radarr, Prowlarr, qBittorrent
5. Run `nix eval .#nixosConfigurations.mangrove.config.services.authentik.settings.blueprints_dir` to confirm the path resolves to the merged Nix store path

## Open Questions Before Implementation

- Confirm whether `lib.mkAfter` on `systemd.services.authentik.serviceConfig.EnvironmentFile` merges with the list the authentik-nix module creates, or conflicts. If it conflicts, a wrapper env file (merging both templates into one) is the fallback.
- Confirm exact Authentik embedded outpost name on the running instance (default is "authentik Embedded Outpost" but may differ if renamed in UI).
