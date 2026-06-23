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

  # Cloudflare Tunnel routes all traffic to https://caddy:443 (a Docker hostname
  # from the previous Proxmox setup). Map it to localhost so cloudflared can
  # reach Caddy without needing Docker networking.
  networking.hosts."127.0.0.1" = [ "caddy" ];

  # ---------------------------------------------------------------------------
  # Caddy — reverse proxy for all services (Cloudflare Tunnel → Caddy → service)
  # All backends bind only to 127.0.0.1; Caddy is never directly reachable
  # from outside the host.
  # ---------------------------------------------------------------------------
  services.caddy = {
    enable = true;

    # Use Caddy's internal CA to issue certs for all vhosts; the Cloudflare
    # Tunnel origin is https://caddy:443 and must have "No TLS Verify" enabled
    # in the Cloudflare dashboard (Zero Trust → Tunnels → public hostnames).
    globalConfig = ''
      local_certs
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

    # Cloudflare Tunnel connects to https://caddy:443 with originServerName
    # "*.schenkenberger.dev", so cloudflared sends TLS SNI="*.schenkenberger.dev".
    # Caddy matches this site block, presents a wildcard cert, then routes
    # by HTTP Host header. Individual virtualHosts handle direct connections.
    virtualHosts."*.schenkenberger.dev" = {
      listenAddresses = [ "127.0.0.1" ];
      extraConfig = ''
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
          import authentik_forward_auth
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
          reverse_proxy localhost:${toString config.mylab.ports.qbittorrent}
        }

        @romm host romm.schenkenberger.dev
        handle @romm {
          reverse_proxy localhost:${toString config.mylab.ports.romm}
        }

        @jellyfin host jellyfin.schenkenberger.dev
        handle @jellyfin {
          reverse_proxy localhost:${toString config.mylab.ports.jellyfin}
        }

        @files host files.schenkenberger.dev
        handle @files {
          reverse_proxy localhost:${toString config.mylab.ports.copyparty}
        }

        @panel host panel.schenkenberger.dev
        handle @panel {
          reverse_proxy localhost:${toString config.mylab.ports.pelican}
        }
      '';
    };
  };

  environment.persistence."/persist" = {
    directories = [ "/var/lib/caddy" ];
  };
}
