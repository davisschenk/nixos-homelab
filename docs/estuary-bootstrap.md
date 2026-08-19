# Estuary bootstrap

`estuary` is created by Terraform as an OVHcloud VPS-1 in Hillsboro and then replaced in place with NixOS.

## Account setup

1. In the HCP Terraform organization `davisschenk-homelab`, project `nixos-homelab-production`, create the workspace `nixos-homelab-production` and set it to local execution.
2. Create a GitHub `planning` environment containing read-only OVH, Cloudflare, and HCP credentials.
3. Create a protected `production` environment requiring approval with self-review allowed.
4. Add the production OVH, Cloudflare, and HCP credentials listed in `.github/workflows/production.yml`.
5. Set `TF_BOOTSTRAP_SSH_CIDR` to the administrator's current public IPv4 CIDR and leave `TF_BOOTSTRAP_COMPLETE=false`.

Use workspace-scoped team tokens for `TFE_PLAN_TOKEN` and `TFE_TOKEN` when the HCP Terraform tier supports team management. On tiers without team management, use separate expiring user tokens and rotate them independently; the planning workflow remains plan-only, but its token inherits the user's HCP permissions.

The generated CI keys are under `/home/davis/.config/nixos-homelab/bootstrap`:

- Store `ci-wireguard.key` as the production secret `CI_WIREGUARD_PRIVATE_KEY`.
- Store `ci-deploy-ed25519` as the production secret `CI_SSH_DEPLOY_KEY`.
- Back up `estuary-age-key.txt` in Bitwarden Secrets Manager before creating the VPS.

## First installation

1. Merge and approve the production workflow with `TF_BOOTSTRAP_COMPLETE=false`.
2. Read `estuary_ipv4` from the Terraform outputs and retrieve OVH's temporary Debian password.
3. Install the administrator SSH key on Debian.
4. Copy `estuary-age-key.txt` into a temporary tree at `var/lib/sops-nix/key.txt` with mode 0600.
5. Run nixos-anywhere with that tree:

```sh
nix run github:nix-community/nixos-anywhere -- \
  --flake .#estuary \
  --extra-files /path/to/temporary-tree \
  root@ESTUARY_IPV4
```

6. Remove the temporary tree containing `estuary-age-key.txt`.
7. Run the final manual `just deploy` from the home LAN to enable WireGuard on `mangrove`.
8. Verify that `wg show wg-estuary` reports a current handshake on both hosts.
9. Set `TF_BOOTSTRAP_COMPLETE=true` and approve the next production workflow.

Public SSH is removed at the OVH edge after step 9. Subsequent deployments use the ephemeral GitHub-hosted WireGuard peer and deploy-rs.
