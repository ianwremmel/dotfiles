{ ... }: {
  # The `default` profile is the personal-machine profile (vs. `agent` which
  # stays lean). cli-tools.nix carries personal-machine CLI installs that
  # don't belong on agent boxes.
  imports = [
    ./cli-tools.nix
  ];

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
