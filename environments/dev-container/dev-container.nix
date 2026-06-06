{ pkgs, lib, ... }:
let
  jsonFormat = pkgs.formats.json { };

  # Grafana MCP server — homelab-specific (points at this cluster's Grafana), so
  # it lives here rather than in the shared agent profile. The agent profile's
  # claude.nix exports the base MCP list to ~/.config/agent/mcp-servers.json;
  # this file sits alongside it for the host to merge at boot.
  grafanaMcp = jsonFormat.generate "mcp-servers-homelab.json" {
    servers = [
      {
        name = "grafana";
        transport = "stdio";
        command = "mcp-grafana";
        args = [ "-t" "stdio" ];
        env = {
          GRAFANA_URL = "http://kube-prometheus-stack-grafana.monitoring.svc.cluster.local";
          GRAFANA_SERVICE_ACCOUNT_TOKEN = "$GRAFANA_SERVICE_ACCOUNT_TOKEN";
        };
      }
    ];
  };

  jq       = "${pkgs.jq}/bin/jq";
  git      = "${pkgs.git}/bin/git";
  gh       = "${pkgs.gh}/bin/gh";
  aws      = "${pkgs.awscli2}/bin/aws";
  # Use distinct names so these store-path strings don't shadow the `pkgs`
  # package attrs of the same name in the `with pkgs;` home.packages list.
  talosctlBin = "${pkgs.talosctl}/bin/talosctl";
  kubectlBin  = "${pkgs.kubectl}/bin/kubectl";
in
{
  # Cluster / infra tooling for the homelab dev container. Versions track
  # nixpkgs; if a tool needs to match the cluster exactly (talosctl / kubectl
  # skew), pin it here via an overlay.
  home.packages = with pkgs; [
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
    mcp-grafana
    awscli2 # also used by the cluster-credential activation script
  ];

  home.file.".config/agent/mcp-servers-homelab.json".source = grafanaMcp;

  # Force the mounted Claude Bot key for github.com so `git push` attributes to
  # the bot, not whatever the operator forwards over `ssh -A`. Merges with the
  # shared programs.ssh github.com block (User/HostName/PreferredAuthentications).
  programs.ssh.settings."github.com" = {
    IdentityFile = "~/.ssh/id_ed25519";
    IdentitiesOnly = "yes";
    IdentityAgent = "none";
  };

  # --- Runtime bootstrap. Each runs on every apply (idempotent), reads secrets
  # from env vars at activation time (never baked into the store), and soft-fails
  # so a missing secret or down endpoint warns rather than aborting the apply. ---

  # Credentials: restore Claude/Codex tokens (newer-wins by expiry), configure
  # the bk CLI org, and set the git identity from the GitHub token.
  home.activation.restoreAgentCredentials =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      # Wrap (don't `exit`) the dry-run guard: activation entries are sourced
      # into one script, so a top-level `exit` would kill the whole activation.
      if [ -z "$DRY_RUN_CMD" ]; then
      (
        set +e
        if [ -n "''${CLAUDE_CREDENTIALS:-}" ] && echo "$CLAUDE_CREDENTIALS" | ${jq} empty 2>/dev/null; then
          mkdir -p "$HOME/.claude"
          if [ ! -f "$HOME/.claude/.credentials.json" ]; then
            echo "$CLAUDE_CREDENTIALS" > "$HOME/.claude/.credentials.json"
            chmod 600 "$HOME/.claude/.credentials.json"
          else
            disk_expires=$(${jq} -r '.claudeAiOauth.expiresAt // 0' "$HOME/.claude/.credentials.json" 2>/dev/null || echo 0)
            env_expires=$(echo "$CLAUDE_CREDENTIALS" | ${jq} -r '.claudeAiOauth.expiresAt // 0')
            if [ "$env_expires" -gt "$disk_expires" ] 2>/dev/null; then
              echo "$CLAUDE_CREDENTIALS" > "$HOME/.claude/.credentials.json"
              chmod 600 "$HOME/.claude/.credentials.json"
            fi
          fi
        fi
        if [ -n "''${CODEX_CREDENTIALS:-}" ] && echo "$CODEX_CREDENTIALS" | ${jq} empty 2>/dev/null; then
          mkdir -p "$HOME/.codex"
          if [ ! -f "$HOME/.codex/auth.json" ]; then
            echo "$CODEX_CREDENTIALS" > "$HOME/.codex/auth.json"
            chmod 600 "$HOME/.codex/auth.json"
          else
            disk_expires=$(${jq} -r '.expires_at // 0' "$HOME/.codex/auth.json" 2>/dev/null || echo 0)
            env_expires=$(echo "$CODEX_CREDENTIALS" | ${jq} -r '.expires_at // 0')
            if [ "$env_expires" -gt "$disk_expires" ] 2>/dev/null; then
              echo "$CODEX_CREDENTIALS" > "$HOME/.codex/auth.json"
              chmod 600 "$HOME/.codex/auth.json"
            fi
          fi
        fi
        if [ -n "''${BUILDKITE_API_TOKEN:-}" ] && command -v bk >/dev/null 2>&1 \
            && ! grep -q 'selected_org' "$HOME/.config/bk.yaml" 2>/dev/null; then
          mkdir -p "$HOME/.config"
          bk config set selected_org ianremmelllc 2>/dev/null || true
        fi
        if [ -n "''${GITHUB_TOKEN:-}" ]; then
          if gh_json=$(${gh} api user 2>/dev/null); then
            login=$(echo "$gh_json" | ${jq} -r '.login // empty')
            name=$(echo  "$gh_json" | ${jq} -r '.name  // empty')
            email=$(echo "$gh_json" | ${jq} -r '.email // empty')
            if [ -n "$login" ]; then
              [ -z "$name" ]  && name="$login"
              [ -z "$email" ] && email="$login@users.noreply.github.com"
              ${git} config --global user.name  "$name"
              ${git} config --global user.email "$email"
            fi
          fi
        fi
      ) || echo "[pairing] WARNING: credential restore aborted unexpectedly" >&2
      fi
    '';

  # Project repos: clone (or fetch) the slugs in repos.txt into ~/projects.
  home.activation.cloneAgentProjects =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ -z "$DRY_RUN_CMD" ]; then
      (
        set +e
        repos_file=${./repos.txt}
        projects="$HOME/projects"
        mkdir -p "$projects"
        while IFS= read -r slug; do
          slug="''${slug%%#*}"
          slug="$(echo "$slug" | tr -d '[:space:]')"
          [ -z "$slug" ] && continue
          case "$slug" in
            *[!A-Za-z0-9._/-]* | *..* | /* | */ | */*/*)
              echo "[pairing] skipping malformed repo slug '$slug'" >&2; continue ;;
          esac
          case "$slug" in */*) ;; *) echo "[pairing] skipping repo slug without owner '$slug'" >&2; continue ;; esac
          name="''${slug##*/}"
          dest="$projects/$name"
          if [ -d "$dest/.git" ]; then
            ${git} -C "$dest" fetch --all --prune --quiet || echo "[pairing] fetch failed: $slug" >&2
          else
            [ -e "$dest" ] && rm -rf "$dest"
            ${git} clone --quiet "git@github.com:$slug.git" "$dest" || echo "[pairing] clone failed: $slug" >&2
          fi
        done < "$repos_file"
      ) || echo "[pairing] WARNING: project clone aborted unexpectedly" >&2
      fi
    '';

  # Cluster credentials: fetch Terraform state from Garage S3 and derive
  # talosconfig/kubeconfig. Endpoint comes from $GARAGE_ENDPOINT (no hostname
  # committed); skipped when it or the AWS creds are unset.
  home.activation.bootstrapClusterCreds =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ -z "$DRY_RUN_CMD" ]; then
      (
        set +e
        if [ -z "''${GARAGE_ENDPOINT:-}" ] || [ -z "''${AWS_ACCESS_KEY_ID:-}" ] || [ -z "''${AWS_SECRET_ACCESS_KEY:-}" ]; then
          echo "[pairing] cluster creds: GARAGE_ENDPOINT or AWS creds unset; skipping" >&2
          exit 0
        fi
        state_tmp=$(mktemp "''${TMPDIR:-/tmp}/tofu-state.XXXXXX.json")
        trap 'rm -f "$state_tmp"' EXIT
        if ! ${aws} --endpoint-url "$GARAGE_ENDPOINT" --region us-east-1 \
             s3 cp "s3://terraform-state/homelab/terraform.tfstate" "$state_tmp" --no-progress >/dev/null 2>&1; then
          echo "[pairing] cluster creds: state fetch from Garage failed" >&2; exit 0
        fi
        mkdir -p "$HOME/.talos" "$HOME/.kube"
        if ! ${jq} -er '.outputs.talosconfig.value' "$state_tmp" > "$HOME/.talos/config" 2>/dev/null; then
          echo "[pairing] cluster creds: state missing talosconfig output" >&2; exit 0
        fi
        chmod 600 "$HOME/.talos/config"
        ips_json=$(${jq} -ce '.outputs.controlplane_ips.value | select(type == "array" and length > 0)' "$state_tmp" 2>/dev/null) || {
          echo "[pairing] cluster creds: state missing/empty controlplane_ips" >&2; exit 0; }
        mapfile -t ips < <(echo "$ips_json" | ${jq} -r '.[]')
        first_ip="''${ips[0]}"
        ${talosctlBin} config endpoint "''${ips[@]}"
        ${talosctlBin} config node "$first_ip"
        if ! ${talosctlBin} kubeconfig --force "$HOME/.kube/config" >/dev/null 2>&1; then
          echo "[pairing] cluster creds: talosctl kubeconfig failed" >&2; exit 0
        fi
        chmod 600 "$HOME/.kube/config"
        if ! ${kubectlBin} config set-cluster homelab-cluster --server="https://$first_ip:6443" >/dev/null \
           || ! ${kubectlBin} config set-context --current --namespace=argocd >/dev/null; then
          echo "[pairing] cluster creds: kubectl config failed" >&2; exit 0
        fi
        echo "[pairing] cluster creds configured (endpoints: ''${ips[*]})" >&2
      ) || echo "[pairing] WARNING: cluster cred bootstrap aborted unexpectedly" >&2
      fi
    '';
}
