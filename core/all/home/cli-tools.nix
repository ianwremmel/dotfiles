{ lib, pkgs, ... }: {
  # CLI tools that every machine gets. Migrated from
  # `environments/all/Brewfile` plus the non-bash aggregator entries in
  # `plugins/homebrew/Brewfile.erb` (coreutils, gh). The corresponding
  # `brew '<name>'` lines are removed from the Brewfiles by this same
  # slice; brew bundle cleanup uninstalls them on next apply and these
  # nix-installed versions take over via PATH precedence.
  home.packages = with pkgs; [
    # GNU coreutils + replacements for outdated macOS variants
    coreutils
    findutils
    gnused
    gnugrep
    gnumake
    wget

    # Dev essentials
    git
    git-lfs
    gh
    # vim: provided by programs.vim
    shellcheck
    tree
    watch
    screen
    # NOTE: brew 'watchman' is retained in environments/all/Brewfile because
    # watchman's folly C++ dep fails to build on aarch64-darwin with the
    # current nixpkgs version. Re-evaluate on next nixpkgs bump (folly may
    # compile cleanly again).

    # AWS tooling
    awscli2
    chamber

    # Web / API
    httpie

    # Infrastructure
    tflint

    # Language runtimes
    openjdk
    python3

    # Shell extras (the zsh binary itself is provided by programs.zsh.enable)
    bash             # general-purpose Bash 5 on PATH (~/.nix-profile/bin/bash)
    bash-completion  # nixpkgs `bash-completion` is the v2 series (brew name: bash-completion@2)
    zsh-completions
  ] ++ lib.optionals pkgs.stdenv.isDarwin [
    # macOS only. terraform is unfree (BSL), so cache.nixos.org carries no
    # build and every host compiles it locally. Linux container hosts can't
    # give nix the kernel namespaces its build sandbox needs, so that compile
    # runs unsandboxed, and the Go toolchain writes telemetry into nix's HOME
    # stand-in `/homeless-shelter` — whose existence makes nix abort every
    # later unsandboxed build, breaking the whole activation. Linux hosts use
    # `opentofu` instead. Requires nixpkgs.config.allowUnfree = true.
    terraform
  ];
}
