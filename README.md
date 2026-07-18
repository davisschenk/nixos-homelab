# mangrove homelab

NixOS flake for `mangrove` — a self-hosted homelab server with impermanence (btrfs root wipe on boot), SOPS-encrypted secrets, and Cloudflare Tunnel ingress.

## Hardware

| Component | Device |
|-----------|--------|
| NVMe (OS) | `/dev/nvme0n1` — btrfs, root + persist + nix + home |
| HDD (data) | `/dev/sda` — btrfs, media / downloads / backups / vm |

## Services

| Service | URL | Description |
|---------|-----|-------------|
| Authentik | `auth.schenkenberger.dev` | SSO / identity provider |
| Grafana | `grafana.schenkenberger.dev` | Metrics dashboards |
| Mealie | `mealie.schenkenberger.dev` | Recipe manager |
| RomM | `romm.schenkenberger.dev` | ROM manager |
| Pelican Panel | `panel.schenkenberger.dev` | Game server panel |
| Sonarr | `sonarr.schenkenberger.dev` | TV series manager |
| Radarr | `radarr.schenkenberger.dev` | Movie manager |
| Prowlarr | `prowlarr.schenkenberger.dev` | Indexer manager |
| qBittorrent | `qbit.schenkenberger.dev` | Torrent client |
| Actual Budget | `actual.schenkenberger.dev` | Budget manager |
| Tilt Hydrometer Platform | `tilt.schenkenberger.dev` | Fermentation monitor |
| Copyparty | `copyparty.schenkenberger.dev` | File server |

All services are accessed via Cloudflare Tunnel → Caddy reverse proxy. No ports are exposed directly to the internet.

## Repository Layout

```
hosts/mangrove/
  default.nix            # Host-specific config (bootloader, GPU passthrough)
  hardware-configuration.nix
  disko.nix              # Disk partitioning layout

modules/nixos/
  base.nix               # Users, SSH, firewall, impermanence, btrfs wipe
  networking.nix         # Cloudflare Tunnel + Caddy reverse proxy
  auth.nix               # Authentik SSO
  monitoring.nix         # Prometheus + Grafana
  backup.nix             # Restic backups to local /data/backups
  arr.nix                # Sonarr / Radarr / Prowlarr / qBittorrent (VPN)
  media.nix              # Jellyfin
  mealie.nix             # Recipe manager
  romm.nix               # ROM manager (Docker)
  pelican.nix            # Pelican Panel + Wings
  gaming-vm.nix          # libvirt / QEMU / VFIO GPU passthrough
  actual.nix             # Actual Budget
  tilt.nix               # Tilt Hydrometer Platform (Docker + PostgreSQL)
  copyparty.nix          # File server
  ports.nix              # Centralised port assignments

secrets/                 # SOPS-encrypted secrets (age key)
```

## Prerequisites

- [Nix](https://nixos.org/download) with flakes enabled
- [just](https://github.com/casey/just)
- [BWS CLI](https://bitwarden.com/help/secrets-manager-cli/) (`bws`) + `BWS_ACCESS_TOKEN` for bootstrapping the age key

## First-Time Setup (from this workstation)

### 1. Restore the SOPS age key

```bash
export BWS_ACCESS_TOKEN=<your-token>
just bootstrap-age-key
```

This writes the age key to `~/.config/sops/age/keys.txt` so SOPS can decrypt secrets.

### 2. Push changes to GitHub

The installer ISO pulls the flake from `github:davisschenk/nixos-homelab`, so all changes must be pushed first:

```bash
git push origin master
```

### 3. Build the installer ISO

```bash
just build-iso
# produces result/iso/mangrove-installer.iso
```

### 4. Flash to USB

```bash
# Check your USB drive with: lsblk
sudo dd if=result/iso/mangrove-installer.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

### 5. Install

1. Boot `mangrove` from the USB
2. Run:
   ```bash
   install-mangrove
   ```
   This will **erase `/dev/nvme0n1` and `/dev/sda`** and install NixOS from GitHub.
3. Reboot when prompted

### 6. First SSH access

```bash
ssh davis@mangrove.local
```

Uses the ed25519 key already baked into the config. No password needed.

### 7. Bootstrap SOPS age key on the new machine

The age key must be present at `/persist/etc/sops/age/keys.txt` before secrets can be decrypted at runtime:

```bash
ssh davis@mangrove.local
export BWS_ACCESS_TOKEN=<your-token>
just bootstrap-age-key   # run from a clone of the repo on the server,
                         # or manually write the key to the path above
```

Then restart any services that depend on SOPS secrets.

## Day-to-Day Operations

```bash
just deploy          # Build + deploy to mangrove over SSH
just dry-run         # Preview what would change without activating
just check           # Evaluate the flake (catch errors)
just lint            # Run statix + deadnix linters
just lint-fix        # Auto-fix lint warnings
just fmt             # Format all .nix files with nixfmt
just update          # Update all flake inputs
just edit <secret>   # Edit a SOPS secret (e.g. just edit authentik)
just view <secret>   # View a decrypted secret read-only
just rekey           # Re-encrypt all secrets after rotating age key
just check-secrets   # Verify all secret files are encrypted
```

## Secrets

Secrets are encrypted with [SOPS](https://github.com/getsops/sops) using an age key. The key is stored in Bitwarden Secrets Manager and can be restored with `just bootstrap-age-key`.

| File | Contents |
|------|----------|
| `secrets/authentik.yaml` | Authentik secret key |
| `secrets/mail.yaml` | Shared mail credentials (Mailjet) |
| `secrets/grafana.yaml` | Grafana secret key |
| `secrets/mealie.yaml` | Mealie OIDC client secret, OpenAI key |
| `secrets/coder.yaml` | Coder OIDC client secret, template-push API token, GitHub external-auth client id/secret |
| `secrets/pelican.yaml` | Pelican app key, DB password, Wings token |
| `secrets/romm.yaml` | RomM DB password, auth secret, IGDB keys |
| `secrets/restic.yaml` | Restic repository path + password |
| `secrets/vpn.yaml` | WireGuard VPN config for arr stack |
| `secrets/cloudflare-tunnel.yaml` | Cloudflare Tunnel token |

## Architecture Notes

- **Impermanence**: `/` is wiped on every boot (btrfs `@` subvolume recreated). Only `/persist`, `/nix`, `/home`, and `/var/log` survive reboots.
- **Ingress**: All traffic enters via Cloudflare Tunnel. Caddy handles TLS termination and reverse proxying. No ports are open to the internet.
- **SSO**: Most services use Authentik forward auth via Caddy.
- **Backups**: Restic backs up to `/data/backups/restic` on the local 8TB drive.
- **GPU passthrough**: AMD Radeon 540/550 (`1002:699f`, `1002:aae0`) is passed to a Windows gaming VM via VFIO.
