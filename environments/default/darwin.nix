{ ... }: {
  homebrew = {
    # Personal-machine casks — additive on top of the universal list in `all/darwin/default.nix`.
    # nix-darwin's homebrew option is list-typed, so these concatenate.
    casks = [
      "adobe-creative-cloud"
      "discord"
      "iterm2"
      "proton-mail"
      "proton-mail-bridge"
      "quicken"
      "steam"
      "synology-drive"
      "webstorm"
      "zoom"
    ];

    masApps = {
      Byword    = 420212497;
      Tailscale = 1475387142;
    };

    brews = [
      # argo: a brew rather than a nix package because pkgs.argo is absent
      # from nixpkgs 26.05.
      "argo"
    ];
  };
}
