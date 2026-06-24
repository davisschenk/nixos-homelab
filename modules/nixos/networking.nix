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

  sops.secrets."cloudflare_api_token" = {
    sopsFile = ../../secrets/cloudflare-tunnel.yaml;
  };

  sops.templates."cloudflared-env" = {
    content = "CLOUDFLARE_TUNNEL_TOKEN=${config.sops.placeholder."cloudflare_tunnel_token"}";
    restartUnits = [ "cloudflared.service" ];
  };

  sops.templates."caddy-env" = {
    content = "CLOUDFLARE_API_TOKEN=${config.sops.placeholder."cloudflare_api_token"}";
    restartUnits = [ "caddy.service" ];
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

  # Cloudflare Tunnel routes all traffic to https://caddy:443 (a Docker hostname
  # from the previous Proxmox setup). Map it to localhost so cloudflared can
  # reach Caddy without needing Docker networking.
  networking.hosts."127.0.0.1" = [ "caddy" ];

  # ---------------------------------------------------------------------------
  # Caddy — reverse proxy for all services (Cloudflare Tunnel → Caddy → service)
  # Built with the caddy-dns/cloudflare plugin so Caddy handles ACME DNS-01
  # automatically — no external security.acme needed.
  # ---------------------------------------------------------------------------
  services.caddy = {
    enable = true;

    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/cloudflare@v0.2.4" ];
      hash = "sha256-VHm9POg2KixGsMsAcfFFDMK9x6niRJ1iJV9kkSwkSjc=";
    };

    # Inject the Cloudflare API token so Caddy's DNS-01 challenge can use it
    # via {env.CLOUDFLARE_API_TOKEN} in the Caddyfile
    environmentFile = config.sops.templates."caddy-env".path;

    globalConfig = ''
      email davisschenk@gmail.com
    '';

    extraConfig = ''
      (cloudflare_tls) {
        encode gzip
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
        }
      }

      (authentik_forward_auth) {
        forward_auth localhost:${toString config.mylab.ports.authentik} {
          uri /outpost.goauthentik.io/auth/caddy
          copy_headers X-authentik-username X-authentik-groups X-authentik-email X-authentik-name X-authentik-uid
          trusted_proxies 127.0.0.1
        }
      }
    '';

    # Cloudflare Tunnel connects to https://caddy:443 with originServerName
    # "*.schenkenberger.dev", so cloudflared sends TLS SNI="*.schenkenberger.dev".
    # Caddy matches this site block, handles DNS-01 via Cloudflare to obtain a
    # wildcard cert, then routes by HTTP Host header.
    virtualHosts."*.schenkenberger.dev" = {
      listenAddresses = [ "127.0.0.1" ];
      extraConfig = ''
        import cloudflare_tls

        @auth host auth.schenkenberger.dev
        handle @auth {
          reverse_proxy localhost:${toString config.mylab.ports.authentik}
        }

        @mealie host mealie.schenkenberger.dev
        handle @mealie {
          reverse_proxy localhost:${toString config.mylab.ports.mealie}
        }

        @actual host actual.schenkenberger.dev
        handle @actual {
          reverse_proxy localhost:${toString config.mylab.ports.actual}
        }

        @grafana host grafana.schenkenberger.dev
        handle @grafana {
          reverse_proxy localhost:${toString config.mylab.ports.grafana}
        }

        @sonarr host sonarr.schenkenberger.dev
        handle @sonarr {
          import authentik_forward_auth
          reverse_proxy localhost:${toString config.mylab.ports.sonarr}
        }

        @radarr host radarr.schenkenberger.dev
        handle @radarr {
          import authentik_forward_auth
          reverse_proxy localhost:${toString config.mylab.ports.radarr}
        }

        @prowlarr host prowlarr.schenkenberger.dev
        handle @prowlarr {
          import authentik_forward_auth
          reverse_proxy localhost:${toString config.mylab.ports.prowlarr}
        }

        @qbit host qbit.schenkenberger.dev
        handle @qbit {
          import authentik_forward_auth
          reverse_proxy 192.168.15.1:${toString config.mylab.ports.qbittorrent}
        }

        @romm host romm.schenkenberger.dev
        handle @romm {
          reverse_proxy localhost:${toString config.mylab.ports.romm}
        }

        @jellyfin host jellyfin.schenkenberger.dev
        handle @jellyfin {
          reverse_proxy localhost:${toString config.mylab.ports.jellyfin}
        }

        @seerr host seerr.schenkenberger.dev
        handle @seerr {
          reverse_proxy localhost:${toString config.mylab.ports.jellyseerr}
        }

        @files host files.schenkenberger.dev
        handle @files {
          import authentik_forward_auth
          reverse_proxy localhost:${toString config.mylab.ports.copyparty} {
            header_up X-Idp-User {http.request.header.X-Authentik-Username}
            header_up X-Idp-Groups {http.request.header.X-Authentik-Groups}
          }
        }

        @panel host panel.schenkenberger.dev
        handle @panel {
          reverse_proxy localhost:${toString config.mylab.ports.pelican}
        }
      '';
    };
  };

  environment.persistence."/persist" = {
    directories = [
      "/var/lib/caddy"
    ];
  };
}
