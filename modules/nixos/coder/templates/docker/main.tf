# Coder workspace template: Docker containers on the same host running
# Nix-built "coder-workspace:latest" (see ../../workspace-image.nix,
# loaded into the daemon by the coder-workspace-image-load systemd unit).
#
# Not deployed via Nix — push with:
#   coder login https://coder.schenkenberger.dev
#   cd modules/nixos/coder/templates/docker && terraform init
#   coder templates push docker-dev --directory . --yes

terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 2.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 4.0"
    }
  }
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"
  # No `dir` — deprecated in favor of just leaving it at $HOME (which for
  # root already is /root anyway).

  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = data.coder_workspace_owner.me.email
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = data.coder_workspace_owner.me.email
  }

  # Runs once when the agent starts. Sets up git identity and clones the
  # standing project set on first start. Git-over-SSH auth is handled by
  # Coder itself — every workspace's agent transparently wraps `ssh` via
  # `coder gitssh` using a per-user key Coder generates and manages (`coder
  # publickey`), so no key material needs to be provisioned here at all;
  # the user adds that one Coder-managed public key to GitHub once, and it
  # works for every workspace they ever create. Host key verification still
  # needs a populated known_hosts, though — `coder gitssh` doesn't relax
  # that on its own (confirmed: cloning failed with "Host key verification
  # failed" until known_hosts was seeded here). No `set -e` — a failure
  # cloning one repo (or a transient ssh-keyscan network hiccup on
  # container start) shouldn't block git config or the other clones.
  # $HOME is bind-mounted from /persist/coder/workspaces/<name>, so this is
  # idempotent across stop/start — already-cloned repos are left alone,
  # never re-cloned or clobbered.
  startup_script = <<-EOT
    git config --global user.name "${coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)}"
    git config --global user.email "${data.coder_workspace_owner.me.email}"

    mkdir -p ~/.ssh
    touch ~/.ssh/known_hosts
    for i in 1 2 3 4 5; do
      ssh-keyscan -t ed25519 github.com >> ~/.ssh/known_hosts 2>/dev/null && break
      sleep 2
    done

    clone_if_missing() {
      dest="$HOME/$2"
      if [ ! -d "$dest" ]; then
        git clone "$1" "$dest"
      fi
    }
    clone_if_missing git@github.com:davisschenk/nixos-homelab.git nixos-homelab
    clone_if_missing git@github.com:davisschenk/tilt-app.git tilt-app
    clone_if_missing git@github.com:davisschenk/bog-bank.git bog-bank
  EOT
}

# VS Code in the browser, proxied by Coder under the *.schenkenberger.dev
# wildcard (see networking.nix) — this is what makes the workspace "easily
# accessible" from a browser without any local editor setup.
module "code-server" {
  count     = data.coder_workspace.me.start_count
  source    = "registry.coder.com/coder/code-server/coder"
  version   = "~> 1.5"
  agent_id  = coder_agent.main.id
  folder    = "/root"
  order     = 1
  subdomain = true
}

# Looked up rather than pulled/built — must already be present in the local
# daemon (loaded by coder-workspace-image-load.service), errors clearly if not.
data "docker_image" "workspace" {
  name = "coder-workspace:latest"
}

resource "docker_container" "workspace" {
  count      = data.coder_workspace.me.start_count
  image      = data.docker_image.workspace.id
  name       = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname   = data.coder_workspace.me.name
  entrypoint = ["sh", "-c", coder_agent.main.init_script]
  env        = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  # Bind mount, not a docker_volume — /var/lib/docker (and any named volume
  # in it) is wiped on every host reboot, /persist is not. Runs as root
  # inside the container (no uid matching needed for a bind mount owned by
  # the host's docker daemon), acceptable since this template is gated to a
  # single admin account via the Authentik policy binding on the Coder app.
  volumes {
    host_path      = "/persist/coder/workspaces/${data.coder_workspace.me.name}"
    container_path = "/root"
    read_only      = false
  }

  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
}
