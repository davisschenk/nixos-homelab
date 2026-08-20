# Agent notes for this repo

Conventions for anyone (human or agent) editing this NixOS flake.

## Development workflow

1. Start from current `master` on a focused feature branch.
2. Keep unrelated working-tree changes untouched and never commit plaintext secrets.
3. Run `just fmt-check` and `just lint` for every Nix change.
4. Evaluate or build the affected host locally. Run `just test-ingress` for WireGuard,
   nftables, DNAT, source-IP preservation, or policy-routing changes.
5. Open a PR and let the path-filtered checks finish. Terraform PRs must complete
   their protected plan/apply job before merge.
6. Deploy by merging to protected `master`. The production workflow applies
   Terraform, joins WireGuard from an ephemeral runner, deploys Estuary and then
   Mangrove, and removes its credentials.

CI deliberately limits ordinary Nix PRs to formatting and linting. Full builds and
VM tests are local, risk-based checks; do not remove them merely because CI skips
them. Use manual `just deploy` only for bootstrap or recovery.

## Shared contracts

- `infra/ingress.json` is the only source of truth for public forwarded ports.
  Terraform and Nix consume it; never duplicate ingress ranges elsewhere.
- `modules/common/wireguard.nix` owns the hub/spoke topology and forwarding rules.
- Keep public IPs and other unbounded values in log bodies, not Loki labels.
- Reuse `modules/common/dbip-city.nix` for GeoIP enrichment and include visible
  DB-IP attribution on dashboards that display its data.
- Estuary is stateless and must not receive Mangrove service secrets.

## Comments — last resort, not documentation

Default to **no comments**. Well-named options and small module files should
read as self-explanatory — don't narrate what a line does.

Write one only when something is genuinely non-obvious: a workaround, an
ordering dependency, a footgun already hit once. State the *why* in one line.
If it needs more than one line, that's a sign the code should be clearer
instead, or the reasoning belongs in the commit message, not the file.

Good (terse, explains a hidden constraint):
```nix
# Issuer must keep the trailing slash — strict issuer validation.
```

Avoid (paragraph narrating a debugging story — put this in the commit
message instead):
```nix
# (Deliberately not touching CODER_EXTERNAL_AUTH_GITHUB_DEFAULT_PROVIDER_ENABLE
# here — despite being a real, separately-documented flag, setting it
# crashes coderd with "read external auth providers from env: parse
# number: GITHUB_DEFAULT_PROVIDER_ENABLE" ...
```

## Module structure

A typical service module (`modules/nixos/<service>.nix` or `<service>/default.nix`):

- `sops.secrets."<service>_<name>"` → `sops.templates."<service>-env"` (interpolates
  placeholders, sets `restartUnits`)
- Service block (`services.<x>` or `virtualisation.oci-containers.containers.<x>`),
  port from `modules/nixos/ports.nix`'s `mylab.ports.<service>`, OIDC via Authentik
- `systemd.tmpfiles.rules` for data dir perms
- `environment.persistence."/persist".directories`

Authentik integration is separate: a blueprint at
`modules/nixos/authentik/blueprints/<name>.yaml`, registered in `blueprintNames`
in `blueprints.nix`. Caddy routes live centrally in `networking.nix`, not
per-module.

## Naming

- Nix files: lowercase, matching the service name.
- Sops secrets: snake_case, service-prefixed (`coder_oidc_client_secret`).
- Systemd oneshots: `<service>-<verb>` (`coder-templates-push`).

## Tooling

- `just fmt` / `just fmt-check` — nixfmt
- `just lint` / `just lint-fix` — statix + deadnix
- `just validate-ingress` — validate the shared ingress contract
- `just build` / `just build-estuary` — build the affected host
- `just test-ingress` — run the three-node forwarding VM test
- `just check` — broad flake and deploy-rs evaluation
- `just deploy` / `just dry-run` — manual recovery paths

For fast config validation without a full build:
```
nix eval --apply 'x: x.drvPath' .#nixosConfigurations.mangrove.config.<attr>
```
