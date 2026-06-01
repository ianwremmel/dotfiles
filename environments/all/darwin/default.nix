{ username, ... }: {
  imports = [ ./defaults.nix ];

  # System-wide PATH for brew binaries. Casks ship CLI tools under
  # /opt/homebrew/bin/ (e.g., 1password-cli, aws-vault). The user's
  # ~/.nix-profile/bin/ stays ahead in PATH for interactive shells; this
  # is the system baseline.
  environment.systemPath = [ "/opt/homebrew/bin" "/opt/homebrew/sbin" ];

  # Declarative login-shell management. nix-darwin writes /etc/passwd via dscl
  # and ensures the shell is in /etc/shells. No marker file; no interactive
  # prompt; idempotent.
  environment.shells = [
    "/Users/${username}/.nix-profile/bin/zsh"
  ];

  # Xcode license acceptance. Runs as root during activation; xcodebuild
  # short-circuits if the license is already accepted, so it's idempotent. The
  # `|| true` ensures activation continues if Xcode isn't installed yet (e.g.,
  # first apply before masApps.Xcode finishes downloading).
  system.activationScripts.xcodeLicense.text = ''
    if [ -x /usr/bin/xcodebuild ]; then
      /usr/bin/xcodebuild -license accept 2>/dev/null || true
    fi
  '';

  # Homebrew base settings; per-environment cask/mas/brew lists come from
  # each environment's darwin module. nix-darwin's homebrew module
  # generates a Brewfile under the hood and runs `brew bundle` on activate
  # — brew itself must already be installed (framework/compat handles
  # the bash-side bootstrap on a fresh machine).
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;       # don't auto-update brew on every apply
      # WARNING: `uninstall` removes ANY brew package (cask, formula, mas)
      # not declared in homebrew.{casks,brews,masApps} on this machine —
      # including things you may have installed manually. If you want a
      # package, declare it here or in your private flake's darwin module;
      # otherwise expect it to disappear on the next apply.
      cleanup    = "uninstall";
      upgrade    = true;        # upgrade declared packages on apply
    };

    # Universal casks/mas/brews — every macOS machine gets these.
    casks = [
      "aws-vault-binary"  # renamed from aws-vault in homebrew-cask
      "1password"
      "1password-cli"
      "docker-desktop"  # renamed from docker in homebrew-cask
      "elgato-control-center"
      "elgato-stream-deck"
      "fork"
      "firefox"
      "gitup-app"  # renamed from gitup in homebrew-cask
      "gpg-suite"
      "grandperspective"
      "ngrok"
      "obsidian"
      "visual-studio-code"
      "vlc"
      "xquartz"
      # Nerd Font for starship's git-branch glyph. After install, set this as
      # iTerm's font in Settings → Profiles → Text → Font.
      "font-meslo-lg-nerd-font"
    ];

    masApps = {
      Magnet = 441258766;
      Slack  = 803453959;
      Xcode  = 497799835;
    };

    brews = [
      # `mas` is the CLI that installs Mac App Store apps. nix-darwin's
      # `homebrew.masApps` writes `mas 'Name', id: N` lines into the
      # generated Brewfile, but `mas` itself isn't added implicitly. The
      # `onActivation.cleanup = "uninstall"` policy would remove mas
      # otherwise — and a later activation needing to (re)install a
      # masApp would fail because the `mas` binary is gone. Declare it
      # explicitly here so cleanup respects it.
      "mas"
      # watchman: a brew rather than a nix package because pkgs.watchman fails
      # to compile — its folly C++ dep doesn't build on aarch64-darwin in the
      # current nixpkgs.
      "watchman"
    ];
  };
}
