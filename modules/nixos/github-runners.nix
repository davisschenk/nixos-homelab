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

  # One block per repo — copy this to add another. Fine-grained PAT per repo
  # (Administration: Read & write, scoped to just that repo) so a compromised
  # runner container can't touch other repos' runner registrations.
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
  };

  # EPHEMERAL runners exit 0 after one job by design; oci-containers' default
  # Restart=on-failure would leave the container dead until the next
  # `nixos-rebuild switch`. Restart=always re-registers a fresh runner for
  # the next queued job. RestartSec/burst limits keep a bad PAT from
  # crash-looping into start-limit-hit (mirrors coder-templates-push.service).
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
