# Coder — self-hosted remote-dev-workspace platform. Workspaces run as Docker
# containers provisioned via a Terraform template in ./templates/docker/,
# pushed automatically by coder-templates-push.service below whenever the
# template content changes — not a manual `coder templates push` runbook
# step. Each workspace surfaces code-server (VS Code in the browser) through
# Coder's own app proxy, so this module is the whole answer to "an
# easily-accessible browser coding environment" — see workspace-image.nix for
# the tools baked into the workspace image itself.
#
# Claude Code / Codex / `gh` auth inside a workspace is deliberately NOT
# provisioned here — it's per-user state, and Coder already has a home for
# that ("User Secrets": `coder secret` CLI, injected into every workspace a
# user owns at startup, before the container's entrypoint runs) that beats
# anything this module could do with Nix/sops (those are per-deployment, not
# per-user). One-time setup, run once from any workspace (or locally with
# `coder login https://coder.schenkenberger.dev`):
#
#   claude setup-token   # prints a 1-year OAuth token; bills against your
#                         # Claude subscription, not pay-per-token API usage
#   echo -n '<token>' | coder secret create claude-oauth --env CLAUDE_CODE_OAUTH_TOKEN
#
#   codex login --device-auth   # headless-friendly OAuth flow; bills against
#                                # your ChatGPT plan
#   coder secret create codex-auth --file ~/.codex/auth.json < ~/.codex/auth.json
#
# Both then auto-inject into every *new* workspace with no login step;
# existing workspaces pick them up on their next restart. `gh` auth instead
# comes from the GitHub external-auth provider below (CODER_EXTERNAL_AUTH_0_*)
# once linked via the "GitHub" button Coder adds to the workspace page.
{ config, pkgs, lib, ... }:
let
  sopsFile = ../../../secrets/coder.yaml;
  coderWorkspaceImage = import ./workspace-image.nix { inherit pkgs; };
in
{
  # terraform (BSL-1.1) and claude-code are both marked unfree in nixpkgs.
  nixpkgs.config.allowUnfreePredicate =
    pkg: builtins.elem (lib.getName pkg) [ "terraform" "claude-code" ];

  sops.secrets."coder_oidc_client_secret" = { inherit sopsFile; };
  sops.secrets."coder_api_token" = { inherit sopsFile; };
  sops.secrets."coder_github_client_id" = { inherit sopsFile; };
  sops.secrets."coder_github_client_secret" = { inherit sopsFile; };

  sops.templates."coder-env" = {
    content = ''
      CODER_OIDC_CLIENT_SECRET=${config.sops.placeholder."coder_oidc_client_secret"}
      CODER_EXTERNAL_AUTH_0_CLIENT_ID=${config.sops.placeholder."coder_github_client_id"}
      CODER_EXTERNAL_AUTH_0_CLIENT_SECRET=${config.sops.placeholder."coder_github_client_secret"}
    '';
    restartUnits = [ "coder.service" ];
  };

  # Long-lived personal access token for a Coder Owner account, used only to
  # push template updates non-interactively (CODER_URL + CODER_SESSION_TOKEN
  # are the CLI's documented env-var auth path). Created once via `coder
  # tokens create` after bootstrapping the initial admin account; restarting
  # this unit on secret change is what lets a fresh token "just work" without
  # any other manual step.
  sops.templates."coder-templates-push-env" = {
    content = ''
      CODER_URL=https://coder.schenkenberger.dev
      CODER_SESSION_TOKEN=${config.sops.placeholder."coder_api_token"}
    '';
    restartUnits = [ "coder-templates-push.service" ];
  };

  services.coder = {
    enable = true;
    accessUrl = "https://coder.schenkenberger.dev";
    # *.schenkenberger.dev (not a nested *.coder.schenkenberger.dev) — see the
    # catch-all handle block in networking.nix for why: Cloudflare's edge TLS
    # only covers one level of wildcard per zone here, so a second-level
    # wildcard hostname fails the handshake at Cloudflare's edge entirely.
    wildcardAccessUrl = "*.schenkenberger.dev";
    listenAddress = "127.0.0.1:${toString config.mylab.ports.coder}";
    # database.* left at defaults (createLocally=true, user/db "coder") —
    # shares the existing persisted Postgres cluster used by Authentik.
    environment.file = config.sops.templates."coder-env".path;
    environment.extra = {
      CODER_OIDC_ISSUER_URL = "https://auth.schenkenberger.dev/application/o/coder/";
      CODER_OIDC_CLIENT_ID = "coder";
      CODER_OIDC_SCOPES = "openid,profile,email";
      CODER_OIDC_SIGN_IN_TEXT = "Authentik";
      CODER_OIDC_ICON_URL = "https://cdn.jsdelivr.net/gh/selfhst/icons/png/coder.png";
      CODER_OIDC_ALLOW_SIGNUPS = "true";
      # Authentik doesn't set email_verified=true on its ID token claims by
      # default (no email-confirmation flow configured) — Coder otherwise
      # hard-rejects login with "Verify the ... email address on your OIDC
      # provider to authenticate!". Access is already gated by the policy
      # binding on the Coder application in Authentik, not by this claim.
      CODER_OIDC_IGNORE_EMAIL_VERIFIED = "true";
      # Default admin-token cap is 7 days — too short for the long-lived
      # token coder-templates-push.service uses to authenticate
      # non-interactively. This is a single-admin homelab, not a
      # multi-tenant deployment, so a 1-year cap is an acceptable tradeoff
      # against rotating it by hand.
      CODER_MAX_ADMIN_TOKEN_LIFETIME = "8760h";
      # Authentik is the only login path — Coder ships a default, zero-config
      # "Sign in with GitHub" button (its own managed OAuth app) that would
      # otherwise let anyone with a GitHub account sign up, bypassing the
      # Authentik policy-binding gate entirely.
      CODER_OAUTH2_GITHUB_DEFAULT_PROVIDER_ENABLE = "false";
      # (Deliberately not touching CODER_EXTERNAL_AUTH_GITHUB_DEFAULT_PROVIDER_ENABLE
      # here — despite being a real, separately-documented flag, setting it
      # crashes coderd with "read external auth providers from env: parse
      # number: GITHUB_DEFAULT_PROVIDER_ENABLE": Coder's external-auth env
      # parser scans every CODER_EXTERNAL_AUTH_* var expecting an index
      # number right after that prefix and chokes on this one, confirmed on
      # a real deploy. It defaults to "true", meaning coderd's own
      # Coder-hosted GitHub app (shares data with Coder Inc if ever used) is
      # technically still reachable — but only under its own default ID,
      # which nothing below references, so in practice it's never
      # triggered. The custom provider below (index 0, id "primary-github")
      # is what workspaces actually use for git-over-HTTPS and `gh`.
      CODER_EXTERNAL_AUTH_0_ID = "primary-github";
      CODER_EXTERNAL_AUTH_0_TYPE = "github";
      # Password auth stays reachable for Owner-role accounts only (Coder's
      # own anti-lockout carve-out) — fine, since the only owner-role
      # accounts here (automation) authenticate via API token, not this page.
      CODER_DISABLE_PASSWORD_AUTH = "true";
    };
  };

  # coderd talks to the Docker Engine API directly (kreuzwerker/docker
  # Terraform provider) for the Docker-backed workspace template — needs
  # socket access.
  users.users.coder.extraGroups = [ "docker" ];

  # coderd's built-in Terraform provisioner does LookPath("terraform") under
  # this unit's ProtectSystem=full — `path` is the supported way to extend a
  # systemd service's PATH without conflicting with NixOS's own default
  # `environment.PATH` definition for the unit.
  systemd.services.coder.path = [ pkgs.terraform ];

  # coderd validates its OIDC issuer against Authentik eagerly at startup and
  # exits (doesn't retry in-process) if it gets a transient 503 — observed on
  # a real deploy racing against Authentik's own startup (migrations + gunicorn
  # boot take longer than systemd's default restart burst window). `after`
  # reduces the race; the looser restart limits give it enough retries to
  # actually outlast Authentik's startup instead of hitting start-limit-hit.
  systemd.services.coder.after = [ "authentik.service" ];
  systemd.services.coder.serviceConfig.RestartSec = "5s";
  systemd.services.coder.unitConfig.StartLimitIntervalSec = 120;
  systemd.services.coder.unitConfig.StartLimitBurst = 20;

  environment.systemPackages = [
    pkgs.coder
    pkgs.terraform
  ];

  environment.persistence."/persist" = {
    directories = [
      {
        directory = "/var/lib/coder";
        user = "coder";
        group = "coder";
        mode = "0750";
      }
    ];
  };

  # Parent dir for per-workspace bind mounts (see templates/docker/main.tf).
  # Individual workspace subdirs are auto-created by the Docker daemon (root)
  # on first container start, so no per-workspace persistence entry is needed —
  # /persist itself is never wiped.
  systemd.tmpfiles.rules = [
    "d /persist/coder/workspaces 0750 coder coder -"
  ];

  systemd.services.coder.unitConfig.RequiresMountsFor = [ "/persist/coder/workspaces" ];

  # /var/lib/docker (and its image store) sits on the root subvolume, which is
  # wiped every boot — this image has to be reloaded every time the daemon
  # comes up, not just when the derivation changes.
  systemd.services.coder-workspace-image-load = {
    description = "Load the Coder workspace Docker image into the local daemon";
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    # Forces a re-run on `nixos-rebuild switch` even though this oneshot is
    # "inactive (dead)" after boot and wouldn't otherwise restart just because
    # its ExecStart store path changed.
    restartTriggers = [ coderWorkspaceImage ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = false;
      ExecStart = pkgs.writeShellScript "load-coder-workspace-image" ''
        ${coderWorkspaceImage} | ${pkgs.docker}/bin/docker load
      '';
    };
  };

  # Pushes ./templates/docker as the "docker-dev" template on every activation
  # where its content changed (restartTriggers), using the API token above.
  #
  # after/requires on coder.service only guarantees coder.service's start job
  # completed, not that coderd is actually serving — Type=simple/exec units
  # are "active" as soon as the process forks, well before coderd finishes
  # booting. coder.service itself races Authentik's startup the same way (see
  # its own after=authentik.service comment above) and can crash-loop a few
  # times before it sticks, so this can hit a 502 from a coder.service that's
  # mid-restart. Restart=on-failure (oneshot services support this — they just
  # don't restart on a clean exit) retries instead of failing the deploy hard.
  systemd.services.coder-templates-push = {
    description = "Push the Coder Docker workspace template";
    after = [ "coder.service" ];
    requires = [ "coder.service" ];
    wantedBy = [ "multi-user.target" ];
    restartTriggers = [ ./templates/docker/main.tf ];
    path = [ pkgs.terraform ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = false;
      EnvironmentFile = config.sops.templates."coder-templates-push-env".path;
      ExecStart = "${pkgs.coder}/bin/coder templates push docker-dev --directory ${./templates/docker} --yes";
      Restart = "on-failure";
      RestartSec = "10s";
    };
    unitConfig = {
      StartLimitIntervalSec = 300;
      StartLimitBurst = 10;
    };
  };
}
