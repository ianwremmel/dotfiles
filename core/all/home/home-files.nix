{ lib, ... }:
let
  # Auto-discover every file under ./home-files/home/ and map it to the same
  # relative path under $HOME. The source tree's layout IS the home layout.
  # Per-file (not a whole-dir symlink) so non-repo entries (e.g. ~/bin/steam)
  # are never shadowed. Scripts under bin/ are installed executable. Add a new
  # dotfile or script by dropping it in ./home-files/home/<rel> and ./apply.
  homeTree = ./home-files/home;
  prefix = toString homeTree + "/";
  files = builtins.filter
    (p: !(builtins.elem (baseNameOf (toString p)) [ ".DS_Store" ".gitkeep" ]))
    (lib.filesystem.listFilesRecursive homeTree);
  discovered = lib.listToAttrs (map
    (p:
      let rel = lib.removePrefix prefix (toString p);
      in lib.nameValuePair rel {
        source = p;
        executable = lib.hasPrefix "bin/" rel;
      })
    files);

  # Pre-existing regular files to clear so home-manager can link. Derived from
  # the discovered set plus the specially-handled files: .screenrc (via
  # programs.screen), .ssh/config (now owned by programs.ssh), the
  # now-vestigial .gitignore (old excludesfile path), and .config/git/ignore
  # (a hand-created global ignore now owned by programs.git.ignores — its sole
  # pattern was folded into git.nix's ignores list).
  clearPaths = (builtins.attrNames discovered)
    ++ [ ".screenrc" ".ssh/config" ".gitignore" ".config/git/ignore" ];
in
{
  programs.screen = {
    enable = true;
    package = null;                       # screen binary comes from cli-tools.nix; this just manages ~/.screenrc
    screenrc = ./home-files/screenrc;
  };

  home.file = discovered;

  # Clear the legacy rsynced regular files so home-manager can take over.
  # Direct rm (no backup) — exact tracked copies; rsync -av already clobbered
  # local edits on every apply, and git has the content. Guarded so it only
  # touches a real file that isn't already our symlink. List is derived, not
  # hardcoded — new home-files entries contribute their own cleanup.
  home.activation.clearLegacyHomedirFiles =
    lib.hm.dag.entryBefore [ "checkLinkTargets" ] (
      lib.concatMapStringsSep "\n"
        (rel: ''if [ -f "$HOME/${rel}" ] && [ ! -L "$HOME/${rel}" ]; then /bin/rm "$HOME/${rel}"; fi'')
        clearPaths
    );
}
