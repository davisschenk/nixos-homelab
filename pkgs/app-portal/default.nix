{
  buildNpmPackage,
  runCommand,
}:
let
  starline = buildNpmPackage {
    pname = "star-technology-lines";
    version = "0.1.0";
    src = ../../apps/star-technology-lines;
    npmDepsHash = "sha256-vD6pzaQgW8Mx0dFyLtBcOt8w0KYfH+JaAF2AW8Q2AD4=";
    VITE_BASE_PATH = "/starline/";

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r dist/. $out/
      runHook postInstall
    '';
  };
in
runCommand "homelab-app-portal" { } ''
  mkdir -p $out/starline
  cp ${../../apps/portal/index.html} $out/index.html
  cp ${../../apps/portal/main.js} $out/main.js
  cp ${../../apps/portal/styles.css} $out/styles.css
  cp ${../../apps/portal/apps.json} $out/apps.json
  cp -r ${starline}/. $out/starline/
''
