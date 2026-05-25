{ pkgs, ... }: {
  home.packages = [ pkgs.ripgrep ];

  # `settings.user.{name,email}` is the current home-manager option path
  # (the old `programs.git.userName` / `userEmail` are deprecated aliases).
  programs.git.settings.user = {
    name  = "ianwremmel";
    email = "1182361+ianwremmel@users.noreply.github.com";
  };
}
