{
  config,
  pkgs,
  ...
}:
let
  # nixarr VPN namespace host-side gateway — see nixarr vpnNamespace subnet config
  nixarrVpnGateway = "192.168.15.1";
in
{
  # Cloudflare Tunnel sole public ingress; no ports need opening
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

  # Map caddy to localhost (was Docker hostname in Proxmox setup); hairpin wings.schenkenberger.dev too
  networking.hosts."127.0.0.1" = [ "caddy" "wings.schenkenberger.dev" ];

  # caddy-dns/cloudflare plugin handles DNS-01 challenges without external security.acme
  services.caddy = {
    enable = true;

    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/cloudflare@v0.2.4" ];
      hash = "sha256-hEHgAG0F0ozHRAPuxEqLyTATBrE+pajeXDiSNwniorg=";
    };

    # Cloudflare API token for DNS-01 challenges via {env.CLOUDFLARE_API_TOKEN}
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

    virtualHosts."*.schenkenberger.dev" = {
      listenAddresses = [ "127.0.0.1" ];
      extraConfig = ''
        import cloudflare_tls

        @auth host auth.schenkenberger.dev
        handle @auth {
          reverse_proxy localhost:${toString config.mylab.ports.authentik}
        }

        # Mealie's own OIDC handles auth; forward-auth would add unnecessary hop
        @mealie host mealie.schenkenberger.dev
        handle @mealie {
          reverse_proxy localhost:${toString config.mylab.ports.mealie}
        }

        @actual host actual.schenkenberger.dev
        handle @actual {
          reverse_proxy localhost:${toString config.mylab.ports.actual}
        }

        # OIDC handled by app; no forward-auth needed
        @wealthfolio host wealthfolio.schenkenberger.dev
        handle @wealthfolio {
          reverse_proxy localhost:${toString config.mylab.ports.wealthfolio}
        }

        @tilt host tilt.schenkenberger.dev
        handle @tilt {
          reverse_proxy localhost:${toString config.mylab.ports.tilt}
        }

        # Authentik SSO is only login path; forward-auth would add extra hop
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
          reverse_proxy ${nixarrVpnGateway}:${toString config.mylab.ports.qbittorrent}
        }

        @romm host romm.schenkenberger.dev
        handle @romm {
          reverse_proxy localhost:${toString config.mylab.ports.romm}
        }

        # Native app clients (mobile, Smart TV) lack SSO support; use Jellyfin's auth
        @jellyfin host jellyfin.schenkenberger.dev
        handle @jellyfin {
          reverse_proxy localhost:${toString config.mylab.ports.jellyfin}
        }

        # Jellyseerr: intentionally no forward-auth to allow external sharing links.
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

        @wings host wings.schenkenberger.dev
        handle @wings {
          reverse_proxy localhost:${toString config.mylab.ports.wings}
        }

        @frigate host frigate.schenkenberger.dev
        handle @frigate {
          import authentik_forward_auth
          reverse_proxy localhost:${toString config.mylab.ports.frigate}
        }

        @homeassistant host homeassistant.schenkenberger.dev
        handle @homeassistant {
          import authentik_forward_auth
          reverse_proxy localhost:${toString config.mylab.ports.homeassistant}
        }

        @console host console.schenkenberger.dev
        handle @console {
          import authentik_forward_auth
          reverse_proxy localhost:${toString config.mylab.ports.novnc}
        }

        # App handles OIDC; no forward-auth
        @coder host coder.schenkenberger.dev
        handle @coder {
          reverse_proxy localhost:${toString config.mylab.ports.coder}
        }

        # Cloudflare edge TLS only supports one wildcard level; workspace apps use *.schenkenberger.dev
        @coder_app header_regexp Host ^[a-z0-9-]+--[a-z0-9-]+--[a-z0-9-]+(--[a-z0-9-]+)?\.schenkenberger\.dev$
        handle @coder_app {
          reverse_proxy localhost:${toString config.mylab.ports.coder}
        }

        handle {
          redir * https://http.cat/404
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
