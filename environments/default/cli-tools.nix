{ pkgs, ... }: {
  # CLI tools that only the `default` (personal) environment gets — not installed
  # on `agent` boxes.
  home.packages = with pkgs; [
    # Configuration management / scripting
    ansible
    bats
    uv

    # AWS / cloud
    aws-sam-cli
    flyctl

    # YAML processing
    yq-go

    # Terraform-like IaC (the OpenTofu fork; we kept terraform in the
    # `all` layer and add opentofu here as the default-environment companion
    # — both available because some workflows still expect each).
    opentofu

    # Kubernetes / homelab tooling
    argocd
    cilium-cli
    kubernetes-helm
    k9s
    kubectl
    talosctl
    # NOTE: `argo` (Argo Workflows CLI) is declared as a homebrew brew in
    # ./darwin.nix because it does not exist in nixpkgs 26.05. Re-evaluate on the
    # next nixpkgs bump (argo may land upstream).
  ];
}
