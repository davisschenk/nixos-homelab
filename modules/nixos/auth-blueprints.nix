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

  customBlueprintsDir = pkgs.runCommand "authentik-blueprints" { } ''
    cp -rL ${defaultBlueprintsDir}/. $out/
    mkdir -p $out/custom
    cp ${mealieBlueprint} $out/custom/mealie.yaml
  '';
in
{
  services.authentik.settings.blueprints_dir = customBlueprintsDir;
}
