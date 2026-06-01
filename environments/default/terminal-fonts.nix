{ pkgs, lib, ... }:
let
  font = "MesloLGSNF-Regular 14";   # "MesloLGS Nerd Font" 14pt; PostScript name + size

  # NSKeyedArchiver-encoded NSFont for "MesloLGSNF-Regular" at 14pt, base64.
  # Terminal.app stores profile fonts as this binary blob. Regenerate with:
  #   swift -e 'import AppKit; let f = NSFont(name: "MesloLGSNF-Regular", size: 14)!; print(try! NSKeyedArchiver.archivedData(withRootObject: f, requiringSecureCoding: false).base64EncodedString())'
  terminalFontBlob =
    "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGkCwwVFlUkbnVsbNQNDg8QERITFFZOU1NpemVYTlNmRmxhZ3NWTlNOYW1lViRjbGFzcyNALAAAAAAAABAQgAKAA18QEk1lc2xvTEdTTkYtUmVndWxhctIXGBkaWiRjbGFzc25hbWVYJGNsYXNzZXNWTlNGb250ohkbWE5TT2JqZWN0CBEaJCkyN0lMUVNYXmdud36FjpCSlKmuucLJzAAAAAAAAAEBAAAAAAAAABwAAAAAAAAAAAAAAAAAAADV";
in
lib.mkIf pkgs.stdenv.isDarwin {
  # Patch the font onto the EXISTING iTerm "Default"/"tmux" profiles and
  # Terminal.app's "Homebrew" profile in place (rather than creating parallel
  # dynamic profiles, which don't auto-take-over the default/tmux roles). A
  # Python plistlib `defaults export -> modify -> defaults import` round-trip
  # writes through cfprefsd cleanly and matches profiles by name (order- and
  # count-independent).
  #
  # CONSTRAINT: iTerm and Terminal.app must be QUIT during ./apply — both
  # rewrite their prefs on quit and would otherwise revert these changes.
  # Idempotent: re-running sets the same values.
  home.activation.terminalFonts =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      # No `|| true`: the patcher already skips absent preference domains
      # gracefully (a failed `defaults export` is treated as "not present"), so
      # any error that escapes here is real and should fail the activation
      # rather than leave ./apply reporting a success that didn't happen.
      ${pkgs.python3}/bin/python3 ${./patch-terminal-fonts.py} \
        ${lib.escapeShellArg font} ${lib.escapeShellArg terminalFontBlob}
    '';
}
