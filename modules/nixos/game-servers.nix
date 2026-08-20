{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.mylab.gameServers;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
  ingressEntries = builtins.fromJSON (builtins.readFile ../../infra/ingress.json);
  ingressByName = lib.listToAttrs (map (entry: lib.nameValuePair entry.name entry) ingressEntries);
  uuidPattern = "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}";
  namePattern = "[a-z0-9_-]+";
  domainPattern = "(\\*\\.)?[a-z0-9]([a-z0-9.-]*[a-z0-9])?";
  uuidValid = value: value == null || builtins.match uuidPattern value != null;
  selectorSet = owner: owner.email != null || owner.externalId != null;
  selectorValid = owner: (owner.email != null) != (owner.externalId != null);
  ownerType = types.submodule {
    options = {
      email = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      externalId = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
    };
  };
  allocationType = types.submodule {
    options = {
      ip = mkOption { type = types.str; };
      port = mkOption { type = types.port; };
      primary = mkOption {
        type = types.bool;
        default = false;
      };
    };
  };
  exposureType = types.submodule {
    options = {
      allocation = mkOption { type = types.str; };
      ingress = mkOption { type = types.str; };
      protocol = mkOption {
        type = types.enum [
          "tcp"
          "udp"
        ];
      };
    };
  };
  limitsType = types.submodule {
    options = {
      memory = mkOption {
        type = types.ints.unsigned;
        default = 1024;
      };
      swap = mkOption {
        type = types.int;
        default = 0;
      };
      disk = mkOption {
        type = types.ints.unsigned;
        default = 10240;
      };
      io = mkOption {
        type = types.ints.between 10 1000;
        default = 500;
      };
      cpu = mkOption {
        type = types.ints.unsigned;
        default = 100;
      };
      threads = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
    };
  };
  featureLimitsType = types.submodule {
    options = {
      databases = mkOption {
        type = types.ints.unsigned;
        default = 0;
      };
      allocations = mkOption {
        type = types.ints.unsigned;
        default = 0;
      };
      backups = mkOption {
        type = types.ints.unsigned;
        default = 0;
      };
    };
  };
  infrarustRouteType = types.submodule {
    options = {
      enable = mkEnableOption "hostname routing through Infrarust";
      domains = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      proxyMode = mkOption {
        type = types.enum [
          "passthrough"
          "offline"
          "server_only"
          "client_only"
        ];
        default = "passthrough";
      };
      sendProxyProtocol = mkOption {
        type = types.bool;
        default = false;
      };
      wakeOnConnect = mkOption {
        type = types.bool;
        default = false;
      };
      startTimeout = mkOption {
        type = types.str;
        default = "180s";
      };
      pollInterval = mkOption {
        type = types.str;
        default = "5s";
      };
      shutdownAfter = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
    };
  };
  serverType = types.submodule {
    options = {
      state = mkOption {
        type = types.enum [
          "present"
          "absent"
        ];
        default = "present";
      };
      adoptUuid = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      deleteConfirmationUuid = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      displayName = mkOption {
        type = types.str;
        default = "";
      };
      description = mkOption {
        type = types.str;
        default = "";
      };
      owner = mkOption {
        type = ownerType;
        default = { };
      };
      eggUuid = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      image = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      startup = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      environment = mkOption {
        type = types.attrsOf types.str;
        default = { };
      };
      secretEnvironmentFile = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      limits = mkOption {
        type = limitsType;
        default = { };
      };
      featureLimits = mkOption {
        type = featureLimitsType;
        default = { };
      };
      oomKiller = mkOption {
        type = types.bool;
        default = true;
      };
      allocations = mkOption {
        type = types.attrsOf allocationType;
        default = { };
      };
      exposures = mkOption {
        type = types.listOf exposureType;
        default = [ ];
      };
      minecraft.infrarust = mkOption {
        type = infrarustRouteType;
        default = { };
      };
    };
  };
  presentServers = lib.filterAttrs (_: server: server.state == "present") cfg.servers;
  allAllocations = lib.concatLists (
    lib.mapAttrsToList (
      _: server:
      lib.mapAttrsToList (
        _: allocation: "${allocation.ip}:${toString allocation.port}"
      ) server.allocations
    ) presentServers
  );
  allDomains = lib.concatLists (
    lib.mapAttrsToList (_: server: server.minecraft.infrarust.domains) presentServers
  );
  exposureValid =
    server: exposure:
    let
      allocation = server.allocations.${exposure.allocation} or null;
      gate = ingressByName.${exposure.ingress} or null;
    in
    allocation != null
    && gate != null
    && gate.target == "mangrove"
    && gate.protocol == exposure.protocol
    && allocation.port >= gate.from
    && allocation.port <= gate.to;
  domainValid =
    domain:
    domain == lib.toLower domain
    && builtins.match domainPattern domain != null
    && domain != cfg.infrarust.domainSuffix
    && lib.hasSuffix ".${cfg.infrarust.domainSuffix}" domain;
  serverValid =
    server:
    if server.state == "absent" then
      server.deleteConfirmationUuid != null && uuidValid server.deleteConfirmationUuid
    else
      uuidValid server.adoptUuid
      && server.eggUuid != null
      && uuidValid server.eggUuid
      && selectorValid (if selectorSet server.owner then server.owner else cfg.defaultOwner)
      && lib.length (lib.filter (allocation: allocation.primary) (lib.attrValues server.allocations)) == 1
      && lib.all (exposureValid server) server.exposures
      && (
        !server.minecraft.infrarust.enable
        || (
          cfg.infrarust.enable
          && lib.all (allocation: allocation.ip == "127.0.0.1") (lib.attrValues server.allocations)
          && server.minecraft.infrarust.domains != [ ]
          && lib.all domainValid server.minecraft.infrarust.domains
        )
      );
  infrarustGate = ingressByName.${cfg.infrarust.publicIngress} or null;
  serverManifest = lib.mapAttrs (name: server: {
    inherit (server)
      state
      description
      image
      startup
      environment
      ;
    adopt_uuid = server.adoptUuid;
    delete_confirmation_uuid = server.deleteConfirmationUuid;
    display_name = if server.displayName == "" then name else server.displayName;
    owner =
      if selectorSet server.owner then
        {
          email = server.owner.email;
          external_id = server.owner.externalId;
        }
      else
        null;
    egg_uuid = server.eggUuid;
    secret_environment_file = server.secretEnvironmentFile;
    limits = {
      inherit (server.limits)
        memory
        swap
        disk
        io
        cpu
        threads
        ;
    };
    feature_limits = {
      inherit (server.featureLimits) databases allocations backups;
    };
    oom_killer = server.oomKiller;
    allocations = lib.mapAttrs (_: allocation: {
      inherit (allocation) ip port primary;
    }) server.allocations;
    exposures = map (exposure: {
      inherit (exposure) allocation ingress protocol;
    }) server.exposures;
    minecraft.infrarust = {
      inherit (server.minecraft.infrarust) domains;
      enable = server.minecraft.infrarust.enable;
      proxy_mode = server.minecraft.infrarust.proxyMode;
      send_proxy_protocol = server.minecraft.infrarust.sendProxyProtocol;
      wake_on_connect = server.minecraft.infrarust.wakeOnConnect;
      start_timeout = server.minecraft.infrarust.startTimeout;
      poll_interval = server.minecraft.infrarust.pollInterval;
      shutdown_after = server.minecraft.infrarust.shutdownAfter;
    };
  }) cfg.servers;
  manifest = pkgs.writeText "pelican-reconciler-manifest.json" (
    builtins.toJSON {
      panel_url = cfg.panelUrl;
      panel_host = cfg.panelHost;
      public_panel_url = cfg.publicPanelUrl;
      node_uuid = cfg.nodeUuid;
      default_owner = {
        email = cfg.defaultOwner.email;
        external_id = cfg.defaultOwner.externalId;
      };
      application_api_key_file = cfg.applicationApiKeyFile;
      client_api_key_file = cfg.clientApiKeyFile;
      backup_marker = cfg.backupMarker;
      backup_max_age_seconds = cfg.backupMaxAgeHours * 3600;
      state_file = cfg.stateFile;
      ingress = ingressEntries;
      servers = serverManifest;
      infrarust = {
        enable = cfg.infrarust.enable;
        public_ingress = cfg.infrarust.publicIngress;
        domain_suffix = cfg.infrarust.domainSuffix;
        listen_address = cfg.infrarust.listenAddress;
        listen_port = cfg.infrarust.listenPort;
        admin_address = cfg.infrarust.adminAddress;
        admin_port = cfg.infrarust.adminPort;
        admin_api_key_file = cfg.infrarust.adminApiKeyFile;
        external_url = cfg.infrarust.externalUrl;
        runtime_dir = "/run/infrarust";
        plugins_dir = "/var/lib/infrarust/plugins";
        ban_file = "/var/lib/infrarust/bans.json";
      };
    }
  );
  reconcilerCommand = pkgs.writeShellApplication {
    name = "game-server-reconcile";
    text = ''
      exec ${cfg.package}/bin/pelican-reconcile --manifest ${manifest} "$@"
    '';
  };
in
{
  options.mylab.gameServers = {
    enable = mkEnableOption "declarative Pelican game-server reconciliation";
    panelUrl = mkOption {
      type = types.str;
      default = "http://127.0.0.1:${toString config.mylab.ports.pelican}";
    };
    panelHost = mkOption {
      type = types.str;
      default = "panel.schenkenberger.dev";
    };
    publicPanelUrl = mkOption {
      type = types.str;
      default = "https://panel.schenkenberger.dev";
    };
    nodeUuid = mkOption {
      type = types.str;
      default = config.services.pelican.wings.uuid;
    };
    defaultOwner = mkOption {
      type = ownerType;
      default = { };
    };
    applicationApiKeyFile = mkOption {
      type = types.str;
      default = "/run/secrets/pelican_reconciler_api_key";
    };
    clientApiKeyFile = mkOption {
      type = types.nullOr types.str;
      default = null;
    };
    backupMarker = mkOption {
      type = types.str;
      default = "/var/lib/pelican-reconciler/last-restic-success";
    };
    backupMaxAgeHours = mkOption {
      type = types.ints.positive;
      default = 36;
    };
    stateFile = mkOption {
      type = types.str;
      default = "/var/lib/pelican-reconciler/servers.json";
    };
    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ../../pkgs/pelican-reconciler { };
    };
    servers = mkOption {
      type = types.attrsOf serverType;
      default = { };
    };
    infrarust = {
      enable = mkEnableOption "native Infrarust V2 proxy";
      package = mkOption {
        type = types.package;
        default = pkgs.callPackage ../../pkgs/infrarust { };
      };
      publicIngress = mkOption {
        type = types.str;
        default = "games-tcp";
      };
      domainSuffix = mkOption {
        type = types.str;
        default = "mc.schenkenberger.dev";
      };
      listenAddress = mkOption {
        type = types.str;
        default = "0.0.0.0";
      };
      listenPort = mkOption {
        type = types.port;
        default = config.mylab.ports.minecraft;
      };
      adminAddress = mkOption {
        type = types.str;
        default = "127.0.0.1";
      };
      adminPort = mkOption {
        type = types.port;
        default = config.mylab.ports.infrarust;
      };
      adminApiKeyFile = mkOption {
        type = types.str;
        default = "/run/secrets/infrarust_api_key";
      };
      externalUrl = mkOption {
        type = types.str;
        default = "https://infrarust.schenkenberger.dev";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = selectorValid cfg.defaultOwner;
        message = "mylab.gameServers.defaultOwner must set exactly one of email or externalId.";
      }
      {
        assertion = uuidValid cfg.nodeUuid;
        message = "mylab.gameServers.nodeUuid must be a valid UUID.";
      }
      {
        assertion = lib.all (name: builtins.match namePattern name != null) (lib.attrNames cfg.servers);
        message = "Game-server catalog names must match [a-z0-9_-]+.";
      }
      {
        assertion = lib.all serverValid (lib.attrValues cfg.servers);
        message = "A game-server declaration is incomplete or violates allocation, ingress, owner, deletion, or Infrarust constraints.";
      }
      {
        assertion = lib.length allAllocations == lib.length (lib.unique allAllocations);
        message = "Pelican allocations must be unique across declared present servers.";
      }
      {
        assertion = lib.length allDomains == lib.length (lib.unique allDomains);
        message = "Infrarust domains must be unique across declared present servers.";
      }
      {
        assertion =
          !cfg.infrarust.enable
          || (
            infrarustGate != null
            && infrarustGate.target == "mangrove"
            && infrarustGate.protocol == "tcp"
            && cfg.infrarust.listenPort >= infrarustGate.from
            && cfg.infrarust.listenPort <= infrarustGate.to
          );
        message = "The Infrarust listener must be covered by its declared TCP ingress gate.";
      }
      {
        assertion =
          !cfg.infrarust.enable
          || lib.all (
            server:
            lib.all (allocation: allocation.ip != "0.0.0.0" || allocation.port != cfg.infrarust.listenPort) (
              lib.attrValues server.allocations
            )
          ) (lib.attrValues presentServers);
        message = "An all-interface Pelican allocation conflicts with the native Infrarust listener.";
      }
      {
        assertion =
          !lib.any (server: server.state == "absent" || server.minecraft.infrarust.wakeOnConnect) (
            lib.attrValues cfg.servers
          )
          || cfg.clientApiKeyFile != null;
        message = "Guarded deletion and wake-on-connect require clientApiKeyFile.";
      }
    ];

    sops.secrets.pelican_reconciler_api_key = {
      sopsFile = ../../secrets/pelican.yaml;
      owner = "root";
      group = "game-servers";
      mode = "0440";
    };
    sops.secrets.pelican_reconciler_client_key = mkIf (cfg.clientApiKeyFile != null) {
      sopsFile = ../../secrets/pelican.yaml;
      owner = "root";
      group = "game-servers";
      mode = "0440";
    };
    sops.secrets.infrarust_api_key = mkIf cfg.infrarust.enable {
      sopsFile = ../../secrets/pelican.yaml;
      owner = "infrarust";
      group = "game-servers";
      mode = "0440";
    };

    users.groups.game-servers = { };
    users.groups.infrarust = mkIf cfg.infrarust.enable { };
    users.users.infrarust = mkIf cfg.infrarust.enable {
      isSystemUser = true;
      group = "infrarust";
      extraGroups = [ "game-servers" ];
    };

    environment.systemPackages = [ reconcilerCommand ];
    systemd.tmpfiles.rules = [
      "d /var/lib/pelican-reconciler 2750 root game-servers -"
    ];

    systemd.services.pelican-reconcile = {
      description = "Reconcile Nix-defined Pelican game servers";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
        "nginx.service"
        "pelican-panel-setup.service"
      ];
      restartTriggers = [ manifest ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${cfg.package}/bin/pelican-reconcile --manifest ${manifest} apply";
        User = "root";
        Group = "game-servers";
        UMask = "0027";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ "/var/lib/pelican-reconciler" ];
      };
    };

    systemd.services.infrarust = mkIf cfg.infrarust.enable {
      description = "Infrarust Minecraft proxy";
      wantedBy = [ "multi-user.target" ];
      wants = [
        "network-online.target"
        "pelican-reconcile.service"
      ];
      after = [
        "network-online.target"
        "pelican-reconcile.service"
      ];
      restartTriggers = [
        manifest
        cfg.infrarust.package
      ];
      serviceConfig = {
        User = "infrarust";
        Group = "infrarust";
        RuntimeDirectory = "infrarust";
        RuntimeDirectoryMode = "0700";
        StateDirectory = "infrarust";
        StateDirectoryMode = "0750";
        ExecStartPre = "${cfg.package}/bin/pelican-reconcile --manifest ${manifest} render-infrarust";
        ExecStart = "${cfg.infrarust.package}/bin/infrarust --config /run/infrarust/infrarust.toml";
        Restart = "on-failure";
        RestartSec = "5s";
        UMask = "0077";
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "strict";
        ReadWritePaths = [
          "/run/infrarust"
          "/var/lib/infrarust"
        ];
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
      };
    };

    environment.persistence."/persist".directories = [
      "/var/lib/pelican-reconciler"
    ]
    ++ lib.optional cfg.infrarust.enable "/var/lib/infrarust";
  };
}
