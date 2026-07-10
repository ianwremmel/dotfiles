{ pkgs, ... }: {
  # Agent-environment CLI tools, on top of the shared core/all set. `gh`,
  # `awscli2`, `chamber`, and `terraform` already come from core/all, so they
  # are not repeated here.
  home.packages = with pkgs; [
    buildkite-cli # the `bk` CLI
  ];
}
