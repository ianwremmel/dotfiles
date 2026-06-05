{ pkgs, lib, ... }:
let
  src = ./remote-agent;
  prefix = toString src + "/";

  # Auto-discover the shim files (the test/ dir aside) and map each to
  # ~/bin/<name>. Drop a file in ./remote-agent/ and it's installed — no edit
  # here. The shims are co-located under ~/bin so each resolves its sibling
  # _remote-agent.sh by directory; ~/bin is declared on PATH via home.sessionPath
  # and re-prepended in interactive shells by core/all/home/shells.nix's
  # interactivePath (Debian's /etc/profile resets root's PATH, dropping it
  # otherwise — which would leave these shims, and Claude's hooks that call them,
  # unable to find each other).
  discovered = lib.listToAttrs (map
    (p:
      let name = lib.removePrefix prefix (toString p); in
      lib.nameValuePair "bin/${name}" {
        source = p;
        executable = name != "_remote-agent.sh";
      })
    (builtins.filter
      (p: !(lib.hasInfix "/test/" (toString p)))
      (lib.filesystem.listFilesRecursive src)));

  # open-link also answers to these names (xdg-open/www-browser/$BROWSER) so
  # CLIs that probe them open URLs on the connecting client too.
  aliases = lib.listToAttrs (map
    (n: lib.nameValuePair "bin/${n}" { source = src + "/open-link"; executable = true; })
    [ "xdg-open" "www-browser" ]);
in
{
  # Shims that bridge to the connecting client over the SSH channel: open URLs,
  # clipboard in/out, play sounds, and forward OAuth callback ports. They
  # degrade to OSC-8/OSC-52 terminal escapes when no Mac agent socket is
  # present. Linux only — on macOS the native pbcopy/open should win.
  home.file = lib.mkIf pkgs.stdenv.isLinux (discovered // aliases);

  # The shims call nc (unix-socket netcat, openbsd flags -U/-N), ss, and setsid;
  # bundle them so the profile is self-contained on a host without distro tools.
  home.packages = lib.mkIf pkgs.stdenv.isLinux [
    pkgs.netcat-openbsd
    pkgs.iproute2
    pkgs.util-linux
  ];
  home.sessionVariables = lib.mkIf pkgs.stdenv.isLinux { BROWSER = "open-link"; };
}
