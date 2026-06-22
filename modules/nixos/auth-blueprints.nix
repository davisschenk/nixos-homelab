{ config, pkgs, lib, ... }:
let
  defaultBlueprintsDir =
    "${config.services.authentik.authentikComponents.staticWorkdirDeps}/blueprints";

  mealieBlueprint = pkgs.writeText "mealie.yaml" ''
    version: 1
    metadata:
      name: "Mealie OIDC"
      labels:
        blueprints.goauthentik.io/instantiate: "true"
    entries:
      - model: authentik_core.group
        state: present
        identifiers:
          name: "mealie-user"
        attrs:
          name: "mealie-user"
      - model: authentik_core.group
        state: present
        identifiers:
          name: "mealie-admin"
        attrs:
          name: "mealie-admin"
      - model: authentik_providers_oauth2.oauth2provider
        state: present
        identifiers:
          name: "Mealie Provider"
        attrs:
          authorization_flow: !find [authentik_flows.flow, {slug: "default-provider-authorization-implicit-consent"}]
          client_id: "mealie"
          client_secret: !env_var MEALIE_OIDC_CLIENT_SECRET
          redirect_uris:
            - url: "https://mealie.schenkenberger.dev/"
              matching_mode: prefix
          sub_mode: hashed_user_id
          include_claims_in_id_token: true
          signing_key: !find [authentik_crypto.certificatekeypair, {name: "authentik Self-signed Certificate"}]
      - model: authentik_core.application
        state: present
        identifiers:
          slug: "mealie"
        attrs:
          name: "Mealie"
          slug: "mealie"
          provider: !find [authentik_providers_oauth2.oauth2provider, {name: "Mealie Provider"}]
          policy_engine_mode: any
  '';

  rommBlueprint = pkgs.writeText "romm.yaml" ''
    version: 1
    metadata:
      name: "RomM OIDC"
      labels:
        blueprints.goauthentik.io/instantiate: "true"
    entries:
      - model: authentik_providers_oauth2.oauth2provider
        state: present
        identifiers:
          name: "RomM Provider"
        attrs:
          authorization_flow: !find [authentik_flows.flow, {slug: "default-provider-authorization-implicit-consent"}]
          client_id: "romm"
          client_secret: !env_var ROMM_OIDC_CLIENT_SECRET
          redirect_uris:
            - url: "https://romm.schenkenberger.dev/api/oauth/openid"
              matching_mode: strict
          sub_mode: hashed_user_id
          include_claims_in_id_token: true
          signing_key: !find [authentik_crypto.certificatekeypair, {name: "authentik Self-signed Certificate"}]
      - model: authentik_core.application
        state: present
        identifiers:
          slug: "romm"
        attrs:
          name: "RomM"
          slug: "romm"
          provider: !find [authentik_providers_oauth2.oauth2provider, {name: "RomM Provider"}]
          policy_engine_mode: any
  '';

  forwardAuthBlueprint = pkgs.writeText "forward-auth.yaml" ''
    version: 1
    metadata:
      name: "Forward Auth Services"
      labels:
        blueprints.goauthentik.io/instantiate: "true"
    entries:
      - model: authentik_providers_proxy.proxyprovider
        state: present
        identifiers:
          name: "Grafana Provider"
        attrs:
          authorization_flow: !find [authentik_flows.flow, {slug: "default-provider-authorization-implicit-consent"}]
          external_host: "https://grafana.schenkenberger.dev"
          mode: forward_single
          cookie_domain: "schenkenberger.dev"
      - model: authentik_core.application
        state: present
        identifiers:
          slug: "grafana"
        attrs:
          name: "Grafana"
          slug: "grafana"
          provider: !find [authentik_providers_proxy.proxyprovider, {name: "Grafana Provider"}]
          policy_engine_mode: any
      - model: authentik_providers_proxy.proxyprovider
        state: present
        identifiers:
          name: "Sonarr Provider"
        attrs:
          authorization_flow: !find [authentik_flows.flow, {slug: "default-provider-authorization-implicit-consent"}]
          external_host: "https://sonarr.schenkenberger.dev"
          mode: forward_single
          cookie_domain: "schenkenberger.dev"
      - model: authentik_core.application
        state: present
        identifiers:
          slug: "sonarr"
        attrs:
          name: "Sonarr"
          slug: "sonarr"
          provider: !find [authentik_providers_proxy.proxyprovider, {name: "Sonarr Provider"}]
          policy_engine_mode: any
      - model: authentik_providers_proxy.proxyprovider
        state: present
        identifiers:
          name: "Radarr Provider"
        attrs:
          authorization_flow: !find [authentik_flows.flow, {slug: "default-provider-authorization-implicit-consent"}]
          external_host: "https://radarr.schenkenberger.dev"
          mode: forward_single
          cookie_domain: "schenkenberger.dev"
      - model: authentik_core.application
        state: present
        identifiers:
          slug: "radarr"
        attrs:
          name: "Radarr"
          slug: "radarr"
          provider: !find [authentik_providers_proxy.proxyprovider, {name: "Radarr Provider"}]
          policy_engine_mode: any
      - model: authentik_providers_proxy.proxyprovider
        state: present
        identifiers:
          name: "Prowlarr Provider"
        attrs:
          authorization_flow: !find [authentik_flows.flow, {slug: "default-provider-authorization-implicit-consent"}]
          external_host: "https://prowlarr.schenkenberger.dev"
          mode: forward_single
          cookie_domain: "schenkenberger.dev"
      - model: authentik_core.application
        state: present
        identifiers:
          slug: "prowlarr"
        attrs:
          name: "Prowlarr"
          slug: "prowlarr"
          provider: !find [authentik_providers_proxy.proxyprovider, {name: "Prowlarr Provider"}]
          policy_engine_mode: any
      - model: authentik_providers_proxy.proxyprovider
        state: present
        identifiers:
          name: "qBittorrent Provider"
        attrs:
          authorization_flow: !find [authentik_flows.flow, {slug: "default-provider-authorization-implicit-consent"}]
          external_host: "https://qbit.schenkenberger.dev"
          mode: forward_single
          cookie_domain: "schenkenberger.dev"
      - model: authentik_core.application
        state: present
        identifiers:
          slug: "qbittorrent"
        attrs:
          name: "qBittorrent"
          slug: "qbittorrent"
          provider: !find [authentik_providers_proxy.proxyprovider, {name: "qBittorrent Provider"}]
          policy_engine_mode: any
      - model: authentik_outposts.outpost
        state: present
        identifiers:
          name: "authentik Embedded Outpost"
        attrs:
          providers:
            - !find [authentik_providers_proxy.proxyprovider, {name: "Grafana Provider"}]
            - !find [authentik_providers_proxy.proxyprovider, {name: "Sonarr Provider"}]
            - !find [authentik_providers_proxy.proxyprovider, {name: "Radarr Provider"}]
            - !find [authentik_providers_proxy.proxyprovider, {name: "Prowlarr Provider"}]
            - !find [authentik_providers_proxy.proxyprovider, {name: "qBittorrent Provider"}]
  '';

  customBlueprintsDir = pkgs.runCommand "authentik-blueprints" { } ''
    cp -rL ${defaultBlueprintsDir}/. $out/
    chmod u+w $out
    mkdir -p $out/custom
    cp ${mealieBlueprint}       $out/custom/mealie.yaml
    cp ${rommBlueprint}         $out/custom/romm.yaml
    cp ${forwardAuthBlueprint}  $out/custom/forward-auth.yaml
  '';
in
{
  services.authentik.settings.blueprints_dir = customBlueprintsDir;
}
