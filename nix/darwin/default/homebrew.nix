{ ... }: {
  homebrew = {
    # Personal-machine casks — additive on top of base.nix's universal list.
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
      # Escape-hatched (slice 9): pkgs.argo absent from nixpkgs 26.05.
      "argo"
    ];
  };
}
