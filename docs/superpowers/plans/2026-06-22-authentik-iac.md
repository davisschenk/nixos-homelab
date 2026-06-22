# Authentik IaC Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Declare all Authentik internal objects (OIDC providers, proxy providers, applications, groups, outpost bindings) as Nix-generated YAML blueprints that are auto-applied on every nixos-rebuild.

**Architecture:** A new NixOS module (`auth-blueprints.nix`) generates blueprint YAML files via `pkgs.writeText`, merges them with Authentik's default blueprints into a combined Nix store directory via `pkgs.runCommand`, and sets `services.authentik.settings.blueprints_dir` to that path. OIDC client secrets are injected by extending the existing `authentik-env` sops template in `auth.nix` with two additional vars read by blueprints via Authentik's `!env_var` YAML tag.

**Tech Stack:** NixOS module system, sops-nix, authentik-nix flake, Authentik Blueprints (YAML)

## Global Constraints

- All changes must `nix eval .#nixosConfigurations.mangrove` without errors before commit
- Never hardcode secrets — all secrets via `config.sops.placeholder`
- Blueprint files use `state: present` (idempotent upsert, not replace)
- The Authentik instance is fresh — no existing UI state to preserve
- Domain: `schenkenberger.dev` — all service URLs use this domain

---

### Task 1: Ensure OIDC client secrets exist in SOPS

**Files:**
- Check/edit: `secrets/mealie.yaml`
- Check/edit: `secrets/romm.yaml`

**Interfaces:**
- Produces: `mealie_oidc_client_secret` and `romm_oidc_client_secret` keys in their respective SOPS files, consumed by Tasks 2 and 4–5

- [ ] **Step 1: Check if `mealie_oidc_client_secret` already exists**

```bash
just view mealie
```

Look for a `mealie_oidc_client_secret` key. If it is present, skip to Step 4.

- [ ] **Step 2: Generate a secret for Mealie OIDC client**

```bash
openssl rand -hex 32
```

Copy the output — this is your `mealie_oidc_client_secret` value.

- [ ] **Step 3: Add it to `secrets/mealie.yaml`**

```bash
just edit mealie
```

Add the following line to the decrypted YAML (alongside existing keys):

```yaml
mealie_oidc_client_secret: <paste-generated-value>
```

Save and close — sops re-encrypts on exit.

- [ ] **Step 4: Check if `romm_oidc_client_secret` already exists**

```bash
just view romm
```

Look for `romm_oidc_client_secret`. If present, this task is done.

- [ ] **Step 5: Generate a secret for RomM OIDC client**

```bash
openssl rand -hex 32
```

- [ ] **Step 6: Add it to `secrets/romm.yaml`**

```bash
just edit romm
```

Add:

```yaml
romm_oidc_client_secret: <paste-generated-value>
```

- [ ] **Step 7: Commit**

```bash
git add secrets/mealie.yaml secrets/romm.yaml
git commit -m "secrets: add OIDC client secrets for Mealie and RomM"
```

---

### Task 2: Extend `auth.nix` to expose OIDC secrets to Authentik

**Files:**
- Modify: `modules/nixos/auth.nix`

**Interfaces:**
- Consumes: `mealie_oidc_client_secret` (from `secrets/mealie.yaml`), `romm_oidc_client_secret` (from `secrets/romm.yaml`)
- Produces: env vars `MEALIE_OIDC_CLIENT_SECRET` and `ROMM_OIDC_CLIENT_SECRET` available in the `authentik` and `authentik-worker` systemd units at runtime, consumed by blueprint `!env_var` tags in Tasks 4–5

Adding these to the existing `authentik-env` template is the correct approach — it uses the same single `environmentFile` path that the `authentik-nix` module already wires in, avoiding any systemd serviceConfig merging issues.

- [ ] **Step 1: Edit `modules/nixos/auth.nix`**

Replace the existing `sops.templates."authentik-env"` block:

```nix
  sops.templates."authentik-env" = {
    content = ''
      AUTHENTIK_SECRET_KEY=${config.sops.placeholder."authentik_secret_key"}
      AUTHENTIK_EMAIL__USERNAME=${config.sops.placeholder."mail_username"}
      AUTHENTIK_EMAIL__PASSWORD=${config.sops.placeholder."mail_password"}
    '';
    restartUnits = [
      "authentik.service"
      "authentik-worker.service"
    ];
  };
```

With:

```nix
  sops.templates."authentik-env" = {
    content = ''
      AUTHENTIK_SECRET_KEY=${config.sops.placeholder."authentik_secret_key"}
      AUTHENTIK_EMAIL__USERNAME=${config.sops.placeholder."mail_username"}
      AUTHENTIK_EMAIL__PASSWORD=${config.sops.placeholder."mail_password"}
      MEALIE_OIDC_CLIENT_SECRET=${config.sops.placeholder."mealie_oidc_client_secret"}
      ROMM_OIDC_CLIENT_SECRET=${config.sops.placeholder."romm_oidc_client_secret"}
    '';
    restartUnits = [
      "authentik.service"
      "authentik-worker.service"
    ];
  };
```

- [ ] **Step 2: Verify eval passes**

```bash
nix eval .#nixosConfigurations.mangrove.config.system.build.toplevel 2>&1 | head -5
```

Expected: no errors (prints a store path).

- [ ] **Step 3: Commit**

```bash
git add modules/nixos/auth.nix
git commit -m "auth: expose OIDC client secrets to Authentik environment for blueprints"
```

---

### Task 3: Create `auth-blueprints.nix` scaffold with blueprints directory

**Files:**
- Create: `modules/nixos/auth-blueprints.nix`
- Modify: `modules/nixos/default.nix`

**Interfaces:**
- Consumes: `config.services.authentik.authentikComponents.staticWorkdirDeps` (the `authentik-nix` package attribute containing default blueprints/flows)
- Produces: `services.authentik.settings.blueprints_dir` set to a merged Nix store path; a `customBlueprintsDir` let-binding that Tasks 4–5 will extend with blueprint files

- [ ] **Step 1: Create `modules/nixos/auth-blueprints.nix`**

```nix
{ config, pkgs, lib, ... }:
let
  defaultBlueprintsDir =
    "${config.services.authentik.authentikComponents.staticWorkdirDeps}/blueprints";

  customBlueprintsDir = pkgs.runCommand "authentik-blueprints" { } ''
    cp -rL ${defaultBlueprintsDir}/. $out/
    mkdir -p $out/custom
  '';
in
{
  services.authentik.settings.blueprints_dir = customBlueprintsDir;
}
```

- [ ] **Step 2: Add import to `modules/nixos/default.nix`**

```nix
{
  imports = [
    ./ports.nix
    ./base.nix
    ./networking.nix
    ./auth.nix
    ./auth-blueprints.nix
    ./media.nix
    ./arr.nix
    ./monitoring.nix
    ./copyparty.nix
    ./romm.nix
    ./pelican.nix
    ./gaming-vm.nix
    ./mealie.nix
    ./actual.nix
    ./backup.nix
  ];
}
```

- [ ] **Step 3: Verify the blueprints dir resolves**

```bash
nix eval .#nixosConfigurations.mangrove.config.services.authentik.settings.blueprints_dir
```

Expected: a Nix store path like `/nix/store/...-authentik-blueprints`.

- [ ] **Step 4: Commit**

```bash
git add modules/nixos/auth-blueprints.nix modules/nixos/default.nix
git commit -m "auth: add auth-blueprints module with merged blueprints directory"
```

---

### Task 4: Add Mealie OIDC blueprint

**Files:**
- Modify: `modules/nixos/auth-blueprints.nix`

**Interfaces:**
- Consumes: `MEALIE_OIDC_CLIENT_SECRET` env var (from Task 2 template), `mealie_oidc_client_secret` sops placeholder
- Produces: Authentik objects on first boot — group `mealie-user`, group `mealie-admin`, OAuth2Provider `Mealie Provider` (client_id `mealie`), Application `mealie`

The blueprint uses `!env_var MEALIE_OIDC_CLIENT_SECRET` (an Authentik-native YAML tag resolved at apply time) and `!find` to cross-reference objects within the same blueprint. The authorization flow `default-provider-authorization-implicit-consent` is a slug created by Authentik's default system blueprint on first boot.

- [ ] **Step 1: Update `modules/nixos/auth-blueprints.nix`**

Replace the entire file with:

```nix
{ config, pkgs, lib, ... }:
let
  defaultBlueprintsDir =
    "${config.services.authentik.authentikComponents.staticWorkdirDeps}/blueprints";

  mealieBlueprint = pkgs.writeText "mealie.yaml" ''
    version: 1
    metadata:
      name: "Mealie OIDC"
      labels:
        blueprints.goauthentik.io/instantiate: "true"
    entries:
      - model: authentik_core.group
        state: present
        identifiers:
          name: "mealie-user"
        attrs:
          name: "mealie-user"
      - model: authentik_core.group
        state: present
        identifiers:
          name: "mealie-admin"
        attrs:
          name: "mealie-admin"
      - model: authentik_providers_oauth2.oauth2provider
        state: present
        identifiers:
          name: "Mealie Provider"
        attrs:
          authorization_flow: !find [authentik_flows.flow, {slug: "default-provider-authorization-implicit-consent"}]
          client_id: "mealie"
          client_secret: !env_var MEALIE_OIDC_CLIENT_SECRET
          redirect_uris:
            - url: "https://mealie.schenkenberger.dev/"
              matching_mode: prefix
          sub_mode: hashed_user_id
          include_claims_in_id_token: true
          signing_key: !find [authentik_crypto.certificatekeypair, {name: "authentik Self-signed Certificate"}]
      - model: authentik_core.application
        state: present
        identifiers:
          slug: "mealie"
        attrs:
          name: "Mealie"
          slug: "mealie"
          provider: !find [authentik_providers_oauth2.oauth2provider, {name: "Mealie Provider"}]
          policy_engine_mode: any
  '';

  customBlueprintsDir = pkgs.runCommand "authentik-blueprints" { } ''
    cp -rL ${defaultBlueprintsDir}/. $out/
    mkdir -p $out/custom
    cp ${mealieBlueprint} $out/custom/mealie.yaml
  '';
in
{
  services.authentik.settings.blueprints_dir = customBlueprintsDir;
}
```

- [ ] **Step 2: Verify eval**

```bash
nix eval .#nixosConfigurations.mangrove.config.services.authentik.settings.blueprints_dir
```

Expected: a new store path (different hash from Task 3 — the directory now has content).

- [ ] **Step 3: Commit**

```bash
git add modules/nixos/auth-blueprints.nix
git commit -m "auth: add Mealie OIDC blueprint (groups, provider, application)"
```

---

### Task 5: Add RomM OIDC blueprint

**Files:**
- Modify: `modules/nixos/auth-blueprints.nix`

**Interfaces:**
- Consumes: `ROMM_OIDC_CLIENT_SECRET` env var (from Task 2 template)
- Produces: Authentik objects — OAuth2Provider `RomM Provider` (client_id `romm`), Application `romm`

- [ ] **Step 1: Update `modules/nixos/auth-blueprints.nix`**

Add `rommBlueprint` after `mealieBlueprint` in the `let` block, and extend `customBlueprintsDir`:

```nix
{ config, pkgs, lib, ... }:
let
  defaultBlueprintsDir =
    "${config.services.authentik.authentikComponents.staticWorkdirDeps}/blueprints";

  mealieBlueprint = pkgs.writeText "mealie.yaml" ''
    version: 1
    metadata:
      name: "Mealie OIDC"
      labels:
        blueprints.goauthentik.io/instantiate: "true"
    entries:
      - model: authentik_core.group
        state: present
        identifiers:
          name: "mealie-user"
        attrs:
          name: "mealie-user"
      - model: authentik_core.group
        state: present
        identifiers:
          name: "mealie-admin"
        attrs:
          name: "mealie-admin"
      - model: authentik_providers_oauth2.oauth2provider
        state: present
        identifiers:
          name: "Mealie Provider"
        attrs:
          authorization_flow: !find [authentik_flows.flow, {slug: "default-provider-authorization-implicit-consent"}]
          client_id: "mealie"
          client_secret: !env_var MEALIE_OIDC_CLIENT_SECRET
          redirect_uris:
            - url: "https://mealie.schenkenberger.dev/"
              matching_mode: prefix
          sub_mode: hashed_user_id
          include_claims_in_id_token: true
          signing_key: !find [authentik_crypto.certificatekeypair, {name: "authentik Self-signed Certificate"}]
      - model: authentik_core.application
        state: present
        identifiers:
          slug: "mealie"
        attrs:
          name: "Mealie"
          slug: "mealie"
          provider: !find [authentik_providers_oauth2.oauth2provider, {name: "Mealie Provider"}]
          policy_engine_mode: any
  '';

  rommBlueprint = pkgs.writeText "romm.yaml" ''
    version: 1
    metadata:
      name: "RomM OIDC"
      labels:
        blueprints.goauthentik.io/instantiate: "true"
    entries:
      - model: authentik_providers_oauth2.oauth2provider
        state: present
        identifiers:
          name: "RomM Provider"
        attrs:
          authorization_flow: !find [authentik_flows.flow, {slug: "default-provider-authorization-implicit-consent"}]
          client_id: "romm"
          client_secret: !env_var ROMM_OIDC_CLIENT_SECRET
          redirect_uris:
            - url: "https://romm.schenkenberger.dev/api/oauth/openid"
              matching_mode: strict
          sub_mode: hashed_user_id
          include_claims_in_id_token: true
          signing_key: !find [authentik_crypto.certificatekeypair, {name: "authentik Self-signed Certificate"}]
      - model: authentik_core.application
        state: present
        identifiers:
          slug: "romm"
        attrs:
          name: "RomM"
          slug: "romm"
          provider: !find [authentik_providers_oauth2.oauth2provider, {name: "RomM Provider"}]
          policy_engine_mode: any
  '';

  customBlueprintsDir = pkgs.runCommand "authentik-blueprints" { } ''
    cp -rL ${defaultBlueprintsDir}/. $out/
    mkdir -p $out/custom
    cp ${mealieBlueprint} $out/custom/mealie.yaml
    cp ${rommBlueprint}   $out/custom/romm.yaml
  '';
in
{
  services.authentik.settings.blueprints_dir = customBlueprintsDir;
}
```

- [ ] **Step 2: Verify eval**

```bash
nix eval .#nixosConfigurations.mangrove.config.services.authentik.settings.blueprints_dir
```

Expected: a new store path.

- [ ] **Step 3: Commit**

```bash
git add modules/nixos/auth-blueprints.nix
git commit -m "auth: add RomM OIDC blueprint (provider, application)"
```

---

### Task 6: Add forward-auth blueprints and embedded outpost binding

**Files:**
- Modify: `modules/nixos/auth-blueprints.nix`

**Interfaces:**
- Produces: Authentik objects — ProxyProvider + Application for Grafana, Sonarr, Radarr, Prowlarr, qBittorrent; embedded outpost updated with all five proxy providers bound to it

The embedded outpost (`"authentik Embedded Outpost"`) is created by Authentik on first boot. The blueprint updates it with `state: present` to bind the proxy providers, which activates the `/outpost.goauthentik.io/auth/caddy` endpoint that Caddy's `authentik_forward_auth` snippet calls. The outpost `providers` list is authoritative — any provider not listed here will be unbound.

- [ ] **Step 1: Update `modules/nixos/auth-blueprints.nix`**

Add `forwardAuthBlueprint` and update `customBlueprintsDir`:

```nix
{ config, pkgs, lib, ... }:
let
  defaultBlueprintsDir =
    "${config.services.authentik.authentikComponents.staticWorkdirDeps}/blueprints";

  mealieBlueprint = pkgs.writeText "mealie.yaml" ''
    version: 1
    metadata:
      name: "Mealie OIDC"
      labels:
        blueprints.goauthentik.io/instantiate: "true"
    entries:
      - model: authentik_core.group
        state: present
        identifiers:
          name: "mealie-user"
        attrs:
          name: "mealie-user"
      - model: authentik_core.group
        state: present
        identifiers:
          name: "mealie-admin"
        attrs:
          name: "mealie-admin"
      - model: authentik_providers_oauth2.oauth2provider
        state: present
        identifiers:
          name: "Mealie Provider"
        attrs:
          authorization_flow: !find [authentik_flows.flow, {slug: "default-provider-authorization-implicit-consent"}]
          client_id: "mealie"
          client_secret: !env_var MEALIE_OIDC_CLIENT_SECRET
          redirect_uris:
            - url: "https://mealie.schenkenberger.dev/"
              matching_mode: prefix
          sub_mode: hashed_user_id
          include_claims_in_id_token: true
          signing_key: !find [authentik_crypto.certificatekeypair, {name: "authentik Self-signed Certificate"}]
      - model: authentik_core.application
        state: present
        identifiers:
          slug: "mealie"
        attrs:
          name: "Mealie"
          slug: "mealie"
          provider: !find [authentik_providers_oauth2.oauth2provider, {name: "Mealie Provider"}]
          policy_engine_mode: any
  '';

  rommBlueprint = pkgs.writeText "romm.yaml" ''
    version: 1
    metadata:
      name: "RomM OIDC"
      labels:
        blueprints.goauthentik.io/instantiate: "true"
    entries:
      - model: authentik_providers_oauth2.oauth2provider
        state: present
        identifiers:
          name: "RomM Provider"
        attrs:
          authorization_flow: !find [authentik_flows.flow, {slug: "default-provider-authorization-implicit-consent"}]
          client_id: "romm"
          client_secret: !env_var ROMM_OIDC_CLIENT_SECRET
          redirect_uris:
            - url: "https://romm.schenkenberger.dev/api/oauth/openid"
              matching_mode: strict
          sub_mode: hashed_user_id
          include_claims_in_id_token: true
          signing_key: !find [authentik_crypto.certificatekeypair, {name: "authentik Self-signed Certificate"}]
      - model: authentik_core.application
        state: present
        identifiers:
          slug: "romm"
        attrs:
          name: "RomM"
          slug: "romm"
          provider: !find [authentik_providers_oauth2.oauth2provider, {name: "RomM Provider"}]
          policy_engine_mode: any
  '';

  forwardAuthBlueprint = pkgs.writeText "forward-auth.yaml" ''
    version: 1
    metadata:
      name: "Forward Auth Services"
      labels:
        blueprints.goauthentik.io/instantiate: "true"
    entries:
      - model: authentik_providers_proxy.proxyprovider
        state: present
        identifiers:
          name: "Grafana Provider"
        attrs:
          authorization_flow: !find [authentik_flows.flow, {slug: "default-provider-authorization-implicit-consent"}]
          external_host: "https://grafana.schenkenberger.dev"
          mode: forward_single
          cookie_domain: "schenkenberger.dev"
      - model: authentik_core.application
        state: present
        identifiers:
          slug: "grafana"
        attrs:
          name: "Grafana"
          slug: "grafana"
          provider: !find [authentik_providers_proxy.proxyprovider, {name: "Grafana Provider"}]
          policy_engine_mode: any
      - model: authentik_providers_proxy.proxyprovider
        state: present
        identifiers:
          name: "Sonarr Provider"
        attrs:
          authorization_flow: !find [authentik_flows.flow, {slug: "default-provider-authorization-implicit-consent"}]
          external_host: "https://sonarr.schenkenberger.dev"
          mode: forward_single
          cookie_domain: "schenkenberger.dev"
      - model: authentik_core.application
        state: present
        identifiers:
          slug: "sonarr"
        attrs:
          name: "Sonarr"
          slug: "sonarr"
          provider: !find [authentik_providers_proxy.proxyprovider, {name: "Sonarr Provider"}]
          policy_engine_mode: any
      - model: authentik_providers_proxy.proxyprovider
        state: present
        identifiers:
          name: "Radarr Provider"
        attrs:
          authorization_flow: !find [authentik_flows.flow, {slug: "default-provider-authorization-implicit-consent"}]
          external_host: "https://radarr.schenkenberger.dev"
          mode: forward_single
          cookie_domain: "schenkenberger.dev"
      - model: authentik_core.application
        state: present
        identifiers:
          slug: "radarr"
        attrs:
          name: "Radarr"
          slug: "radarr"
          provider: !find [authentik_providers_proxy.proxyprovider, {name: "Radarr Provider"}]
          policy_engine_mode: any
      - model: authentik_providers_proxy.proxyprovider
        state: present
        identifiers:
          name: "Prowlarr Provider"
        attrs:
          authorization_flow: !find [authentik_flows.flow, {slug: "default-provider-authorization-implicit-consent"}]
          external_host: "https://prowlarr.schenkenberger.dev"
          mode: forward_single
          cookie_domain: "schenkenberger.dev"
      - model: authentik_core.application
        state: present
        identifiers:
          slug: "prowlarr"
        attrs:
          name: "Prowlarr"
          slug: "prowlarr"
          provider: !find [authentik_providers_proxy.proxyprovider, {name: "Prowlarr Provider"}]
          policy_engine_mode: any
      - model: authentik_providers_proxy.proxyprovider
        state: present
        identifiers:
          name: "qBittorrent Provider"
        attrs:
          authorization_flow: !find [authentik_flows.flow, {slug: "default-provider-authorization-implicit-consent"}]
          external_host: "https://qbit.schenkenberger.dev"
          mode: forward_single
          cookie_domain: "schenkenberger.dev"
      - model: authentik_core.application
        state: present
        identifiers:
          slug: "qbittorrent"
        attrs:
          name: "qBittorrent"
          slug: "qbittorrent"
          provider: !find [authentik_providers_proxy.proxyprovider, {name: "qBittorrent Provider"}]
          policy_engine_mode: any
      - model: authentik_outposts.outpost
        state: present
        identifiers:
          name: "authentik Embedded Outpost"
        attrs:
          providers:
            - !find [authentik_providers_proxy.proxyprovider, {name: "Grafana Provider"}]
            - !find [authentik_providers_proxy.proxyprovider, {name: "Sonarr Provider"}]
            - !find [authentik_providers_proxy.proxyprovider, {name: "Radarr Provider"}]
            - !find [authentik_providers_proxy.proxyprovider, {name: "Prowlarr Provider"}]
            - !find [authentik_providers_proxy.proxyprovider, {name: "qBittorrent Provider"}]
  '';

  customBlueprintsDir = pkgs.runCommand "authentik-blueprints" { } ''
    cp -rL ${defaultBlueprintsDir}/. $out/
    mkdir -p $out/custom
    cp ${mealieBlueprint}       $out/custom/mealie.yaml
    cp ${rommBlueprint}         $out/custom/romm.yaml
    cp ${forwardAuthBlueprint}  $out/custom/forward-auth.yaml
  '';
in
{
  services.authentik.settings.blueprints_dir = customBlueprintsDir;
}
```

- [ ] **Step 2: Verify eval**

```bash
nix eval .#nixosConfigurations.mangrove.config.services.authentik.settings.blueprints_dir
```

Expected: a new store path.

- [ ] **Step 3: Inspect the generated blueprint directory in the Nix store**

```bash
STORE_PATH=$(nix eval --raw .#nixosConfigurations.mangrove.config.services.authentik.settings.blueprints_dir)
ls "$STORE_PATH/custom/"
```

Expected output:
```
forward-auth.yaml  mealie.yaml  romm.yaml
```

- [ ] **Step 4: Commit**

```bash
git add modules/nixos/auth-blueprints.nix
git commit -m "auth: add forward-auth blueprints and embedded outpost binding"
```

---

### Task 7: Deploy and verify

**Files:** none (deployment only)

- [ ] **Step 1: Build the system closure without switching**

```bash
nixos-rebuild build --flake .#mangrove
```

Expected: exits 0, prints a store path.

- [ ] **Step 2: Switch**

```bash
sudo nixos-rebuild switch --flake .#mangrove
```

Expected: activates without errors.

- [ ] **Step 3: Check Authentik picked up the blueprints directory**

```bash
sudo systemctl status authentik.service | grep blueprints
```

Or check the Authentik log for blueprint application messages:

```bash
sudo journalctl -u authentik.service -n 50 | grep -i blueprint
```

Expected: log lines indicating blueprints were found and applied (status "Successful").

- [ ] **Step 4: Verify blueprints in the Authentik admin UI**

Navigate to `https://auth.schenkenberger.dev/if/admin/#/core/blueprints`.

Expected: five blueprints listed:
- `Mealie OIDC` — Status: Successful
- `RomM OIDC` — Status: Successful
- `Forward Auth Services` — Status: Successful
- (plus Authentik's default system/default blueprints)

- [ ] **Step 5: Verify OIDC login for Mealie**

Visit `https://mealie.schenkenberger.dev`. You should be redirected to Authentik, then back to Mealie after login.

- [ ] **Step 6: Verify forward auth for Grafana**

Visit `https://grafana.schenkenberger.dev`. You should be redirected to Authentik for SSO before reaching Grafana.

- [ ] **Step 7: Troubleshoot if a blueprint shows "Error" status**

If any blueprint fails, check the Authentik worker log:

```bash
sudo journalctl -u authentik-worker.service -n 100 | grep -i "blueprint\|error"
```

Common issues and fixes:
- `"authentik Self-signed Certificate" not found` — The signing key name differs; check under Authentik admin → Crypto → Certificates and update the `!find` name in the blueprint
- `env_var MEALIE_OIDC_CLIENT_SECRET not set` — The env template didn't reload; run `sudo systemctl restart authentik.service authentik-worker.service`
- `"default-provider-authorization-implicit-consent" not found` — The default flow slug differs in this Authentik version; check under Flows and update the `!find` slug

---

## Notes on Blueprint Schema Compatibility

The blueprint YAML in this plan targets Authentik 2024.2+ field formats:
- `redirect_uris` is a list of `{url, matching_mode}` objects (not plain strings)
- `mode: forward_single` for single-domain proxy providers

If the `authentik-nix` flake ships an older Authentik version, `redirect_uris` may need to revert to a flat list of strings:
```yaml
redirect_uris: "https://mealie.schenkenberger.dev/\nhttps://mealie.schenkenberger.dev/auth/callback"
```
Check `nix eval .#nixosConfigurations.mangrove.config.services.authentik.authentikComponents` for the Authentik version.
