{ config, pkgs, ... }:
let
  defaultBlueprintsDir =
    "${config.services.authentik.authentikComponents.staticWorkdirDeps}/blueprints";

  customBlueprintsDir = pkgs.runCommand "authentik-blueprints" { } ''
    cp -rL ${defaultBlueprintsDir}/. $out/
    mkdir -p $out/custom
  '';
in
{
  services.authentik.settings.blueprints_dir = customBlueprintsDir;
}
