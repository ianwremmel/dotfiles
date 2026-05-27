{ pkgs, ... }: {
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
    terraform  # unfree; requires nixpkgs.config.allowUnfree = true
    tflint

    # Language runtimes
    openjdk
    python3

    # Shell extras (the zsh binary itself is provided by programs.zsh.enable)
    bash             # also stays in Brewfile per Decision 4 (bash-5 bootstrap)
    bash-completion  # nixpkgs `bash-completion` is the v2 series (brew name: bash-completion@2); also stays in Brewfile per Decision 4
    zsh-completions
  ];
}
