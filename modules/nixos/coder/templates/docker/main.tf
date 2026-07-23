# Coder workspace template: one Docker container per workspace, built
# directly from the chosen repo's .devcontainer/devcontainer.json by
# envbuilder (https://github.com/coder/envbuilder) — no custom base image
# to build or load, unlike the old workspace-image.nix approach.
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
    envbuilder = {
      source = "coder/envbuilder"
    }
  }
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# No longer optional: envbuilder clones over HTTPS with this token before
# the agent (and therefore `coder gitssh`) exists, so unlike the pre-envbuilder
# template there's no SSH fallback — a workspace can't build without it.
data "coder_external_auth" "github" {
  id       = "primary-github"
  optional = false
}

# One workspace = one repo now — envbuilder builds a single devcontainer.json
# per container, so the old "clone all three projects into one workspace"
# model doesn't apply. Immutable: the persistent bind mount below is keyed to
# whichever repo first built it, so changing this on an existing workspace
# would leave stale build state sitting next to the new repo's clone.
data "coder_parameter" "repo" {
  name         = "repo"
  display_name = "Repository"
  description  = "Project to clone and build via its .devcontainer/devcontainer.json."
  mutable      = false
  order        = 1

  option {
    name  = "nixos-homelab"
    value = "https://github.com/davisschenk/nixos-homelab.git"
    icon  = "/icon/github.svg"
  }
  option {
    name  = "tilt-app"
    value = "https://github.com/davisschenk/tilt-app.git"
    icon  = "/icon/github.svg"
  }
  option {
    name  = "bog-bank"
    value = "https://github.com/davisschenk/bog-bank.git"
    icon  = "/icon/github.svg"
  }
}

locals {
  repo_url  = data.coder_parameter.repo.value
  repo_name = trimsuffix(basename(local.repo_url), ".git")

  # /persist survives reboots (root fs doesn't); /workspaces is where the
  # container sees it. Bind-mounted (not docker_volume) for the same reason
  # the old template was: /var/lib/docker is wiped every boot.
  workspace_host_dir = "/persist/coder/workspaces/${data.coder_workspace.me.name}"
  workspace_dir      = "/workspaces/${local.repo_name}"
  tools_dir          = "/workspaces/.coder-tools"

  git_author_name  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
  git_author_email = data.coder_workspace_owner.me.email

  # Pin a real release, not :latest — see https://github.com/coder/envbuilder/pkgs/container/envbuilder
  devcontainer_builder_image = "ghcr.io/coder/envbuilder:1.3.0"

  envbuilder_env = {
    ENVBUILDER_GIT_URL = local.repo_url
    # GitHub accepts any non-empty username when the password is a valid
    # OAuth/App token — "x-access-token" is GitHub's documented placeholder.
    ENVBUILDER_GIT_USERNAME     = "x-access-token"
    ENVBUILDER_GIT_PASSWORD     = data.coder_external_auth.github.access_token
    ENVBUILDER_WORKSPACE_FOLDER = local.workspace_dir
    ENVBUILDER_FALLBACK_IMAGE   = "codercom/enterprise-base:ubuntu"
    ENVBUILDER_INIT_SCRIPT      = coder_agent.main.init_script
    CODER_AGENT_TOKEN           = coder_agent.main.token
    # access_url is already a public hostname (coder.schenkenberger.dev), not
    # localhost, so unlike Coder's single-machine reference templates there's
    # no need to rewrite it to host.docker.internal for the container to reach it.
    CODER_AGENT_URL = data.coder_workspace.me.access_url
  }

  docker_env = [for k, v in local.envbuilder_env : "${k}=${v}"]
}

resource "docker_image" "devcontainer_builder" {
  name         = local.devcontainer_builder_image
  keep_locally = true
}

resource "docker_container" "workspace" {
  count    = data.coder_workspace.me.start_count
  image    = docker_image.devcontainer_builder.image_id
  name     = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name
  env      = local.docker_env

  # docker GID on mangrove — see the docker.sock mount below.
  group_add = ["131"]

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  volumes {
    host_path      = local.workspace_host_dir
    container_path = "/workspaces"
    read_only      = false
  }

  # Same host dir, mirrored at its own host-identical path — devcontainer
  # features like docker-outside-of-docker bind-mount source paths that get
  # resolved by the *host's* dockerd, not this container's filesystem, so a
  # path only valid in here (like "/workspaces/bog-bank") doesn't exist there.
  volumes {
    host_path      = local.workspace_host_dir
    container_path = local.workspace_host_dir
    read_only      = false
  }

  # Docker-outside-of-Docker: no daemon of its own, talks to the host's.
  # Mounted at docker-host.sock, not docker.sock directly — that's the path
  # the devcontainers docker-outside-of-docker feature expects the real
  # socket at, so it can install the CLI and symlink docker.sock -> this
  # itself. Mounting straight to docker.sock collides with that symlink
  # ("File exists"), which fails the feature install and silently falls
  # envbuilder back to a bare image with no containerUser — see the repo
  # this was debugged against (bog-bank) for the failure mode.
  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker-host.sock"
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

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"
  dir  = local.workspace_dir

  env = {
    GIT_AUTHOR_NAME     = local.git_author_name
    GIT_AUTHOR_EMAIL    = local.git_author_email
    GIT_COMMITTER_NAME  = local.git_author_name
    GIT_COMMITTER_EMAIL = local.git_author_email
    # gh reads GH_TOKEN with no separate `gh auth login` step needed — same
    # external-auth token envbuilder already used to clone the repo.
    GH_TOKEN = data.coder_external_auth.github.access_token
    # $PATH is expanded by the shell Coder uses to launch sessions.
    PATH = "${local.tools_dir}/bin:$PATH"
  }

  # docker_container.workspace is a `count` resource, so it's destroyed and
  # rebuilt by envbuilder on every workspace stop/start — only /workspaces
  # (the bind mount) survives that. apt packages land outside it and are
  # reinstalled every start (cheap); curl/npm-installed tools go into the
  # persisted $TOOLS_DIR instead, gated by a sentinel there, so those install
  # exactly once for the life of the workspace. Generic CLI polish
  # (starship/atuin/zoxide/etc.) lives here instead of duplicated across
  # every repo's devcontainer.json — devcontainer.json stays project-specific.
  startup_script = <<-EOT
    set -u

    # envbuilder builds (git clone, feature installs) as root, so everything
    # under the /workspaces bind mount — a *host* path, persisted across
    # rebuilds — comes out root-owned. containerUser then drops to a non-root
    # session that can't write anywhere in there (breaks direnv, this
    # script's own $TOOLS_DIR below, etc.) until it's chowned back.
    sudo chown -R "$(id -u):$(id -g)" /workspaces

    TOOLS_DIR="${local.tools_dir}"
    mkdir -p "$TOOLS_DIR/bin"

    # group_add=["131"] (docker.sock's host GID) has no name in the
    # container's /etc/group, so `groups`/`id` warn "cannot find name for
    # group ID 131" — give it one.
    getent group 131 >/dev/null 2>&1 || sudo groupadd -g 131 dockerhost

    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update -qq
      for pkg in zsh jq tmux direnv fzf ripgrep bat nodejs npm; do
        dpkg -s "$pkg" >/dev/null 2>&1 || sudo apt-get install -y "$pkg" >/dev/null 2>&1
      done
      [ -x /usr/bin/batcat ] && ln -sf /usr/bin/batcat "$TOOLS_DIR/bin/bat"

      command -v gh >/dev/null 2>&1 || {
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /usr/share/keyrings/githubcli-archive-keyring.gpg >/dev/null
        sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
        sudo apt-get update -qq && sudo apt-get install -y gh >/dev/null 2>&1
      }

      current_shell=$(getent passwd "$(whoami)" | cut -d: -f7)
      [ "$current_shell" = "$(command -v zsh)" ] || sudo chsh -s "$(command -v zsh)" "$(whoami)"
    fi

    if [ ! -f "$TOOLS_DIR/.installed" ]; then
      curl -fsSL https://starship.rs/install.sh | sh -s -- -y -b "$TOOLS_DIR/bin" >/dev/null 2>&1
      BIN_DIR="$TOOLS_DIR/bin" sh -c "$(curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh)" >/dev/null 2>&1
      curl --proto '=https' --tlsv1.2 -fsSf https://setup.atuin.sh | sh -s -- --no-modify-path >/dev/null 2>&1
      [ -x "$HOME/.atuin/bin/atuin" ] && ln -sf "$HOME/.atuin/bin/atuin" "$TOOLS_DIR/bin/atuin"
      curl -fsSL https://just.systems/install.sh | bash -s -- --to "$TOOLS_DIR/bin" >/dev/null 2>&1
      npm install -g --prefix "$TOOLS_DIR" @anthropic-ai/claude-code @openai/codex >/dev/null 2>&1
      touch "$TOOLS_DIR/.installed"
    fi
  EOT

  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }
  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }
  metadata {
    display_name = "Home Disk"
    key          = "2_home_disk"
    script       = "coder stat disk --path $HOME"
    interval     = 60
    timeout      = 1
  }
}

# Applies davisschenk/dotfiles on every agent start (chezmoi-managed zsh
# config + starship's Pure preset — see that repo's install.sh/README).
module "dotfiles" {
  count                = data.coder_workspace.me.start_count
  source               = "registry.coder.com/coder/dotfiles/coder"
  version              = "~> 1.4"
  agent_id             = coder_agent.main.id
  default_dotfiles_uri = "https://github.com/davisschenk/dotfiles"
}

# Single instance now — one workspace is one project, so there's no more
# per-project folder-switcher buttons alongside this.
module "code-server" {
  count     = data.coder_workspace.me.start_count
  source    = "registry.coder.com/coder/code-server/coder"
  version   = "~> 1.5"
  agent_id  = coder_agent.main.id
  folder    = local.workspace_dir
  order     = 1
  subdomain = true
}
