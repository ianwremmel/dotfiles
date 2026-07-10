{ pkgs, lib, ... }: {
  # Agent-environment CLI tools, on top of the shared core/all set. `gh`,
  # `awscli2`, `chamber`, and `terraform` already come from core/all, so they
  # are not repeated here.
  home.packages = with pkgs; [
    buildkite-cli # the `bk` CLI
  ] ++ lib.optionals pkgs.stdenv.isLinux [
    # Cluster / infra tooling for agent hosts. Versions track nixpkgs; if a tool
    # must match the cluster exactly (talosctl / kubectl skew), pin it via an
    # overlay. Linux-only, like the hosts themselves.
    kubectl
    kubernetes-helm
    argocd
    argo-workflows # the `argo` CLI
    talosctl
    opentofu
    yq-go
    aws-sam-cli
    flyctl
    bats
    awscli2
    mcp-grafana # invoked by the homelab .mcp.json the bundle installs
  ];
}
