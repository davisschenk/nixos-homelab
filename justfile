# justfile — mangrove homelab utils
# Usage: just <recipe>

set shell := ["bash", "-euo", "pipefail", "-c"]

host := "mangrove"
target := "10.0.0.2"
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
    PUBKEY=$(echo "$KEY" | age-keygen -y)
    {
      echo "# created by: just bootstrap-age-key"
      echo "# public key: $PUBKEY"
      echo "$KEY"
    } > "$HOME/.config/sops/age/keys.txt"
    chmod 600 "$HOME/.config/sops/age/keys.txt"
    echo "Age key written to $HOME/.config/sops/age/keys.txt"

# ── SOPS ──────────────────────────────────────────────────────────────────────

sops := "nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#sops --command sops"
nixos_rebuild := "nix --extra-experimental-features 'nix-command flakes' run nixpkgs#nixos-rebuild --"

# Edit or create a secret file (e.g. `just edit authentik`)
edit file:
    {{sops}} {{secrets_dir}}/{{file}}.yaml

# View a secret file decrypted (read-only)
view file:
    {{sops}} --decrypt {{secrets_dir}}/{{file}}.yaml

# Add the host's SSH key to .sops.yaml so the server can decrypt secrets at boot.
# Run this ONCE after the server has booted for the first time:
#   1. Run this recipe to get the host age key
#   2. Paste the output into .sops.yaml under keys: as &mangrove
#   3. Uncomment the - *mangrove line in creation_rules
#   4. Run: just rekey
#   5. Remove the admin private key from /persist/etc/sops/age/keys.txt on the server
setup-host-key:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Fetching host SSH public key from mangrove..."
    HOST_AGE_KEY=$(ssh-keyscan -t ed25519 {{target}} 2>/dev/null | nix --extra-experimental-features 'nix-command flakes' run nixpkgs#ssh-to-age --)
    echo ""
    echo "Host age public key:"
    echo "  $HOST_AGE_KEY"
    echo ""
    echo "Add this to .sops.yaml:"
    echo "  - &mangrove $HOST_AGE_KEY"
    echo "Then uncomment '# - *mangrove' in creation_rules and run: just rekey"

# Re-encrypt all secret files (e.g. after rotating keys)
rekey:
    #!/usr/bin/env bash
    set -euo pipefail
    for f in {{secrets_dir}}/*.yaml; do
        echo "Rekeying $f..."
        {{sops}} updatekeys --yes "$f"
    done

# Check that all secret files are SOPS-encrypted (have sops metadata)
# Run this before deploying — plaintext secrets must never be committed
check-secrets:
    #!/usr/bin/env bash
    set -euo pipefail
    failed=0
    for f in {{secrets_dir}}/*.yaml; do
        if ! grep -q 'sops:' "$f"; then
            echo "NOT ENCRYPTED: $f"
            failed=1
        fi
        perms=$(stat -c '%a' "$f")
        if [[ "$perms" != "600" ]]; then
            echo "BAD PERMISSIONS ($perms, expected 600): $f"
            failed=1
        fi
    done
    if [[ $failed -eq 1 ]]; then
        echo ""
        echo "ERROR: Secret file issues found. Run: chmod 600 secrets/*.yaml"
        exit 1
    fi
    echo "All secret files are encrypted and have correct permissions."

# Fix secret file permissions (run after git clone or pull)
fix-secret-perms:
    chmod 600 {{secrets_dir}}/*.yaml
    echo "Permissions set to 600 for all secret files."

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
    {{nixos_rebuild}} build --flake .#{{host}}

# Build and show what would change (dry activate)
dry-run:
    {{nixos_rebuild}} dry-activate --flake .#{{host}} --target-host davis@{{target}} --sudo

# Deploy to host via SSH (builds locally, activates remotely)
deploy: check-secrets
    {{nixos_rebuild}} switch --flake .#{{host}} --target-host davis@{{target}} --sudo

# Boot into new config on next reboot (without activating now)
deploy-boot: check-secrets
    {{nixos_rebuild}} boot --flake .#{{host}} --target-host davis@{{target}} --sudo

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

# ── Linting ──────────────────────────────────────────────────────────────────

# Run statix + deadnix linters (check only, no changes)
lint:
    nix --extra-experimental-features 'nix-command flakes' run nixpkgs#statix -- check .
    nix --extra-experimental-features 'nix-command flakes' run nixpkgs#deadnix -- .

# Run statix + deadnix and auto-fix issues
lint-fix:
    nix --extra-experimental-features 'nix-command flakes' run nixpkgs#statix -- fix .
    nix --extra-experimental-features 'nix-command flakes' run nixpkgs#deadnix -- --edit .

# ── Formatting ───────────────────────────────────────────────────────────────

# Format all .nix files with nixfmt
fmt:
    find . -name '*.nix' -not -path './.git/*' -print0 | xargs -0 nix --extra-experimental-features 'nix-command flakes' run nixpkgs#nixfmt --

# Check formatting without writing changes
fmt-check:
    find . -name '*.nix' -not -path './.git/*' -print0 | xargs -0 nix --extra-experimental-features 'nix-command flakes' run nixpkgs#nixfmt -- --check

# ── Git ───────────────────────────────────────────────────────────────────────

# Show diff of staged + unstaged changes
diff:
    git diff HEAD
