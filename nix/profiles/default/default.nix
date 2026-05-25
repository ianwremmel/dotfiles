{ pkgs, ... }: {
  home.packages = [ pkgs.ripgrep ];

  programs.git = {
    userName  = "ianwremmel";
    userEmail = "1182361+ianwremmel@users.noreply.github.com";
  };
}
