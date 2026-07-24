{ config, lib, ... }:
let
  sopsFile = ../../secrets/github-runners.yaml;
in
{
  sops.secrets."bog_bank_runner_pat" = { inherit sopsFile; };

  sops.templates."github-runner-bog-bank-env" = {
    content = ''
      ACCESS_TOKEN=${config.sops.placeholder."bog_bank_runner_pat"}
    '';
    restartUnits = [ "docker-github-runner-bog-bank.service" ];
  };

  # Fine-grained PAT scoped per repo limits blast radius if container compromised.
  virtualisation.oci-containers.containers.github-runner-bog-bank = {
    image = "myoung34/github-runner:2.335.1-ubuntu-noble";
    autoStart = true;
    environment = {
      REPO_URL = "https://github.com/davisschenk/bog-bank";
      RUNNER_SCOPE = "repo";
      RUNNER_NAME_PREFIX = "mangrove";
      LABELS = "self-hosted,homelab,mangrove";
      EPHEMERAL = "true";
      DISABLE_AUTO_UPDATE = "true";
    };
    environmentFiles = [ config.sops.templates."github-runner-bog-bank-env".path ];
    extraOptions = [ "--memory=4g" "--cpus=2" ];
    # docker-build.yml runs docker buildx here; give it the host's daemon
    # (docker-outside-of-docker) instead of nesting dockerd in the runner.
    volumes = [ "/var/run/docker.sock:/var/run/docker.sock" ];
  };

  # EPHEMERAL runners need Restart=always (exits after each job; on-failure would leave dead) plus rate limits.
  systemd.services."docker-github-runner-bog-bank" = {
    serviceConfig = {
      Restart = lib.mkForce "always";
      RestartSec = "10s";
    };
    unitConfig = {
      StartLimitIntervalSec = 120;
      StartLimitBurst = 20;
    };
  };
}
