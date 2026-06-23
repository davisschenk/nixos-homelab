# Authentik Blueprint Icons

## Context

`modules/nixos/auth-blueprints.nix` declares all Authentik applications as blueprints but does not set an icon on any of them. This design adds icons to all seven applications so they appear with logos in the Authentik user portal.

## Approach

Add an `icon` field to the `attrs` block of each `authentik_core.application` entry, pointing to [dashboard-icons](https://github.com/walkxcode/dashboard-icons) via jsdelivr CDN. All seven apps are present in that repo.

Self-hosted fallback (copying icons into Authentik's media directory via `pkgs.fetchurl`) was considered but ruled out — dashboard-icons via jsdelivr has high availability and all apps are covered, so the added Nix build complexity isn't warranted.

## Change

**File:** `modules/nixos/auth-blueprints.nix` — 7 lines added, one `icon:` field per application.

**Icon URL pattern:** `https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons@main/png/<name>.png`

| Application | Icon filename |
|-------------|---------------|
| Mealie | `mealie.png` |
| RomM | `romm.png` |
| Grafana | `grafana.png` |
| Sonarr | `sonarr.png` |
| Radarr | `radarr.png` |
| Prowlarr | `prowlarr.png` |
| qBittorrent | `qbittorrent.png` |

The blueprint uses `state: present`, so Authentik upserts the `icon` field onto existing application objects on next blueprint re-apply — no manual cleanup needed.

## Verification

1. `nix eval .#nixosConfigurations.mangrove.config.services.authentik.settings.blueprints_dir` — should succeed
2. After `nixos-rebuild switch`, check Authentik admin → Blueprints — all three custom blueprints show "Successful"
3. Open the Authentik user portal — all seven apps show their icons
