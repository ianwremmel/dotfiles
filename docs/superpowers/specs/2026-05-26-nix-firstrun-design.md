# Nix Firstrun Slice Design

**Date:** 2026-05-26
**Status:** Draft — pending user approval
**Branch:** `nix-firstrun` (stacks on `nix-darwin` / PR #70 → `nix-homebrew` / PR #69 → `nix-nodejs` / PR #68 → `nix-prompt` / PR #67 → `nix-shells` / PR #66 → `nix-commit-signing` / PR #65 → `nix-git` / PR #64 → `nix-profiles` / PR #63 → `nix-cross-platform` / PR #62)

## Goal

Migrate `environments/all/firstrun` — a ~500-line bash script of `defaults write` calls, sudo system commands, and `defaults -currentHost` writes — into nix-darwin's declarative system layer. Retire `framework/firstrun` (the bash plugin loader) and `environments/all/firstrun` (the content) entirely. Scrub the now-vestigial `FIRSTRUN_APPLIED` key from existing `~/.dotfilesrc` files via a home-manager activation. Close deferral #4 by pinning iTerm's font preference declaratively. Strip three obsolete chunks (Dashboard pref, interactive `osascript` quit, the post-defaults `killall` block).

This slice closes two of the four open deferrals (#2 firstrun, #4 iTerm font) and matches the candidate "macOS `defaults` management" slice already called out in the status doc.

## Decisions (locked)

1. **Fully retire `framework/firstrun` and `environments/all/firstrun`.** Per the user: "fully retire it, assuming we have a replacement for every piece." Every line in the source script has a confirmed replacement (see Architecture → Mapping table). The bash loader, its registration in the framework, and the `FIRSTRUN_APPLIED` config key all go away.
2. **One file: `nix/darwin/defaults.nix`.** All `system.defaults.*`, `CustomUserPreferences`, and `system.activationScripts` content lives in a single file organized with comment headers matching the source script's section dividers (General UI/UX, Trackpad, Screen, Finder, Dock, Safari, Mail, Terminal, etc.). Mirrors slice 10's `nix/darwin/base.nix` "kitchen sink" pattern. Easier to scan against the legacy file during review.
3. **Native nix-darwin options first.** Every domain with a native nix-darwin module uses that module: `system.defaults.{NSGlobalDomain, dock, finder, screencapture, screensaver, menuExtraClock, ActivityMonitor, SoftwareUpdate, LaunchServices, trackpad}`. `time.timeZone = "America/Los_Angeles"` replaces `sudo systemsetup -settimezone`.
4. **`CustomUserPreferences` for domains without native options.** Safari (~20 keys), Mail, Messages, Chrome + Chrome Canary, TextEdit, DiskUtility, QuickTimePlayerX, addressbook, BluetoothAudioAgent, print.PrintingPrefs, terminal, TimeMachine, commerce, systempreferences, NetworkBrowser, Xcode. The PlistBuddy nested-dict Finder edits (`DesktopViewSettings.IconViewSettings.arrangeBy = "grid"`, `StandardViewSettings.IconViewSettings.arrangeBy = "grid"`) also go here as nested-dict CustomUserPreferences entries.
5. **`system.activationScripts` for non-`defaults` sudo commands.** `nvram SystemAudioVolume`, `pmset -a sms 0`, `pmset -b sleep -c sleep`, `pmset -b displaysleep -c displaysleep`, `systemsetup -setnetworktimeserver`, `systemsetup -setusingnetworktime on`, `chflags nohidden ~/Library`, `chflags nohidden /Volumes`, `lsregister -kill -r -domain ...`, the `-currentHost` write for `ImageCapture disableHotPlug`, and the `windowserver DisplayResolutionEnabled` system-level write. Activations run as root, so no sudo keep-alive loop is needed.
6. **Drop entirely (obsolete or redundant in nix-darwin context):**
   - `defaults write com.apple.dashboard mcx-disabled` — Dashboard was removed from macOS in 10.15 (2019). The setting is a no-op.
   - `osascript -e 'tell application "System Preferences" to quit'` — only useful when running interactively; `darwin-rebuild` activations don't conflict with a running Settings app the way an end-user firstrun script could.
   - The final `killall` block (Activity Monitor, Address Book, Calendar, cfprefsd, Contacts, Dock, Finder, Mail, Messages, Photos, Safari, SystemUIServer, iCal). nix-darwin already kicks `cfprefsd`, `Dock`, `SystemUIServer`, and `Finder` after defaults activations. The remaining apps (Safari, Mail, Messages, Photos, Activity Monitor, Address Book, Calendar, Contacts, iCal) pick up new prefs on next launch. Documented in the migration guide that a one-time relaunch may be needed for Mail/Safari/Messages on first apply.
7. **iTerm font selection (closes deferral #4).** `system.defaults.CustomUserPreferences."com.googlecode.iterm2"` pins the default-profile font. iTerm stores `Normal Font` in its plist; the implementation will commit to the working format during the plan phase (likely a `"MesloLGS-NF-Regular 14"` string, with a fallback strategy if iTerm requires binary NSFont encoding). If the simple form turns out not to work, the spec covers two fallback paths in the Open Question section; the plan picks the one that actually applies.
8. **Universal-only.** `nix/darwin/defaults.nix` is always included in `darwinConfigurations.<profile>@<system>` and applies to every darwin profile. The current firstrun lives in `environments/all/`, so universal scope is preserved. Per-profile override capability comes for free via Nix module merging if anyone ever needs it; not designed for upfront (YAGNI).
9. **`FIRSTRUN_APPLIED` scrubbed from `~/.dotfilesrc`.** A `home.activation.removeFirstrunAppliedKey` script in a new `nix/profiles/all/dotfilesrc-cleanup.nix` runs on every `home-manager switch`. If `~/.dotfilesrc` exists and contains `FIRSTRUN_APPLIED=`, strip the line in place. Idempotent: subsequent runs find no match and exit as a no-op. No backup file — the key is trivially recoverable if needed.
10. **No marker file for the defaults themselves.** `defaults write` is idempotent, so re-running on every `darwin-rebuild switch` is harmless and actively desired (reverts accidental prefs drift). The `system.activationScripts` blocks for `pmset`/`nvram`/`systemsetup`/`chflags` are also idempotent in practice.
11. **Migration guide block in `nix/README.md`.** Documents (a) the firstrun retirement, (b) that Mail/Safari/Messages may need a one-time relaunch on first apply, (c) iTerm font is now declarative, (d) the `FIRSTRUN_APPLIED` cleanup happens automatically. Follows the same "For the <slice> slice" sub-block pattern established by prior slices.
12. **No work-specific values added.** All firstrun content currently lives in `environments/all/` (universal). No private-flake darwin additions are required. The private-darwin migration remains its own future slice.

## Architecture

```text
NEW FILES:
  nix/darwin/defaults.nix                  # system.defaults + CustomUserPreferences + activationScripts
  nix/profiles/all/dotfilesrc-cleanup.nix  # home.activation that strips FIRSTRUN_APPLIED

MODIFIED FILES:
  nix/darwin/base.nix                      # imports ./defaults.nix
  nix/profiles/all/default.nix             # imports ./dotfilesrc-cleanup.nix (or equivalent)
  nix/README.md                            # +migration guide block for firstrun slice

DELETED:
  framework/firstrun                       # bash loader retired
  environments/all/firstrun                # content migrated

UNTOUCHED:
  framework/config                         # config_read/config_write still used by other plugins
  framework/dotfilesrc layout              # other keys (DOTFILES_ENVIRONMENT, etc.) untouched
  All other slices' nix files              # no cross-slice coupling
  custom_environments/                     # no private-side changes needed for this slice
```

### Mapping table — every line in `environments/all/firstrun` → its replacement

| Source line(s) | Destination | Notes |
| -------------- | ----------- | ----- |
| `sudo -v` + keep-alive loop | dropped | activations run as root non-interactively |
| `osascript -e 'tell System Preferences to quit'` | dropped | activations don't conflict with running Settings |
| `sudo nvram SystemAudioVolume=" "` | `system.activationScripts.disableBootChime` | not a defaults write |
| `defaults write com.apple.menuextra.battery` | `system.defaults.CustomUserPreferences."com.apple.menuextra.battery"` | no native module |
| `defaults write NSGlobalDomain NSWindowResizeTime` | `system.defaults.NSGlobalDomain.NSWindowResizeTime` | native |
| `defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode{,2}` | `system.defaults.NSGlobalDomain.NSNavPanelExpandedStateForSaveMode{,2}` | native |
| `defaults write NSGlobalDomain PMPrintingExpandedStateForPrint{,2}` | `system.defaults.NSGlobalDomain.PMPrintingExpandedStateForPrint{,2}` | native |
| `defaults write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud` | `system.defaults.NSGlobalDomain.NSDocumentSaveNewDocumentsToCloud` | native |
| `defaults write com.apple.print.PrintingPrefs "Quit When Finished"` | `CustomUserPreferences."com.apple.print.PrintingPrefs"."Quit When Finished"` | no native module |
| `lsregister -kill -r -domain ...` | `system.activationScripts.lsregisterReset` | LaunchServices cleanup |
| `defaults write com.apple.systempreferences NSQuitAlwaysKeepsWindows` | `CustomUserPreferences."com.apple.systempreferences".NSQuitAlwaysKeepsWindows` | no native module |
| `defaults write NSGlobalDomain NSDisableAutomaticTermination` | `system.defaults.NSGlobalDomain.NSDisableAutomaticTermination` | native |
| `defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled` | `system.defaults.NSGlobalDomain.NSAutomaticDashSubstitutionEnabled` | native |
| `defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled` | `system.defaults.NSGlobalDomain.NSAutomaticQuoteSubstitutionEnabled` | native |
| `defaults write NSGlobalDomain AppleInterfaceStyle Dark` | `system.defaults.NSGlobalDomain.AppleInterfaceStyle = "Dark"` | native |
| `sudo pmset -a sms 0` | `system.activationScripts.disableSMS` | pmset, not defaults |
| `defaults write NSGlobalDomain com.apple.swipescrolldirection` | `system.defaults.NSGlobalDomain."com.apple.swipescrolldirection"` | native |
| `defaults write com.apple.BluetoothAudioAgent "Apple Bitpool Min (editable)"` | `CustomUserPreferences."com.apple.BluetoothAudioAgent"` | no native module |
| `defaults write NSGlobalDomain AppleKeyboardUIMode` | `system.defaults.NSGlobalDomain.AppleKeyboardUIMode` | native |
| `sudo systemsetup -settimezone "America/Los_Angeles"` | `time.timeZone = "America/Los_Angeles"` | native nix-darwin top-level option |
| `sudo systemsetup -setnetworktimeserver "time.apple.com"` | `system.activationScripts.networkTimeServer` | no native nix-darwin option |
| `sudo systemsetup -setusingnetworktime on` | `system.activationScripts.networkTimeServer` | same script |
| `defaults write com.apple.screensaver askForPassword{,Delay}` | `system.defaults.screensaver.askForPassword{,Delay}` | native |
| `defaults -currentHost write com.apple.screensaver idleTime 0` | `system.defaults.screensaver.idleTime` OR `system.activationScripts.screensaverIdleTime` | see open question #4 — verify whether nix-darwin's screensaver module writes ByHost or NSGlobalDomain; fall back to activation if it doesn't cover `idleTime` |
| `sudo pmset -b sleep -c sleep` | `system.activationScripts.pmsetSleep` | pmset, not defaults |
| `sudo pmset -b displaysleep -c displaysleep` | `system.activationScripts.pmsetDisplaySleep` | pmset, not defaults |
| `defaults write com.apple.screencapture {location,type,disable-shadow}` | `system.defaults.screencapture.{location,type,disable-shadow}` | native |
| `defaults write NSGlobalDomain AppleFontSmoothing` | `system.defaults.NSGlobalDomain.AppleFontSmoothing` | native |
| `sudo defaults write /Library/Preferences/com.apple.windowserver DisplayResolutionEnabled` | `system.activationScripts.windowserverHiDPI` | system-level pref outside `system.defaults` scope |
| `defaults write com.apple.finder NewWindowTarget{,Path}` | `system.defaults.finder.NewWindowTarget{,Path}` | native (or via `_FXShowPosixPathInTitle`-style escape if not modeled) |
| `defaults write com.apple.finder Show{External,Mounted,Removable}*OnDesktop` | `system.defaults.finder.Show*OnDesktop` | native |
| `defaults write com.apple.finder SidebarZoneOrder1`, `ShowRecentTags`, `QLEnableTextSelection` | `CustomUserPreferences."com.apple.finder"` | not in native module |
| `defaults write com.apple.finder AppleShowAllFiles` | `system.defaults.finder.AppleShowAllFiles` | native |
| `defaults write com.apple.finder ShowStatusBar` | `system.defaults.finder.ShowStatusBar` | native |
| `defaults write com.apple.finder ShowPathbar` | `system.defaults.finder.ShowPathbar` | native |
| `defaults write NSGlobalDomain AppleShowAllExtensions` | `system.defaults.NSGlobalDomain.AppleShowAllExtensions` | native |
| `defaults write com.apple.finder _FXShowPosixPathInTitle` | `system.defaults.finder._FXShowPosixPathInTitle` | native |
| `defaults write com.apple.finder _FXSortFoldersFirst` | `system.defaults.finder._FXSortFoldersFirst` | native |
| `defaults write com.apple.finder FXDefaultSearchScope` | `system.defaults.finder.FXDefaultSearchScope` | native |
| `defaults write com.apple.finder FXEnableExtensionChangeWarning` | `system.defaults.finder.FXEnableExtensionChangeWarning` | native |
| `defaults write NSGlobalDomain com.apple.springing.{enabled,delay}` | `system.defaults.NSGlobalDomain."com.apple.springing.{enabled,delay}"` | native |
| `defaults write com.apple.desktopservices DSDontWrite{NetworkStores,USBStores}` | `system.defaults.LaunchServices` or `CustomUserPreferences."com.apple.desktopservices"` | depends on nix-darwin module coverage; verify in plan |
| PlistBuddy `DesktopViewSettings.IconViewSettings.arrangeBy = grid` | `CustomUserPreferences."com.apple.finder".DesktopViewSettings.IconViewSettings.arrangeBy = "grid"` | nested dict |
| PlistBuddy `StandardViewSettings.IconViewSettings.arrangeBy = grid` | `CustomUserPreferences."com.apple.finder".StandardViewSettings.IconViewSettings.arrangeBy = "grid"` | nested dict |
| `defaults write com.apple.finder FXPreferredViewStyle` | `system.defaults.finder.FXPreferredViewStyle` | native |
| `defaults write com.apple.NetworkBrowser BrowseAllInterfaces` | `CustomUserPreferences."com.apple.NetworkBrowser"` | no native module |
| `chflags nohidden ~/Library` | `system.activationScripts.unhideLibrary` | not a defaults write |
| `sudo chflags nohidden /Volumes` | `system.activationScripts.unhideVolumes` | not a defaults write |
| `defaults write com.apple.dock tilesize`, `mineffect`, `minimize-to-application`, `enable-spring-load-actions-on-all-items`, `show-process-indicators`, `persistent-apps`, `static-only`, `orientation`, `dashboard-in-overlay`, `mru-spaces`, `autohide-delay`, `autohide`, `showhidden`, `wvous-bl-corner`, `wvous-bl-modifier` | `system.defaults.dock.*` | all native |
| `defaults write com.apple.dashboard mcx-disabled` | dropped | Dashboard removed in macOS 10.15 |
| `defaults write com.apple.menuextra.clock DateFormat`, `FlashDateSeparators`, `IsAnalog` | `system.defaults.menuExtraClock.*` | native |
| `defaults write com.apple.Safari .*` (~20 keys) | `CustomUserPreferences."com.apple.Safari"` | no native module; all keys as one dict |
| `defaults write NSGlobalDomain WebKitDeveloperExtras` | `system.defaults.NSGlobalDomain.WebKitDeveloperExtras` | native |
| `defaults write com.apple.mail .*` | `CustomUserPreferences."com.apple.mail"` | no native module |
| `defaults write com.apple.terminal {StringEncodings,SecureKeyboardEntry}` | `CustomUserPreferences."com.apple.terminal"` | no native module |
| `defaults write com.apple.TimeMachine DoNotOfferNewDisksForBackup` | `CustomUserPreferences."com.apple.TimeMachine"` | no native module |
| `defaults write com.apple.ActivityMonitor {OpenMainWindow,IconType,ShowCategory,SortColumn,SortDirection}` | `system.defaults.ActivityMonitor.*` | native |
| `defaults write com.apple.addressbook {ABNameDisplay,ABNameSortingFormat}` | `CustomUserPreferences."com.apple.addressbook"` | no native module |
| `defaults write com.apple.TextEdit {RichText,PlainTextEncoding,PlainTextEncodingForWrite}` | `CustomUserPreferences."com.apple.TextEdit"` | no native module |
| `defaults write com.apple.DiskUtility {DUDebugMenuEnabled,advanced-image-options}` | `CustomUserPreferences."com.apple.DiskUtility"` | no native module |
| `defaults write com.apple.QuickTimePlayerX MGPlayMovieOnOpen` | `CustomUserPreferences."com.apple.QuickTimePlayerX"` | no native module |
| `defaults write com.apple.SoftwareUpdate {AutomaticCheckEnabled,ScheduleFrequency,AutomaticDownload,CriticalUpdateInstall,ConfigDataInstall}` | `system.defaults.SoftwareUpdate.*` | native |
| `defaults write com.apple.commerce AutoUpdate` | `CustomUserPreferences."com.apple.commerce"` | no native module |
| `defaults -currentHost write com.apple.ImageCapture disableHotPlug` | `system.activationScripts.imageCaptureDisableHotPlug` | `-currentHost` writes go to ByHost; native module doesn't cover this |
| `defaults write com.apple.messageshelper.MessageController SOInputLineSettings -dict-add ...` | `CustomUserPreferences."com.apple.messageshelper.MessageController".SOInputLineSettings` (full dict) | overwriting the full dict is acceptable since we only care about those two keys |
| `defaults write com.google.Chrome[.canary] .*` | `CustomUserPreferences."com.google.Chrome"` and `"com.google.Chrome.canary"` | no native module |
| `defaults write com.apple.dt.Xcode.plist DVTTextTabKeyIndentBehavior` | `CustomUserPreferences."com.apple.dt.Xcode".DVTTextTabKeyIndentBehavior` | no native module |
| iTerm font (NEW — closes deferral #4) | `CustomUserPreferences."com.googlecode.iterm2"` | scope addition for this slice |
| `killall` block at end | dropped | nix-darwin already kicks cfprefsd/Dock/SystemUIServer/Finder; remaining apps pick up prefs on next launch |
| `framework/firstrun` loader | deleted | bash plugin retirement |
| `FIRSTRUN_APPLIED` config key | scrubbed from `~/.dotfilesrc` via `home.activation` | new cleanup script |

## Activation script contents

Each entry below becomes a single `system.activationScripts.<name>.text` block in `nix/darwin/defaults.nix`. All run as root during `darwin-rebuild switch`.

```nix
disableBootChime.text         = "/usr/sbin/nvram SystemAudioVolume=' '";
disableSMS.text               = "/usr/bin/pmset -a sms 0";
pmsetSleep.text               = "/usr/bin/pmset -b sleep 15 -c sleep 15";
pmsetDisplaySleep.text        = "/usr/bin/pmset -b displaysleep 5 -c displaysleep 15";
networkTimeServer.text        = ''
  /usr/sbin/systemsetup -setnetworktimeserver "time.apple.com" > /dev/null
  /usr/sbin/systemsetup -setusingnetworktime on > /dev/null
'';
unhideLibrary.text            = "/usr/bin/sudo -u ${user} /usr/bin/chflags nohidden /Users/${user}/Library";
unhideVolumes.text            = "/usr/bin/chflags nohidden /Volumes";
lsregisterReset.text          = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user";
windowserverHiDPI.text        = "/usr/bin/defaults write /Library/Preferences/com.apple.windowserver DisplayResolutionEnabled -bool true";
imageCaptureDisableHotPlug.text = "/usr/bin/sudo -u ${user} /usr/bin/defaults -currentHost write com.apple.ImageCapture disableHotPlug -bool true";
```

`${user}` is templated from `nix-darwin`'s `users.users.<name>` — typically `ian` for the `default` profile.

## Home-manager activation: `FIRSTRUN_APPLIED` scrub

In `nix/profiles/all/dotfilesrc-cleanup.nix`:

```nix
{ lib, ... }:
{
  home.activation.removeFirstrunAppliedKey =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ -f "$HOME/.dotfilesrc" ] && /usr/bin/grep -q '^FIRSTRUN_APPLIED=' "$HOME/.dotfilesrc"; then
        /usr/bin/grep -v '^FIRSTRUN_APPLIED=' "$HOME/.dotfilesrc" > "$HOME/.dotfilesrc.tmp"
        /bin/mv "$HOME/.dotfilesrc.tmp" "$HOME/.dotfilesrc"
        /bin/chmod 0600 "$HOME/.dotfilesrc"
      fi
    '';
}
```

Idempotent: the `grep -q` check exits early if the key isn't present. No backup file (per user direction).

## `nix/darwin/base.nix` change

Add the import:

```nix
imports = [
  ./defaults.nix
  # ... existing imports
];
```

## `nix/profiles/all/default.nix` (or equivalent all-profile aggregator) change

Add the import:

```nix
imports = [
  ./dotfilesrc-cleanup.nix
  # ... existing imports
];
```

Exact path/name verified during the plan phase against the current shape of slice 3's profile aggregator.

## Framework + content deletions

- Delete `framework/firstrun`.
- Delete the registration of `firstrun_main` from wherever the framework's main loop dispatches it (likely `apply` or `framework/framework`).
- Delete `environments/all/firstrun`.

The `FIRSTRUN_APPLIED` config key has no other readers/writers in the codebase (verified during the brainstorm: only `framework/firstrun` itself touches it), so no other code changes are required to remove it.

## Migration guide block in `nix/README.md`

Append a "For the nix-firstrun slice" sub-block:

````markdown
### For the nix-firstrun slice

This slice migrates `environments/all/firstrun` (the macOS preferences script) into
nix-darwin's declarative system layer.

**One-time apply notes:**

- Mail, Safari, Messages, Photos, Activity Monitor, Address Book, Calendar,
  Contacts, and iCal may need a one-time relaunch after this slice's first
  `./apply` for their new preferences to take effect. nix-darwin already
  kicks `cfprefsd`, `Dock`, `SystemUIServer`, and `Finder` automatically.

- The `FIRSTRUN_APPLIED=1` entry in your `~/.dotfilesrc` is now vestigial and
  is automatically removed by the home-manager activation. The rest of your
  config file is untouched.

- iTerm's font (Nerd Font, set up in the nix-darwin slice's cask install) is
  now pinned declaratively. If iTerm's font preference reverts to a default
  after this slice, the activation will re-set it on next `./apply`.

**Private flake update (only if you have one):**

If your private flake extends `darwinConfigurations` with additional
`system.defaults.*` or `CustomUserPreferences` entries, no changes are
required — Nix module merging handles additive private prefs on top of the
public baseline. If your private flake conflicts with a key set in the
public `nix/darwin/defaults.nix`, override it explicitly with `lib.mkForce`
in the private module.
````

## Open questions resolved during plan / implementation

These are surfaced now so the plan and implementation know to verify, but they don't gate spec approval:

1. **iTerm font format.** The first attempt uses `CustomUserPreferences."com.googlecode.iterm2"."Normal Font" = "MesloLGS-NF-Regular 14";`. If iTerm reads the string and applies the font on next launch, ship it. If iTerm ignores the key (because it expects a binary-archived NSFont), the fallback is an activation script that runs `defaults write com.googlecode.iterm2 "Normal Font" -data <hex>` with a captured-from-a-working-machine value. The plan decides which path applies after a 15-minute spike on a clean iTerm prefs file.
2. **`desktopservices DSDontWrite{NetworkStores,USBStores}`.** Likely under nix-darwin's `system.defaults.LaunchServices` or `system.defaults.NSGlobalDomain`; if neither covers it, falls back to `CustomUserPreferences."com.apple.desktopservices"`. Decided during plan-phase verification against the current nix-darwin docs.
3. **`finder.NewWindowTargetPath` with `$HOME` interpolation.** The source uses `file://$HOME/`. In Nix, this is `"file://${config.home.homeDirectory}/"` if home-manager exposes it at the system level, otherwise a hardcoded `"file:///Users/${user}/"`. The plan decides based on the simplest workable form.
4. **`screensaver idleTime 0` via `-currentHost`.** The source writes to `~/Library/Preferences/ByHost/com.apple.screensaver.<UUID>.plist`. nix-darwin's `system.defaults.screensaver` may or may not target ByHost depending on version. The plan verifies on the current nix-darwin pin; if `idleTime` isn't covered or writes to the wrong path, falls back to a `system.activationScripts.screensaverIdleTime` that drops to the user and runs `defaults -currentHost write`. The `askForPassword{,Delay}` keys (which the source writes WITHOUT `-currentHost`) stay on the native module regardless.

## Testing approach

This slice has no automated tests (per `CLAUDE.md`: "No automated tests. Manual testing via `./apply`."). The implementation plan will include a verification checklist:

1. **Pre-apply snapshot.** Capture `defaults read` for each affected domain on the current machine — `defaults read NSGlobalDomain`, `defaults read com.apple.dock`, etc. — to a tmp file. Used as the diff baseline.
2. **Apply the slice.** Run `./apply` on a machine where the legacy `FIRSTRUN_APPLIED=1` is already set, then on a fresh shell to confirm `darwin-rebuild switch` ran the new activations.
3. **Verify settings landed.** Re-run `defaults read` for each domain; diff against pre-apply. Every key in the firstrun source should now have the expected value.
4. **Verify `FIRSTRUN_APPLIED` is gone.** `grep FIRSTRUN_APPLIED ~/.dotfilesrc` returns nothing. Other config keys still present.
5. **Verify no `framework/firstrun` execution.** `DOTFILES_DEBUG=1 ./apply 2>&1 | grep -i firstrun` returns nothing.
6. **iTerm font check.** Quit and relaunch iTerm; default profile uses the Nerd Font (starship branch glyph renders correctly).
7. **Manual relaunch verification.** Quit and reopen Mail/Safari/Messages once; confirm their new prefs took effect (e.g., Safari's developer menu, Mail's animations disabled).
8. **Idempotence check.** `./apply` a second time; no errors, `~/.dotfilesrc` unchanged on second run (no duplicate edits), no unexpected diffs in `defaults read`.

## Risk and rollback

**Risk:** A `CustomUserPreferences` typo silently writes nonsense to a system pref domain, or a native `system.defaults.*` option's name changed between nix-darwin versions. The blast radius is bounded — every change is a `defaults write`, reversible by `defaults delete`.

**Rollback:** If the slice breaks an app's preferences in a way the user notices:

1. `git revert` the slice's commits and re-`./apply` — the previous nix-darwin state takes over.
2. The deleted `environments/all/firstrun` and `framework/firstrun` are recoverable from `git show`.
3. The `FIRSTRUN_APPLIED=1` entry is trivially re-addable with `echo 'FIRSTRUN_APPLIED=1' >> ~/.dotfilesrc`.

No data loss is possible — every operation is either a preference write or a one-line config edit.

## Out of scope

- **Private-darwin migration.** Deferred to its own future slice (the "recommended next" candidate flagged in the status doc that we explicitly chose to defer in favor of this one).
- **macOS `system.defaults.CustomSystemPreferences` audit beyond what firstrun touches.** Other system-wide prefs the user might want to manage declaratively (e.g., FileVault, firewall, sharing) are out of scope.
- **`vim`, `vscode`, `homedir`, `claude` bash-plugin retirements.** Future slices.
- **iTerm dynamic profile management** beyond the font preference. iTerm's full prefs (color schemes, keybindings, window arrangements) are still managed manually.

## Cross-references

- Master design: `docs/superpowers/specs/2026-05-22-nix-migration-design.md`
- Prior slice (nix-darwin): `docs/superpowers/specs/2026-05-26-nix-darwin-design.md` (defers firstrun explicitly in decision #11)
- Status log: `docs/superpowers/nix-migration-status.md` (deferral #2 firstrun, deferral #4 iTerm font, candidate "macOS `defaults` management" slice)
- Migration guide: `nix/README.md` (will gain a new "For the nix-firstrun slice" sub-block in this slice)
