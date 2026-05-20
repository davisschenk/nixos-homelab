# Caddy Cloudflare DNS Plugin + TLS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the `caddy-dns/cloudflare` plugin to Caddy so it obtains Let's Encrypt wildcard certs via DNS-01 challenge, enabling HTTPS on all vhosts.

**Architecture:** A new sops secret (`cloudflare-dns.yaml`) holds the Cloudflare API token. A sops template injects it into Caddy's environment. The Caddy package is overridden via `pkgs.caddy.withPlugins`; the global config is updated to use `acme_dns cloudflare` instead of `auto_https off`. After deploy, Cloudflare dashboard tunnel routes must be updated from `http://` to `https://` backends.

**Tech Stack:** NixOS, sops-nix, `pkgs.caddy.withPlugins`, `caddy-dns/cloudflare` plugin, Let's Encrypt DNS-01 ACME.

---

### Task 1: Create the Cloudflare DNS API token secret file

**Files:**
- Create: `secrets/cloudflare-dns.yaml`

- [ ] **Step 1: Create the placeholder secrets file**

  ```yaml
  # PLACEHOLDER — encrypt with: sops -e -i secrets/cloudflare-dns.yaml before deploy
  # API token requires: Zone:DNS:Edit permission, scoped to schenkenberger.dev
  cloudflare_api_token: "REPLACE_WITH_CLOUDFLARE_API_TOKEN"
  ```

  Save to `secrets/cloudflare-dns.yaml`.

- [ ] **Step 2: Verify the file exists alongside peers**

  Run: `ls secrets/`
  Expected: `cloudflare-dns.yaml` appears alongside `cloudflare-tunnel.yaml`, `authentik.yaml`, etc.

- [ ] **Step 3: Commit**

  ```bash
  git add secrets/cloudflare-dns.yaml
  git commit -m "chore: add cloudflare-dns secret placeholder"
  ```

---

### Task 2: Wire sops secret + Caddy environment file in networking.nix

**Files:**
- Modify: `modules/nixos/networking.nix`

This follows the exact same pattern as the existing `cloudflared-env` template directly above in the same file.

- [ ] **Step 1: Add the sops secret and template**

  In `modules/nixos/networking.nix`, after the existing `sops.templates."cloudflared-env"` block and before `systemd.services.cloudflared`, add:

  ```nix
  sops.secrets."cloudflare_api_token" = {
    sopsFile = ../../secrets/cloudflare-dns.yaml;
  };

  sops.templates."caddy-env" = {
    content = "CF_API_TOKEN=${config.sops.placeholder."cloudflare_api_token"}";
    restartUnits = [ "caddy.service" ];
  };
  ```

- [ ] **Step 2: Add environmentFile to the caddy service block**

  In the `services.caddy` attribute set (currently has `enable`, `globalConfig`, `extraConfig`), add:

  ```nix
  environmentFile = config.sops.templates."caddy-env".path;
  ```

- [ ] **Step 3: Check the config evaluates**

  Run: `nix --extra-experimental-features 'nix-command flakes' eval .#nixosConfigurations.mangrove.config.services.caddy.environmentFile`
  Expected: a path ending in `/caddy-env` (something like `"/run/secrets-rendered/caddy-env"`)

- [ ] **Step 4: Commit**

  ```bash
  git add modules/nixos/networking.nix
  git commit -m "feat: add cloudflare API token secret and caddy env wiring"
  ```

---

### Task 3: Add the Caddy plugin package with placeholder hash

**Files:**
- Modify: `modules/nixos/networking.nix`

The `pkgs.caddy.withPlugins` function builds Caddy with extra Go modules via xcaddy. It needs a vendor directory hash that must be bootstrapped: use `lib.fakeHash` first, then replace with the real hash after a build attempt.

- [ ] **Step 1: Add `lib` to the module arguments**

  Change the first line of `modules/nixos/networking.nix` from:

  ```nix
  {
    config,
    pkgs,
    ...
  }:
  ```

  to:

  ```nix
  {
    config,
    lib,
    pkgs,
    ...
  }:
  ```

- [ ] **Step 2: Add the plugin package override to services.caddy**

  Add `package` to the `services.caddy` attribute set:

  ```nix
  package = pkgs.caddy.withPlugins {
    plugins = [ "github.com/caddy-dns/cloudflare@v0.2.1" ];
    hash = lib.fakeHash;
  };
  ```

- [ ] **Step 3: Verify the config still evaluates (syntax check)**

  Run: `nix --extra-experimental-features 'nix-command flakes' eval .#nixosConfigurations.mangrove.config.services.caddy.package.pname`
  Expected: `"caddy"` (not an error)

- [ ] **Step 4: Commit the fakeHash state**

  ```bash
  git add modules/nixos/networking.nix
  git commit -m "feat: add caddy cloudflare DNS plugin (hash pending bootstrap)"
  ```

---

### Task 4: Bootstrap the real vendor hash

**Files:**
- Modify: `modules/nixos/networking.nix`

Nix requires the exact hash of the vendor directory produced by xcaddy. The only way to get it is to attempt a build, let it fail with the wrong hash, and read the correct hash from the error.

- [ ] **Step 1: Trigger the build to get the real hash**

  Run (will fail intentionally):
  ```bash
  nix --extra-experimental-features 'nix-command flakes' build .#nixosConfigurations.mangrove.config.services.caddy.package 2>&1 | grep "got:"
  ```
  Expected output contains a line like:
  ```
         got:    sha256-<base64-hash>=
  ```

- [ ] **Step 2: Replace fakeHash with the real hash**

  In `modules/nixos/networking.nix`, replace:
  ```nix
  hash = lib.fakeHash;
  ```
  with the hash from the previous step:
  ```nix
  hash = "sha256-<value-from-got-line>";
  ```

- [ ] **Step 3: Verify the package builds cleanly**

  Run: `nix --extra-experimental-features 'nix-command flakes' build .#nixosConfigurations.mangrove.config.services.caddy.package`
  Expected: build completes with no errors, result symlink appears

- [ ] **Step 4: Commit**

  ```bash
  git add modules/nixos/networking.nix
  git commit -m "feat: pin caddy cloudflare DNS plugin vendor hash"
  ```

---

### Task 5: Switch Caddy to HTTPS — remove auto_https off, add acme_dns

**Files:**
- Modify: `modules/nixos/networking.nix`

- [ ] **Step 1: Replace globalConfig content**

  In `modules/nixos/networking.nix`, change:

  ```nix
  globalConfig = ''
    auto_https off
  '';
  ```

  to:

  ```nix
  globalConfig = ''
    email davisschenk@gmail.com
    acme_dns cloudflare {env.CF_API_TOKEN}
  '';
  ```

  This removes the HTTP-only mode and tells Caddy to use Cloudflare's DNS API for all ACME DNS-01 challenges. Every named vhost automatically gets a Let's Encrypt certificate; no per-vhost TLS config is needed.

- [ ] **Step 2: Verify the full system config builds**

  Run: `nix --extra-experimental-features 'nix-command flakes' build .#nixosConfigurations.mangrove.config.system.build.toplevel`
  Expected: build completes successfully

- [ ] **Step 3: Commit**

  ```bash
  git add modules/nixos/networking.nix
  git commit -m "feat: enable Caddy HTTPS via Cloudflare DNS-01 ACME"
  ```

---

### Task 6: Manual — Update Cloudflare dashboard tunnel routes

This step happens **after deploying** to the host. It cannot be automated in the Nix config because the tunnel routes are stored in Cloudflare's control plane.

**Where:** Zero Trust → Networks → Tunnels → [your tunnel] → Public Hostnames

**For each public hostname** (e.g., `mealie.schenkenberger.dev`, `grafana.schenkenberger.dev`, etc.):

- [ ] **Step 1: Update the Service URL**

  Change each route's service URL from:
  ```
  http://127.0.0.1:<port>   (or http://localhost:<port>)
  ```
  to:
  ```
  https://127.0.0.1:443
  ```
  (All vhosts are now served by Caddy on port 443.)

- [ ] **Step 2: Enable No TLS Verify on the origin request**

  Under **Additional application settings → TLS**, enable:
  - **No TLS Verify** ✓

  This is required because Caddy's cert is issued for `*.schenkenberger.dev`, not for `127.0.0.1`. The tunnel daemon connects to `127.0.0.1` so hostname verification would fail without this setting. The cert itself is valid; only the hostname mismatch is being bypassed.

- [ ] **Step 3: Verify services are reachable through the tunnel**

  Open each service in a browser and confirm:
  - The browser shows a valid HTTPS padlock
  - No certificate errors

---

## Deployment note

Before deploying, the placeholder `secrets/cloudflare-dns.yaml` must be encrypted with sops:

```bash
# Fill in the real token, then:
sops -e -i secrets/cloudflare-dns.yaml
```

The Cloudflare API token needs **Zone:DNS:Edit** permission scoped to `schenkenberger.dev`. Create it at: Cloudflare dashboard → My Profile → API Tokens → Create Token → Edit zone DNS (template).
