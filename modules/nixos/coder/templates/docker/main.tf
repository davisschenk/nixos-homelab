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

# GitHub external auth (see ../../default.nix's CODER_EXTERNAL_AUTH_0_* for
# the custom OAuth app this points at). `optional = true` so a workspace can
# still be created/started before the owner links it — git-over-SSH via
# `coder gitssh` keeps working as the fallback either way (Coder tries
# external-auth tokens first, falls back to SSH automatically). The token
# below feeds GH_TOKEN, which `gh` reads natively.
data "coder_external_auth" "github" {
  id       = "primary-github"
  optional = true
}

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"
  # No `dir` — deprecated in favor of just leaving it at $HOME (/home/dev,
  # per the image's non-root "dev" user).

  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = data.coder_workspace_owner.me.email
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = data.coder_workspace_owner.me.email
    GH_TOKEN            = try(data.coder_external_auth.github.access_token, "")
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
    # Docker auto-creates a missing bind-mount source as root:root, and the
    # container itself runs as non-root "dev" (uid 1000) — without this,
    # the very first command below would fail with permission denied on
    # $HOME. Recursive, since workspaces migrated from the old root-based
    # image have existing repo contents owned root:root all the way down.
    # Gated on a sentinel file rather than $HOME's own ownership — $HOME
    # itself can already read as dev:dev (e.g. Docker set it that way, or a
    # prior partial fix touched it) while everything underneath is still
    # root:root, which would make an ownership-based check skip the walk
    # and leave the real problem in place (hit this exact case on a real
    # migrated workspace). Recursive chown covers $HOME itself too, so no
    # separate non-recursive chown is needed before this.
    if [ ! -f "$HOME/.chown-done" ]; then
      sudo chown -R dev:dev "$HOME"
      touch "$HOME/.chown-done"
    fi

    # zsh's new-user-install wizard checks for a ~/.zshrc specifically (system-
    # wide /etc/zshrc doesn't satisfy it) and otherwise blocks the very first
    # interactive shell with an interactive prompt. Idempotent no-op after
    # the first start.
    touch ~/.zshrc

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

# Applies davisschenk/dotfiles on every agent start (chezmoi-managed zsh
# config + starship's Pure preset — see that repo's install.sh/README).
# No hardcoded `dotfiles_uri`: leaving it to `default_dotfiles_uri` instead
# means the module exposes its own `coder_parameter`, pre-filled with this
# default but overridable per-user — same "per-user config isn't a Nix/
# Terraform hardcode" philosophy as the Claude Code/Codex/gh auth setup
# documented in ../../default.nix.
module "dotfiles" {
  count                = data.coder_workspace.me.start_count
  source               = "registry.coder.com/coder/dotfiles/coder"
  version              = "~> 1.4"
  agent_id             = coder_agent.main.id
  default_dotfiles_uri = "https://github.com/davisschenk/dotfiles"
}

# VS Code in the browser, proxied by Coder under the *.schenkenberger.dev
# wildcard (see networking.nix) — this is what makes the workspace "easily
# accessible" from a browser without any local editor setup.
module "code-server" {
  count     = data.coder_workspace.me.start_count
  source    = "registry.coder.com/coder/code-server/coder"
  version   = "~> 1.5"
  agent_id  = coder_agent.main.id
  folder    = "/home/dev"
  order     = 1
  subdomain = true
}

# One button per project, opening code-server (the same instance the module
# above starts on :13337) straight into that project's folder — the
# `?folder=` query param is exactly how the module's own "code-server" app
# does it (confirmed from registry.coder.com/coder/code-server's source),
# so these just point the same port at different folders.
locals {
  projects = ["nixos-homelab", "tilt-app", "bog-bank"]
}

resource "coder_app" "project" {
  for_each     = data.coder_workspace.me.start_count > 0 ? toset(local.projects) : toset([])
  agent_id     = coder_agent.main.id
  slug         = each.value
  display_name = each.value
  url          = "http://localhost:13337/?folder=${urlencode("/home/dev/${each.value}")}"
  icon         = "/icon/code.svg"
  subdomain    = true
  order        = 2

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 5
    threshold = 6
  }
}

# Dev Containers integration — installs @devcontainers/cli on the parent
# agent (this workspace already bind-mounts the host's docker.sock below,
# which is exactly this module's prerequisite) so each project can define
# its own tools in its own .devcontainer/devcontainer.json instead of
# everything living in ../../workspace-image.nix. Each dev container that
# exists shows up in the Coder dashboard as a sub-agent with its own
# apps/SSH/port forwarding.
#
# All three projects now carry their own .devcontainer/devcontainer.json
# (each authored + build-tested with @devcontainers/cli directly, not just
# hand-written): nixos-homelab installs the just/nixd/statix/deadnix/sops
# toolchain via the nix feature's `packages` option; bog-bank installs Nix +
# direnv and activates its own flake.nix devShell (single source of truth
# for cargo/leptosfmt/etc, nothing to keep in sync here); tilt-app installs
# rust + node features plus sea-orm-cli via postCreateCommand (needs
# pkg-config + libssl-dev first — sea-orm's sqlx-postgres backend links
# native OpenSSL). Once these are in day-to-day use, sea-orm-cli and
# leptosfmt can come out of ../../workspace-image.nix — left in place for
# now since removing them today would break anyone still relying on the
# outer shell before switching over.
module "devcontainers-cli" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/devcontainers-cli/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main.id
}

resource "coder_devcontainer" "project" {
  for_each         = data.coder_workspace.me.start_count > 0 ? toset(local.projects) : toset([])
  depends_on       = [module.devcontainers-cli]
  agent_id         = coder_agent.main.id
  workspace_folder = "/home/dev/${each.value}"
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

  # The container's /etc/group lists "dev" as a member of "docker" (gid 131,
  # matching mangrove's real docker group), but that mapping alone doesn't
  # apply supplementary groups to the running process — Docker sets a
  # container process's groups explicitly at creation, it doesn't consult
  # NSS/group file membership at runtime. Without this, `docker ps` inside
  # the workspace fails with "permission denied" on the bind-mounted socket
  # despite /etc/group looking correct (confirmed on a real deploy).
  group_add = ["131"]

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  # Bind mount, not a docker_volume — /var/lib/docker (and any named volume
  # in it) is wiped on every host reboot, /persist is not. Docker
  # auto-creates this as root:root on first use since it doesn't exist yet;
  # the agent's startup_script chowns it to dev:dev on every start (a no-op
  # once already correct).
  volumes {
    host_path      = "/persist/coder/workspaces/${data.coder_workspace.me.name}"
    container_path = "/home/dev"
    read_only      = false
  }

  # Docker-outside-of-Docker: the workspace container has no daemon of its
  # own, just the CLI + compose plugin, talking to the *host's* dockerd over
  # its socket — the same pattern Coder itself uses for provisioning. This is
  # why the image's "docker" group is set to mangrove's real docker GID (131).
  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
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
