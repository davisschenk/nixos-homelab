# Debian base for dynamically-linked binaries (rustup, code-server).
{ pkgs }:
let
  baseImage = pkgs.dockerTools.pullImage {
    imageName = "debian";
    imageDigest = "sha256:7b140f374b289a7c2befc338f42ebe6441b7ea838a042bbd5acbfca6ec875818";
    hash = "sha256-XHYltdiS2FpEQ52ZdA+iaeRAFfSHNK+OTgmSZsZe8hg=";
    finalImageName = "debian";
    finalImageTag = "bookworm-slim";
  };

  # GID must match host docker group for bind-mounted socket permissions.
  dockerGid = "131";

  # Redirect npm install to $HOME (store is read-only).
  npmGlobalPrefix = "/home/dev/.npm-global";

  workspaceTools = with pkgs; [
    bashInteractive
    coreutils
    gnutar
    gzip
    which
    git
    gh
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
    # Project tools moved to individual repo devcontainer configs.
    nix
    # Docker-outside-of-docker via host socket.
    docker
    docker-compose
    sudo
    zsh
    zsh-autosuggestions
    zsh-syntax-highlighting
    starship
    fzf
    zoxide
    eza
    bat
    atuin
    chezmoi
  ];

  toolsPath = pkgs.lib.makeBinPath workspaceTools;

  # zshenv sourced by all zsh invocations; plugin paths Nix-specific.
  zshenv = pkgs.writeText "zshenv" ''
    export PATH="/usr/local/bin:${toolsPath}:${npmGlobalPrefix}/bin:$PATH"
    export NPM_CONFIG_PREFIX="${npmGlobalPrefix}"
    export ZSH_AUTOSUGGESTIONS_SH="${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
    export ZSH_SYNTAX_HIGHLIGHTING_SH="${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
  '';

  # Full replacement file; OCI layers override earlier files entirely.
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

  # File persists through sudo environment reset.
  nixConf = pkgs.writeText "nix.conf" ''
    experimental-features = nix-command flakes
    sandbox = false
  '';

  # PAM requires /etc/pam.d/sudo; pam_permit sufficient since sudoers gates access.
  pamSudo = pkgs.writeText "pam-sudo" ''
    auth     sufficient  ${pkgs.linux-pam}/lib/security/pam_permit.so
    account  sufficient  ${pkgs.linux-pam}/lib/security/pam_permit.so
    session  optional    ${pkgs.linux-pam}/lib/security/pam_permit.so
  '';

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
  # Register store paths in Nix DB (nix-collect-garbage needs them).
  includeNixDB = true;
  # rm -rf bin/lib; merged-usr FHS collision would break base image binaries.
  extraCommands = ''
    rm -rf bin lib

    # Coder's bootstrap script needs real cert path (not just $SSL_CERT_FILE).
    mkdir -p etc/ssl/certs
    cp ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt etc/ssl/certs/ca-certificates.crt

    # /etc/profile resets PATH; restore via profile.d for login shells.
    mkdir -p etc/profile.d
    echo 'export PATH="/usr/local/bin:${toolsPath}:${npmGlobalPrefix}/bin:$PATH"' > etc/profile.d/00-nix-tools-path.sh
    echo 'export NPM_CONFIG_PREFIX="${npmGlobalPrefix}"' >> etc/profile.d/00-nix-tools-path.sh

    # Full replacement file required (Coder agent uses /etc/passwd for login shell).
    cp ${zshenv} etc/zshenv
    cp ${passwd} etc/passwd
    cp ${group} etc/group
    cp ${shells} etc/shells

    # Replaces symlinked sudo config from store.
    mkdir -p etc/pam.d
    cp ${pamSudo} etc/pam.d/sudo

    rm -f etc/sudoers
    cp ${sudoers} etc/sudoers
    chmod 440 etc/sudoers

    # nixpkgs sudo lacks setuid; fakeRootCommands below applies it.
    mkdir -p usr/local/bin
    cp -L ${pkgs.sudo}/bin/sudo usr/local/bin/sudo

    mkdir -p home/dev nix/var/nix/gcroots/per-user/dev
    mkdir -p etc/nix
    cp ${nixConf} etc/nix/nix.conf
  '';
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
      "PATH=/usr/local/bin:${toolsPath}:${npmGlobalPrefix}/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin"
      "SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt"
      "SHELL=${pkgs.zsh}/bin/zsh"
      "LANG=C.UTF-8"
      "HOME=/home/dev"
      "NPM_CONFIG_PREFIX=${npmGlobalPrefix}"
    ];
    # Non-root by default — see the `passwd`/`group`/`sudoers` files above.
    User = "1000:1000";
    Cmd = [ "/bin/sh" ];
  };
}
