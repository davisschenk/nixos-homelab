# Private app portal

`apps.schenkenberger.dev` is a static library for small homelab apps. Authentik protects the entire host through Caddy forward auth. The portal index and app manifest are served from this directory.

To add another static app, build it into a subdirectory of the `app-portal` package in `pkgs/app-portal/default.nix`, then add its card to `apps.json`. Keep the app's asset base path under its subdirectory.
