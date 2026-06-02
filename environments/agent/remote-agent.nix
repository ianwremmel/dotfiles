{ pkgs, lib, ... }:
let
  src = ./remote-agent;

  # Package the shims together so each one resolves its sibling
  # _remote-agent.sh via `readlink -f` (home.file would put each file in its own
  # store path and break that), then symlink the command names onto PATH.
  remoteAgent = pkgs.runCommand "remote-agent-shims" { } ''
    mkdir -p "$out/lib/remote-agent" "$out/bin"
    install -m0644 ${src}/_remote-agent.sh "$out/lib/remote-agent/_remote-agent.sh"
    for f in open-link pbcopy pbpaste play-sound remote-agent-watch-port; do
      install -m0755 ${src}/"$f" "$out/lib/remote-agent/$f"
    done
    # open-link also answers to xdg-open / www-browser / $BROWSER so CLIs that
    # probe those names open URLs on the connecting client too.
    for c in open-link xdg-open www-browser; do
      ln -s "$out/lib/remote-agent/open-link" "$out/bin/$c"
    done
    ln -s "$out/lib/remote-agent/pbcopy"                  "$out/bin/pbcopy"
    ln -s "$out/lib/remote-agent/pbpaste"                 "$out/bin/pbpaste"
    ln -s "$out/lib/remote-agent/play-sound"             "$out/bin/play-sound"
    ln -s "$out/lib/remote-agent/remote-agent-watch-port" "$out/bin/remote-agent-watch-port"
  '';
in
{
  # Shims that bridge to the connecting client over the SSH channel: open URLs,
  # clipboard in/out, play sounds, and forward OAuth callback ports. They
  # degrade to OSC-8/OSC-52 terminal escapes when no Mac agent socket is
  # present. Linux only — on macOS the native pbcopy/open should win.
  home.packages = lib.mkIf pkgs.stdenv.isLinux [ remoteAgent ];
  home.sessionVariables = lib.mkIf pkgs.stdenv.isLinux { BROWSER = "open-link"; };
}
