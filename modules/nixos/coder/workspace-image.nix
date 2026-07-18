# Docker image for Coder workspaces. Built on a Debian base (not a from-scratch
# Nix rootfs) because rustup's downloaded toolchains and code-server's
# curl-installed release binary are prebuilt, dynamically-linked ELF binaries
# that expect a real FHS dynamic linker (/lib64/ld-linux-x86-64.so.2), which a
# from-scratch Nix image doesn't provide.
{ pkgs }:
let
  baseImage = pkgs.dockerTools.pullImage {
    imageName = "debian";
    imageDigest = "sha256:7b140f374b289a7c2befc338f42ebe6441b7ea838a042bbd5acbfca6ec875818";
    hash = "sha256-XHYltdiS2FpEQ52ZdA+iaeRAFfSHNK+OTgmSZsZe8hg=";
    finalImageName = "debian";
    finalImageTag = "bookworm-slim";
  };

  # GID 131 — must match mangrove's real `docker` group (`getent group docker`
  # on the host) so the bind-mounted /var/run/docker.sock's group ownership
  # resolves correctly inside the container (no user-namespace remapping here,
  # so permission checks are on raw numeric IDs shared with the host).
  dockerGid = "131";

  workspaceTools = with pkgs; [
    bashInteractive
    coreutils
    gnutar
    gzip
    which
    git
    openssh
    curl
    cacert
    tmux
    direnv
    jq
    ripgrep
    less
    gcc
    gnumake
    pkg-config
    openssl
    nodejs_latest
    python3
    uv
    rustup
    claude-code
    codex
    just
    # Project-specific: sea-orm-cli (tilt-app migrations), leptosfmt (bog-bank
    # `just check`) — clippy/rustfmt come from `rustup component add`, done
    # once a toolchain is installed, not baked in here.
    sea-orm-cli
    leptosfmt
    # Nix itself, so nixos-homelab and bog-bank (both ship a flake.nix) can
    # actually be built/checked from inside a workspace.
    nix
    # Docker CLI + compose plugin only — no daemon in the container. Talks to
    # the *host's* dockerd over the bind-mounted socket (see main.tf), same
    # "docker-outside-of-docker" pattern Coder itself uses for provisioning.
    docker
    docker-compose
    sudo
    # Interactive shell environment
    zsh
    zsh-autosuggestions
    zsh-syntax-highlighting
    starship
    fzf
    zoxide
    eza
    bat
    atuin
  ];

  toolsPath = pkgs.lib.makeBinPath workspaceTools;

  # Starship's official "Pure" preset (starship.rs/presets/pure-preset) —
  # verbatim, not reimplemented — faithfully replicates the classic Pure
  # zsh prompt (sindresorhus/pure): minimal two-line prompt, no Nerd Font
  # glyphs needed (matters here since code-server's integrated terminal runs
  # in whatever font the browser provides, which usually isn't one).
  starshipToml = pkgs.writeText "starship.toml" ''
    "$schema" = 'https://starship.rs/config-schema.json'

    format = """
    $username\
    $hostname\
    $directory\
    $git_branch\
    $git_state\
    $git_status\
    $cmd_duration\
    $line_break\
    $python\
    $character"""

    [directory]
    style = "blue"

    [character]
    success_symbol = "[❯](purple)"
    error_symbol = "[❯](red)"
    vimcmd_symbol = "[❮](green)"

    [git_branch]
    format = "[$branch]($style)"
    style = "bright-black"

    [git_status]
    format = "[[(*$conflicted$untracked$modified$staged$renamed$deleted)](218) ($ahead_behind$stashed)]($style)"
    style = "cyan"
    conflicted = "​"
    untracked = "​"
    modified = "​"
    staged = "​"
    renamed = "​"
    deleted = "​"
    stashed = "≡"

    [git_state]
    format = '\([$state( $progress_current/$progress_total)]($style)\) '
    style = "bright-black"

    [cmd_duration]
    format = "[$duration]($style) "
    style = "yellow"

    [python]
    format = "[$virtualenv]($style) "
    style = "bright-black"
    detect_extensions = []
    detect_files = []
  '';

  # Sourced for every zsh invocation (login or not, interactive or not) —
  # the zsh equivalent of /etc/profile.d for bash/sh. zsh does NOT read
  # /etc/profile on its own, so the PATH fix below is separate from (but
  # mirrors) the bash one in extraCommands.
  zshenv = pkgs.writeText "zshenv" ''
    export PATH="/usr/local/bin:${toolsPath}:$PATH"
  '';

  zshrc = pkgs.writeText "zshrc" ''
    HISTFILE=~/.zsh_history
    HISTSIZE=50000
    SAVEHIST=50000
    setopt SHARE_HISTORY
    setopt HIST_IGNORE_ALL_DUPS
    setopt HIST_IGNORE_SPACE
    setopt APPEND_HISTORY
    setopt INC_APPEND_HISTORY

    autoload -Uz compinit && compinit

    alias ls='eza'
    alias ll='eza -la --git'
    alias la='eza -a'
    alias cat='bat --paging=never'
    alias gs='git status'
    alias ga='git add'
    alias gc='git commit'
    alias gp='git push'
    alias gl='git log --oneline --graph --decorate'
    alias gd='git diff'

    export STARSHIP_CONFIG=/etc/starship.toml
    eval "$(starship init zsh)"
    eval "$(zoxide init zsh --cmd cd)"
    eval "$(atuin init zsh)"
    source <(fzf --zsh)

    # zsh-syntax-highlighting must be sourced last — it wraps existing
    # widgets, so anything sourced after it that also wraps widgets breaks.
    source ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh
    source ${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
  '';

  # `extraCommands` only ever sees the `contents` packages' own symlinkJoin
  # tree — NOT fromImage's filesystem, so `sed -i` on the base image's real
  # /etc/passwd fails outright ("No such file or directory": it genuinely
  # isn't there during this build step). The fix is to ship a full REPLACEMENT
  # file instead of patching the original — OCI layers apply in order, so a
  # file present in this (later) layer overrides the same path from fromImage
  # (an earlier layer) entirely, same mechanism that lets `rm -rf bin lib`
  # above work. Content below is debian:bookworm-slim's stock /etc/passwd
  # verbatim, plus a non-root "dev" user (uid/gid 1000, home /home/dev,
  # zsh as its shell) — the workspace container now runs as this user by
  # default (see `config.User` below) rather than root.
  passwd = pkgs.writeText "passwd" ''
    root:x:0:0:root:/root:/bin/bash
    daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
    bin:x:2:2:bin:/bin:/usr/sbin/nologin
    sys:x:3:3:sys:/dev:/usr/sbin/nologin
    sync:x:4:65534:sync:/bin:/bin/sync
    games:x:5:60:games:/usr/games:/usr/sbin/nologin
    man:x:6:12:man:/var/cache/man:/usr/sbin/nologin
    lp:x:7:7:lp:/var/spool/lpd:/usr/sbin/nologin
    mail:x:8:8:mail:/var/mail:/usr/sbin/nologin
    news:x:9:9:news:/var/spool/news:/usr/sbin/nologin
    uucp:x:10:10:uucp:/var/spool/uucp:/usr/sbin/nologin
    proxy:x:13:13:proxy:/bin:/usr/sbin/nologin
    www-data:x:33:33:www-data:/var/www:/usr/sbin/nologin
    backup:x:34:34:backup:/var/backups:/usr/sbin/nologin
    list:x:38:38:Mailing List Manager:/var/list:/usr/sbin/nologin
    irc:x:39:39:ircd:/run/ircd:/usr/sbin/nologin
    _apt:x:42:65534::/nonexistent:/usr/sbin/nologin
    nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin
    dev:x:1000:1000:dev:/home/dev:${pkgs.zsh}/bin/zsh
  '';

  # Same reasoning as `passwd` — stock debian:bookworm-slim /etc/group, plus
  # a "dev" group and a "docker" group at mangrove's real docker GID so the
  # bind-mounted socket's permissions resolve correctly (see `dockerGid`).
  group = pkgs.writeText "group" ''
    root:x:0:
    daemon:x:1:
    bin:x:2:
    sys:x:3:
    adm:x:4:
    tty:x:5:
    disk:x:6:
    lp:x:7:
    mail:x:8:
    news:x:9:
    uucp:x:10:
    man:x:12:
    proxy:x:13:
    kmem:x:15:
    dialout:x:20:
    fax:x:21:
    voice:x:22:
    cdrom:x:24:
    floppy:x:25:
    tape:x:26:
    sudo:x:27:
    audio:x:29:
    dip:x:30:
    www-data:x:33:
    backup:x:34:
    operator:x:37:
    list:x:38:
    irc:x:39:
    src:x:40:
    shadow:x:42:
    utmp:x:43:
    video:x:44:
    sasl:x:45:
    plugdev:x:46:
    staff:x:50:
    games:x:60:
    users:x:100:
    nogroup:x:65534:
    dev:x:1000:
    docker:x:${dockerGid}:dev
  '';

  sudoers = pkgs.writeText "sudoers" ''
    Defaults env_keep += "PATH"
    root ALL=(ALL:ALL) ALL
    dev ALL=(ALL) NOPASSWD:ALL
  '';

  # A real config file rather than the $NIX_CONFIG env var — sudo resets the
  # environment by default (only PATH is kept, see `sudoers` above), so
  # `sudo nix ...` silently lost experimental-features/sandbox=false anyway.
  # This is read regardless of how nix is invoked.
  nixConf = pkgs.writeText "nix.conf" ''
    experimental-features = nix-command flakes
    sandbox = false
  '';

  # sudo also goes through PAM for account/session management, not just the
  # sudoers file — with no /etc/pam.d/sudo at all, PAM refused it outright
  # ("PAM account management error: Permission denied"). pam_permit.so
  # always succeeds; fine here since sudoers' NOPASSWD is what's actually
  # gating access, not PAM.
  pamSudo = pkgs.writeText "pam-sudo" ''
    auth     sufficient  ${pkgs.linux-pam}/lib/security/pam_permit.so
    account  sufficient  ${pkgs.linux-pam}/lib/security/pam_permit.so
    session  optional    ${pkgs.linux-pam}/lib/security/pam_permit.so
  '';

  # Same reasoning as `passwd`/`group` — stock debian:bookworm-slim /etc/shells,
  # plus zsh's path.
  shells = pkgs.writeText "shells" ''
    # /etc/shells: valid login shells
    /bin/sh
    /usr/bin/sh
    /bin/bash
    /usr/bin/bash
    /bin/rbash
    /usr/bin/rbash
    /bin/dash
    /usr/bin/dash
    ${pkgs.zsh}/bin/zsh
  '';
in
pkgs.dockerTools.streamLayeredImage {
  name = "coder-workspace";
  tag = "latest";
  fromImage = baseImage;
  contents = workspaceTools;
  maxLayers = 100;
  # Registers every `contents` package as a valid path in Nix's own SQLite
  # database inside the image — without this, the `nix` binary we're now
  # shipping would have no record of any of these store paths, and running
  # `nix-collect-garbage` as `dev` could delete the entire curated toolset
  # right out from under itself.
  includeNixDB = true;
  # `contents` merges every listed package via `symlinkJoin` into ONE
  # "customisation layer" with top-level bin/, lib/, share/ dirs (this is the
  # actual mechanism — nixpkgs' dockerTools source confirms it, contrary to
  # what an earlier version of this comment assumed). On a merged-usr FHS base
  # like Debian, where /bin and /lib are themselves symlinks to /usr/bin and
  # /usr/lib, that customisation layer's *real* bin/ and lib/ directories
  # replace those symlinks outright when layered on top — which took down
  # every dynamically-linked binary already in the base image (found via a
  # failing `/usr/bin/grep`: file present, but its interpreter path resolved
  # through the now-broken /lib symlink to nowhere). Deleting bin/ and lib/
  # from the customisation layer avoids the collision entirely; nothing here
  # needs them since PATH below points straight at each package's own
  # /nix/store output rather than a merged bin/ dir.
  extraCommands = ''
    rm -rf bin lib

    # `contents` only adds packages at their own /nix/store paths — it does not
    # populate conventional FHS locations like /etc/ssl/certs/ca-certificates.crt.
    # Not every TLS-using tool respects $SSL_CERT_FILE (some hardcode this exact
    # path), so materialize a real file there rather than relying on the env var
    # alone — found the hard way: the Coder agent's own bootstrap script curls
    # its binary over HTTPS and failed with "error adding trust anchors" without
    # this, since the path it resolved to (my own SSL_CERT_FILE setting) didn't
    # exist in a streamed image.
    mkdir -p etc/ssl/certs
    cp ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt etc/ssl/certs/ca-certificates.crt

    # Debian's stock /etc/profile unconditionally overwrites PATH for login
    # shells (`PATH="/usr/local/sbin:...:/bin"` for root, no reference to
    # whatever was inherited from the container's own environment) — found
    # the hard way: `docker exec sh -c` (non-login) saw the right PATH, but
    # `coder ssh`/the web terminal (which spawn a login shell) got none of
    # these tools at all. /etc/profile sources every /etc/profile.d/*.sh
    # *after* resetting PATH, so a script there is the correct, standard
    # place to re-append it for every shell, login or not.
    mkdir -p etc/profile.d
    echo 'export PATH="/usr/local/bin:${toolsPath}:$PATH"' > etc/profile.d/00-nix-tools-path.sh

    # zsh as the default interactive shell, with starship + a modern CLI kit
    # (fzf, zoxide, eza, bat, atuin) wired up in /etc/zshrc. Coder's agent
    # looks up the login shell via /etc/passwd (not $SHELL), so it has to be
    # a full replacement file, not a `sed`/`>>` patch — see comment above the
    # `passwd`/`group`/`shells` definitions for why.
    cp ${zshenv} etc/zshenv
    cp ${zshrc} etc/zshrc
    cp ${starshipToml} etc/starship.toml
    cp ${passwd} etc/passwd
    cp ${group} etc/group
    cp ${shells} etc/shells

    # Passwordless sudo for dev — needed for: the one-time chown of the
    # bind-mounted home dir (Docker auto-creates missing bind-mount sources
    # as root:root, see main.tf's startup_script), and any Nix store writes,
    # since /nix/store's pre-existing content here is root-owned. `rm -f`
    # first: the sudo package's own output ships a default etc/sudoers,
    # symlinked in via `contents` as a read-only link into the nix store —
    # `cp` can't overwrite that in place.
    mkdir -p etc/pam.d
    cp ${pamSudo} etc/pam.d/sudo

    rm -f etc/sudoers
    cp ${sudoers} etc/sudoers
    chmod 440 etc/sudoers

    # nixpkgs' sudo binary is deliberately built without the setuid bit
    # (NixOS instead generates a setuid *wrapper* at activation time via the
    # security.sudo module — not something available in a plain Docker
    # image) — found the hard way: sudo refused to run at all ("must be
    # owned by uid 0 and have the setuid bit set"). `cp -L` dereferences the
    # symlink into a real, standalone file; the actual chown-to-root +
    # setuid-chmod happens in `fakeRootCommands` below, not here — plain
    # `extraCommands` isn't wrapped in fakeroot and `chown 0:0` fails
    # outright ("Invalid argument") without it. /usr/local/bin is listed
    # first in PATH specifically so this copy shadows the (non-setuid) one
    # still reachable via ${toolsPath}.
    mkdir -p usr/local/bin
    cp -L ${pkgs.sudo}/bin/sudo usr/local/bin/sudo

    mkdir -p home/dev nix/var/nix/gcroots/per-user/dev
    mkdir -p etc/nix
    cp ${nixConf} etc/nix/nix.conf
  '';
  # Needs real (faked) root to chown+setuid the sudo copy above — see that
  # comment for why this can't just be one more line in `extraCommands`.
  fakeRootCommands = ''
    chown 0:0 usr/local/bin/sudo
    chmod 4755 usr/local/bin/sudo
  '';
  config = {
    # PATH points directly at each package's own /nix/store/.../bin rather
    # than any merged bin/ dir (see extraCommands above for why that dir gets
    # deleted) — also sidesteps symlinkJoin collision errors across unrelated
    # packages that happen to ship same-named files. Also re-exported by
    # /etc/profile.d/00-nix-tools-path.sh (bash/sh) and /etc/zshenv (zsh) for
    # login shells, which don't inherit this (see extraCommands above).
    Env = [
      "PATH=/usr/local/bin:${toolsPath}:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin"
      "SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt"
      "STARSHIP_CONFIG=/etc/starship.toml"
      "SHELL=${pkgs.zsh}/bin/zsh"
      "LANG=C.UTF-8"
      "HOME=/home/dev"
    ];
    # Non-root by default — see the `passwd`/`group`/`sudoers` files above.
    User = "1000:1000";
    Cmd = [ "/bin/sh" ];
  };
}
