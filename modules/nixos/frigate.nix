{ config, ... }:
{
  sops.secrets."frigate_rtsp_username" = {
    sopsFile = ../../../secrets/frigate.yaml;
  };
  sops.secrets."frigate_rtsp_password" = {
    sopsFile = ../../../secrets/frigate.yaml;
  };

  sops.templates."frigate-config" = {
    path = "/persist/containers/frigate/config.yml";
    content = ''
      mqtt:
        enabled: false

      ffmpeg:
        hwaccel_args: preset-vaapi

      detectors:
        ov:
          type: openvino
          device: AUTO

      model:
        path: /config/model_cache/openvino/FP32/ssdlite_mobilenet_v2.xml
        input_tensor: nhwc
        input_pixel_format: bgr
        width: 300
        height: 300

      cameras:
        hazycam:
          ffmpeg:
            inputs:
              - path: "rtsp://${config.sops.placeholder."frigate_rtsp_username"}:${config.sops.placeholder."frigate_rtsp_password"}@10.0.0.162/stream1"
                roles:
                  - record
              - path: "rtsp://${config.sops.placeholder."frigate_rtsp_username"}:${config.sops.placeholder."frigate_rtsp_password"}@10.0.0.162/stream2"
                roles:
                  - detect
          detect:
            enabled: true
            width: 1280
            height: 720
          objects:
            track:
              - dog
              - person
          audio:
            enabled: true
            listen:
              - bark
              - dog
          onvif:
            host: 10.0.0.162
            port: 2020
            user: "${config.sops.placeholder."frigate_rtsp_username"}"
            password: "${config.sops.placeholder."frigate_rtsp_password"}"
          autotracking:
            enabled: true
            calibrate_on_startup: true
            zooming: disabled
            required_zones: []
            tracked_object: dog
          record:
            enabled: true
            retain:
              days: 7
            events:
              retain:
                default: 14
    '';
  };

  virtualisation.oci-containers.containers.frigate = {
    image = "ghcr.io/blakeblackshear/frigate:stable";
    autoStart = true;
    ports = [ "127.0.0.1:${toString config.mylab.ports.frigate}:5000" ];
    volumes = [
      "/persist/containers/frigate:/config"
      "/data/frigate:/media/frigate"
      "/etc/localtime:/etc/localtime:ro"
    ];
    environment = {
      TZ = "America/Denver";
    };
    extraOptions = [
      "--device=/dev/dri/renderD128:/dev/dri/renderD128"
      "--shm-size=256m"
    ];
  };

  systemd.tmpfiles.rules = [
    "d /persist/containers/frigate 0755 root root -"
    "d /data/frigate 0755 root root -"
  ];

  systemd.services."docker-frigate" = {
    unitConfig.RequiresMountsFor = [
      "/persist/containers/frigate"
      "/data/frigate"
    ];
    after = [ "sops-nix.service" ];
    requires = [ "sops-nix.service" ];
  };
}
