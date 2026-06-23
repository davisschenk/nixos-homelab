# Authentik Blueprint Icons Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `icon` fields to all seven `authentik_core.application` blueprint entries so apps appear with logos in the Authentik user portal.

**Architecture:** One `icon:` line added per application in the existing blueprint YAML strings inside `modules/nixos/auth-blueprints.nix`. Icons are served from the walkxcode/dashboard-icons repo via jsdelivr CDN — no build-time fetching, no new Nix infrastructure.

**Tech Stack:** NixOS module system, Authentik Blueprints (YAML), jsdelivr CDN

## Global Constraints

- All changes must `nix eval .#nixosConfigurations.mangrove` without errors before commit
- Icon URL pattern: `https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons@main/png/<name>.png`
- Blueprint entries use `state: present` — Authentik upserts on re-apply, no manual cleanup needed

---

### Task 1: Add icons to all application blueprints

**Files:**
- Modify: `modules/nixos/auth-blueprints.nix`

**Interfaces:**
- Consumes: existing `authentik_core.application` attrs blocks (one per app)
- Produces: `icon` field populated on all seven Authentik application objects after next blueprint apply

- [ ] **Step 1: Add `icon` to the Mealie application entry**

In `modules/nixos/auth-blueprints.nix`, find the `authentik_core.application` entry with `slug: "mealie"` (inside `mealieBlueprint`) and add the `icon` line:

```yaml
      - model: authentik_core.application
        state: present
        identifiers:
          slug: "mealie"
        attrs:
          name: "Mealie"
          slug: "mealie"
          icon: "https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons@main/png/mealie.png"
          provider: !Find [authentik_providers_oauth2.oauth2provider, [name, Mealie Provider]]
          policy_engine_mode: any
```

- [ ] **Step 2: Add `icon` to the RomM application entry**

In `rommBlueprint`, find the `authentik_core.application` entry with `slug: "romm"` and add the `icon` line:

```yaml
      - model: authentik_core.application
        state: present
        identifiers:
          slug: "romm"
        attrs:
          name: "RomM"
          slug: "romm"
          icon: "https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons@main/png/romm.png"
          provider: !Find [authentik_providers_oauth2.oauth2provider, [name, RomM Provider]]
          policy_engine_mode: any
```

- [ ] **Step 3: Add `icon` to all five forward-auth application entries**

In `forwardAuthBlueprint`, add the `icon` line to each `authentik_core.application` entry:

```yaml
      - model: authentik_core.application
        state: present
        identifiers:
          slug: "grafana"
        attrs:
          name: "Grafana"
          slug: "grafana"
          icon: "https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons@main/png/grafana.png"
          provider: !Find [authentik_providers_proxy.proxyprovider, [name, Grafana Provider]]
          policy_engine_mode: any
      ...
      - model: authentik_core.application
        state: present
        identifiers:
          slug: "sonarr"
        attrs:
          name: "Sonarr"
          slug: "sonarr"
          icon: "https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons@main/png/sonarr.png"
          provider: !Find [authentik_providers_proxy.proxyprovider, [name, Sonarr Provider]]
          policy_engine_mode: any
      ...
      - model: authentik_core.application
        state: present
        identifiers:
          slug: "radarr"
        attrs:
          name: "Radarr"
          slug: "radarr"
          icon: "https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons@main/png/radarr.png"
          provider: !Find [authentik_providers_proxy.proxyprovider, [name, Radarr Provider]]
          policy_engine_mode: any
      ...
      - model: authentik_core.application
        state: present
        identifiers:
          slug: "prowlarr"
        attrs:
          name: "Prowlarr"
          slug: "prowlarr"
          icon: "https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons@main/png/prowlarr.png"
          provider: !Find [authentik_providers_proxy.proxyprovider, [name, Prowlarr Provider]]
          policy_engine_mode: any
      ...
      - model: authentik_core.application
        state: present
        identifiers:
          slug: "qbittorrent"
        attrs:
          name: "qBittorrent"
          slug: "qbittorrent"
          icon: "https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons@main/png/qbittorrent.png"
          provider: !Find [authentik_providers_proxy.proxyprovider, [name, qBittorrent Provider]]
          policy_engine_mode: any
```

- [ ] **Step 4: Verify Nix eval passes**

```bash
nix eval .#nixosConfigurations.mangrove.config.services.authentik.settings.blueprints_dir
```

Expected: prints a `/nix/store/...-authentik-blueprints` path with no errors.

- [ ] **Step 5: Inspect the generated blueprint files contain the icon lines**

```bash
STORE_PATH=$(nix eval --raw .#nixosConfigurations.mangrove.config.services.authentik.settings.blueprints_dir)
grep -r "icon:" "$STORE_PATH/custom/"
```

Expected output (7 lines, one per app):
```
/nix/store/.../custom/mealie.yaml:          icon: "https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons@main/png/mealie.png"
/nix/store/.../custom/romm.yaml:          icon: "https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons@main/png/romm.png"
/nix/store/.../custom/forward-auth.yaml:          icon: "https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons@main/png/grafana.png"
/nix/store/.../custom/forward-auth.yaml:          icon: "https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons@main/png/sonarr.png"
/nix/store/.../custom/forward-auth.yaml:          icon: "https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons@main/png/radarr.png"
/nix/store/.../custom/forward-auth.yaml:          icon: "https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons@main/png/prowlarr.png"
/nix/store/.../custom/forward-auth.yaml:          icon: "https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons@main/png/qbittorrent.png"
```

- [ ] **Step 6: Commit**

```bash
git add modules/nixos/auth-blueprints.nix
git commit -m "auth: add dashboard icons to all authentik application blueprints"
```

- [ ] **Step 7: Deploy and verify**

```bash
sudo nixos-rebuild switch --flake .#mangrove
```

Then in the Authentik admin UI navigate to **System → Blueprints** and confirm all three custom blueprints show status **Successful**. Open the user portal (`https://auth.schenkenberger.dev`) and confirm all seven apps display their icons.
