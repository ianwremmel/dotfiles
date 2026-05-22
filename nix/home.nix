{ pkgs, username, ... }:
{
  home.username = username;
  # Home directory differs by OS; Linux root is a special case (/root, not /home/root).
  home.homeDirectory =
    if pkgs.stdenv.isDarwin then "/Users/${username}"
    else if username == "root" then "/root"
    else "/home/${username}";
  home.stateVersion = "25.11"; # pins home-manager behavior; never bump casually
  programs.home-manager.enable = true; # home-manager manages itself

  programs.bat = {
    enable = true;          # installs bat (the package half of the slice)
    config.theme = "ansi";  # writes ~/.config/bat/config (the dotfile half)
  };
}
