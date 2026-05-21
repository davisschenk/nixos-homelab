# justfile — mangrove homelab utils
# Usage: just <recipe>

set shell := ["bash", "-euo", "pipefail", "-c"]

host := "mangrove"
secrets_dir := "secrets"

# ── SOPS ──────────────────────────────────────────────────────────────────────

# Edit or create a secret file (e.g. `just edit authentik`)
edit file:
    sops {{secrets_dir}}/{{file}}.yaml

# View a secret file decrypted (read-only)
view file:
    sops --decrypt {{secrets_dir}}/{{file}}.yaml

# Re-encrypt all secret files (e.g. after rotating keys)
rekey:
    #!/usr/bin/env bash
    for f in {{secrets_dir}}/*.yaml; do
        [[ "$(basename "$f")" == ".sops.yaml" ]] && continue
        echo "Rekeying $f..."
        sops updatekeys --yes "$f"
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
    cat {{secrets_dir}}/.sops.yaml

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
