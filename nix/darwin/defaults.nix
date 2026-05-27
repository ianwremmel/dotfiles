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
      # WebKitDeveloperExtras: not in nix-darwin's native NSGlobalDomain module;
      # routed via CustomUserPreferences.NSGlobalDomain below.
      "com.apple.springing.enabled"         = true;
      "com.apple.springing.delay"           = 0.0;
    };

    # ----- Finder -----
    finder = {
      NewWindowTarget                  = "Other";
      NewWindowTargetPath              = "file:///Users/${username}/";
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
      # wvous-bl-corner: nix-darwin's module requires a positive int or null.
      # The source script writes 0 ("no action"), which is the macOS default —
      # routed via CustomUserPreferences."com.apple.dock" below to preserve
      # the explicit write.
      # wvous-bl-modifier: not in nix-darwin's native module; same routing.
    };

    # ----- Screencapture -----
    screencapture = {
      location       = "/Users/${username}/Downloads";
      type           = "png";
      disable-shadow = true;
    };

    # ----- Screensaver -----
    # askForPassword{,Delay} go to the standard plist.
    screensaver = {
      askForPassword      = true;
      askForPasswordDelay = 5;
      # idleTime: rejected by nix-darwin's screensaver module — moved to
      # system.activationScripts.firstrunUserCommands below (uses
      # `defaults -currentHost write` against the user's ByHost plist).
    };

    # ----- Activity Monitor -----
    # ShowCategory: nix-darwin's module restricts to 100..107 (named filter
    # constants). The source script writes 0, which doesn't match any of those.
    # Routed via CustomUserPreferences below to preserve the legacy value.
    ActivityMonitor = {
      OpenMainWindow = true;
      IconType       = 5;
      SortColumn     = "CPUUsage";
      SortDirection  = 0;
    };

    # ----- Software Update -----
    # nix-darwin's native module only exposes AutomaticallyInstallMacOSUpdates.
    # The rest go via CustomUserPreferences."com.apple.SoftwareUpdate" below.

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

      # ----- NSGlobalDomain keys not in nix-darwin's native module -----
      NSGlobalDomain = {
        WebKitDeveloperExtras = true;
      };

      # ----- Dock keys not in nix-darwin's native module -----
      "com.apple.dock" = {
        wvous-bl-corner   = 0;
        wvous-bl-modifier = 0;
      };

      # ----- Activity Monitor keys not in nix-darwin's native module -----
      "com.apple.ActivityMonitor" = {
        ShowCategory = 0;
      };

      # ----- Software Update keys not in nix-darwin's native module -----
      "com.apple.SoftwareUpdate" = {
        AutomaticCheckEnabled = true;
        AutomaticDownload     = 1;
        ConfigDataInstall     = 1;
        CriticalUpdateInstall = 1;
        ScheduleFrequency     = 1;
      };

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

      # ----- Finder keys not in nix-darwin's native module -----
      # NewWindowTargetPath is set natively above (the native finder.NewWindowTarget="Other"
      # assertion requires it). The rest stay here.
      "com.apple.finder" = {
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

      # ----- Address Book ----- (removed: TCC-protected domain; nix-darwin activation fails when writing com.apple.addressbook)

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
      # using `defaults -currentHost write` instead (see the
      # `firstrunUserCommands` activation below).
      "com.apple.ImageCapture" = {
        disableHotPlug = true;
      };

      # ----- App Store auto-update -----
      "com.apple.commerce" = {
        AutoUpdate = true;
      };

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

      # ----- iTerm 2 -----
      # Pin the Nerd Font for the default profile so starship's git-branch
      # glyph renders. iTerm reads `Normal Font` on launch. If iTerm ignored
      # this entry (because it expects a binary-encoded NSFont rather than
      # a plain string), the visible font won't change — falling back to a
      # binary `-data` write captured from a working machine would be the
      # next step.
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
    /usr/bin/sudo -H -u ${username} /usr/bin/chflags nohidden /Users/${username}/Library

    # Disable screensaver (idleTime = 0). The `-currentHost` write targets
    # ~/Library/Preferences/ByHost/com.apple.screensaver.<UUID>.plist, which
    # nix-darwin's screensaver module does not cover. `-H` is required so the
    # elevated shell's $HOME is the target user's home (not root's /var/root) —
    # otherwise `defaults -currentHost` resolves the ByHost dir under the wrong
    # home and the write lands in the wrong place.
    /usr/bin/sudo -H -u ${username} /usr/bin/defaults -currentHost write \
      com.apple.screensaver idleTime -int 0
  '';
}
