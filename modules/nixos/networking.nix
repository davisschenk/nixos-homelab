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

  # sops.secrets produces a file with only the raw value; systemd EnvironmentFile
  # requires KEY=value format, so we use a sops.template to produce it.
  sops.templates."cloudflared-env" = {
    content = "CLOUDFLARE_TUNNEL_TOKEN=${config.sops.placeholder."cloudflare_tunnel_token"}";

    restartUnits = [ "cloudflared.service" ];
  };

  systemd.services.cloudflared = {
    description = "Cloudflare Tunnel";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel --no-autoupdate run --token $CLOUDFLARE_TUNNEL_TOKEN";
      EnvironmentFile = config.sops.templates."cloudflared-env".path;
      Restart = "on-failure";
      RestartSec = "5s";
      DynamicUser = true;
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
        forward_auth localhost:${toString config.mylab.ports.authentik} {
          uri /outpost.goauthentik.io/auth/caddy
          copy_headers X-authentik-username X-authentik-groups X-authentik-email X-authentik-name X-authentik-uid
          trusted_proxies private_ranges
        }
      }
    '';
  };

  environment.persistence."/persist" = {
    directories = [ "/var/lib/caddy" ];
  };
}
