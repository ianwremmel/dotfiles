{ config, lib, pkgs, ... }:
let
  # Where the managed directives land, and the Include that pulls them into the
  # writable user config. Relative paths in an Include are resolved against
  # ~/.ssh, so `config.d/dotfiles.conf` is ~/.ssh/config.d/dotfiles.conf.
  fragmentRel = ".ssh/config.d/dotfiles.conf";
  includeLine = "Include config.d/dotfiles.conf";
in
{
  # Managed ~/.ssh directives (freeform OpenSSH, keyed by host).
  # enableDefaultConfig is off so home-manager doesn't inject its opinionated `*`
  # defaults (Compression / ControlMaster / HashKnownHosts / …) — we declare the
  # `*` block ourselves. Most-specific blocks first; `*` is pinned last with the
  # DAG, since ssh takes the first value seen for each option. Other environments
  # and the dev container merge their own entries into programs.ssh.settings
  # (e.g. a host alias, or the github bot key); all of it flows into the single
  # rendered file that we redirect to the fragment below.
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    settings = {
      "github.com" = {
        User = "git";
        HostName = "github.com";
        PreferredAuthentications = "publickey";
      };

      # Hosts that should not be auto-trusted.
      "no-auto-trust" = {
        header = "Host *.amazonaws.com github.com monkey.org *.heroku.com";
        StrictHostKeyChecking = "yes";
      };

      "*" = lib.hm.dag.entryAfter [ "github.com" "no-auto-trust" ] (
        {
          ForwardAgent = "yes";
          AddKeysToAgent = "yes";
          IdentityFile = "~/.ssh/id_rsa";
        }
        // lib.optionalAttrs pkgs.stdenv.isDarwin { UseKeychain = "yes"; }
      );
    };
  };

  # ~/.ssh/config is owned by runtime tooling — some corporate SSH helpers
  # rewrite it in place to inject per-workspace Host blocks — so it can't be a
  # read-only store symlink (the tool's write fails with EACCES).
  # Instead: suppress home-manager's own ~/.ssh/config link, expose the rendered
  # directives as a read-only fragment, and seed a writable ~/.ssh/config that
  # Includes the fragment. The fragment refreshes from Nix on every apply; the
  # writable config is touched only to ensure the Include is present, so we never
  # clobber a tool-injected block.
  home.file.".ssh/config".enable = lib.mkForce false;
  home.file.${fragmentRel}.source = config.home.file.".ssh/config".source;

  # Seed after linkGeneration, so the fragment symlink the Include points at is
  # already in place (an interrupted earlier step never leaves us Including a
  # missing file). Idempotent — acts only on the old read-only store symlink or
  # a missing file (seed fresh), or a real file lacking our Include (prepend).
  # A real config left by a runtime tool is preserved: we add the Include,
  # never clear it. The Include goes FIRST: ssh takes the first value seen per
  # option, so our managed directives (the no-auto-trust StrictHostKeyChecking
  # block, the github.com identity) must precede any tool/hand block to stay
  # authoritative — the same precedence the old single rendered config had.
  home.activation.seedSshConfigInclude =
    lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      cfg="$HOME/.ssh/config"
      run mkdir -p "$HOME/.ssh"
      run chmod 0700 "$HOME/.ssh"
      seed_fresh=
      if [ -L "$cfg" ]; then
        # Only the old read-only store symlink is ours to replace. A symlink
        # pointing anywhere else is a deliberate user setup — leave it untouched.
        case "$(readlink "$cfg")" in
          /nix/store/*) seed_fresh=1 ;;
          *) ;;
        esac
      elif [ ! -e "$cfg" ]; then
        seed_fresh=1
      fi
      if [ -n "$seed_fresh" ]; then
        run rm -f "$cfg"
        if [ -z "$DRY_RUN_CMD" ]; then
          printf '%s\n' '${includeLine}' > "$cfg"
          chmod 0600 "$cfg"
        else
          echo "would seed $cfg with '${includeLine}'"
        fi
      elif [ -f "$cfg" ] && ! grep -qxF '${includeLine}' "$cfg"; then
        # Pre-existing real config (tool- or hand-managed): prepend the Include
        # so the managed directives win first-match, without disturbing the
        # existing content. cat-into-place keeps the file's inode/owner/mode;
        # then strip group/world write in case a tool created it loosely.
        if [ -z "$DRY_RUN_CMD" ]; then
          tmp="$cfg.nix-seed"
          { printf '%s\n\n' '${includeLine}'; cat "$cfg"; } > "$tmp"
          cat "$tmp" > "$cfg"
          rm -f "$tmp"
          chmod go-w "$cfg"
        else
          echo "would prepend '${includeLine}' to $cfg"
        fi
      fi
    '';
}
