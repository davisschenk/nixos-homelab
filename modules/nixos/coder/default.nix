# Per-user auth (Claude Code, Codex, `gh`) managed via coder secrets, not per-deployment Nix/sops.
{ config, pkgs, lib, ... }:
let
  sopsFile = ../../../secrets/coder.yaml;
in
{
  # terraform is marked unfree (BSL-1.1) in nixpkgs.
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "terraform" ];

  sops.secrets."coder_oidc_client_secret" = { inherit sopsFile; };
  sops.secrets."coder_api_token" = { inherit sopsFile; };
  sops.secrets."coder_github_client_id" = { inherit sopsFile; };
  sops.secrets."coder_github_client_secret" = { inherit sopsFile; };
  sops.secrets."coder_claude_code_oauth_token" = { inherit sopsFile; };

  sops.templates."coder-env" = {
    content = ''
      CODER_OIDC_CLIENT_SECRET=${config.sops.placeholder."coder_oidc_client_secret"}
      CODER_EXTERNAL_AUTH_0_CLIENT_ID=${config.sops.placeholder."coder_github_client_id"}
      CODER_EXTERNAL_AUTH_0_CLIENT_SECRET=${config.sops.placeholder."coder_github_client_secret"}
    '';
    restartUnits = [ "coder.service" ];
  };

  # Long-lived API token for non-interactive template pushes.
  sops.templates."coder-templates-push-env" = {
    content = ''
      CODER_URL=https://coder.schenkenberger.dev
      CODER_SESSION_TOKEN=${config.sops.placeholder."coder_api_token"}
    '';
    restartUnits = [ "coder-templates-push.service" ];
  };

  # `coder templates push` doesn't read TF_VAR_* (that's a plain-terraform
  # convention) — it only takes --var/--variables-file, hence a YAML file
  # instead of another env line on coder-templates-push-env.
  sops.templates."coder-templates-push-tasks-vars" = {
    content = ''
      claude_code_oauth_token: "${config.sops.placeholder."coder_claude_code_oauth_token"}"
    '';
    restartUnits = [ "coder-templates-push-tasks.service" ];
  };

  services.coder = {
    enable = true;
    accessUrl = "https://coder.schenkenberger.dev";
    # *.schenkenberger.dev (not nested) — Cloudflare edge TLS only covers one wildcard level per zone.
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
      # Authentik doesn't set email_verified by default; access gated by Authentik policy binding instead.
      CODER_OIDC_IGNORE_EMAIL_VERIFIED = "true";
      # 7-day default is too short for templates-push; 1-year is acceptable for single-admin homelab.
      CODER_MAX_ADMIN_TOKEN_LIFETIME = "8760h";
      # Coder session token is independent of Authentik's; matched to 2-week Authentik session length.
      CODER_SESSION_DURATION = "336h";
      # Disable Coder's default GitHub provider to enforce Authentik policy-binding gate.
      CODER_OAUTH2_GITHUB_DEFAULT_PROVIDER_ENABLE = "false";
      # Omit CODER_EXTERNAL_AUTH_GITHUB_DEFAULT_PROVIDER_ENABLE — setting it crashes coderd's env parser.
      CODER_EXTERNAL_AUTH_0_ID = "primary-github";
      CODER_EXTERNAL_AUTH_0_TYPE = "github";
      # Password auth disabled except for Owner-role accounts (anti-lockout); automation uses API token.
      CODER_DISABLE_PASSWORD_AUTH = "true";
    };
  };

  # coderd needs Docker socket access for the Terraform workspace provider.
  users.users.coder.extraGroups = [ "docker" ];

  # Terraform binary must be in unit PATH for coderd's provisioner under ProtectSystem=full.
  systemd.services.coder.path = [ pkgs.terraform ];

  # Loose restart limits outlast Authentik startup race; coderd exits on OIDC validation fail.
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

  # Per-workspace subdirs auto-created by Docker on container start; /persist itself persists.
  systemd.tmpfiles.rules = [
    "d /persist/coder/workspaces 0750 coder coder -"
  ];

  systemd.services.coder.unitConfig.RequiresMountsFor = [ "/persist/coder/workspaces" ];

  # Restart=on-failure tolerates coderd startup races; after/requires don't guarantee coderd is serving.
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

  systemd.services.coder-templates-push-tasks = {
    description = "Push the Coder Claude Tasks workspace template";
    after = [ "coder.service" ];
    requires = [ "coder.service" ];
    wantedBy = [ "multi-user.target" ];
    restartTriggers = [ ./templates/tasks/main.tf ];
    path = [ pkgs.terraform ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = false;
      EnvironmentFile = config.sops.templates."coder-templates-push-env".path;
      ExecStart = "${pkgs.coder}/bin/coder templates push claude-tasks --directory ${./templates/tasks} --variables-file ${config.sops.templates."coder-templates-push-tasks-vars".path} --yes";
      Restart = "on-failure";
      RestartSec = "10s";
    };
    unitConfig = {
      StartLimitIntervalSec = 300;
      StartLimitBurst = 10;
    };
  };
}
