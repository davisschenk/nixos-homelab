{ config, pkgs, ... }:
let
  defaultBlueprintsDir =
    "${config.services.authentik.authentikComponents.staticWorkdirDeps}/blueprints";

  groupsBlueprint = pkgs.writeText "groups.yaml" (builtins.readFile ./blueprints/groups.yaml);
  mealieBlueprint = pkgs.writeText "mealie.yaml" (builtins.readFile ./blueprints/mealie.yaml);
  rommBlueprint = pkgs.writeText "romm.yaml" (builtins.readFile ./blueprints/romm.yaml);
  brandingBlueprint = pkgs.writeText "branding.yaml" (builtins.readFile ./blueprints/branding.yaml);
  grafanaBlueprint = pkgs.writeText "grafana.yaml" (builtins.readFile ./blueprints/grafana.yaml);
  sonarrBlueprint = pkgs.writeText "sonarr.yaml" (builtins.readFile ./blueprints/sonarr.yaml);
  radarrBlueprint = pkgs.writeText "radarr.yaml" (builtins.readFile ./blueprints/radarr.yaml);
  prowlarrBlueprint = pkgs.writeText "prowlarr.yaml" (builtins.readFile ./blueprints/prowlarr.yaml);
  qbittorrentBlueprint = pkgs.writeText "qbittorrent.yaml" (builtins.readFile ./blueprints/qbittorrent.yaml);
  jellyfinBlueprint = pkgs.writeText "jellyfin.yaml" (builtins.readFile ./blueprints/jellyfin.yaml);
  jellyseerrBlueprint = pkgs.writeText "jellyseerr.yaml" (builtins.readFile ./blueprints/jellyseerr.yaml);
  copypartyBlueprint = pkgs.writeText "copyparty.yaml" (builtins.readFile ./blueprints/copyparty.yaml);
  actualBlueprint = pkgs.writeText "actual.yaml" (builtins.readFile ./blueprints/actual.yaml);
  outpostBlueprint = pkgs.writeText "outpost.yaml" (builtins.readFile ./blueprints/outpost.yaml);

  customBlueprintsDir = pkgs.runCommand "authentik-blueprints" { } ''
    cp -rL ${defaultBlueprintsDir}/. $out/
    chmod u+w $out
    mkdir -p $out/custom
    cp ${groupsBlueprint}                  $out/custom/groups.yaml
    cp ${mealieBlueprint}                  $out/custom/mealie.yaml
    cp ${rommBlueprint}                    $out/custom/romm.yaml
    cp ${brandingBlueprint}                $out/custom/branding.yaml
    cp ${grafanaBlueprint}      $out/custom/grafana.yaml
    cp ${sonarrBlueprint}       $out/custom/sonarr.yaml
    cp ${radarrBlueprint}       $out/custom/radarr.yaml
    cp ${prowlarrBlueprint}     $out/custom/prowlarr.yaml
    cp ${qbittorrentBlueprint}  $out/custom/qbittorrent.yaml
    cp ${jellyfinBlueprint}     $out/custom/jellyfin.yaml
    cp ${jellyseerrBlueprint}   $out/custom/jellyseerr.yaml
    cp ${copypartyBlueprint}    $out/custom/copyparty.yaml
    cp ${actualBlueprint}       $out/custom/actual.yaml
    cp ${outpostBlueprint}      $out/custom/outpost.yaml
  '';
in
{
  services.authentik.settings.blueprints_dir = customBlueprintsDir;
}
