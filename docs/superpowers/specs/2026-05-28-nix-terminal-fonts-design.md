# Nix Terminal Fonts Slice Design

**Date:** 2026-05-28
**Status:** Draft — pending user approval
**Branch:** `nix-terminal-fonts` (stacks on `nix-homedir` / PR #75 → `nix-vscode` / PR #74 → … → master)

## Goal

Close the long-deferred terminal-font deferral (originally deferral #4, reopened after the nix-firstrun slice's plain-string attempt was found not to work). Make iTerm2 and Terminal.app actually render the MesloLGS Nerd Font so starship's git-branch/powerline glyphs display correctly — declaratively, via home-manager.

## Background — why the firstrun attempt failed

The nix-firstrun slice wrote `CustomUserPreferences."com.googlecode.iterm2"."Normal Font" = "MesloLGS-NF-Regular 14"` as a **top-level** default. Investigation for this slice found two reasons it never worked:

1. **Wrong key location.** iTerm's font is not a top-level pref — it lives per-profile inside the `New Bookmarks` array. The user's actual profiles ("Default" GUID `BC395EC2-…`, and "tmux" GUID `B419BC64-…`) were both set to `Monaco 20`. The top-level `Normal Font` key was simply ignored.
2. **Wrong font name.** The installed Nerd Font's real PostScript names are `MesloLGSNF-Regular` ("MesloLGS Nerd Font") and `MesloLGSNFM-Regular` (the Mono variant) — not `MesloLGS-NF-Regular`. The correct iTerm font value is `MesloLGSNF-Regular 14`.

Terminal.app stores its font as a binary NSFont blob (NSKeyedArchiver) inside the per-profile dict (the user's default/startup profile is "Homebrew"), which is why no plain-string write reaches it either.

## Decisions (locked)

1. **iTerm via Dynamic Profiles (clobber-immune), both profiles.** home-manager writes `~/Library/Application Support/iTerm2/DynamicProfiles/nix.json` defining two profiles, each using `"Dynamic Profile Parent Name"` to inherit an existing profile and override only the font:
   - **`Default (nix)`** — GUID `95362E86-C10E-48E3-9FA1-DC4596B0F677`, parent `"Default"`.
   - **`tmux (nix)`** — GUID `BF5B17AC-8CB2-4C36-942E-F45E91EAF11A`, parent `"tmux"`.
   Dynamic profiles are read fresh on iTerm launch and are NOT part of the plist iTerm rewrites on quit, so they can't be clobbered by a running iTerm (the deciding advantage over patching `New Bookmarks` in place).
2. **Font: `MesloLGSNF-Regular 14`** ("MesloLGS Nerd Font", non-Mono — the starship/powerlevel10k-recommended variant; allows double-width icon glyphs). Set as both `"Normal Font"` and `"Non Ascii Font"`, with `"Use Non-ASCII Font" = false` (use the normal font for non-ASCII too).
3. **Auto-activate the Default-inheriting profile.** Set `targets.darwin.defaults."com.googlecode.iterm2"."Default Bookmark Guid" = "95362E86-…"` so `Default (nix)` becomes the active default. The `tmux (nix)` profile is selected manually for tmux windows once (tmux isn't GUID-pinned anywhere in the user's prefs — verified — so there's nothing to repoint automatically).
4. **Terminal.app via a stored NSFont blob injected by activation.** Terminal has no dynamic-profiles equivalent. A `home.activation` injects a precomputed NSKeyedArchiver NSFont blob for `MesloLGSNF-Regular` size 14 into the "Homebrew" profile's `Font` key, using a cfprefsd-safe round-trip: `defaults export` → `plutil -replace 'Window Settings.Homebrew.Font' -data <base64>` → `defaults import`.
5. **Store the precomputed blob (with a regen comment), don't generate at activation.** The 273-byte base64 blob is committed as a Nix string with a comment documenting the Swift one-liner to regenerate it. Rationale: avoids a hard Xcode-CLT dependency and a multi-second `swift` compile on every `./apply`; the NSFont archive format is stable in practice. (Generating in a nix derivation isn't possible — swift needs the macOS SDK, unavailable in the nix build sandbox.)
6. **Remove the stale iTerm block from `nix/darwin/defaults.nix`.** The firstrun slice's `CustomUserPreferences."com.googlecode.iterm2"` font keys are ignored cruft and now superseded. Removing them also avoids two layers (nix-darwin + home-manager `targets.darwin.defaults`) writing the same `com.googlecode.iterm2` domain.
7. **Profile: `default`, darwin-gated.** iTerm/Terminal are macOS GUI apps; the module lives in the `default` (personal-macOS) profile and is wrapped in `lib.mkIf pkgs.stdenv.isDarwin` so the `default@*-linux` matrix build is a no-op.
8. **No content beyond fonts.** This slice only sets fonts. It does not manage colors, keybindings, or other iTerm/Terminal settings (the dynamic profiles inherit everything else from their parents).
9. **No work-specific values.** The blob is a non-sensitive NSFont archive (font name + size); fine for the public `default` profile.

## Architecture

```text
NEW FILES:
  nix/profiles/default/terminal-fonts.nix          # iTerm dynamic profiles + Default Bookmark Guid + Terminal.app activation

MODIFIED FILES:
  nix/profiles/default/default.nix                 # imports ./terminal-fonts.nix
  nix/darwin/defaults.nix                          # remove stale CustomUserPreferences."com.googlecode.iterm2" block
  nix/README.md                                    # +migration guide sub-block

UNTOUCHED:
  ~/Library/Preferences/com.googlecode.iterm2.plist  # iTerm's own prefs — never edited (dynamic profiles are separate)
  the existing "Default"/"tmux" iTerm profiles        # kept as dynamic-profile parents
  ~/Library/Preferences/com.apple.Terminal.plist      # only the Homebrew profile's Font key is touched, via export/import round-trip
```

## `nix/profiles/default/terminal-fonts.nix` (full content)

```nix
{ pkgs, lib, ... }:
let
  font = "MesloLGSNF-Regular 14";   # "MesloLGS Nerd Font" 14pt; PostScript name + size

  defaultGuid = "95362E86-C10E-48E3-9FA1-DC4596B0F677";
  tmuxGuid    = "BF5B17AC-8CB2-4C36-942E-F45E91EAF11A";

  # NSKeyedArchiver-encoded NSFont for "MesloLGSNF-Regular" at 14pt, base64.
  # Terminal.app stores profile fonts as this binary blob. Regenerate with:
  #   swift -e 'import AppKit; let f = NSFont(name: "MesloLGSNF-Regular", size: 14)!; print(try! NSKeyedArchiver.archivedData(withRootObject: f, requiringSecureCoding: false).base64EncodedString())'
  terminalFontBlob =
    "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGkCwwVFlUkbnVsbNQNDg8QERITFFZOU1NpemVYTlNmRmxhZ3NWTlNOYW1lViRjbGFzcyNALAAAAAAAABAQgAKAA18QEk1lc2xvTEdTTkYtUmVndWxhctIXGBkaWiRjbGFzc25hbWVYJGNsYXNzZXNWTlNGb250ohkbWE5TT2JqZWN0CBEaJCkyN0lMUVNYXmdud36FjpCSlKmuucLJzAAAAAAAAAEBAAAAAAAAABwAAAAAAAAAAAAAAAAAAADV";

  iterm2DynamicProfiles = {
    Profiles = [
      {
        Name = "Default (nix)";
        Guid = defaultGuid;
        "Dynamic Profile Parent Name" = "Default";
        "Normal Font" = font;
        "Non Ascii Font" = font;
        "Use Non-ASCII Font" = false;
      }
      {
        Name = "tmux (nix)";
        Guid = tmuxGuid;
        "Dynamic Profile Parent Name" = "tmux";
        "Normal Font" = font;
        "Non Ascii Font" = font;
        "Use Non-ASCII Font" = false;
      }
    ];
  };
in
lib.mkIf pkgs.stdenv.isDarwin {
  # iTerm: dynamic profiles (read on launch; immune to iTerm rewriting its own
  # prefs plist on quit). The Default-inheriting one is set as the default
  # bookmark below so it auto-activates; the tmux one is selected manually for
  # tmux windows (tmux is not GUID-pinned anywhere in iTerm's prefs).
  home.file."Library/Application Support/iTerm2/DynamicProfiles/nix.json".text =
    builtins.toJSON iterm2DynamicProfiles;

  targets.darwin.defaults."com.googlecode.iterm2"."Default Bookmark Guid" = defaultGuid;

  # Terminal.app: no dynamic-profiles equivalent. Inject the NSFont blob into
  # the "Homebrew" profile (the user's default/startup profile) via a
  # cfprefsd-safe export -> plutil -replace -> import round-trip. Idempotent.
  # NOTE: if Terminal.app is running during ./apply it may rewrite its prefs on
  # quit and revert this; quit Terminal.app before applying for it to stick.
  home.activation.terminalAppFont =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      tmp="$(/usr/bin/mktemp)"
      if /usr/bin/defaults export com.apple.Terminal "$tmp" 2>/dev/null \
         && /usr/bin/plutil -replace 'Window Settings.Homebrew.Font' \
              -data '${terminalFontBlob}' "$tmp" 2>/dev/null; then
        /usr/bin/defaults import com.apple.Terminal "$tmp"
      fi
      /bin/rm -f "$tmp"
    '';
}
```

Notes:
- `builtins.toJSON` is fine for the dynamic-profile file — iTerm reads JSON dynamic profiles.
- `"Use Non-ASCII Font" = false` means iTerm uses `Normal Font` for non-ASCII glyphs too; we still set `Non Ascii Font` to the same value for completeness.
- The activation guards on `defaults export` + `plutil` succeeding before `import`, so a missing "Homebrew" profile or export failure won't corrupt anything (it just skips). It runs `entryAfter [ "writeBoundary" ]` (standard for non-link activations that mutate external state).
- `plutil -replace` keypath `'Window Settings.Homebrew.Font'`: `.` separates levels; "Window Settings" (with a space) is a single key — plutil handles spaces in keys.

## `nix/profiles/default/default.nix` change

Add `./terminal-fonts.nix` to imports:

```nix
  imports = [
    ./claude.nix
    ./cli-tools.nix
    ./terminal-fonts.nix
  ];
```

## `nix/darwin/defaults.nix` change

Remove the `# ----- iTerm 2 -----` block under `CustomUserPreferences` (the `"com.googlecode.iterm2" = { "Normal Font" = …; "Non Ascii Font" = …; "Use Non-ASCII Font" = …; };` entry added by nix-firstrun). It is ignored by iTerm and now superseded. Leave all other `CustomUserPreferences` domains intact.

## Migration guide block in `nix/README.md`

Append after the "For the nix-homedir slice" sub-block, paragraph-heading style:

```markdown
For the nix-terminal-fonts slice (iTerm2 + Terminal.app Nerd Font, declarative):

Closes the terminal-font deferral. The nix-firstrun attempt wrote a top-level
`Normal Font` pref, which iTerm ignores (the font lives per-profile in
`New Bookmarks`), with a typo'd PostScript name. This slice does it correctly:

- **iTerm2** — two Dynamic Profiles (`~/Library/Application Support/iTerm2/DynamicProfiles/nix.json`)
  inherit your existing `Default` and `tmux` profiles and override the font to
  `MesloLGSNF-Regular 14` ("MesloLGS Nerd Font"). The Default-inheriting profile
  (`Default (nix)`) is set as iTerm's default bookmark, so it auto-activates;
  relaunch iTerm to see it. For tmux windows, select the `tmux (nix)` profile
  once. Dynamic profiles can't be clobbered by iTerm rewriting its own prefs.
- **Terminal.app** — the "Homebrew" profile's font (a binary NSFont blob) is set
  via a `defaults export → plutil -replace → defaults import` round-trip in a
  home-manager activation. **Quit Terminal.app before `./apply`** for the change
  to stick (Terminal rewrites its prefs on quit and has no dynamic-profiles
  escape hatch). You use iTerm as the daily driver, so this is low-impact.

**Changing the font:** edit `font` in `nix/profiles/default/terminal-fonts.nix`
and `./apply`. For Terminal.app, also regenerate the NSFont blob (the Swift
one-liner is in the file's comment) since Terminal needs the binary archive.

**Private flake update (only if you have one):** if your private flake adds
iTerm dynamic profiles or `targets.darwin.defaults` for these domains, Nix
module merging handles additive entries; conflicting keys need `lib.mkForce`.
```

## Open questions resolved during plan / implementation

1. **`plutil -replace` keypath with the space in "Window Settings".** Verify `plutil -replace 'Window Settings.Homebrew.Font' -data <b64> <file>` targets the right nested key (it should — `.` is the level separator, spaces are literal). If plutil mis-parses, fall back to a Python `plistlib` round-trip (load exported plist, set `pl["Window Settings"]["Homebrew"]["Font"] = base64.b64decode(blob)`, write, import).
2. **`targets.darwin.defaults` option name/shape.** Confirm the home-manager option is `targets.darwin.defaults.<domain>.<key>` at this pin (the `modules/targets/darwin/user-defaults` module exists). If the path differs, set the `Default Bookmark Guid` via a small `home.activation` `defaults write` instead.
3. **Dynamic profile "Use Non-ASCII Font" key name.** Confirm iTerm reads `"Use Non-ASCII Font"` (boolean) and `"Non Ascii Font"` (string) from dynamic-profile JSON the same as from the main plist. If the JSON expects different casing, adjust.
4. **Terminal blob validity at apply.** After apply (Terminal quit), open Terminal → the Homebrew profile shows MesloLGS Nerd Font 14. If the blob doesn't take, regenerate via the documented Swift snippet on the actual machine (handles any local font-name nuance).

## Testing

Per project convention (no automated tests), manual verification in the plan:

1. **Pre-flight:** capture `defaults read com.googlecode.iterm2 "New Bookmarks"` font values (Monaco 20) and `defaults read com.apple.Terminal "Window Settings.Homebrew.Font"` (current blob); confirm DynamicProfiles dir empty.
2. **Eval gates (pre-apply):** the module evals; `home.file."Library/Application Support/iTerm2/DynamicProfiles/nix.json"` is present; `targets.darwin.defaults` resolves; `nix/darwin/defaults.nix` no longer references `com.googlecode.iterm2`; agent@linux build is a no-op (isDarwin guard).
3. **After `./apply`:**
   - `~/Library/Application Support/iTerm2/DynamicProfiles/nix.json` exists (symlink), contains the two profiles with `MesloLGSNF-Regular 14`.
   - `defaults read com.googlecode.iterm2 "Default Bookmark Guid"` → `95362E86-…`.
   - `defaults read com.apple.Terminal "Window Settings.Homebrew.Font"` → a blob decoding to MesloLGSNF-Regular 14 (compare to the source blob, or `plutil -p`).
   - **Manual visual:** relaunch iTerm → Default window uses MesloLGS Nerd Font; starship branch glyph renders (no missing-glyph box). Select `tmux (nix)` → tmux windows use it. Quit+reopen Terminal.app → Homebrew profile uses it.
4. **Idempotence:** second `./apply` — dynamic-profile file unchanged; the Terminal activation re-injects the same blob (no-op effect).

## Risk and rollback

**Risk profile:** Low-medium. iTerm side is low-risk (dynamic profiles are additive, non-destructive, separate file). Terminal side is the riskier part: the `defaults import` replaces the com.apple.Terminal domain from the exported+modified copy (preserves everything else; tiny race only if Terminal writes between export and import — mitigated by quit-first guidance). The stored blob is opaque but documented/regenerable.

**Rollback:** `git revert` the slice + `./apply`. The iTerm dynamic-profile file is removed (iTerm reverts to the original Default/tmux profiles automatically); `Default Bookmark Guid` reverts. For Terminal, the activation stops running; the last-imported font persists until manually changed (re-set the Homebrew profile font by hand if reverting fully). No data loss — iTerm's own profiles were never edited.

## Out of scope

- **Other iTerm/Terminal settings** (colors, keybindings, window size) — fonts only.
- **The "tmux" iTerm integration auto-pointing at the new profile** — tmux isn't GUID-pinned, so the user selects `tmux (nix)` manually; not worth special machinery.
- **Generating the NSFont blob at activation time** — rejected (Xcode-CLT dependency + per-apply swift cost); stored blob with regen comment instead.
- **Other terminal emulators** (Alacritty, kitty, etc.) — not installed/used.

## Cross-references

- Master design: `docs/superpowers/specs/2026-05-22-nix-migration-design.md`
- nix-firstrun slice (the original font attempt): `docs/superpowers/specs/2026-05-26-nix-firstrun-design.md`
- Status doc (local, uncommitted): `docs/superpowers/nix-migration-status.md` — closes the reopened iTerm/Terminal font deferral
- Migration guide: `nix/README.md`
