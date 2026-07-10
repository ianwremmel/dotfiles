{ pkgs, lib, ... }:
let
  jq       = "${pkgs.jq}/bin/jq";
  git      = "${pkgs.git}/bin/git";
  gh       = "${pkgs.gh}/bin/gh";
  # git shells out to plain `ssh`, which isn't on the activation environment's
  # PATH — pin it or every git@github.com clone/fetch in activation dies with
  # "cannot run ssh: No such file or directory".
  gitSsh   = "GIT_SSH_COMMAND=${pkgs.openssh}/bin/ssh";
in
{
  # Cluster / infra tooling for the interactive agent host. Versions track
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
    awscli2
  ];

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
    lib.hm.dag.entryBetween [ "writeHomelabMcp" ] [ "writeBoundary" ] ''
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
          # Reject a name of "." or ".." outright: it would make dest the
          # projects dir (or its parent), and the rm -rf below could then target
          # something far larger than one repo. The slug guards above already
          # drop "owner/.." (via *..*) and "owner/" (via */), but not "owner/."
          # which yields name=".".
          case "$name" in .|..) echo "[pairing] skipping repo slug with unsafe name '$slug'" >&2; continue ;; esac
          dest="$projects/$name"
          if [ -d "$dest/.git" ]; then
            ${gitSsh} ${git} -C "$dest" fetch --all --prune --quiet || echo "[pairing] fetch failed: $slug" >&2
          else
            [ -e "$dest" ] && rm -rf "$dest"
            ${gitSsh} ${git} clone --quiet "git@github.com:$slug.git" "$dest" || echo "[pairing] clone failed: $slug" >&2
          fi
        done < "$repos_file"
      ) || echo "[pairing] WARNING: project clone aborted unexpectedly" >&2
      fi
    '';
}
