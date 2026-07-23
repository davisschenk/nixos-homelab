{ config, pkgs, ... }:
{
  # Browser-based VNC console for libvirt VMs (currently just the "windows" gaming VM),
  # fronted by Caddy + Authentik forward-auth — see networking.nix and
  # authentik/blueprints/vm-console.yaml.
  systemd.services.vm-console = {
    description = "noVNC web console for libvirt VMs";
    after = [ "libvirtd.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.novnc}/bin/novnc --listen 127.0.0.1:${toString config.mylab.ports.novnc} --vnc localhost:5900";
      DynamicUser = true;
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };
}
