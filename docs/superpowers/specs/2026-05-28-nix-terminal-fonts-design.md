# Nix Terminal Fonts Slice Design

**Date:** 2026-05-28
**Status:** Implemented (pivoted from dynamic profiles to in-place patching — see Decision 1)
**Branch:** `nix-terminal-fonts` (stacks on `nix-homedir` / PR #75 → `nix-vscode` / PR #74 → … → master)

## Goal

Close the long-deferred terminal-font deferral (originally deferral #4, reopened after the nix-firstrun slice's plain-string attempt was found not to work). Make iTerm2 and Terminal.app actually render the MesloLGS Nerd Font so starship's git-branch/powerline glyphs display correctly — declaratively, via home-manager, on the user's **existing** profiles.

## Background — why the firstrun attempt failed

The nix-firstrun slice wrote `CustomUserPreferences."com.googlecode.iterm2"."Normal Font" = "MesloLGS-NF-Regular 14"` as a **top-level** default. Two reasons it never worked:

1. **Wrong key location.** iTerm's font is per-profile, inside the `New Bookmarks` array — not a top-level pref. The user's profiles ("Default" GUID `BC395EC2-…`, "tmux" GUID `B419BC64-…`) were both `Monaco 20`; the top-level key was ignored.
2. **Wrong font name.** The installed Nerd Font's real PostScript names are `MesloLGSNF-Regular` ("MesloLGS Nerd Font") / `MesloLGSNFM-Regular` (Mono) — not `MesloLGS-NF-Regular`. The correct value is `MesloLGSNF-Regular 14`.

Terminal.app stores its font as a binary NSFont blob (NSKeyedArchiver) in the per-profile dict (the user's default/startup profile is "Homebrew").

The font itself is already installed and registered — via the `font-meslo-lg-nerd-font` cask (slice 10), present in `~/Library/Fonts/` and discoverable by CoreText. This slice does NOT install fonts; it only sets the per-profile font preference.

## Decision 1 — mechanism (pivoted)

**Patch the font onto the EXISTING profiles in place, not via dynamic profiles.**

The slice was first designed around iTerm Dynamic Profiles (parallel profiles inheriting Default/tmux, with the default-bookmark GUID repointed). That was abandoned during implementation because it created *parallel* profiles that don't automatically take over the default/tmux roles:

- The `Default Bookmark Guid` pref (needed to auto-activate the dynamic Default profile) lives in iTerm's own plist, which a **running iTerm rewrites on quit** — so the repoint got clobbered.
- The "tmux" profile is **not GUID-pinned anywhere** in iTerm's prefs (verified), so a parallel `tmux (nix)` profile can't be made the one iTerm uses without manual selection.

Both problems vanish if we patch the **existing** Default and tmux profiles directly: they remain the default / the tmux profile (whatever selects them still does), now rendering the Nerd Font. A running app still clobbers any pref write, so the unavoidable constraint — **quit iTerm and Terminal.app during `./apply`** — applies to either mechanism; in-place is simply the one that satisfies the goal.

## Decisions (locked)

1. **In-place patch of existing profiles** (see Decision 1 above), via a single Python `plistlib` round-trip: `defaults export <domain> → modify → defaults import <domain>`. The round-trip writes through cfprefsd cleanly (no `killall cfprefsd` needed). Profiles are matched **by name** (order- and count-independent; leaves other profiles untouched).
2. **Font: `MesloLGSNF-Regular 14`** ("MesloLGS Nerd Font", non-Mono — the powerlevel10k/starship-recommended variant, tuned for these prompts; iTerm renders its double-width icon glyphs fine). Set as both `"Normal Font"` and `"Non Ascii Font"`. (The Mono variant `MesloLGSNFM-Regular` is the safer generic-terminal default; non-Mono is the documented pick for this user's starship prompt.)
3. **iTerm: patch profiles named "Default" and "tmux"** in `com.googlecode.iterm2` `New Bookmarks`. No new profiles, no `Default Bookmark Guid` change (the existing Default profile stays the default), no tmux re-selection.
4. **Terminal.app: set the "Homebrew" profile's `Font`** in `com.apple.Terminal` `Window Settings` to a precomputed NSKeyedArchiver NSFont blob (bytes → `<data>`), creating the key if absent (it was). Same `plistlib` round-trip as iTerm.
5. **Store the precomputed blob (with a regen comment), don't generate at activation.** The 273-byte base64 blob is a Nix string with a comment documenting the Swift one-liner to regenerate. Avoids a hard Xcode-CLT dependency and per-apply `swift` cost; the NSFont archive format is stable. (Can't generate in a nix derivation — swift needs the macOS SDK, unavailable in the build sandbox.)
6. **Remove the stale iTerm block from `nix/darwin/defaults.nix`.** The firstrun slice's `CustomUserPreferences."com.googlecode.iterm2"` font keys are ignored cruft and now superseded.
7. **Profile: `default`, darwin-gated.** iTerm/Terminal are macOS GUI apps; the module is in the `default` (personal-macOS) profile, wrapped in `lib.mkIf pkgs.stdenv.isDarwin` so the `default@*-linux` matrix build is a no-op.
8. **Fonts only.** No colors/keybindings/other settings — the existing profiles keep everything else.
9. **No font installation.** The Nerd Font is already installed via the slice-10 cask; this slice only sets the per-profile font preference (no `pkgs.nerd-fonts.*`, no `fonts.fontconfig`).
10. **No work-specific values.** The blob is a non-sensitive NSFont archive (name + size).

## Architecture

```text
NEW FILES:
  nix/profiles/default/terminal-fonts.nix          # darwin-gated module: the patch activation + font/blob lets
  nix/profiles/default/patch-terminal-fonts.py     # plistlib patcher (iTerm Default/tmux + Terminal Homebrew)

MODIFIED FILES:
  nix/profiles/default/default.nix                 # imports ./terminal-fonts.nix
  nix/darwin/defaults.nix                          # remove stale CustomUserPreferences."com.googlecode.iterm2" block
  nix/README.md                                    # +migration guide sub-block

UNTOUCHED:
  font installation                                # already via the font-meslo-lg-nerd-font cask (slice 10)
  iTerm/Terminal profiles other than the font key  # patched in place, everything else preserved
  Default Bookmark Guid                            # existing Default profile stays the default
```

## `nix/profiles/default/terminal-fonts.nix` (full content)

```nix
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
  # Terminal.app's "Homebrew" profile in place. A Python plistlib
  # `defaults export -> modify -> defaults import` round-trip writes through
  # cfprefsd cleanly and matches profiles by name (order/count-independent).
  #
  # CONSTRAINT: iTerm and Terminal.app must be QUIT during ./apply — both
  # rewrite their prefs on quit and would otherwise revert these changes.
  # Idempotent: re-running sets the same values.
  home.activation.terminalFonts =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${pkgs.python3}/bin/python3 ${./patch-terminal-fonts.py} \
        ${lib.escapeShellArg font} ${lib.escapeShellArg terminalFontBlob} || true
    '';
}
```

## `nix/profiles/default/patch-terminal-fonts.py`

A small Python 3 patcher (full source in the file). It:
- Round-trips each domain via `defaults export` → `plistlib.load` → mutate → `plistlib.dump` → `defaults import`.
- **iTerm** (`com.googlecode.iterm2`): for every `New Bookmarks` profile whose `Name` is `"Default"` or `"tmux"`, sets `Normal Font` and `Non Ascii Font` to the font string.
- **Terminal** (`com.apple.Terminal`): sets `Window Settings → Homebrew → Font` to `base64.b64decode(blob)` (bytes → `<data>`), creating the key.
- Takes `<font>` and `<terminal-blob-base64>` as argv (passed from the module via `lib.escapeShellArg`).

## `nix/profiles/default/default.nix` change

Add `./terminal-fonts.nix` to imports (alphabetical, after `./cli-tools.nix`).

## `nix/darwin/defaults.nix` change

Remove the `# ----- iTerm 2 -----` block + the `"com.googlecode.iterm2" = { … };` entry under `CustomUserPreferences`. Leave all other domains intact.

## Migration guide block in `nix/README.md`

```markdown
For the nix-terminal-fonts slice (iTerm2 + Terminal.app Nerd Font, declarative):

Closes the terminal-font deferral. The nix-firstrun attempt wrote a top-level
`Normal Font` pref (ignored — the font lives per-profile) with a typo'd
PostScript name. This slice patches the font onto your EXISTING profiles in
place via a Python plistlib `defaults export → modify → import` round-trip
(`nix/profiles/default/patch-terminal-fonts.py`, run from a home-manager
activation):

- **iTerm2** — the `Default` and `tmux` profiles get `Normal Font` /
  `Non Ascii Font` set to `MesloLGSNF-Regular 14` ("MesloLGS Nerd Font").
- **Terminal.app** — the `Homebrew` profile's `Font` (a binary NSFont blob,
  generated once via Swift and stored with a regen comment) is set.

**CONSTRAINT: quit iTerm2 and Terminal.app before `./apply`.** Both rewrite
their prefs on quit, so a running app reverts the change. Relaunch them after
applying to see the font. The patch is idempotent.

**Changing the font:** edit `font` in `nix/profiles/default/terminal-fonts.nix`.
For Terminal.app, also regenerate the NSFont blob (the Swift one-liner is in the
file's comment). The font itself is installed by the `font-meslo-lg-nerd-font`
cask (nix-darwin slice), not here.

**Private flake update (only if you have one):** if your private flake also
patches these domains, be aware both run on activation; last writer wins per key.
```

## Testing

Verification performed (all passed):

1. Pre-apply: iTerm Default/tmux at `Monaco 20`; Terminal Homebrew had no `Font` key.
2. Eval gates: `home.activation.terminalFonts` references the patcher; no DynamicProfiles `home.file`; Python syntax valid; full home-manager build evals; `default@x86_64-linux` is a no-op (isDarwin guard).
3. After `./apply` (iTerm + Terminal quit):
   - iTerm `New Bookmarks` "Default" and "tmux" both → `Normal Font` / `Non Ascii Font` = `MesloLGSNF-Regular 14`. Exactly 2 such profiles (no leftover `(nix)` duplicates from the earlier dynamic-profile attempt).
   - Terminal `Window Settings.Homebrew.Font` present, 273 bytes, decodes to contain `MesloLGSNF-Regular`.
   - The old `~/Library/Application Support/iTerm2/DynamicProfiles/nix.json` symlink removed (orphan cleanup).
   - **Visual (user-confirmed):** glyphs render correctly in iTerm + Terminal.
4. Idempotence: re-running sets the same values (matched by name).

## Risk and rollback

**Risk:** Low. Each domain is round-tripped via `defaults export`/`import` (cfprefsd-safe). The patcher guards on export succeeding and on the expected structure existing before mutating, and only touches the font keys (iTerm) / the Homebrew Font key (Terminal). The clobber risk (running app reverts on quit) is mitigated by the quit-first constraint and idempotent re-apply.

**Rollback:** `git revert` the slice; re-`./apply` (the activation stops running). The last-set font persists until manually changed; reset the profile fonts by hand if reverting fully. No data loss — only font keys are touched.

## Out of scope

- Other iTerm/Terminal settings (colors, keybindings); other terminal emulators.
- Font installation (already via the cask).
- Full declarative iTerm config (the "custom prefs folder" / whole-plist approach) — would replace the user's entire config; this slice is font-only.

## Cross-references

- Master design: `docs/superpowers/specs/2026-05-22-nix-migration-design.md`
- nix-firstrun slice (the original font attempt): `docs/superpowers/specs/2026-05-26-nix-firstrun-design.md`
- Status doc (local, uncommitted): `docs/superpowers/nix-migration-status.md` — closes the reopened iTerm/Terminal font deferral
- Migration guide: `nix/README.md`
```
