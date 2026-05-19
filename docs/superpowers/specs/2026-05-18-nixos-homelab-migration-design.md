# NixOS Homelab Migration Design

**Date:** 2026-05-18
**Host:** mangrove
**Migration from:** Proxmox + Docker LXC

---

## Hardware

| Component | Spec |
|-----------|------|
| CPU | Intel i5-12600K (UHD 770 iGPU) |
| RAM | 64GB |
| M.2 | 1TB (OS drive) |
| HDD | 8TB (data drive) |
| GPU | Dedicated (passed through to Windows VM) |

---

## Repository Structure

```
nixos-homelab/
├── flake.nix
├── flake.lock
├── hosts/
│   └── mangrove/
│       ├── default.nix
│       ├── hardware-configuration.nix
│       └── vm/
│           └── windows.xml
├── modules/
│   └── nixos/
│       ├── default.nix
│       ├── base.nix
│       ├── networking.nix
│       ├── media.nix
│       ├── arr.nix
│       ├── auth.nix
│       ├── monitoring.nix
│       ├── containers.nix
│       ├── gaming-vm.nix
│       └── pelican.nix
├── secrets/
│   ├── .sops.yaml
│   ├── cloudflare-tunnel.yaml
│   └── vpn.yaml
└── docs/
    └── superpowers/specs/
```

### Flake Inputs

| Input | Purpose |
|-------|---------|
| `nixpkgs` (nixos-unstable) | Base packages |
| `nixarr` | arr stack + VPN network namespace |
| `authentik-nix` | Authentik NixOS module (community) |
| `sops-nix` | Secrets decryption at activation |
| `disko` | Declarative disk partitioning |
| `nixos-impermanence` | Root wipe + persist bind-mounts |
| `home-manager` | Ready for personal machines later |

---

## Disk Layout

### 1TB M.2 — OS Drive (`/dev/nvme0n1`)

Managed by disko, declared in `hosts/mangrove/default.nix`.

```
/dev/nvme0n1
├── EFI     512MB   vfat   → /boot
└── root    ~999GB  btrfs
    ├── @          → /          (wiped on each boot via blank snapshot rollback)
    ├── @nix       → /nix
    ├── @home      → /home
    └── @persist   → /persist
```

### 8TB HDD — Data Drive (`/dev/sda`)

```
/dev/sda
└── data    8TB     btrfs (zstd compression)
    ├── @media     → /data/media      (Jellyfin library, ROMs)
    ├── @downloads → /data/downloads  (qbittorrent output)
    └── @backups   → /data/backups
```

### Impermanence

Root (`/`) is rolled back to a blank btrfs snapshot on every boot via `nixos-impermanence`. All stateful data is explicitly bind-mounted from `/persist` using `environment.persistence."/persist"`.

**Persisted paths:**

| Path | Contents |
|------|----------|
| `/persist/etc/ssh` | SSH host keys |
| `/persist/var/lib/jellyfin` | Jellyfin metadata & config |
| `/persist/var/lib/authentik` | Authentik state |
| `/persist/var/lib/postgresql` | Authentik's PostgreSQL DB |
| `/persist/var/lib/prometheus` | Prometheus TSDB |
| `/persist/var/lib/grafana` | Grafana dashboards & config |
| `/persist/containers/` | oci-container bind-mount volumes |
| `/persist/var/lib/libvirt` | VM definitions |

VM disk image lives at `/data/vm/windows.qcow2` (too large for `/persist`).

---

## Services

### Native NixOS Modules

| Service | Module | Notes |
|---------|--------|-------|
| Jellyfin | `services.jellyfin` | iGPU QSV via `hardware.opengl` + render group |
| Caddy | `services.caddy` | HTTP only (no TLS — Cloudflare Tunnel handles it) |
| cloudflared | `services.cloudflared` | Tunnel token from sops-nix |
| Prometheus | `services.prometheus` | |
| Grafana | `services.grafana` | |

### nixarr (community flake)

Handles Sonarr, Radarr, Prowlarr, and qbittorrent inside a WireGuard-based VPN network namespace. The arr stack has no direct bridge to the main network — all outbound traffic is routed through the VPN.

VPN credentials stored in `secrets/vpn.yaml` (sops-nix).

### authentik-nix (community flake)

Authentik runs natively (no Docker). PostgreSQL is managed by the module. State persisted at `/persist/var/lib/authentik` and `/persist/var/lib/postgresql`.

### oci-containers (`virtualisation.oci-containers`)

Nix-declared Docker/Podman containers sharing a `homelab` bridge network.

| Service | Image | Data volume |
|---------|-------|-------------|
| Mealie | `ghcr.io/mealie-recipes/mealie` | `/persist/containers/mealie` |
| Romm | `rommapp/romm` | `/persist/containers/romm` |
| Actual | `actualbudget/actual-server` | `/persist/containers/actual` |
| Copyparty | `copyparty/copyparty` | `/persist/containers/copyparty` |
| Komodo | `ghcr.io/moghtech/komodo` | `/persist/containers/komodo` |
| Dozzle | `amir20/dozzle` | — (read-only Docker socket) |
| Bar/dashboard | (current image) | `/persist/containers/bar` |
| Pelican panel | (pelican image) | `/persist/containers/pelican` |

---

## Networking

### Traffic Flow

```
Internet
  └── Cloudflare Edge (TLS terminated here)
        └── Cloudflare Tunnel / cloudflared (encrypted)
              └── Caddy (HTTP, loopback only)
                    ├── Authentik (forward auth for protected routes)
                    └── Services (Jellyfin, Grafana, Mealie, etc.)
```

All public-facing services go through the Cloudflare Tunnel. Caddy does not bind to any public interface and has no TLS configuration — Cloudflare handles all encryption.

### Firewall

- Caddy listens on loopback only — no firewall rule needed (loopback is not filtered)
- Port 22 (or custom) open for SSH
- libvirt bridge managed automatically by NixOS
- All other ports closed by default (`networking.firewall.enable = true`)

### Authentik Forward Auth

Protected services route through Caddy's `forward_auth` directive pointing to Authentik. Authentik is exposed at `auth.schenkenberger.dev` via the tunnel.

---

## Windows Gaming VM & GPU Passthrough

### GPU Assignment

- **dGPU** → bound to `vfio-pci` at boot, passed through to Windows VM
- **iGPU (UHD 770)** → stays with host, used by Jellyfin for QuickSync (QSV)

### NixOS Configuration (`gaming-vm.nix`)

```nix
boot.kernelParams = [ "intel_iommu=on" "iommu=pt" ];
boot.kernelModules = [ "vfio" "vfio_iommu_type1" "vfio_pci" ];
boot.extraModprobeConfig = "options vfio-pci ids=<dGPU-id>,<dGPU-audio-id>";

virtualisation.libvirtd.enable = true;
```

dGPU PCI IDs are filled in after running `lspci` on the first boot. Stored as a variable in `hosts/mangrove/default.nix`.

### VM Declaration

VM defined as libvirt XML at `hosts/mangrove/vm/windows.xml`, activated via a NixOS activation script. VM disk at `/data/vm/windows.qcow2`.

### IOMMU Grouping Caveat

i5-12600K IOMMU grouping must be verified after install. If the dGPU shares a group with other devices, the `pcie_acs_override=downstream,multifunction` kernel parameter may be needed.

### Jellyfin iGPU (QSV)

```nix
hardware.opengl.enable = true;
hardware.opengl.extraPackages = [ pkgs.intel-media-driver ];
users.users.jellyfin.extraGroups = [ "render" "video" ];
```

On NixOS 25.11+, vpl/FFmpeg support is enabled by default — no overlay required.

---

## Secrets Management

**Tool:** sops-nix

All secrets encrypted with age keys in the `secrets/` directory. `.sops.yaml` declares which keys can decrypt which files.

| Secret file | Contents |
|-------------|----------|
| `secrets/cloudflare-tunnel.yaml` | cloudflared tunnel token |
| `secrets/vpn.yaml` | VPN provider WireGuard credentials |

Secrets are decrypted at NixOS activation and made available to services via `config.sops.secrets.<name>.path`.

---

## Migration Checklist (pre-reset)

Before wiping the Proxmox host, back up:

- [ ] Authentik — users, flows, policies, OAuth app configs
- [ ] Mealie — recipe export
- [ ] Actual — budget data export
- [ ] All oci-container volume data
- [ ] Cloudflare Tunnel token
- [ ] VPN provider WireGuard config
- [ ] SSH keys (if reusing)
