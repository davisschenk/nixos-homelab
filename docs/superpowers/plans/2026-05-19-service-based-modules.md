# Service-Based NixOS Modules Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor `modules/nixos/` so every service file owns its complete vertical slice — SOPS secrets, service config, Caddy virtualHost, and impermanence persist dirs — and delete the catch-all `apps.nix` and `containers.nix`.

**Architecture:** The NixOS module system merges `services.caddy.virtualHosts` and `environment.persistence."/persist".directories` across all imported modules at evaluation time — no explicit wiring between files is needed. Each task is atomic: the service file gains its vhost/persist/secret in the same commit that removes it from the central files, so every intermediate state evaluates cleanly.

**Tech Stack:** NixOS module system, sops-nix, impermanence, Caddy

---

## File Map

| File | Action | After |
|------|--------|-------|
| `modules/nixos/mealie.nix` | Create | Mealie service + Caddy vhost + persist |
| `modules/nixos/actual.nix` | Create | Actual Budget + Caddy vhost + persist |
| `modules/nixos/copyparty.nix` | Create | Copyparty + Caddy vhost |
| `modules/nixos/romm.nix` | Create | Romm oci-container + Caddy vhost + persist |
| `modules/nixos/apps.nix` | Delete | Split into mealie/actual/copyparty |
| `modules/nixos/containers.nix` | Delete | Becomes romm.nix |
| `modules/nixos/auth.nix` | Modify | + Caddy vhost + persist dirs |
| `modules/nixos/media.nix` | Modify | + Caddy vhost + persist dir |
| `modules/nixos/monitoring.nix` | Modify | + Caddy vhost + persist dirs |
| `modules/nixos/arr.nix` | Modify | + vpn secret owned here + vhosts + persist |
| `modules/nixos/pelican.nix` | Modify | + 2 secrets owned here + Caddy vhost + persist dirs |
| `modules/nixos/gaming-vm.nix` | Modify | + libvirt persist dir |
| `modules/nixos/networking.nix` | Modify | Strip all virtualHosts; keep global Caddy config + cloudflared; own cloudflare_tunnel_token |
| `modules/nixos/base.nix` | Modify | Strip service secrets + service persist dirs; host-level only |
| `modules/nixos/default.nix` | Modify | Remove apps/containers, add mealie/actual/copyparty/romm |

### Validation command

All "Verify" steps use this command from the repo root:

```bash
nix --extra-experimental-features "nix-command flakes" eval \
  .#nixosConfigurations.mangrove.config.system.build.toplevel \
  --apply 'x: x.drvPath' 2>&1 | head -20
```

Expected: a single `/nix/store/…` path. Any error message means fix before committing.

---

## Task 1: Create mealie.nix

**Files:**
- Create: `modules/nixos/mealie.nix`
- Modify: `modules/nixos/apps.nix`
- Modify: `modules/nixos/networking.nix`
- Modify: `modules/nixos/default.nix`

- [ ] **Step 1: Create `modules/nixos/mealie.nix`**

```nix
{ ... }:
{
  services.mealie = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9925;
    settings = {
      ALLOW_SIGNUP = "false";
    };
  };

  services.caddy.virtualHosts."mealie.schenkenberger.dev" = {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      import authentik_forward_auth
      reverse_proxy localhost:9925
    '';
  };

  environment.persistence."/persist" = {
    directories = [ "/var/lib/mealie" ];
  };
}
```

- [ ] **Step 2: Replace `modules/nixos/apps.nix`** — remove mealie, keep actual + copyparty

```nix
{ ... }:
{
  services.actual = {
    enable = true;
    settings = {
      hostname = "127.0.0.1";
      port = 5006;
    };
  };

  services.copyparty = {
    enable = true;
    settings = {
      i = "127.0.0.1";
      p = 3923;
      no-reload = true;
    };
    volumes = {
      "/media" = {
        path = "/data/media";
        access = {
          r = "*";
        };
        flags = { };
      };
    };
  };

  environment.persistence."/persist" = {
    directories = [ "/var/lib/actual" ];
  };
}
```

- [ ] **Step 3: Remove mealie virtualHost from `modules/nixos/networking.nix`**

Delete this block from the `virtualHosts` attrset:

```nix
      "mealie.schenkenberger.dev" = {
        listenAddresses = [ "127.0.0.1" ];
        extraConfig = ''
          import authentik_forward_auth
          reverse_proxy localhost:9925
        '';
      };
```

- [ ] **Step 4: Add `mealie.nix` to `modules/nixos/default.nix`**

```nix
{
  imports = [
    ./base.nix
    ./networking.nix
    ./auth.nix
    ./media.nix
    ./arr.nix
    ./monitoring.nix
    ./apps.nix
    ./containers.nix
    ./pelican.nix
    ./gaming-vm.nix
    ./mealie.nix
  ];
}
```

- [ ] **Step 5: Verify**

```bash
nix --extra-experimental-features "nix-command flakes" eval \
  .#nixosConfigurations.mangrove.config.system.build.toplevel \
  --apply 'x: x.drvPath' 2>&1 | head -20
```

Expected: `/nix/store/…` path, no errors.

- [ ] **Step 6: Commit**

```bash
git add modules/nixos/mealie.nix modules/nixos/apps.nix modules/nixos/networking.nix modules/nixos/default.nix
git commit -m "refactor: extract mealie.nix with own vhost and persist"
```

---

## Task 2: Create actual.nix

**Files:**
- Create: `modules/nixos/actual.nix`
- Modify: `modules/nixos/apps.nix`
- Modify: `modules/nixos/networking.nix`
- Modify: `modules/nixos/default.nix`

- [ ] **Step 1: Create `modules/nixos/actual.nix`**

```nix
{ ... }:
{
  services.actual = {
    enable = true;
    settings = {
      hostname = "127.0.0.1";
      port = 5006;
    };
  };

  services.caddy.virtualHosts."actual.schenkenberger.dev" = {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      import authentik_forward_auth
      reverse_proxy localhost:5006
    '';
  };

  environment.persistence."/persist" = {
    directories = [ "/var/lib/actual" ];
  };
}
```

- [ ] **Step 2: Replace `modules/nixos/apps.nix`** — remove actual, keep only copyparty

```nix
{ ... }:
{
  services.copyparty = {
    enable = true;
    settings = {
      i = "127.0.0.1";
      p = 3923;
      no-reload = true;
    };
    volumes = {
      "/media" = {
        path = "/data/media";
        access = {
          r = "*";
        };
        flags = { };
      };
    };
  };
}
```

- [ ] **Step 3: Remove actual virtualHost from `modules/nixos/networking.nix`**

Delete this block from the `virtualHosts` attrset:

```nix
      "actual.schenkenberger.dev" = {
        listenAddresses = [ "127.0.0.1" ];
        extraConfig = ''
          import authentik_forward_auth
          reverse_proxy localhost:5006
        '';
      };
```

- [ ] **Step 4: Add `actual.nix` to `modules/nixos/default.nix`**

```nix
{
  imports = [
    ./base.nix
    ./networking.nix
    ./auth.nix
    ./media.nix
    ./arr.nix
    ./monitoring.nix
    ./apps.nix
    ./containers.nix
    ./pelican.nix
    ./gaming-vm.nix
    ./mealie.nix
    ./actual.nix
  ];
}
```

- [ ] **Step 5: Verify**

```bash
nix --extra-experimental-features "nix-command flakes" eval \
  .#nixosConfigurations.mangrove.config.system.build.toplevel \
  --apply 'x: x.drvPath' 2>&1 | head -20
```

Expected: `/nix/store/…` path, no errors.

- [ ] **Step 6: Commit**

```bash
git add modules/nixos/actual.nix modules/nixos/apps.nix modules/nixos/networking.nix modules/nixos/default.nix
git commit -m "refactor: extract actual.nix with own vhost and persist"
```

---

## Task 3: Create copyparty.nix + delete apps.nix

**Files:**
- Create: `modules/nixos/copyparty.nix`
- Delete: `modules/nixos/apps.nix`
- Modify: `modules/nixos/networking.nix`
- Modify: `modules/nixos/default.nix`

- [ ] **Step 1: Create `modules/nixos/copyparty.nix`**

```nix
{ ... }:
{
  services.copyparty = {
    enable = true;
    settings = {
      i = "127.0.0.1";
      p = 3923;
      no-reload = true;
    };
    volumes = {
      "/media" = {
        path = "/data/media";
        access = {
          r = "*";
        };
        flags = { };
      };
    };
  };

  services.caddy.virtualHosts."files.schenkenberger.dev" = {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      reverse_proxy localhost:3923
    '';
  };
}
```

- [ ] **Step 2: Delete `modules/nixos/apps.nix`**

```bash
rm modules/nixos/apps.nix
```

- [ ] **Step 3: Remove files virtualHost from `modules/nixos/networking.nix`**

Delete this block from the `virtualHosts` attrset:

```nix
      "files.schenkenberger.dev" = {
        listenAddresses = [ "127.0.0.1" ];
        extraConfig = ''
          reverse_proxy localhost:3923
        '';
      };
```

- [ ] **Step 4: Replace `modules/nixos/default.nix`** — swap `apps.nix` for `copyparty.nix`

```nix
{
  imports = [
    ./base.nix
    ./networking.nix
    ./auth.nix
    ./media.nix
    ./arr.nix
    ./monitoring.nix
    ./copyparty.nix
    ./containers.nix
    ./pelican.nix
    ./gaming-vm.nix
    ./mealie.nix
    ./actual.nix
  ];
}
```

- [ ] **Step 5: Verify**

```bash
nix --extra-experimental-features "nix-command flakes" eval \
  .#nixosConfigurations.mangrove.config.system.build.toplevel \
  --apply 'x: x.drvPath' 2>&1 | head -20
```

Expected: `/nix/store/…` path, no errors.

- [ ] **Step 6: Commit**

```bash
git add modules/nixos/copyparty.nix modules/nixos/networking.nix modules/nixos/default.nix
git rm modules/nixos/apps.nix
git commit -m "refactor: extract copyparty.nix, delete apps.nix"
```

---

## Task 4: Create romm.nix + delete containers.nix

**Files:**
- Create: `modules/nixos/romm.nix`
- Delete: `modules/nixos/containers.nix`
- Modify: `modules/nixos/networking.nix`
- Modify: `modules/nixos/base.nix`
- Modify: `modules/nixos/default.nix`

- [ ] **Step 1: Create `modules/nixos/romm.nix`**

```nix
{ ... }:
{
  virtualisation.docker.enable = true;

  virtualisation.oci-containers = {
    backend = "docker";
    containers.romm = {
      image = "rommapp/romm:latest";
      autoStart = true;
      ports = [ "127.0.0.1:8888:8080" ];
      volumes = [
        "/persist/containers/romm/data:/romm/data"
        "/persist/containers/romm/config:/romm/config"
        "/data/media/roms:/romm/library"
      ];
      environment = {
        ROMM_BASE_PATH = "/romm";
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d /persist/containers/romm/data   0750 root root -"
    "d /persist/containers/romm/config 0750 root root -"
    "d /data/media/roms                0755 root root -"
  ];

  systemd.services."docker-romm" = {
    unitConfig.RequiresMountsFor = [
      "/persist/containers/romm"
      "/data/media/roms"
    ];
  };

  services.caddy.virtualHosts."romm.schenkenberger.dev" = {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      import authentik_forward_auth
      reverse_proxy localhost:8888
    '';
  };

  environment.persistence."/persist" = {
    directories = [ "/containers/romm" ];
  };
}
```

- [ ] **Step 2: Delete `modules/nixos/containers.nix`**

```bash
rm modules/nixos/containers.nix
```

- [ ] **Step 3: Remove romm virtualHost from `modules/nixos/networking.nix`**

Delete this block from the `virtualHosts` attrset:

```nix
      "romm.schenkenberger.dev" = {
        listenAddresses = [ "127.0.0.1" ];
        extraConfig = ''
          import authentik_forward_auth
          reverse_proxy localhost:8888
        '';
      };
```

- [ ] **Step 4: Remove `/containers/romm` from `modules/nixos/base.nix`**

Delete this line from `environment.persistence."/persist".directories`:

```nix
      "/containers/romm"
```

- [ ] **Step 5: Replace `modules/nixos/default.nix`** — swap `containers.nix` for `romm.nix`

```nix
{
  imports = [
    ./base.nix
    ./networking.nix
    ./auth.nix
    ./media.nix
    ./arr.nix
    ./monitoring.nix
    ./copyparty.nix
    ./romm.nix
    ./pelican.nix
    ./gaming-vm.nix
    ./mealie.nix
    ./actual.nix
  ];
}
```

- [ ] **Step 6: Verify**

```bash
nix --extra-experimental-features "nix-command flakes" eval \
  .#nixosConfigurations.mangrove.config.system.build.toplevel \
  --apply 'x: x.drvPath' 2>&1 | head -20
```

Expected: `/nix/store/…` path, no errors.

- [ ] **Step 7: Commit**

```bash
git add modules/nixos/romm.nix modules/nixos/networking.nix modules/nixos/base.nix modules/nixos/default.nix
git rm modules/nixos/containers.nix
git commit -m "refactor: extract romm.nix, delete containers.nix"
```

---

## Task 5: Update auth.nix

**Files:**
- Modify: `modules/nixos/auth.nix`
- Modify: `modules/nixos/networking.nix`
- Modify: `modules/nixos/base.nix`

- [ ] **Step 1: Replace `modules/nixos/auth.nix`**

```nix
{ config, ... }:
{
  sops.secrets."authentik_secret_key" = {
    sopsFile = ../../secrets/authentik.yaml;
  };

  sops.templates."authentik-env" = {
    content = ''
      AUTHENTIK_SECRET_KEY=${config.sops.placeholder."authentik_secret_key"}
    '';
    restartUnits = [ "authentik.service" "authentik-worker.service" ];
  };

  services.authentik = {
    enable = true;
    environmentFile = config.sops.templates."authentik-env".path;
    settings = {
      disable_startup_analytics = true;
      avatars = "initials";
    };
  };

  services.caddy.virtualHosts."auth.schenkenberger.dev" = {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      reverse_proxy localhost:9000
    '';
  };

  environment.persistence."/persist" = {
    directories = [
      "/var/lib/authentik"
      "/var/lib/postgresql"
    ];
  };
}
```

- [ ] **Step 2: Remove auth virtualHost from `modules/nixos/networking.nix`**

Delete this block from the `virtualHosts` attrset:

```nix
      "auth.schenkenberger.dev" = {
        listenAddresses = [ "127.0.0.1" ];
        extraConfig = ''
          reverse_proxy localhost:9000
        '';
      };
```

- [ ] **Step 3: Remove auth persist dirs from `modules/nixos/base.nix`**

Delete these two lines from `environment.persistence."/persist".directories`:

```nix
      "/var/lib/authentik"
      "/var/lib/postgresql"
```

- [ ] **Step 4: Verify**

```bash
nix --extra-experimental-features "nix-command flakes" eval \
  .#nixosConfigurations.mangrove.config.system.build.toplevel \
  --apply 'x: x.drvPath' 2>&1 | head -20
```

Expected: `/nix/store/…` path, no errors.

- [ ] **Step 5: Commit**

```bash
git add modules/nixos/auth.nix modules/nixos/networking.nix modules/nixos/base.nix
git commit -m "refactor: auth.nix owns its Caddy vhost and persist dirs"
```

---

## Task 6: Update media.nix

**Files:**
- Modify: `modules/nixos/media.nix`
- Modify: `modules/nixos/networking.nix`
- Modify: `modules/nixos/base.nix`

- [ ] **Step 1: Replace `modules/nixos/media.nix`**

```nix
{ pkgs, ... }:
{
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      intel-compute-runtime
    ];
  };

  services.jellyfin = {
    enable = true;
    openFirewall = false;
  };

  users.users.jellyfin.extraGroups = [
    "render"
    "video"
  ];

  services.caddy.virtualHosts."jellyfin.schenkenberger.dev" = {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      reverse_proxy localhost:8096
    '';
  };

  environment.persistence."/persist" = {
    directories = [ "/var/lib/jellyfin" ];
  };
}
```

- [ ] **Step 2: Remove jellyfin virtualHost from `modules/nixos/networking.nix`**

Delete this block from the `virtualHosts` attrset:

```nix
      "jellyfin.schenkenberger.dev" = {
        listenAddresses = [ "127.0.0.1" ];
        extraConfig = ''
          reverse_proxy localhost:8096
        '';
      };
```

- [ ] **Step 3: Remove `/var/lib/jellyfin` from `modules/nixos/base.nix`**

Delete this line from `environment.persistence."/persist".directories`:

```nix
      "/var/lib/jellyfin"
```

- [ ] **Step 4: Verify**

```bash
nix --extra-experimental-features "nix-command flakes" eval \
  .#nixosConfigurations.mangrove.config.system.build.toplevel \
  --apply 'x: x.drvPath' 2>&1 | head -20
```

Expected: `/nix/store/…` path, no errors.

- [ ] **Step 5: Commit**

```bash
git add modules/nixos/media.nix modules/nixos/networking.nix modules/nixos/base.nix
git commit -m "refactor: media.nix owns its Caddy vhost and persist dir"
```

---

## Task 7: Update monitoring.nix

**Files:**
- Modify: `modules/nixos/monitoring.nix`
- Modify: `modules/nixos/networking.nix`
- Modify: `modules/nixos/base.nix`

- [ ] **Step 1: Replace `modules/nixos/monitoring.nix`**

```nix
{ config, ... }:
{
  sops.secrets."grafana_secret_key" = {
    sopsFile = ../../secrets/grafana.yaml;
    owner = "grafana";
  };

  services.prometheus = {
    enable = true;
    port = 9090;
    retentionTime = "30d";

    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [ { targets = [ "localhost:9100" ]; } ];
      }
      {
        job_name = "jellyfin";
        static_configs = [ { targets = [ "localhost:8096" ]; } ];
        metrics_path = "/metrics";
      }
    ];

    exporters.node = {
      enable = true;
      enabledCollectors = [
        "systemd"
        "processes"
        "filesystem"
        "diskstats"
        "meminfo"
        "cpu"
        "loadavg"
        "netdev"
      ];
    };
  };

  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "127.0.0.1";
        http_port = 3000;
        root_url = "https://grafana.schenkenberger.dev";
      };
      analytics.reporting_enabled = false;
      security.secret_key = "$__file{${config.sops.secrets."grafana_secret_key".path}}";
    };

    provision = {
      enable = true;
      datasources.settings.datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          url = "http://localhost:9090";
          isDefault = true;
        }
      ];
    };
  };

  services.caddy.virtualHosts."grafana.schenkenberger.dev" = {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      import authentik_forward_auth
      reverse_proxy localhost:3000
    '';
  };

  environment.persistence."/persist" = {
    directories = [
      "/var/lib/prometheus2"
      "/var/lib/grafana"
    ];
  };
}
```

- [ ] **Step 2: Remove grafana virtualHost from `modules/nixos/networking.nix`**

Delete this block from the `virtualHosts` attrset:

```nix
      "grafana.schenkenberger.dev" = {
        listenAddresses = [ "127.0.0.1" ];
        extraConfig = ''
          import authentik_forward_auth
          reverse_proxy localhost:3000
        '';
      };
```

- [ ] **Step 3: Remove prometheus2 + grafana persist dirs from `modules/nixos/base.nix`**

Delete these two lines from `environment.persistence."/persist".directories`:

```nix
      "/var/lib/prometheus2"
      "/var/lib/grafana"
```

- [ ] **Step 4: Verify**

```bash
nix --extra-experimental-features "nix-command flakes" eval \
  .#nixosConfigurations.mangrove.config.system.build.toplevel \
  --apply 'x: x.drvPath' 2>&1 | head -20
```

Expected: `/nix/store/…` path, no errors.

- [ ] **Step 5: Commit**

```bash
git add modules/nixos/monitoring.nix modules/nixos/networking.nix modules/nixos/base.nix
git commit -m "refactor: monitoring.nix owns its Caddy vhost and persist dirs"
```

---

## Task 8: Update arr.nix

**Files:**
- Modify: `modules/nixos/arr.nix`
- Modify: `modules/nixos/networking.nix`
- Modify: `modules/nixos/base.nix`

- [ ] **Step 1: Replace `modules/nixos/arr.nix`**

```nix
{ config, ... }:
{
  sops.secrets."vpn_wg_conf" = {
    sopsFile = ../../secrets/vpn.yaml;
  };

  nixarr = {
    enable = true;
    mediaDir = "/data/media";
    stateDir = "/persist/var/lib/nixarr";

    vpn = {
      enable = true;
      wgConf = config.sops.secrets."vpn_wg_conf".path;
    };

    sonarr.enable = true;
    radarr.enable = true;
    prowlarr.enable = true;

    qbittorrent = {
      enable = true;
      stateDir = "/data/downloads/.qbittorrent";
      vpn.enable = true;
      qui.enable = false;
    };
  };

  services.caddy.virtualHosts."sonarr.schenkenberger.dev" = {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      import authentik_forward_auth
      reverse_proxy localhost:8989
    '';
  };

  services.caddy.virtualHosts."radarr.schenkenberger.dev" = {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      import authentik_forward_auth
      reverse_proxy localhost:7878
    '';
  };

  services.caddy.virtualHosts."prowlarr.schenkenberger.dev" = {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      import authentik_forward_auth
      reverse_proxy localhost:9696
    '';
  };

  services.caddy.virtualHosts."qbit.schenkenberger.dev" = {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      import authentik_forward_auth
      reverse_proxy localhost:8080
    '';
  };

  environment.persistence."/persist" = {
    directories = [ "/var/lib/nixarr" ];
  };
}
```

- [ ] **Step 2: Remove arr virtualHosts from `modules/nixos/networking.nix`**

Delete these four blocks from the `virtualHosts` attrset:

```nix
      "sonarr.schenkenberger.dev" = {
        listenAddresses = [ "127.0.0.1" ];
        extraConfig = ''
          import authentik_forward_auth
          reverse_proxy localhost:8989
        '';
      };

      "radarr.schenkenberger.dev" = {
        listenAddresses = [ "127.0.0.1" ];
        extraConfig = ''
          import authentik_forward_auth
          reverse_proxy localhost:7878
        '';
      };

      "prowlarr.schenkenberger.dev" = {
        listenAddresses = [ "127.0.0.1" ];
        extraConfig = ''
          import authentik_forward_auth
          reverse_proxy localhost:9696
        '';
      };

      "qbit.schenkenberger.dev" = {
        listenAddresses = [ "127.0.0.1" ];
        extraConfig = ''
          import authentik_forward_auth
          reverse_proxy localhost:8080
        '';
      };
```

After this step one virtualHost remains in `networking.nix`: `panel.schenkenberger.dev`.

- [ ] **Step 3: Remove vpn secret + nixarr persist from `modules/nixos/base.nix`**

Delete the `vpn_wg_conf` secret block:

```nix
  sops.secrets."vpn_wg_conf" = {
    sopsFile = ../../secrets/vpn.yaml;
  };
```

Delete this line from `environment.persistence."/persist".directories`:

```nix
      "/var/lib/nixarr"
```

- [ ] **Step 4: Verify**

```bash
nix --extra-experimental-features "nix-command flakes" eval \
  .#nixosConfigurations.mangrove.config.system.build.toplevel \
  --apply 'x: x.drvPath' 2>&1 | head -20
```

Expected: `/nix/store/…` path, no errors.

- [ ] **Step 5: Commit**

```bash
git add modules/nixos/arr.nix modules/nixos/networking.nix modules/nixos/base.nix
git commit -m "refactor: arr.nix owns vpn secret, Caddy vhosts, and persist"
```

---

## Task 9: Update pelican.nix

**Files:**
- Modify: `modules/nixos/pelican.nix`
- Modify: `modules/nixos/networking.nix`
- Modify: `modules/nixos/base.nix`

- [ ] **Step 1: Replace `modules/nixos/pelican.nix`**

```nix
# Pelican Panel + Wings
#
# Deploy order for first install:
#   1. Deploy with wings.enable = false. Log into Panel, create a Node.
#   2. Copy UUID + token from Panel → Nodes → <node> → Configuration tab
#      into secrets/pelican.yaml, re-encrypt, set wings.enable = true, redeploy.
{
  config,
  ...
}:
{
  sops.secrets.pelican_token_id = {
    sopsFile = ../../secrets/pelican.yaml;
  };

  sops.secrets.pelican_token = {
    sopsFile = ../../secrets/pelican.yaml;
  };

  sops.secrets.pelican_app_key = {
    sopsFile = ../../secrets/pelican.yaml;
    owner = config.services.pelican.panel.user;
  };

  sops.secrets.pelican_db_password = {
    sopsFile = ../../secrets/pelican.yaml;
    owner = config.services.pelican.panel.user;
  };

  services.pelican.panel = {
    enable = true;
    app = {
      url = "https://panel.schenkenberger.dev";
      keyFile = config.sops.secrets.pelican_app_key.path;
    };
    database = {
      createLocally = true;
      passwordFile = config.sops.secrets.pelican_db_password.path;
    };
    redis = {
      createLocally = true;
    };
    enableNginx = true;
  };

  services.nginx.defaultListenAddresses = [ "127.0.0.1" ];
  services.nginx.virtualHosts."panel.schenkenberger.dev" = {
    listen = [ { addr = "127.0.0.1"; port = 8000; ssl = false; } ];
  };

  services.pelican.wings = {
    enable = false;
    uuid = "00000000-0000-0000-0000-000000000000";
    remote = "https://panel.schenkenberger.dev";
    tokenIdFile = config.sops.secrets.pelican_token_id.path;
    tokenFile = config.sops.secrets.pelican_token.path;
    api = {
      host = "127.0.0.1";
      port = 8080;
    };
    openFirewall = false;
  };

  networking.firewall.allowedTCPPorts = [ 2022 ];

  services.caddy.virtualHosts."panel.schenkenberger.dev" = {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      reverse_proxy localhost:8000
    '';
  };

  environment.persistence."/persist" = {
    directories = [
      "/var/lib/pelican"
      "/var/lib/pelican-wings"
      "/var/lib/mysql"
    ];
  };
}
```

- [ ] **Step 2: Replace `modules/nixos/networking.nix`** — remove last virtualHost + empty virtualHosts block

The complete `networking.nix` after this step:

```nix
{
  config,
  pkgs,
  ...
}:
{
  # ---------------------------------------------------------------------------
  # Cloudflare Tunnel — sole public ingress, no ports need to be opened
  # ---------------------------------------------------------------------------
  systemd.services.cloudflared = {
    description = "Cloudflare Tunnel";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel --no-autoupdate run --token $CLOUDFLARE_TUNNEL_TOKEN";
      EnvironmentFile = config.sops.secrets."cloudflare_tunnel_token".path;
      Restart = "on-failure";
      RestartSec = "5s";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      PrivateTmp = true;
      ProtectHome = true;
    };
  };

  # ---------------------------------------------------------------------------
  # Caddy — reverse proxy for all services (Cloudflare Tunnel → Caddy → service)
  # All backends bind only to 127.0.0.1; Caddy is never directly reachable
  # from outside the host.
  # ---------------------------------------------------------------------------
  services.caddy = {
    enable = true;

    globalConfig = ''
      auto_https off
    '';

    # Snippet used by services that require Authentik SSO
    extraConfig = ''
      (authentik_forward_auth) {
        forward_auth localhost:9000 {
          uri /outpost.goauthentik.io/auth/caddy
          copy_headers X-authentik-username X-authentik-groups X-authentik-email X-authentik-name X-authentik-uid
          trusted_proxies private_ranges
        }
      }
    '';
  };
}
```

- [ ] **Step 3: Remove pelican secrets + persist dirs from `modules/nixos/base.nix`**

Delete the `pelican_token_id` secret block:

```nix
  sops.secrets."pelican_token_id" = {
    sopsFile = ../../secrets/pelican.yaml;
  };
```

Delete the `pelican_token` secret block:

```nix
  sops.secrets."pelican_token" = {
    sopsFile = ../../secrets/pelican.yaml;
  };
```

Delete these two lines from `environment.persistence."/persist".directories`:

```nix
      "/var/lib/pelican"
      "/var/lib/pelican-wings"
```

- [ ] **Step 4: Verify**

```bash
nix --extra-experimental-features "nix-command flakes" eval \
  .#nixosConfigurations.mangrove.config.system.build.toplevel \
  --apply 'x: x.drvPath' 2>&1 | head -20
```

Expected: `/nix/store/…` path, no errors.

- [ ] **Step 5: Commit**

```bash
git add modules/nixos/pelican.nix modules/nixos/networking.nix modules/nixos/base.nix
git commit -m "refactor: pelican.nix owns secrets, Caddy vhost, and persist dirs"
```

---

## Task 10: Update gaming-vm.nix

**Files:**
- Modify: `modules/nixos/gaming-vm.nix`
- Modify: `modules/nixos/base.nix`

- [ ] **Step 1: Replace `modules/nixos/gaming-vm.nix`**

```nix
{ pkgs, ... }:
{
  boot.kernelParams = [
    "intel_iommu=on"
    "iommu=pt"
  ];
  boot.kernelModules = [
    "vfio"
    "vfio_iommu_type1"
    "vfio_pci"
  ];

  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = false;
      swtpm.enable = true;
    };
  };

  programs.virt-manager.enable = true;

  environment.persistence."/persist" = {
    directories = [ "/var/lib/libvirt" ];
  };
}
```

- [ ] **Step 2: Remove `/var/lib/libvirt` from `modules/nixos/base.nix`**

Delete this line from `environment.persistence."/persist".directories`:

```nix
      "/var/lib/libvirt"
```

- [ ] **Step 3: Verify**

```bash
nix --extra-experimental-features "nix-command flakes" eval \
  .#nixosConfigurations.mangrove.config.system.build.toplevel \
  --apply 'x: x.drvPath' 2>&1 | head -20
```

Expected: `/nix/store/…` path, no errors.

- [ ] **Step 4: Commit**

```bash
git add modules/nixos/gaming-vm.nix modules/nixos/base.nix
git commit -m "refactor: gaming-vm.nix owns libvirt persist dir"
```

---

## Task 11: Finalize networking.nix — own the cloudflare_tunnel_token secret

**Files:**
- Modify: `modules/nixos/networking.nix`
- Modify: `modules/nixos/base.nix`

The cloudflared systemd service already reads `config.sops.secrets."cloudflare_tunnel_token".path`. The declaration is currently in `base.nix`; this task moves it to `networking.nix` so it lives next to its only consumer. `sops.defaultSopsFile` stays in `base.nix` — the moved declaration uses an explicit `sopsFile` attribute.

- [ ] **Step 1: Replace `modules/nixos/networking.nix`** — add cloudflare_tunnel_token declaration

```nix
{
  config,
  pkgs,
  ...
}:
{
  # ---------------------------------------------------------------------------
  # Cloudflare Tunnel — sole public ingress, no ports need to be opened
  # ---------------------------------------------------------------------------
  sops.secrets."cloudflare_tunnel_token" = {
    sopsFile = ../../secrets/cloudflare-tunnel.yaml;
  };

  systemd.services.cloudflared = {
    description = "Cloudflare Tunnel";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel --no-autoupdate run --token $CLOUDFLARE_TUNNEL_TOKEN";
      EnvironmentFile = config.sops.secrets."cloudflare_tunnel_token".path;
      Restart = "on-failure";
      RestartSec = "5s";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      PrivateTmp = true;
      ProtectHome = true;
    };
  };

  # ---------------------------------------------------------------------------
  # Caddy — reverse proxy for all services (Cloudflare Tunnel → Caddy → service)
  # All backends bind only to 127.0.0.1; Caddy is never directly reachable
  # from outside the host.
  # ---------------------------------------------------------------------------
  services.caddy = {
    enable = true;

    globalConfig = ''
      auto_https off
    '';

    # Snippet used by services that require Authentik SSO
    extraConfig = ''
      (authentik_forward_auth) {
        forward_auth localhost:9000 {
          uri /outpost.goauthentik.io/auth/caddy
          copy_headers X-authentik-username X-authentik-groups X-authentik-email X-authentik-name X-authentik-uid
          trusted_proxies private_ranges
        }
      }
    '';
  };
}
```

- [ ] **Step 2: Remove `cloudflare_tunnel_token` secret from `modules/nixos/base.nix`**

Delete this block:

```nix
  sops.secrets."cloudflare_tunnel_token" = {
    sopsFile = ../../secrets/cloudflare-tunnel.yaml;
  };
```

- [ ] **Step 3: Verify**

```bash
nix --extra-experimental-features "nix-command flakes" eval \
  .#nixosConfigurations.mangrove.config.system.build.toplevel \
  --apply 'x: x.drvPath' 2>&1 | head -20
```

Expected: `/nix/store/…` path, no errors.

- [ ] **Step 4: Confirm base.nix is clean**

```bash
grep -n "sops\.secrets\|/var/lib\|/containers" modules/nixos/base.nix
```

Expected: no output — all service-specific secrets and persist dirs have been moved out.

- [ ] **Step 5: Confirm default.nix has correct imports**

```bash
cat modules/nixos/default.nix
```

Expected: 12 imports — `base`, `networking`, `auth`, `media`, `arr`, `monitoring`, `copyparty`, `romm`, `pelican`, `gaming-vm`, `mealie`, `actual`. No `apps` or `containers`.

- [ ] **Step 6: Commit**

```bash
git add modules/nixos/networking.nix modules/nixos/base.nix
git commit -m "refactor: networking.nix owns cloudflare_tunnel_token — service-based modules complete"
```
