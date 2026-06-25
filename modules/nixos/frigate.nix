{ config, ... }:
{
  sops.secrets."frigate_rtsp_username" = {
    sopsFile = ../../secrets/frigate.yaml;
  };
  sops.secrets."frigate_rtsp_password" = {
    sopsFile = ../../secrets/frigate.yaml;
  };

  sops.templates."frigate-config" = {
    restartUnits = [ "docker-frigate.service" ];
    content = ''
      mqtt:
        enabled: true
        host: host.docker.internal
        port: 1883

      ffmpeg:
        hwaccel_args: preset-vaapi

      model:
        path: /openvino-model/ssdlite_mobilenet_v2.xml
        input_tensor: nhwc
        input_pixel_format: bgr
        width: 300
        height: 300

      detectors:
        ov:
          type: openvino
          device: AUTO

      cameras:
        hazycam:
          ffmpeg:
            inputs:
              - path: "rtsp://${config.sops.placeholder."frigate_rtsp_username"}:${config.sops.placeholder."frigate_rtsp_password"}@10.0.0.162/stream1"
                roles:
                  - record
                  - audio
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
          zones:
            full_frame:
              coordinates: 0,0,1280,0,1280,720,0,720
          onvif:
            host: 10.0.0.162
            port: 2020
            user: "${config.sops.placeholder."frigate_rtsp_username"}"
            password: "${config.sops.placeholder."frigate_rtsp_password"}"
            autotracking:
              enabled: true
              calibrate_on_startup: true
              zooming: disabled
              required_zones:
                - full_frame
              track:
                - dog
          record:
            enabled: true
            continuous:
              days: 7
            detections:
              retain:
                days: 14
                mode: all
    '';
  };

  virtualisation.oci-containers.containers.frigate = {
    image = "ghcr.io/blakeblackshear/frigate:stable";
    autoStart = true;
    ports = [ "127.0.0.1:${toString config.mylab.ports.frigate}:5000" ];
    volumes = [
      "/persist/containers/frigate:/config"
      "${config.sops.templates."frigate-config".path}:/config/config.yml:ro"
      "/data/frigate:/media/frigate"
      "/etc/localtime:/etc/localtime:ro"
    ];
    environment = {
      TZ = "America/Denver";
    };
    extraOptions = [
      "--device=/dev/dri/renderD128:/dev/dri/renderD128"
      "--shm-size=256m"
      "--add-host=host.docker.internal:host-gateway"
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
  };
}
