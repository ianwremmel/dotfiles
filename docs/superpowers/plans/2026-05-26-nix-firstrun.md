# Nix Firstrun Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate `environments/all/firstrun` (a ~500-line bash script of macOS `defaults write` + sudo commands) into nix-darwin's declarative system layer via a new `nix/darwin/defaults.nix`. Retire `framework/firstrun` and `environments/all/firstrun`. Strip `FIRSTRUN_APPLIED` from `~/.dotfilesrc` via a home-manager activation. Close deferral #4 by pinning iTerm's font declaratively.

**Architecture:** Single atomic feat commit creates `nix/darwin/defaults.nix` and `nix/profiles/all/dotfilesrc-cleanup.nix`, modifies `nix/darwin/base.nix` (adds `imports = [ ./defaults.nix ]`), modifies `nix/profiles/all/default.nix` (adds `./dotfilesrc-cleanup.nix` to imports), modifies `framework/framework` (drops the `firstrun` source line and the `firstrun_main` call), and deletes `framework/firstrun` + `environments/all/firstrun`. A second commit updates `nix/README.md` with the slice's migration guide sub-block. A third task is verification-only.

**Tech Stack:** Nix flakes, nix-darwin (`nix-darwin-26.05`), home-manager (`release-26.05`), Bash 5, macOS `defaults` / `pmset` / `systemsetup` / `nvram` / `chflags` / `lsregister`.

---

## Notes for the executor

- **Reference spec:** `docs/superpowers/specs/2026-05-26-nix-firstrun-design.md`. Read it first; the spec's mapping table is the authoritative source of truth for which firstrun line goes where.
- **No automated test framework.** "Tests" are verification commands with expected output, captured in Task 3.
- **Branch:** `nix-firstrun`. Stacks on `nix-darwin` (PR #70) → `nix-homebrew` (PR #69) → … → master. **Do NOT merge anything.**
- **Stacking machinery** (assumed working from prior slices): `homeModules.{all,default,agent}`, `darwinModules.{base,default}`, `lib.mkHome`, `lib.mkDarwin`, `darwinConfigurations.<profile>@<system>`, `nix/host.nix` (untracked) with `{ username; profile; }`.
- **Sandbox disable required for:** `nix`, `./apply`, `git commit` (gpg signing), `darwin-rebuild`, `sudo …`, anything writing to `~/.dotfilesrc`, `/Library/Preferences/`, or `/etc/`. Use `dangerouslyDisableSandbox: true`. If `nix` isn't on PATH, prepend `source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh`.
- **Run commands from repo root** (`/Users/ian/projects/dotfiles`).
- **Pre-existing local state assumed:**
  - `nix/host.nix` = `{ username = "ian"; profile = "default"; }`, untracked.
  - `~/.dotfilesrc` contains `DOTFILES_ENVIRONMENT=default` and `FIRSTRUN_APPLIED=1` (set by historical firstrun runs).
  - `darwin-rebuild` already installed (slice 10).
  - Login shell is `~/.nix-profile/bin/zsh` (slice 6 + slice 10).
  - The current macOS preferences match what `environments/all/firstrun` would have set (the script ran historically; settings are already in place).
- **Conventional commits**, NO `Co-Authored-By: Claude` / `Generated with Claude Code` trailers.
- **No work-specific values.** All firstrun content lives in `environments/all/` (universal); no private-flake additions needed for this slice.
- **Fallback strategy for open questions** (from the spec):
  - **iTerm font:** Step 4's `defaults.nix` includes the string-form `Normal Font` entry. If iTerm ignores it (verified manually after Task 1's `./apply`), Task 3 documents a follow-up — do NOT block Task 1 on this.
  - **`desktopservices DSDontWriteNetworkStores`/`DSDontWriteUSBStores`:** Task 1 routes these through `CustomUserPreferences."com.apple.desktopservices"`. If nix-darwin emits a deprecation warning saying these should go through `system.defaults.LaunchServices` instead, swap during the same task (cheap fix).
  - **`finder.NewWindowTargetPath`:** Task 1 uses a hardcoded `"file:///Users/${username}/"` (where `${username}` is the Nix interpolation, not shell). Simplest workable form.
  - **`screensaver idleTime` via `-currentHost`:** Task 1 attempts `system.defaults.screensaver.idleTime = 0;`. If `nix eval` rejects the option name, swap to an activation-script fallback in the same step (the spec describes both paths).
- **`framework/customize` and `framework/compat`** are untouched. The `FIRSTRUN_APPLIED` key has no other readers/writers in the codebase (`grep -rn FIRSTRUN_APPLIED` returns only `framework/firstrun:6` and `framework/firstrun:27`).

---

## Task 1: Atomic firstrun migration

Every code change in one commit so the repo never sits in a half-migrated state where (e.g.) `framework/firstrun` has been deleted but the nix-darwin defaults haven't been wired up.

**Files:**

- Create: `nix/darwin/defaults.nix`
- Create: `nix/profiles/all/dotfilesrc-cleanup.nix`
- Modify: `nix/darwin/base.nix` (add `imports = [ ./defaults.nix ];`)
- Modify: `nix/profiles/all/default.nix` (add `./dotfilesrc-cleanup.nix` to imports list)
- Modify: `framework/framework` (delete `source ./framework/firstrun` and `firstrun_main` call)
- Delete: `framework/firstrun`
- Delete: `environments/all/firstrun`

### Step-by-step

- [ ] **Step 1: Capture pre-flight state**

```bash
echo "=== current FIRSTRUN_APPLIED state ==="
grep -E '^FIRSTRUN_APPLIED=' "$HOME/.dotfilesrc" 2>&1 || echo "(absent)"
echo ""
echo "=== ~/.dotfilesrc full content ==="
cat "$HOME/.dotfilesrc"
echo ""
echo "=== sample of current defaults (the few easiest to spot-check) ==="
defaults read NSGlobalDomain AppleInterfaceStyle 2>&1 || echo "(unset)"
defaults read com.apple.dock orientation 2>&1 || echo "(unset)"
defaults read com.apple.finder _FXShowPosixPathInTitle 2>&1 || echo "(unset)"
defaults read com.apple.screencapture location 2>&1 || echo "(unset)"
echo ""
echo "=== time zone ==="
sudo systemsetup -gettimezone 2>&1 | head -2
echo ""
echo "=== darwin-rebuild present? ==="
command -v darwin-rebuild 2>&1
echo ""
echo "=== framework/firstrun and environments/all/firstrun ==="
ls -la framework/firstrun environments/all/firstrun 2>&1
```

Save the output. Step 18's verification compares against it.

- [ ] **Step 2: Confirm starting file state**

```bash
ls framework/firstrun environments/all/firstrun nix/darwin/base.nix nix/profiles/all/default.nix
grep -n "firstrun" framework/framework
grep -rn FIRSTRUN_APPLIED framework/ environments/ plugins/ | head -10
```

Expected:
- All four paths exist.
- `framework/framework:12: source ./framework/firstrun`
- `framework/framework:29:   firstrun_main`
- `FIRSTRUN_APPLIED` appears ONLY in `framework/firstrun:6` and `framework/firstrun:27`.

If `FIRSTRUN_APPLIED` appears anywhere else, stop and re-read the spec — the cleanup activation is only safe if the key has no other readers/writers.

- [ ] **Step 3: Create `nix/darwin/defaults.nix`**

```nix
{ pkgs, username, ... }: {

  ###############################################################################
  # Time zone                                                                   #
  ###############################################################################

  time.timeZone = "America/Los_Angeles";

  ###############################################################################
  # Native system.defaults options                                              #
  ###############################################################################

  system.defaults = {

    # ----- NSGlobalDomain (cross-cutting UI/behavior settings) -----
    NSGlobalDomain = {
      NSWindowResizeTime                    = 0.001;
      NSNavPanelExpandedStateForSaveMode    = true;
      NSNavPanelExpandedStateForSaveMode2   = true;
      PMPrintingExpandedStateForPrint       = true;
      PMPrintingExpandedStateForPrint2      = true;
      NSDocumentSaveNewDocumentsToCloud     = false;
      NSDisableAutomaticTermination         = true;
      NSAutomaticDashSubstitutionEnabled    = false;
      NSAutomaticQuoteSubstitutionEnabled   = false;
      AppleInterfaceStyle                   = "Dark";
      "com.apple.swipescrolldirection"      = false;
      AppleKeyboardUIMode                   = 3;
      AppleFontSmoothing                    = 2;
      AppleShowAllExtensions                = true;
      AppleShowAllFiles                     = true;
      WebKitDeveloperExtras                 = true;
      "com.apple.springing.enabled"         = true;
      "com.apple.springing.delay"           = 0.0;
    };

    # ----- Finder -----
    finder = {
      NewWindowTarget                  = "Other";
      ShowExternalHardDrivesOnDesktop  = true;
      ShowMountedServersOnDesktop      = true;
      ShowRemovableMediaOnDesktop      = true;
      AppleShowAllFiles                = true;
      ShowStatusBar                    = true;
      ShowPathbar                      = true;
      _FXShowPosixPathInTitle          = true;
      _FXSortFoldersFirst              = true;
      FXDefaultSearchScope             = "SCcf";
      FXEnableExtensionChangeWarning   = false;
      FXPreferredViewStyle             = "Nlsv";
    };

    # ----- Dock -----
    dock = {
      tilesize                                = 36;
      mineffect                               = "scale";
      minimize-to-application                 = false;
      enable-spring-load-actions-on-all-items = true;
      show-process-indicators                 = true;
      persistent-apps                         = [];
      static-only                             = true;
      orientation                             = "left";
      dashboard-in-overlay                    = true;
      mru-spaces                              = false;
      autohide-delay                          = 0.0;
      autohide                                = false;
      showhidden                              = true;
      wvous-bl-corner                         = 0;
      wvous-bl-modifier                       = 0;
    };

    # ----- Screencapture -----
    screencapture = {
      location       = "/Users/${username}/Downloads";
      type           = "png";
      disable-shadow = true;
    };

    # ----- Screensaver -----
    # askForPassword{,Delay} go to the standard plist.
    # idleTime is a `-currentHost` write; nix-darwin's screensaver module is
    # expected to handle ByHost. If `nix eval` rejects `idleTime`, drop the
    # line and add a `screensaverIdleTime` activation script below — see the
    # spec's open question #4.
    screensaver = {
      askForPassword      = true;
      askForPasswordDelay = 5;
      idleTime            = 0;
    };

    # ----- Activity Monitor -----
    ActivityMonitor = {
      OpenMainWindow = true;
      IconType       = 5;
      ShowCategory   = 0;
      SortColumn     = "CPUUsage";
      SortDirection  = 0;
    };

    # ----- Software Update -----
    SoftwareUpdate = {
      AutomaticCheckEnabled = true;
      AutomaticDownload     = 1;
      ConfigDataInstall     = 1;
      CriticalUpdateInstall = 1;
      ScheduleFrequency     = 1;
    };

    # ----- Menu bar clock -----
    menuExtraClock = {
      IsAnalog            = false;
      FlashDateSeparators = false;
      # DateFormat is provided via CustomUserPreferences below — nix-darwin's
      # menuExtraClock module does not expose a free-form DateFormat option.
    };

    ###############################################################################
    # CustomUserPreferences: escape hatch for non-native domains                  #
    ###############################################################################

    CustomUserPreferences = {

      # ----- Battery percentage in menu bar -----
      "com.apple.menuextra.battery" = {
        ShowPercent = "YES";
      };

      # ----- Menu bar clock free-form date format -----
      "com.apple.menuextra.clock" = {
        DateFormat = "EEE MMM d  h:mm a";
      };

      # ----- Print preference "quit when finished" -----
      "com.apple.print.PrintingPrefs" = {
        "Quit When Finished" = true;
      };

      # ----- System preferences resume behavior -----
      "com.apple.systempreferences" = {
        NSQuitAlwaysKeepsWindows = false;
      };

      # ----- Bluetooth audio quality -----
      "com.apple.BluetoothAudioAgent" = {
        "Apple Bitpool Min (editable)" = 40;
      };

      # ----- Finder window target (file URL form) + sidebar/ql -----
      "com.apple.finder" = {
        NewWindowTargetPath = "file:///Users/${username}/";
        SidebarZoneOrder1   = [ "favorites" "devices" "shared" ];
        ShowRecentTags      = false;
        QLEnableTextSelection = true;
        DesktopViewSettings.IconViewSettings.arrangeBy = "grid";
        StandardViewSettings.IconViewSettings.arrangeBy = "grid";
      };

      # ----- Desktop services (DS_Store suppression) -----
      "com.apple.desktopservices" = {
        DSDontWriteNetworkStores = true;
        DSDontWriteUSBStores     = true;
      };

      # ----- Network browser -----
      "com.apple.NetworkBrowser" = {
        BrowseAllInterfaces = true;
      };

      # ----- Safari (~20 keys) -----
      "com.apple.Safari" = {
        UniversalSearchEnabled                                          = false;
        SuppressSearchSuggestions                                       = true;
        WebKitTabToLinksPreferenceKey                                   = true;
        "com.apple.Safari.ContentPageGroupIdentifier.WebKit2TabsToLinks" = true;
        ShowFullURLInSmartSearchField                                   = true;
        HomePage                                                        = "about:blank";
        AutoOpenSafeDownloads                                           = false;
        "com.apple.Safari.ContentPageGroupIdentifier.WebKit2BackspaceKeyNavigationEnabled" = true;
        ShowFavoritesBar                                                = false;
        ShowSidebarInTopSites                                           = false;
        DebugSnapshotsUpdatePolicy                                      = 2;
        IncludeInternalDebugMenu                                        = true;
        FindOnPageMatchesWordStartsOnly                                 = false;
        ProxiesInBookmarksBar                                           = [];
        IncludeDevelopMenu                                              = true;
        WebKitDeveloperExtrasEnabledPreferenceKey                       = true;
        "com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled" = true;
        WebContinuousSpellCheckingEnabled                               = true;
        WebAutomaticSpellingCorrectionEnabled                           = false;
        AutoFillFromAddressBook                                         = false;
        AutoFillPasswords                                               = false;
        AutoFillCreditCardData                                          = false;
        AutoFillMiscellaneousForms                                      = false;
        WarnAboutFraudulentWebsites                                     = true;
        SendDoNotTrackHTTPHeader                                        = true;
        InstallExtensionUpdatesAutomatically                            = true;
      };

      # ----- Mail -----
      "com.apple.mail" = {
        DisableReplyAnimations             = true;
        DisableSendAnimations              = true;
        AddressesIncludeNameOnPasteboard   = false;
        DisableInlineAttachmentViewing     = true;
      };

      # ----- Terminal -----
      "com.apple.terminal" = {
        StringEncodings     = [ 4 ];
        SecureKeyboardEntry = true;
      };

      # ----- Time Machine -----
      "com.apple.TimeMachine" = {
        DoNotOfferNewDisksForBackup = true;
      };

      # ----- Address Book -----
      "com.apple.addressbook" = {
        ABNameDisplay        = 1;
        ABNameSortingFormat  = "sortingLastName sortingFirstName";
      };

      # ----- TextEdit -----
      "com.apple.TextEdit" = {
        RichText                  = 0;
        PlainTextEncoding         = 4;
        PlainTextEncodingForWrite = 4;
      };

      # ----- Disk Utility -----
      "com.apple.DiskUtility" = {
        DUDebugMenuEnabled     = true;
        advanced-image-options = true;
      };

      # ----- QuickTime Player -----
      "com.apple.QuickTimePlayerX" = {
        MGPlayMovieOnOpen = true;
      };

      # ----- Image Capture (suppress hot-plug auto-open) -----
      # NOTE: the source uses `defaults -currentHost write`, which targets
      # ~/Library/Preferences/ByHost/. CustomUserPreferences writes to the
      # standard path. If post-apply verification shows ImageCapture still
      # opens on device plug-in, move this line to an activation script
      # using `defaults -currentHost write` instead (see Step 4 below; the
      # `firstrunUserCommands` activation already drops to the user for
      # this purpose).
      "com.apple.ImageCapture" = {
        disableHotPlug = true;
      };

      # ----- App Store auto-update -----
      "com.apple.commerce" = {
        AutoUpdate = true;
      };

      # ----- Photos -----
      "com.apple.ImageCapture2" = { };  # placeholder; the Photos auto-open
                                        # suppression is via ImageCapture above

      # ----- Messages (overwrite the full dict; we only care about these keys) -----
      "com.apple.messageshelper.MessageController" = {
        SOInputLineSettings = {
          automaticEmojiSubstitutionEnablediMessage = false;
          automaticQuoteSubstitutionEnabled         = false;
        };
      };

      # ----- Chrome (and Canary) -----
      "com.google.Chrome" = {
        AppleEnableSwipeNavigateWithScrolls       = false;
        AppleEnableMouseSwipeNavigateWithScrolls  = false;
        DisablePrintPreview                       = true;
        PMPrintingExpandedStateForPrint2          = true;
      };

      "com.google.Chrome.canary" = {
        AppleEnableSwipeNavigateWithScrolls       = false;
        AppleEnableMouseSwipeNavigateWithScrolls  = false;
        DisablePrintPreview                       = true;
        PMPrintingExpandedStateForPrint2          = true;
      };

      # ----- Xcode -----
      "com.apple.dt.Xcode" = {
        DVTTextTabKeyIndentBehavior = "Always";
      };

      # ----- iTerm 2 (closes deferral #4) -----
      # Pin the Nerd Font for the default profile so starship's git-branch
      # glyph renders. iTerm reads `Normal Font` on launch. If verification
      # shows iTerm ignored this entry (because it expects a binary-encoded
      # NSFont in its plist), document a follow-up — do not block this slice.
      "com.googlecode.iterm2" = {
        "Normal Font"        = "MesloLGS-NF-Regular 14";
        "Non Ascii Font"     = "MesloLGS-NF-Regular 14";
        "Use Non-ASCII Font" = false;
      };
    };
  };

  ###############################################################################
  # Activation scripts: commands that aren't `defaults write`                   #
  ###############################################################################

  # Root-only commands (chflags /Volumes, pmset, systemsetup, nvram, lsregister,
  # system-level defaults). Runs as root during `darwin-rebuild switch`.
  system.activationScripts.firstrunSudoCommands.text = ''
    # Disable boot chime
    /usr/sbin/nvram SystemAudioVolume=" "

    # Disable sudden motion sensor (irrelevant on SSDs)
    /usr/bin/pmset -a sms 0

    # Sleep timings
    /usr/bin/pmset -b sleep 15 -c sleep 15
    /usr/bin/pmset -b displaysleep 5 -c displaysleep 15

    # Network time
    /usr/sbin/systemsetup -setnetworktimeserver "time.apple.com" > /dev/null
    /usr/sbin/systemsetup -setusingnetworktime on > /dev/null

    # Show /Volumes
    /usr/bin/chflags nohidden /Volumes

    # Reset LaunchServices to clear "Open With" duplicates (one-time effect;
    # cheap to re-run)
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
      -kill -r -domain local -domain system -domain user

    # HiDPI display modes (system-level pref outside `system.defaults` scope)
    /usr/bin/defaults write /Library/Preferences/com.apple.windowserver \
      DisplayResolutionEnabled -bool true
  '';

  # User-scoped commands that root needs to drop into the user context for.
  # ~/Library unhide and -currentHost writes both target the user's home.
  system.activationScripts.firstrunUserCommands.text = ''
    /usr/bin/sudo -u ${username} /usr/bin/chflags nohidden /Users/${username}/Library
  '';
}
```

Notes on what this excludes (per the spec's "drop entirely" list):
- No `defaults write com.apple.dashboard mcx-disabled` (Dashboard removed in 10.15).
- No `osascript -e 'tell System Preferences to quit'` (activations don't conflict with running Settings).
- No `killall` block at the end (nix-darwin's activation already kicks `cfprefsd`, `Dock`, `SystemUIServer`, `Finder`; the rest pick up new prefs on next launch).
- No `sudo -v` keep-alive loop (activations run as root non-interactively).

- [ ] **Step 4: Create `nix/profiles/all/dotfilesrc-cleanup.nix`**

```nix
{ lib, ... }: {
  # Scrub the now-vestigial FIRSTRUN_APPLIED key from ~/.dotfilesrc.
  # The framework/firstrun bash plugin (which set this key) was removed in
  # the same commit that introduces this file. Idempotent: if the key is
  # already absent, the activation is a no-op. No backup file is written.
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

- [ ] **Step 5: Add `./defaults.nix` to `nix/darwin/base.nix` imports**

`nix/darwin/base.nix` currently has no `imports` block. Add one at the top of the attrset body:

```nix
{ pkgs, username, ... }: {
  imports = [ ./defaults.nix ];

  # System state version — pins nix-darwin's behavior. Never bump casually.
  system.stateVersion = 5;
  # ... (rest of file unchanged)
```

Use Edit to insert the `imports = [ ./defaults.nix ];` line immediately after `{ pkgs, username, ... }: {` and before `# System state version`. Do NOT touch anything else in this file.

- [ ] **Step 6: Add `./dotfilesrc-cleanup.nix` to `nix/profiles/all/default.nix` imports**

Current file (4 imports):

```nix
{ ... }: {
  imports = [
    ./cli-tools.nix
    ./git.nix
    ./gpg.nix
    ./shells.nix
  ];
}
```

Add `./dotfilesrc-cleanup.nix` to the list (alphabetical placement before `./git.nix`):

```nix
{ ... }: {
  imports = [
    ./cli-tools.nix
    ./dotfilesrc-cleanup.nix
    ./git.nix
    ./gpg.nix
    ./shells.nix
  ];
}
```

- [ ] **Step 7: Strip firstrun from `framework/framework`**

Current file has two firstrun lines:
- Line 12: `source ./framework/firstrun`
- Line 29: `  firstrun_main`

Delete both. The resulting file (verify after edit):

```bash
diff <(grep -c firstrun framework/framework) <(echo 0)
```

Expected: empty diff (no `firstrun` references remain).

- [ ] **Step 8: Delete `framework/firstrun` and `environments/all/firstrun`**

```bash
git rm framework/firstrun environments/all/firstrun
```

- [ ] **Step 9: Evaluate the flake (catch syntax / option-name errors before applying)**

```bash
SYSTEM="$(nix eval --raw --impure --expr builtins.currentSystem)"
nix flake check --no-build --override-input public path:"$PWD/nix" path:"$PWD/nix" 2>&1 | tail -40
nix eval ".#darwinConfigurations.default@${SYSTEM}.config.system.build.toplevel.drvPath" --override-input public path:"$PWD/nix" 2>&1 | tail -5
```

(Adjust the `--override-input` flags if the project's `./apply` uses a different invocation pattern — slice 10's `plugins/nix/nix` is the source of truth.)

Expected: both commands succeed without errors. If `nix eval` rejects a `system.defaults.*` key (e.g., `screensaver.idleTime` not recognized):

1. Comment out the offending line in `nix/darwin/defaults.nix`.
2. Add an equivalent activation-script entry to `system.activationScripts.firstrunUserCommands.text` (for user-scoped) or `firstrunSudoCommands.text` (for root-scoped). Example for `screensaver.idleTime`:

   ```bash
   /usr/bin/sudo -u ${username} /usr/bin/defaults -currentHost write \
     com.apple.screensaver idleTime -int 0
   ```

3. Re-run `nix eval`. Repeat until green.

If `nix eval` rejects a `CustomUserPreferences.<domain>` entry (rare — the module accepts arbitrary key-value pairs), check for Nix syntax errors (e.g., missing quotes around dotted keys like `"com.apple.foo"`).

- [ ] **Step 10: Run `./apply` (full activation)**

```bash
./apply
```

Expected output (look for):
- No `firstrun_main` log lines (the bash plugin loader is gone).
- nix-darwin activation logs `setting up /etc...`, `applying defaults...`, `system.activationScripts.firstrunSudoCommands`, `system.activationScripts.firstrunUserCommands`.
- home-manager activation runs `removeFirstrunAppliedKey` (visible if `DOTFILES_DEBUG=1`).
- No errors. If any activation script fails (e.g., a typo in a `defaults` command), the commit step blocks — fix and re-run before committing.

- [ ] **Step 11: Verify `~/.dotfilesrc` cleanup**

```bash
grep -E '^FIRSTRUN_APPLIED=' "$HOME/.dotfilesrc" 2>&1 || echo "OK: FIRSTRUN_APPLIED is absent"
echo ""
echo "=== other keys still present ==="
grep -v '^FIRSTRUN_APPLIED=' "$HOME/.dotfilesrc"
```

Expected:
- First line prints `OK: FIRSTRUN_APPLIED is absent`.
- Second block shows `DOTFILES_ENVIRONMENT=default` (and any other historical keys) still present.

- [ ] **Step 12: Spot-check sample defaults landed**

```bash
defaults read NSGlobalDomain AppleInterfaceStyle 2>&1   # expect: Dark
defaults read com.apple.dock orientation 2>&1            # expect: left
defaults read com.apple.finder _FXShowPosixPathInTitle 2>&1  # expect: 1
defaults read com.apple.screencapture location 2>&1      # expect: /Users/<username>/Downloads
defaults read com.apple.Safari HomePage 2>&1             # expect: about:blank
defaults read com.apple.menuextra.battery ShowPercent 2>&1  # expect: YES
defaults read com.apple.dt.Xcode DVTTextTabKeyIndentBehavior 2>&1  # expect: Always
sudo systemsetup -gettimezone 2>&1                       # expect: America/Los_Angeles
sudo systemsetup -getusingnetworktime 2>&1               # expect: Network Time: On
pmset -g | grep -E 'sleep|displaysleep' | head -4         # expect: 15 / 15 / 5 / 15 mins
nvram SystemAudioVolume 2>&1                              # expect: a single space character (boot chime off)
```

Any value that's clearly wrong (e.g., `orientation = bottom` when we set `left`): fix the corresponding line in `nix/darwin/defaults.nix` and re-run `./apply` before proceeding. Settings that simply require a relaunch (e.g., Safari prefs) — note them for Step 13's documentation but do NOT block the commit.

- [ ] **Step 13: Manual iTerm font check**

Quit and relaunch iTerm. The default profile should now use MesloLGS Nerd Font. Open a shell and run `echo -e ''` — the powerline branch glyph should render correctly (not as a missing-glyph box).

If iTerm did NOT pick up the font:
- Do NOT block the commit. The iTerm font format is the spec's open question #1.
- Add a follow-up note to the verification in Task 3.
- Optional: keep the user's existing manual-set font.

- [ ] **Step 14: Idempotence check — re-run `./apply`**

```bash
./apply
```

Expected:
- No errors.
- `removeFirstrunAppliedKey` activation finds no `FIRSTRUN_APPLIED=` line and exits as a no-op.
- nix-darwin's `homebrew` step shows no changes.
- `~/.dotfilesrc` has not gained any duplicate lines:
  ```bash
  sort "$HOME/.dotfilesrc" | uniq -c | sort -rn | head -5
  ```
  All counts should be 1.

- [ ] **Step 15: Confirm `firstrun` removed from runtime path**

```bash
DOTFILES_DEBUG=1 ./apply 2>&1 | grep -i firstrun
```

Expected: no output. (Earlier slices' debug lines all referred to `firstrun_main` running; that codepath is now gone.)

- [ ] **Step 16: Stage and commit**

```bash
git status
git diff --stat
git add \
  nix/darwin/defaults.nix \
  nix/profiles/all/dotfilesrc-cleanup.nix \
  nix/darwin/base.nix \
  nix/profiles/all/default.nix \
  framework/framework
git add -u  # picks up the deletions of framework/firstrun and environments/all/firstrun
git status   # verify only the expected files are staged
```

Then commit (sandbox disable required for gpg signing):

```bash
git commit -m "$(cat <<'EOF'
feat(nix): migrate firstrun to nix-darwin; retire bash firstrun plugin

Move every `defaults write` from environments/all/firstrun into a new
nix/darwin/defaults.nix using system.defaults (native), CustomUserPreferences
(escape hatch), and system.activationScripts (sudo commands that aren't
defaults writes). Retire framework/firstrun and environments/all/firstrun.

Scrub the now-vestigial FIRSTRUN_APPLIED key from ~/.dotfilesrc via a
home-manager activation. Pin iTerm's font declaratively (closes deferral
#4 from the migration status doc).

Drop three obsolete chunks: Dashboard mcx-disabled (gone in 10.15), the
interactive osascript quit (not needed in activation context), and the
post-defaults killall block (nix-darwin handles cfprefsd/Dock/Finder
already; other apps pick up new prefs on next launch).
EOF
)"
```

- [ ] **Step 17: Verify commit landed**

```bash
git log --oneline -1
git show --stat HEAD
```

Expected: one commit named `feat(nix): migrate firstrun to nix-darwin; retire bash firstrun plugin`. Stat shows: 2 new files (`nix/darwin/defaults.nix`, `nix/profiles/all/dotfilesrc-cleanup.nix`), 3 modified (`nix/darwin/base.nix`, `nix/profiles/all/default.nix`, `framework/framework`), 2 deleted (`framework/firstrun`, `environments/all/firstrun`).

- [ ] **Step 18: Compare against Step 1's pre-flight state**

Re-run Step 1's command set. Diff against the saved pre-flight output. Expected differences:

- `FIRSTRUN_APPLIED=` line: present pre-apply, absent post-apply.
- `defaults read` for the four spot-checks: values match pre-apply (firstrun ran historically, so the settings were already in place — this confirms nix-darwin didn't regress them).
- `framework/firstrun` and `environments/all/firstrun`: present pre-apply, absent post-apply.

Anything else that diffs (e.g., a `defaults read` value flipped): investigate before declaring the task complete.

---

## Task 2: Update `nix/README.md`

A separate commit so the docs change is reviewable on its own.

**Files:**

- Modify: `nix/README.md`

### Step-by-step

- [ ] **Step 1: Locate the existing "Per-slice migration guide" section**

```bash
grep -n "For the nix-darwin slice\|## Migration guide\|### For" nix/README.md | head -10
```

Expected: at least one `### For the <slice> slice` heading exists (the prior 9 slices added such sub-blocks). Find the most recent one (likely "For the nix-darwin slice") — the new sub-block goes immediately after it.

- [ ] **Step 2: Append the firstrun sub-block**

Insert the following after the last `### For the …` sub-block:

````markdown
### For the nix-firstrun slice

This slice migrates `environments/all/firstrun` (the macOS preferences script)
into nix-darwin's declarative system layer. The bash framework's `firstrun`
plugin is fully retired.

**One-time apply notes:**

- Mail, Safari, Messages, Photos, Activity Monitor, Address Book, Calendar,
  Contacts, and iCal may need a one-time relaunch after this slice's first
  `./apply` for their new preferences to take effect. nix-darwin already
  kicks `cfprefsd`, `Dock`, `SystemUIServer`, and `Finder` automatically.

- The `FIRSTRUN_APPLIED=1` entry in your `~/.dotfilesrc` is now vestigial and
  is automatically removed by a home-manager activation on next `./apply`.
  The rest of your config file is untouched.

- iTerm's font (Nerd Font, set up in the nix-darwin slice's cask install) is
  now pinned declaratively via `system.defaults.CustomUserPreferences."com.googlecode.iterm2"`.
  If iTerm's font preference ever reverts to a default, the next `./apply`
  re-sets it.

**Private flake update (only if you have one):**

If your private flake extends `darwinConfigurations` with additional
`system.defaults.*` or `CustomUserPreferences` entries, no changes are
required — Nix module merging handles additive private prefs on top of the
public baseline. If your private flake conflicts with a key set in the
public `nix/darwin/defaults.nix`, override it with `lib.mkForce` in the
private module.
````

- [ ] **Step 3: Verify the insertion**

```bash
grep -A 2 "For the nix-firstrun slice" nix/README.md | head -5
```

Expected: the heading and first body line appear.

- [ ] **Step 4: Commit**

```bash
git add nix/README.md
git commit -m "docs(nix): document nix-firstrun slice migration"
```

Sandbox disable required for gpg signing.

- [ ] **Step 5: Verify**

```bash
git log --oneline -2
```

Expected:
```
<hash> docs(nix): document nix-firstrun slice migration
<hash> feat(nix): migrate firstrun to nix-darwin; retire bash firstrun plugin
```

---

## Task 3: Cross-slice verification

Verification only. No code changes. Captures any open questions for the user.

### Step-by-step

- [ ] **Step 1: Full reapply on a clean shell**

```bash
exec zsh -l -c '
  cd /Users/ian/projects/dotfiles
  ./apply 2>&1 | tee /tmp/firstrun-slice-apply.log
'
```

Expected: clean apply, no errors. Inspect `/tmp/firstrun-slice-apply.log` for warnings about deprecated options or unknown keys; report any.

- [ ] **Step 2: Diff full `defaults` snapshot vs. pre-slice**

If a pre-slice snapshot exists (Task 1 Step 1's saved output):

```bash
# Re-run the same commands as Task 1 Step 1, save to a post-apply file:
{
  echo "=== ~/.dotfilesrc ===" ; cat "$HOME/.dotfilesrc"
  echo "=== AppleInterfaceStyle ===" ; defaults read NSGlobalDomain AppleInterfaceStyle 2>&1
  echo "=== dock orientation ===" ; defaults read com.apple.dock orientation 2>&1
  echo "=== finder posix path ===" ; defaults read com.apple.finder _FXShowPosixPathInTitle 2>&1
  echo "=== screencapture location ===" ; defaults read com.apple.screencapture location 2>&1
  echo "=== time zone ===" ; sudo systemsetup -gettimezone 2>&1
} > /tmp/firstrun-post-apply.txt
```

Diff against the pre-flight save. Report any unexpected differences.

- [ ] **Step 3: Verify firstrun bash codepath is gone**

```bash
DOTFILES_DEBUG=1 ./apply 2>&1 | grep -iE 'firstrun|FIRSTRUN_APPLIED'
```

Expected: no output. (Only the `removeFirstrunAppliedKey` home-manager activation should ever touch the key, and that's a non-`firstrun`-named activation.)

```bash
grep -rn firstrun framework/ environments/ plugins/ 2>/dev/null
```

Expected: no output. Every `firstrun` reference in the bash framework is gone.

```bash
grep -rn FIRSTRUN_APPLIED framework/ environments/ plugins/ 2>/dev/null
```

Expected: no output.

- [ ] **Step 4: Verify iTerm font took effect (manual)**

Quit and relaunch iTerm. Default profile font should be `MesloLGS-NF-Regular` size 14. If it isn't:

- Capture the actual current value: `defaults read com.googlecode.iterm2 "Normal Font"`.
- Document as a known open question (deferral #4 stays partially open).
- Do NOT revert the slice — the rest of the firstrun migration stands regardless.

- [ ] **Step 5: Verify Mail/Safari/Messages prefs on relaunch (manual)**

Quit and reopen Mail; verify reply/send animations are disabled (compose a message and observe the send animation). Quit and reopen Safari; verify the Develop menu is visible. Quit and reopen Messages; verify automatic emoji/quote substitution is off (type `:)` in a message — should stay as text, not become an emoji or smart quote).

These verifications are manual; document the result in the verification report. If any of them fail, the corresponding `CustomUserPreferences` entry didn't apply — investigate before declaring the slice complete.

- [ ] **Step 6: Confirm two-commit shape on the branch**

```bash
git log --oneline nix-darwin..HEAD
```

Expected: exactly two commits:

```
<hash> docs(nix): document nix-firstrun slice migration
<hash> feat(nix): migrate firstrun to nix-darwin; retire bash firstrun plugin
```

If there are more (e.g., a fixup commit for an iTerm font workaround that's in scope), that's fine — but flag for the user before opening the PR.

- [ ] **Step 7: Update the status doc (LOCAL ONLY — do NOT commit)**

The user does not commit `docs/superpowers/nix-migration-status.md`. Update it locally to reflect:

- Slice 11 complete: nix-firstrun.
- Deferral #2 (firstrun plugin migration): RESOLVED.
- Deferral #4 (iTerm font selection): RESOLVED (if Task 3 Step 4 passes) OR partially resolved (if iTerm ignored the string-form font entry).
- Add nix-firstrun to the shipped-slices table.

- [ ] **Step 8: Open the PR**

DO NOT do this without explicit user approval — per memory `ask-before-merging` and the slice convention. When the user gives the go-ahead:

```bash
git push -u origin nix-firstrun
gh pr create --base nix-darwin --title "feat(nix): migrate firstrun to nix-darwin" --body "$(cat <<'EOF'
## Summary

- Migrates `environments/all/firstrun` (~500-line bash `defaults write` script) into nix-darwin's declarative system layer via a new `nix/darwin/defaults.nix`.
- Retires `framework/firstrun` (bash plugin loader) and `environments/all/firstrun`.
- Scrubs the vestigial `FIRSTRUN_APPLIED` key from `~/.dotfilesrc` via a home-manager activation.
- Pins iTerm's font declaratively, closing migration deferral #4.

## Resolves

- Migration deferral #2: firstrun plugin migration.
- Migration deferral #4: iTerm font selection (if the string-form font entry took effect on the user's machine).

## Test plan

- [ ] `./apply` succeeds with no errors.
- [ ] `~/.dotfilesrc` no longer contains `FIRSTRUN_APPLIED=1`.
- [ ] Spot-check `defaults read` for AppleInterfaceStyle/dock/finder/Safari matches expected values.
- [ ] `grep firstrun framework/ environments/ plugins/` returns empty.
- [ ] iTerm relaunch picks up Nerd Font (or known caveat documented).
- [ ] Mail/Safari/Messages relaunch picks up new prefs.
- [ ] Second `./apply` is idempotent.

## Stacks on

#70 (nix-darwin)
EOF
)"
```

---

## Self-review against the spec

Spec coverage:

- Decision 1 (fully retire firstrun): Task 1 Steps 7-8 (strip from `framework/framework`, delete `framework/firstrun` + `environments/all/firstrun`).
- Decision 2 (one file `nix/darwin/defaults.nix`): Task 1 Step 3.
- Decision 3 (native options first): Task 1 Step 3's `system.defaults` block.
- Decision 4 (`CustomUserPreferences` escape hatch): Task 1 Step 3's `CustomUserPreferences` block.
- Decision 5 (`system.activationScripts` for sudo-only commands): Task 1 Step 3's `firstrunSudoCommands` + `firstrunUserCommands` blocks.
- Decision 6 (drop dashboard, osascript-quit, killall): explicit "Notes on what this excludes" in Task 1 Step 3.
- Decision 7 (iTerm font, closes deferral #4): Task 1 Step 3's `com.googlecode.iterm2` block + Task 3 Step 4's manual verification.
- Decision 8 (universal-only): `nix/darwin/defaults.nix` imported by `base.nix` (universal), not by a profile-specific module.
- Decision 9 (`FIRSTRUN_APPLIED` scrubbed without backup): Task 1 Step 4's `dotfilesrc-cleanup.nix`.
- Decision 10 (no marker file for defaults): no marker created.
- Decision 11 (migration guide block): Task 2.
- Decision 12 (no work-specific values): no private-flake changes required, called out in Notes for the executor.

Placeholder scan: every step has either exact commands, exact code, or exact verification criteria. No "TBD" / "TODO" / "implement later" / "appropriate error handling" / "similar to Task N".

Type consistency: `system.activationScripts.firstrunSudoCommands` and `system.activationScripts.firstrunUserCommands` are referenced consistently across the plan. `removeFirstrunAppliedKey` is referenced consistently. `nix/darwin/defaults.nix` (singular, no subdirectories) is referenced consistently.

---

## Cross-references

- Design spec: `docs/superpowers/specs/2026-05-26-nix-firstrun-design.md`
- Status doc (local, uncommitted): `docs/superpowers/nix-migration-status.md`
- Prior slice plan (for stack / style reference): `docs/superpowers/plans/2026-05-26-nix-darwin.md`
- Master design: `docs/superpowers/specs/2026-05-22-nix-migration-design.md`
