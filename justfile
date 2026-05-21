# justfile — mangrove homelab utils
# Usage: just <recipe>

set shell := ["bash", "-euo", "pipefail", "-c"]

host := "mangrove"
secrets_dir := "secrets"

# ── Bootstrap ─────────────────────────────────────────────────────────────────

# Restore the sops age key from BWS onto this machine
# Requires BWS_ACCESS_TOKEN to be set in the environment
bootstrap-age-key:
    #!/usr/bin/env bash
    set -euo pipefail
    : "${BWS_ACCESS_TOKEN:?BWS_ACCESS_TOKEN must be set}"
    mkdir -p "$HOME/.config/sops/age"
    KEY=$(bws secret get d98f3097-9550-4025-8108-b451002ce98a --output json | python3 -c "import json,sys; print(json.load(sys.stdin)['value'])")
    {
      echo "# created by: just bootstrap-age-key"
      echo "# public key: age19aesmaqmck97rh3hgswmwas4uflmd4kfx47v5gg57yj58jswccuq0x0vyg"
      echo "$KEY"
    } > "$HOME/.config/sops/age/keys.txt"
    chmod 600 "$HOME/.config/sops/age/keys.txt"
    echo "Age key written to $HOME/.config/sops/age/keys.txt"

# ── SOPS ──────────────────────────────────────────────────────────────────────

sops := "nix --extra-experimental-features nix-command --extra-experimental-features flakes shell nixpkgs#sops --command sops"

# Edit or create a secret file (e.g. `just edit authentik`)
edit file:
    {{sops}} {{secrets_dir}}/{{file}}.yaml

# View a secret file decrypted (read-only)
view file:
    {{sops}} --decrypt {{secrets_dir}}/{{file}}.yaml

# Re-encrypt all secret files (e.g. after rotating keys)
rekey:
    #!/usr/bin/env bash
    set -euo pipefail
    sops="nix --extra-experimental-features nix-command --extra-experimental-features flakes shell nixpkgs#sops --command sops"
    for f in {{secrets_dir}}/*.yaml; do
        [[ "$(basename "$f")" == ".sops.yaml" ]] && continue
        echo "Rekeying $f..."
        $sops updatekeys --yes "$f"
    done

# Check that all secret files are SOPS-encrypted (have sops metadata)
# Run this before deploying — plaintext secrets must never be committed
check-secrets:
    #!/usr/bin/env bash
    failed=0
    for f in {{secrets_dir}}/*.yaml; do
        [[ "$(basename "$f")" == ".sops.yaml" ]] && continue
        if ! grep -q 'sops:' "$f"; then
            echo "NOT ENCRYPTED: $f"
            failed=1
        fi
    done
    if [[ $failed -eq 1 ]]; then
        echo ""
        echo "ERROR: Unencrypted secret files found. Run: sops -e -i <file> for each one."
        exit 1
    fi
    echo "All secret files are encrypted."

# List all secret files and their creation/modification timestamps
list-secrets:
    ls -lh {{secrets_dir}}/*.yaml | grep -v '\.sops\.yaml'

# Show which keys are configured in .sops.yaml
show-keys:
    cat .sops.yaml

# ── NixOS ─────────────────────────────────────────────────────────────────────

# Build the installer ISO for mangrove
build-iso:
    nix --extra-experimental-features 'nix-command flakes' build .#mangrove-iso

# Check / evaluate the flake without building
check:
    nix flake check

# Build the system (dry-run, no activation)
build:
    nixos-rebuild build --flake .#{{host}}

# Build and show what would change (dry activate)
dry-run:
    nixos-rebuild dry-activate --flake .#{{host}} --target-host {{host}} --use-remote-sudo

# Deploy to host via SSH (builds locally, activates remotely)
deploy: check-secrets
    nixos-rebuild switch --flake .#{{host}} --target-host {{host}} --build-host localhost --use-remote-sudo

# Boot into new config on next reboot (without activating now)
deploy-boot: check-secrets
    nixos-rebuild boot --flake .#{{host}} --target-host {{host}} --build-host localhost --use-remote-sudo

# ── Flake ─────────────────────────────────────────────────────────────────────

# Update all flake inputs and show what changed
update:
    nix flake update
    git diff flake.lock

# Update a single flake input (e.g. `just update-input nixpkgs`)
update-input input:
    nix flake update {{input}}
    git diff flake.lock

# Show flake outputs
show:
    nix flake show

# ── Formatting ───────────────────────────────────────────────────────────────

# Format all .nix files with nixfmt
fmt:
    nix --extra-experimental-features 'nix-command flakes' run nixpkgs#nixfmt -- $(find . -name '*.nix' -not -path './.git/*')

# Check formatting without writing changes
fmt-check:
    nix --extra-experimental-features 'nix-command flakes' run nixpkgs#nixfmt -- --check $(find . -name '*.nix' -not -path './.git/*')

# ── Git ───────────────────────────────────────────────────────────────────────

# Show diff of staged + unstaged changes
diff:
    git diff HEAD
