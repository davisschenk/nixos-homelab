# Current Homelab Overview

## Hardware

| Component | Spec |
|-----------|------|
| CPU | Intel i5-12600K (includes UHD 770 iGPU) |
| RAM | 64GB |
| M.2 | 1TB |
| HDD | 8TB |
| GPU | Dedicated (used for gaming) |

## Proxmox Setup

- **Docker LXC** — all services running via Docker Compose, managed by Komodo (`ssh server`)
- **Wings LXC** — Pterodactyl Wings for game server management

## Services

| Service | Purpose |
|---------|---------|
| authentik | SSO / identity provider |
| caddy | Reverse proxy (Cloudflare DNS plugin + ACME) |
| cloudflared | Cloudflare Tunnel for external access |
| jellyfin | Media server |
| mealie | Recipe manager |
| romm | ROM manager |
| arr stack | Media automation (Sonarr/Radarr/etc.) |
| qbittorrent | Torrent client (routed through gluetun VPN) |
| tilt | (to be backed up) |
| actual | Budget/finance |
| copyparty | File sharing |
| bar | Dashboard |
| dozzle | Docker log viewer |
| monitoring | Prometheus/Grafana stack |
| komodo | Container management |
| pelican | Game server panel (Pterodactyl successor) |
| vpn | Gluetun — tunnels torrent/arr traffic through VPN provider |

## Networking

- Domain: `schenkenberger.dev` (Cloudflare)
- External access: Cloudflare Tunnel (`cloudflared`) → Caddy reverse proxy
- TLS: Caddy handles ACME via Cloudflare DNS challenge
- Internal: Docker bridge networks (`cloudflare`, `authentik`)
- VPN: Gluetun container-level VPN for arr/qbittorrent (no host-level VPN)

## Important Data to Backup Before Reset

- **Authentik** — users, flows, policies, OAuth apps
- **Tilt** — app data
- **Mealie** — recipes

## Notes

- Wings → Pelican migration already in progress
- iGPU (UHD 770) available for Jellyfin QuickSync once dGPU is passed through to Windows VM
