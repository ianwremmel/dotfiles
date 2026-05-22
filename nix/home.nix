{ username, ... }:
{
  home.username = username;
  # Derived from username. The /Users prefix is macOS-specific; branch this when
  # a Linux (e.g. agent) config is added.
  home.homeDirectory = "/Users/${username}";
  home.stateVersion = "25.11"; # pins home-manager behavior; never bump casually
  programs.home-manager.enable = true; # home-manager manages itself

  programs.bat = {
    enable = true; # installs bat (the package half of the slice)
    config.theme = "ansi"; # writes ~/.config/bat/config (the dotfile half)
  };
}
