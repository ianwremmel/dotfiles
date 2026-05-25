{ pkgs, ... }: {
  home.packages = [ pkgs.ripgrep ];

  # `settings.user.{name,email,signingkey}` is the current home-manager
  # option path. (`name` and `email` replace the deprecated
  # `userName`/`userEmail`; `signingkey` is just a new key under the same
  # `user` subsection.) The signing key id is a public GPG fingerprint —
  # fine to commit.
  programs.git.settings = {
    user = {
      name       = "ianwremmel";
      email      = "1182361+ianwremmel@users.noreply.github.com";
      signingkey = "C9DA1EE9CCF21B28";
    };
    commit.gpgsign = true;
  };
}
