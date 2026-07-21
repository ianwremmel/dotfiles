{ pkgs, lib, ... }:
let
  jsonFormat = pkgs.formats.json { };

  # An agent host drives GitHub and Linear as its own bot account, not as the
  # operator, which is what dispatch's `dedicated` credential mode describes:
  # posts go unwrapped and review requests can target the operator. Applied to
  # both settings files below, since either may be the one dispatch reads.
  dispatchCredentialMode = {
    pluginConfigs."dispatch@agentic".options.credential_mode = "dedicated";
  };

  # System-level Claude Code policy. The consuming host installs this at
  # /etc/claude-code/managed-settings.json. It pre-approves the shared plugin
  # set (see `../claude/plugins.nix`) and wires the remote-agent sound hooks (the
  # play-sound shim plays the sound on the connecting client).
  managedSettings = jsonFormat.generate "claude-managed-settings.json" (
    lib.recursiveUpdate (import ../claude/plugins.nix) (dispatchCredentialMode // {
      hooks = {
        Stop = [{ hooks = [{ type = "command"; command = "play-sound Morse 0.4"; }]; }];
        Notification = [{ hooks = [{ type = "command"; command = "play-sound Ping 0.35"; }]; }];
      };
    })
  );

  # MCP servers the agent kit registers globally. The host substitutes the $VAR
  # tokens at runtime before registering them with `claude mcp add`. A
  # project-scoped server (e.g. homelab's Grafana) goes in that project's own
  # .mcp.json instead — see homelabMcp below.
  mcpServers = jsonFormat.generate "mcp-servers.json" {
    servers = [
      {
        name = "linear";
        transport = "http";
        url = "https://mcp.linear.app/mcp";
        headers.Authorization = "Bearer $LINEAR_API_KEY";
      }
      {
        name = "buildkite";
        transport = "stdio";
        command = "buildkite-mcp-server";
        args = [ "stdio" ];
        env.BUILDKITE_API_TOKEN = "$BUILDKITE_API_TOKEN";
      }
    ];
  };

  # Grafana lives inside the cluster, so this server is only reachable from an
  # agent host and only useful in the homelab repo. Claude Code reads .mcp.json
  # from a project root and expands ${VAR} at load time, so the token is never
  # written to disk.
  homelabMcp = jsonFormat.generate "homelab-mcp.json" {
    mcpServers.grafana = {
      command = "mcp-grafana";
      args = [ "-t" "stdio" ];
      env = {
        GRAFANA_URL = "http://kube-prometheus-stack-grafana.observability.svc.cluster.local";
        GRAFANA_SERVICE_ACCOUNT_TOKEN = "\${GRAFANA_SERVICE_ACCOUNT_TOKEN}";
      };
    };
  };
in
{
  # Exported under ~/.config/agent/ as content the host wires in: the managed
  # settings is a system policy file, and the MCP list is registered at boot with
  # token substitution. Linux only — the sound hooks call the play-sound shim,
  # which (like the sshd config) only ships on Linux agent hosts.
  home.file = lib.mkIf pkgs.stdenv.isLinux {
    ".config/agent/claude-managed-settings.json".source = managedSettings;
    ".config/agent/mcp-servers.json".source = mcpServers;
  };

  dotfiles.claude.settings = lib.mkIf pkgs.stdenv.isLinux dispatchCredentialMode;

  # On a privileged agent host (the dev container activates as root), install the
  # managed-settings as the system policy, so the host doesn't have to place it.
  # Self-skips when activation isn't root or the file is absent (non-Linux).
  home.activation.installAgentManagedSettings =
    # After linkGeneration, not just writeBoundary: it copies from the
    # ~/.config/agent/ symlink, which linkGeneration creates.
    lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      if [ "$(id -u)" = 0 ] && [ -f "$HOME/.config/agent/claude-managed-settings.json" ]; then
        run mkdir -p /etc/claude-code
        run install -m 0644 "$HOME/.config/agent/claude-managed-settings.json" \
          /etc/claude-code/managed-settings.json
      fi
    '';

  # Drop the project's MCP config in when the repo is present. The file is
  # gitignored in homelab, so overwriting it leaves no working-tree change; it is
  # rewritten on every apply, so a hand edit on an agent host does not survive.
  # Linux only: on a personal macOS machine ~/projects/homelab is a human's
  # checkout with its own .mcp.json pointed at the public Grafana endpoint.
  home.activation.writeHomelabMcp = lib.mkIf pkgs.stdenv.isLinux (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ -d "$HOME/projects/homelab" ]; then
        run install -m 0644 ${homelabMcp} "$HOME/projects/homelab/.mcp.json"
      fi
    ''
  );
}
