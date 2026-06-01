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

  # Allow installing unfree packages (terraform's BSL license, etc.).
  # Required for the `terraform` entry in `all/home/cli-tools.nix`.
  nixpkgs.config.allowUnfree = true;

  # Infrastructure only — shared content (universally-installed packages and
  # programs) lives in `all/home/default.nix`, which `lib.mkHome` always
  # composes alongside this base. Environment-specific additions live under
  # `<env>/home.nix`.
}
