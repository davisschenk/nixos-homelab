{ runCommand }:
runCommand "homelab-app-portal" { } ''
  mkdir -p $out
  cp ${../../apps/portal/index.html} $out/index.html
  cp ${../../apps/portal/main.js} $out/main.js
  cp ${../../apps/portal/styles.css} $out/styles.css
  cp ${../../apps/portal/apps.json} $out/apps.json
''
