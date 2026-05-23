{ pkgs, ... }: {
  home.sessionVariables.DOTFILES_PROFILE = "default";
  home.packages = [ pkgs.ripgrep ];
}
