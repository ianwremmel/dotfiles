{ lib, pkgs, ... }:
{
  # ~/.ssh/config via programs.ssh.settings (freeform OpenSSH directives, keyed
  # by host). enableDefaultConfig is off so home-manager doesn't inject its
  # opinionated `*` defaults (Compression / ControlMaster / HashKnownHosts / …)
  # — we declare the `*` block ourselves. Most-specific blocks first; `*` is
  # pinned last with the DAG, since ssh takes the first value seen for each
  # option. Other environments and the dev container merge their own entries in
  # (e.g. a host alias, or the github bot key).
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
}
