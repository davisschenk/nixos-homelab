# Agent notes for this repo

Conventions for anyone (human or agent) editing this NixOS flake.

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
- `just check` — `nix flake check`
- `just build` / `just deploy` / `just dry-run`

For fast config validation without a full build:
```
nix eval --apply 'x: x.drvPath' .#nixosConfigurations.mangrove.config.<attr>
```
