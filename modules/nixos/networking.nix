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
      ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel --no-autoupdate run --token \${CLOUDFLARE_TUNNEL_TOKEN}";
      EnvironmentFile = config.sops.secrets."cloudflare_tunnel_token".path;
      Restart = "on-failure";
      RestartSec = "5s";
      DynamicUser = true;
    };
  };

  # ---------------------------------------------------------------------------
  # Caddy — reverse proxy for all services (Cloudflare Tunnel → Caddy → service)
  # All backends bind only to 127.0.0.1; Caddy is never directly reachable
  # from outside the host.
  # ---------------------------------------------------------------------------
  services.caddy = {
    enable = true;

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

    virtualHosts = {
      # --- No auth ---
      "jellyfin.schenkenberger.dev" = {
        extraConfig = ''
          reverse_proxy localhost:8096
        '';
      };

      "auth.schenkenberger.dev" = {
        extraConfig = ''
          reverse_proxy localhost:9000
        '';
      };

      "files.schenkenberger.dev" = {
        extraConfig = ''
          reverse_proxy localhost:3923
        '';
      };

      "panel.schenkenberger.dev" = {
        extraConfig = ''
          reverse_proxy localhost:8000
        '';
      };

      # --- Forward auth via Authentik ---
      "grafana.schenkenberger.dev" = {
        extraConfig = ''
          import authentik_forward_auth
          reverse_proxy localhost:3000
        '';
      };

      "mealie.schenkenberger.dev" = {
        extraConfig = ''
          import authentik_forward_auth
          reverse_proxy localhost:9925
        '';
      };

      "actual.schenkenberger.dev" = {
        extraConfig = ''
          import authentik_forward_auth
          reverse_proxy localhost:5006
        '';
      };

      "romm.schenkenberger.dev" = {
        extraConfig = ''
          import authentik_forward_auth
          reverse_proxy localhost:8888
        '';
      };

      "sonarr.schenkenberger.dev" = {
        extraConfig = ''
          import authentik_forward_auth
          reverse_proxy localhost:8989
        '';
      };

      "radarr.schenkenberger.dev" = {
        extraConfig = ''
          import authentik_forward_auth
          reverse_proxy localhost:7878
        '';
      };

      "prowlarr.schenkenberger.dev" = {
        extraConfig = ''
          import authentik_forward_auth
          reverse_proxy localhost:9696
        '';
      };

      "qbit.schenkenberger.dev" = {
        extraConfig = ''
          import authentik_forward_auth
          reverse_proxy localhost:8080
        '';
      };
    };
  };
}
