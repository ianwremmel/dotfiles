{ pkgs, lib, ... }:
let
  jsonFormat = pkgs.formats.json { };

  # System-level Claude Code policy. The consuming host installs this at
  # /etc/claude-code/managed-settings.json. It pre-approves the codex plugin
  # marketplace + plugin and wires the remote-agent sound hooks (the play-sound
  # shim plays the sound on the connecting client).
  managedSettings = jsonFormat.generate "claude-managed-settings.json" {
    extraKnownMarketplaces.openai-codex.source = {
      source = "github";
      repo = "openai/codex-plugin-cc";
    };
    enabledPlugins."codex@openai-codex" = true;
    hooks = {
      Stop = [{ hooks = [{ type = "command"; command = "play-sound Morse 0.4"; }]; }];
      Notification = [{ hooks = [{ type = "command"; command = "play-sound Ping 0.35"; }]; }];
    };
  };

  # MCP servers the agent kit registers. The host substitutes the $VAR tokens
  # at runtime and merges in any host-specific servers (e.g. homelab's Grafana)
  # before registering them with `claude mcp add`.
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
in
{
  # Exported under ~/.config/agent/ as content the host wires in (managed
  # settings is a system policy file; the MCP list is registered at boot with
  # token substitution). Skills, rules, and a custom CLAUDE.md can be added
  # later via the same per-file mapping default/claude.nix uses. Linux only:
  # the sound hooks call the play-sound shim, which (like the SSH server config)
  # only ships on Linux agent hosts.
  home.file = lib.mkIf pkgs.stdenv.isLinux {
    ".config/agent/claude-managed-settings.json".source = managedSettings;
    ".config/agent/mcp-servers.json".source = mcpServers;
  };

  # On a privileged agent host (the dev container activates as root), install the
  # managed-settings as the system policy, so the host doesn't have to place it.
  # Self-skips when activation isn't root or the file is absent (non-Linux).
  home.activation.installAgentManagedSettings =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ "$(id -u)" = 0 ] && [ -f "$HOME/.config/agent/claude-managed-settings.json" ]; then
        run mkdir -p /etc/claude-code
        run install -m 0644 "$HOME/.config/agent/claude-managed-settings.json" \
          /etc/claude-code/managed-settings.json
      fi
    '';
}
