{ ... }:
{
  # single-user repo — update username/homeDirectory (and flake.nix `system`) if you fork
  home.username = "ian";
  home.homeDirectory = "/Users/ian";
  home.stateVersion = "25.11"; # pins home-manager behavior; never bump casually
  programs.home-manager.enable = true; # home-manager manages itself
}
