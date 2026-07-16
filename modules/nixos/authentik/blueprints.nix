{ config, pkgs, lib, ... }:
let
  defaultBlueprintsDir =
    "${config.services.authentik.authentikComponents.staticWorkdirDeps}/blueprints";

  blueprintNames = [
    "groups"
    "mealie"
    "romm"
    "branding"
    "grafana"
    "sonarr"
    "radarr"
    "prowlarr"
    "qbittorrent"
    "jellyfin"
    "jellyseerr"
    "copyparty"
    "actual"
    "outpost"
    "frigate"
    "home-assistant"
    "pelican"
    "wealthfolio"
    "tilt"
    "coder"
  ];

  customBlueprintsDir = pkgs.runCommand "authentik-blueprints" { } ''
    cp -rL ${defaultBlueprintsDir}/. $out/
    chmod u+w $out
    mkdir -p $out/custom
    ${lib.concatMapStrings (name: "cp ${./blueprints/${name}.yaml} $out/custom/${name}.yaml\n") blueprintNames}
  '';
in
{
  services.authentik.settings.blueprints_dir = customBlueprintsDir;
}
