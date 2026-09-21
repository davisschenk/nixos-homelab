{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.mylab.mcp;
  serverNames = builtins.attrNames cfg.servers;
  hostPorts = map (name: cfg.servers.${name}.hostPort) serverNames;
  domains = map (name: cfg.servers.${name}.domain) serverNames;
  tokenAuth = pkgs.writers.writePython3Bin "mcp-token-auth" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ../../pkgs/mcp-token-auth/server.py);
in
{
  options.mylab.mcp = {
    enable = lib.mkEnableOption "custom Streamable HTTP MCP hosting";

    servers = lib.mkOption {
      default = { };
      description = "Custom MCP server containers published through Caddy.";
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            options = {
              image = lib.mkOption {
                type = lib.types.str;
                description = "OCI image containing the MCP server.";
              };

              hostPort = lib.mkOption {
                type = lib.types.port;
                description = "Loopback port allocated to the MCP server.";
              };

              containerPort = lib.mkOption {
                type = lib.types.port;
                default = 8000;
                description = "MCP server port inside the container.";
              };

              domain = lib.mkOption {
                type = lib.types.str;
                default = "mcp-${name}.schenkenberger.dev";
                description = "Public hostname for the MCP server.";
              };

              environment = lib.mkOption {
                type = lib.types.attrsOf lib.types.str;
                default = { };
                description = "Non-secret environment variables passed to the container.";
              };

              environmentFiles = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Environment files containing MCP server secrets.";
              };

              volumes = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Container volume mappings.";
              };

              extraOptions = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Additional arguments passed to the container runtime.";
              };
            };
          }
        )
      );
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = builtins.length hostPorts == builtins.length (lib.unique hostPorts);
        message = "mylab.mcp.servers must use unique host ports.";
      }
      {
        assertion = builtins.length domains == builtins.length (lib.unique domains);
        message = "mylab.mcp.servers must use unique domains.";
      }
      {
        assertion = builtins.all (name: builtins.match "[a-z0-9][a-z0-9-]*" name != null) serverNames;
        message = "mylab.mcp server names may contain only lowercase letters, numbers, and hyphens.";
      }
    ];

    sops.secrets.mcp_bearer_token = {
      sopsFile = ../../secrets/mcp.yaml;
      restartUnits = [ "mcp-token-auth.service" ];
    };

    systemd.services.mcp-token-auth = {
      description = "MCP bearer token verifier";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${tokenAuth}/bin/mcp-token-auth --port ${toString config.mylab.ports.mcpAuth} --token-file %d/token";
        LoadCredential = "token:${config.sops.secrets.mcp_bearer_token.path}";
        DynamicUser = true;
        Restart = "on-failure";
        RestartSec = "5s";
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
        ];
      };
    };

    virtualisation.oci-containers.containers = lib.mapAttrs' (
      name: server:
      lib.nameValuePair "mcp-${name}" {
        inherit (server)
          image
          environment
          environmentFiles
          volumes
          extraOptions
          ;
        autoStart = true;
        ports = [ "127.0.0.1:${toString server.hostPort}:${toString server.containerPort}" ];
      }
    ) cfg.servers;
  };
}
