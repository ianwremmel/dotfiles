{ pkgs, ... }: {
  # CLI tools that only the `default` (personal) profile gets. Migrated from
  # `environments/default/Brewfile`. Agent profiles do NOT get these.
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
    # `all` profile and add opentofu here as the default-profile companion
    # — both available because some workflows still expect each).
    opentofu

    # Kubernetes / homelab tooling
    argocd
    cilium-cli
    kubernetes-helm
    k9s
    kubectl
    talosctl
    # NOTE: brew 'argo' is retained in environments/default/Brewfile because
    # `argo` (Argo Workflows CLI) does not exist in nixpkgs 26.05.
    # Re-evaluate on next nixpkgs bump (argo may land upstream).
  ];
}
