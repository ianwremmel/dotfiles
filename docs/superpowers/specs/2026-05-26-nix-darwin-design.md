# Nix Darwin Slice Design

**Date:** 2026-05-26
**Status:** Draft — pending user approval
**Branch:** `nix-darwin` (stacks on `nix-homebrew` / PR #69 → `nix-nodejs` / PR #68 → `nix-prompt` / PR #67 → `nix-shells` / PR #66 → `nix-commit-signing` / PR #65 → `nix-git` / PR #64 → `nix-profiles` / PR #63 → `nix-cross-platform` / PR #62)

## Goal

Bring `nix-darwin` into the flake as a system-level layer alongside `home-manager`. Migrate all remaining Brewfile content (casks, mas-installed apps, escape-hatched brews) into nix-darwin's declarative `homebrew.*` options. Retire `plugins/{homebrew,homebrew_core,xcode}` entirely. Move `chshAndEtcShells` from a home-manager activation hack to nix-darwin's declarative `users.users.<name>.shell` + `environment.shells`. Move the `xcodebuild -license accept` step to `system.activationScripts.xcodeLicense`. Remove the now-redundant `brewPathSetup` let-binding from `shells.nix` (nix-darwin's `environment.systemPath` replaces it). Add a Nerd Font cask so starship's git-branch glyph renders correctly (per memory `starship-glyph-fix-deferred`).

This is the largest single slice in the migration: ~30 file changes spanning a new system layer (`nix/darwin/`), flake restructuring, plugin retirements, framework script changes, shell-config cleanup, and README rewrites. Firstrun (macOS preferences via `defaults write`) migration is deferred to a follow-up slice.

## Decisions (locked)

1. **One mega-slice.** Per the user: "One mega-slice." All of: nix-darwin infrastructure, homebrew declarations, plugin retirements, chsh migration, Xcode license migration, shells.nix cleanup, README updates land in one PR.
2. **nix-darwin manages the system layer; home-manager stays standalone.** Both layers coexist. The `nix` plugin invokes home-manager activation first, then `darwin-rebuild switch` (sudo required; carried by the framework's existing sudo keep-alive). Not nesting home-manager inside nix-darwin keeps the bash plugin framework's flow intact.
3. **`darwinConfigurations` only for the `default` profile on macOS systems.** Agent profile is Linux-only and never gets a darwin config. Distinct `darwinProfiles = [ "default" ]` controls this.
4. **`homebrew.onActivation.cleanup = "uninstall"`.** Declared casks/brews/mas are installed; anything else is uninstalled. Fully declarative; the trade-off is that a cask you previously installed manually (and didn't add to the nix-darwin declarations) gets removed on first activation. README documents this.
5. **`bash` and `bash-completion@2` stay in `homebrew.brews`.** The framework's bash-5 bootstrap still depends on brew's bash (per memory `nix-bootstrap-bash-deferred`). nix's bash also stays in `home.packages` (slice 9). Both coexist.
6. **Add `font-meslo-lg-nerd-font` to `homebrew.casks`** (per memory `starship-glyph-fix-deferred`). User must set this as iTerm's font manually post-install — that part is terminal-app config, not declaratively managed by anything we own.
7. **chsh migration: declarative.** nix-darwin's `users.users.ian.shell = "/Users/ian/.nix-profile/bin/zsh";` + `environment.shells = [ ... ];` replaces the marker-gated `chshAndEtcShells` home-manager activation. Cleaner, no marker file, no interactive prompt.
8. **Xcode license: `system.activationScripts.xcodeLicense`.** The `sudo xcodebuild -license accept` step (formerly in `plugins/xcode/xcode`) becomes a nix-darwin system activation script. Runs as root during activation; no separate sudo prompt; idempotent.
9. **`framework/compat`'s brew bootstrap stays.** Brew is still a prerequisite for nix-darwin's `homebrew` module (which uses brew under the hood). On a fresh machine, the order is: brew install → nix install → home-manager activation → nix-darwin activation. `compat_ensure_homebrew` handles the first step on the bash side.
10. **`framework/customize`'s `brew install gh/jq` fallbacks stay.** Customize runs before nix is installed on first apply; the brew fallback is the only reliable path for gh/jq pre-nix. Defensive code.
11. **`framework/firstrun` and `environments/all/firstrun` stay (deferred to a follow-up slice).** Per the user: "defer firstrun to a follow-up slice." Conceptually separable from this slice's homebrew/system-state work.
12. **No work-specific values in the public repo.** Private cask/mas/brew entries stay in `custom_environments/work/Brewfile` until the user migrates them to a private `darwinConfigurations` extension. README documents the pattern.

## Architecture

```text
NEW FILES:
  nix/darwin/base.nix              # darwin system base (system version, brew enable, PATH, shell, Xcode license)
  nix/darwin/default/homebrew.nix  # default-profile casks/mas/brews

MODIFIED FILES:
  nix/flake.nix                    # +nix-darwin input, +darwinConfigurations, +lib.mkDarwin
  plugins/nix/nix                  # +darwin-rebuild invocation after home-manager
  nix/profiles/all/shells.nix      # -brewPathSetup let-binding, -chshAndEtcShells activation,
                                   #   -brewPathSetup refs in profileExtra blocks
  nix/README.md                    # major updates: Background, Profiles section,
                                   #   new "For the nix-darwin slice" sub-block

DELETED:
  plugins/homebrew/                # whole dir (homebrew + Brewfile.erb)
  plugins/homebrew_core/           # whole dir (homebrew_core)
  plugins/xcode/                   # whole dir (xcode + Brewfile + XcodeBrewfile)
  environments/all/Brewfile        # all entries migrated to nix-darwin
  environments/default/Brewfile    # all entries migrated to nix-darwin

UNTOUCHED:
  framework/compat                 # brew bootstrap stays (pre-nix-darwin requirement)
  framework/customize              # brew install gh/jq fallbacks stay (defensive)
  framework/firstrun               # deferred to a follow-up slice
  environments/all/firstrun        # deferred to a follow-up slice
  nix/profiles/all/{git,gpg,cli-tools,shells}.nix  # home-manager user-layer; no changes needed
  nix/profiles/default/{default,cli-tools}.nix     # same
  All slice-1-through-9 home-manager activations    # unaffected (no marker conflict)
```

## `nix/flake.nix` changes

```nix
{
  description = "ianwremmel dotfiles — public nix slice";

  inputs = {
    nixpkgs.url      = "github:NixOS/nixpkgs/nixos-26.05";
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager, nix-darwin, ... }:
    let
      supportedSystems = [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ];
      darwinSystems    = [ "aarch64-darwin" "x86_64-darwin" ];
      publicProfiles   = [ "default" "agent" ];
      darwinProfiles   = [ "default" ];  # agent is Linux-only; no darwin config
      inherit (nixpkgs) lib;
      host = if builtins.pathExists ./host.nix then import ./host.nix
             else throw "nix/host.nix not found — run ./apply (generates it)";
    in {
      # ---------- existing home-manager scaffolding unchanged ----------
      homeModules = { … };
      lib.mkHome = { … };
      homeConfigurations = { … };

      # ---------- nix-darwin (NEW) ----------
      darwinModules = {
        base    = ./darwin/base.nix;
        default = ./darwin/default/homebrew.nix;
      };

      lib.mkDarwin = { system, modules ? [] }:
        nix-darwin.lib.darwinSystem {
          inherit system;
          specialArgs = { inherit (host) username; };
          modules = [ self.darwinModules.base ] ++ modules;
        };

      darwinConfigurations = builtins.listToAttrs (lib.concatMap (system:
        map (profile: {
          name  = "${profile}@${system}";
          value = self.lib.mkDarwin {
            inherit system;
            modules = [ self.darwinModules.${profile} ];
          };
        }) darwinProfiles
      ) darwinSystems);
    };
}
```

## `nix/darwin/base.nix`

Always-included infrastructure. The `username` comes through via `specialArgs` from `lib.mkDarwin`.

```nix
{ pkgs, username, ... }: {
  # System state version — pins nix-darwin's behavior. Never bump casually.
  system.stateVersion = 5;  # nix-darwin's schema number for release-26.05

  # Enable Nix daemon (matches the Determinate installer's setup).
  nix.enable = true;

  # System-wide PATH additions for brew binaries (replaces the brewPathSetup
  # let-binding from shells.nix). Casks ship CLI tools under /opt/homebrew/bin/
  # (e.g., 1password-cli, aws-vault). The user's ~/.nix-profile/bin/ stays
  # ahead of this in PATH for interactive shells; system PATH is just a
  # fallback baseline.
  environment.systemPath = [ "/opt/homebrew/bin" "/opt/homebrew/sbin" ];

  # Declarative login-shell management (replaces chshAndEtcShells activation).
  # nix-darwin writes to /etc/passwd via dscl and ensures the shell is listed
  # in /etc/shells. No marker file; no interactive prompt; idempotent.
  environment.shells = [
    "/Users/${username}/.nix-profile/bin/zsh"
  ];
  users.users.${username} = {
    home  = "/Users/${username}";
    shell = "/Users/${username}/.nix-profile/bin/zsh";
  };

  # Xcode license acceptance (replaces plugins/xcode/xcode's license logic).
  # Runs as root during activation; xcodebuild short-circuits if the license
  # is already accepted, so this is idempotent. The `|| true` ensures
  # activation continues if Xcode isn't installed yet (e.g., on first run
  # before Xcode finishes downloading from masApps).
  system.activationScripts.xcodeLicense.text = ''
    if [ -x /usr/bin/xcodebuild ]; then
      /usr/bin/xcodebuild -license accept 2>/dev/null || true
    fi
  '';

  # Homebrew base settings; per-profile cask/mas/brew lists come from
  # `nix/darwin/<profile>/homebrew.nix`. nix-darwin's homebrew module
  # generates a Brewfile under the hood and runs `brew bundle` on
  # activation — brew itself must already be installed (framework/compat
  # handles that on bash-side bootstrap).
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;      # don't auto-update brew on every apply
      cleanup    = "uninstall"; # remove packages not declared (fully declarative)
      upgrade    = true;       # upgrade declared packages on apply
    };
    # Universal entries that every macOS machine gets, regardless of profile.
    casks = [
      # Personal-machine casks the user has installed; these were in
      # environments/all/Brewfile.
      "aws-vault"
      "1password"
      "1password-cli"
      "docker"
      "elgato-control-center"
      "elgato-stream-deck"
      "fork"
      "firefox"
      "gitup"
      "gpg-suite"
      "grandperspective"
      "ngrok"
      "obsidian"
      "visual-studio-code"
      "vlc"
      "xquartz"
      # NEW: Nerd Font for starship's git-branch glyph (per memory
      # starship-glyph-fix-deferred). After install, configure iTerm
      # to use "MesloLGS Nerd Font" as the profile font.
      "font-meslo-lg-nerd-font"
    ];
    masApps = {
      # From environments/all/Brewfile
      Magnet = 441258766;
      Slack  = 803453959;
      # From plugins/xcode/Brewfile
      Xcode = 497799835;
    };
    brews = [
      # Escape-hatched formulas from slice 9.
      "watchman"  # nix's pkgs.watchman fails to compile (folly C++ dep on aarch64-darwin)
      # Bash bootstrap helpers — stay on brew per memory nix-bootstrap-bash-deferred.
      "bash"
      "bash-completion@2"
    ];
  };
}
```

## `nix/darwin/default/homebrew.nix`

Personal-machine additions. Merged on top of `base.nix`'s universal entries via nix-darwin's module system (list-typed options concatenate).

```nix
{ ... }: {
  homebrew = {
    casks = [
      # From environments/default/Brewfile — personal-only casks
      "adobe-creative-cloud"
      "discord"
      "iterm2"
      "proton-mail"
      "proton-mail-bridge"
      "quicken"
      "steam"
      "synology-drive"
      "webstorm"
      "zoom"
    ];
    masApps = {
      Byword    = 420212497;
      Tailscale = 1475387142;
    };
    brews = [
      # Escape-hatched (slice 9)
      "argo"  # pkgs.argo absent from nixpkgs 26.05
    ];
  };
}
```

## `plugins/nix/nix` script changes

The existing `dotfiles_nix_apply` function runs home-manager activation. Add a `darwin-rebuild switch` invocation after, macOS-only:

```bash
# (existing home-manager activation logic unchanged)

# nix-darwin: macOS-only system layer. Runs after home-manager so the
# user-level setup (PATH, ~/.nix-profile/) is in place when nix-darwin
# tries to resolve user shells, etc.
if [ "$(uname -s)" = "Darwin" ]; then
  local darwin_target
  darwin_target="${DOTFILES_ENVIRONMENT:-default}@$(_dotfiles_nix_current_system)"

  if ! command -v darwin-rebuild >/dev/null 2>&1; then
    log "Bootstrapping nix-darwin (first apply on this machine; sudo required)"
    sudo nix --extra-experimental-features 'nix-command flakes' run \
      nix-darwin -- switch --flake "$PWD/nix#${darwin_target}"
  else
    log "Activating nix-darwin (sudo required)"
    sudo darwin-rebuild switch --flake "$PWD/nix#${darwin_target}"
  fi
fi
```

The framework's `apply` script already has a sudo keep-alive loop (the early `sudo -v` + background `while sudo -n true` pattern). The user's sudo timestamp is fresh by the time `darwin-rebuild` runs, so no separate password prompt.

`_dotfiles_nix_current_system` is a hypothetical helper; the existing `plugins/nix/nix` already inlines the equivalent — `nix --extra-experimental-features 'nix-command flakes' eval --impure --raw --expr builtins.currentSystem` — in `dotfiles_nix_apply`. Either reuse that inline form or extract to a small helper; both are acceptable. The implementer picks whichever matches the surrounding style.

## `nix/profiles/all/shells.nix` cleanup

Two removals (with their consumers):

1. **`brewPathSetup` let-binding** — removed entirely. Also remove the `brewPathSetup +` prefix from both `programs.bash.profileExtra` and `programs.zsh.profileExtra`. Replaced by nix-darwin's `environment.systemPath`.

2. **`chshAndEtcShells` activation script** — removed entirely. Replaced by nix-darwin's declarative `users.users.<name>.shell` + `environment.shells`.

What stays in `shells.nix`:

- `migrateLegacyShellConfig`, `migrateLegacyGitConfig`, `migrateLegacyGnupgConfig`, `migrateLegacyP10kConfig`, `installFnmDefaultNode` — all home-level state; nix-darwin doesn't touch home dotfiles.
- `programs.bash`, `programs.zsh`, `programs.starship`, `home.file.".inputrc"`, `home.packages = [ pkgs.fnm ]` — all user-layer.
- The inline `eval "$(${pkgs.fnm}/bin/fnm env --use-on-cd ...)"` lines — still needed.

## Plugin retirements

Three plugins go away:

1. **`plugins/homebrew/`** (homebrew + Brewfile.erb) — `brew bundle` orchestration moves to nix-darwin's `homebrew` module.
2. **`plugins/homebrew_core/`** (homebrew_core) — brew bootstrap stays in `framework/compat`'s `compat_ensure_homebrew`; the bash plugin was just a no-op wrapper.
3. **`plugins/xcode/`** (xcode + Brewfile + XcodeBrewfile):
   - Xcode install moves to `homebrew.masApps.Xcode = 497799835;`.
   - License-accept moves to `system.activationScripts.xcodeLicense`.
   - The Brewfile/XcodeBrewfile swap dance is no longer needed (declarative state replaces it).

`framework/customize`'s `brew install gh/jq` fallbacks stay (defensive; runs before nix on first apply).

## Brewfile cleanups

- `environments/all/Brewfile` — deleted entirely (every entry migrated to `nix/darwin/base.nix` or `nix/darwin/default/homebrew.nix`).
- `environments/default/Brewfile` — deleted entirely.
- `plugins/homebrew/Brewfile.erb` — deleted with the plugin.
- `plugins/xcode/Brewfile` and `XcodeBrewfile` — deleted with the plugin.
- `custom_environments/work/Brewfile` — UNTOUCHED (private; user migrates separately following the README's "For the nix-darwin slice" sub-block).

## `apply` script changes

Minimal:

- The `-B` flag (skip brew bundle) becomes a no-op since `plugins/homebrew` is gone. Could remove the flag entirely or keep as a documented-no-op for muscle memory. **Decision: remove it.** Future onlookers shouldn't see dead flags.
- No other apply-script changes required; the nix plugin handles the `darwin-rebuild` invocation internally.

## Cross-profile concerns

- **`darwinConfigurations.default@aarch64-darwin`** and **`darwinConfigurations.default@x86_64-darwin`** are the two public darwin configs the flake exposes.
- **No `darwinConfigurations.agent@…`** — agent is Linux-only.
- **Work private flake** can extend `homebrew.casks`/`homebrew.masApps`/`homebrew.brews` via concatenation (these are list-typed and merge across nix-darwin modules). README's new sub-block documents the pattern.
- **Linux machines never invoke nix-darwin.** The `plugins/nix/nix` script's `uname -s` check ensures this.

## Testing

Same shape as prior slices. Multi-step verification.

- **Pre-flight (macOS):**
  - `brew list --cask` count + list (compare against new declared casks).
  - `mas list` (compare against `masApps` declarations).
  - `dscl . -read /Users/$USER UserShell` → `/Users/$USER/.nix-profile/bin/zsh` (already so from slice 6).
  - `grep zsh /etc/shells` → contains the nix-profile zsh path.
  - `xcodebuild -license check` → license accepted.

- **First-apply bootstrap:** the `nix` plugin detects `darwin-rebuild` is absent → invokes `sudo nix run nix-darwin -- switch --flake "$PWD/nix#default@aarch64-darwin"`. Bootstraps the nix-darwin profile + activates. Sudo prompt expected (covered by `apply`'s keep-alive).

- **Activation:**
  - `darwin-rebuild` is now available at `/run/current-system/sw/bin/darwin-rebuild` (and via the user's nix profile).
  - `system.defaults`/`homebrew.casks`/etc. all applied successfully.
  - Declared casks present in `/Applications/`.
  - `homebrew.onActivation.cleanup = "uninstall"` — if any previously-installed brew/cask isn't declared, it gets removed. **Risk:** verify the declared list captures everything you want.

- **MesloLGS Nerd Font:** installed via the cask; `system_profiler SPFontsDataType` lists it. (Setting iTerm's font is a manual one-time step; not automated.)

- **Xcode license:** `xcodebuild -license check` still passes after activation.

- **Subsequent applies:**
  - `darwin-rebuild` is present → uses the steady-state path.
  - Idempotent: re-running produces no changes.

- **chsh: no marker file needed.** `~/.shells-chsh.hm-migrated` is now dead; the implementer should NOT delete it (it's just unused state on disk). If desired, a one-line note in the README explains it.

- **Cross-slice intact:**
  - `git config alias.fixup`, signing key, etc. (slices 1, 5).
  - `gpg --version` resolves to nix store (slice 5).
  - `which starship`, `which fnm`, `node --version` (slices 7, 8).
  - `git --version` 2.54.0 (slice 5 nixpkgs bump).
  - All `home.packages` formulas from slice 9 resolve via nix.

- **Throwaway private-flake override:**
  - Scratch flake adds `homebrew.casks = [ "monodraw" ];` (or any harmless cask).
  - Activate the throwaway darwin config; verify the cask installs.
  - Tear down; verify the cask uninstalls on next default-profile activation (because `cleanup = "uninstall"`).

- **Linux container (agent profile):** nix-darwin is macOS-only; the `plugins/nix/nix` script's `uname -s = "Darwin"` check skips the entire darwin path. Verify the container activates home-manager normally and never invokes `darwin-rebuild`.

- **Backout drill:** `./apply` with the slice reverted falls back to bash plugins; brew bundle still works against the (re-restored) Brewfiles. NOTE: nix-darwin's system-state changes (`/etc/passwd` entries, `system.activationScripts` artifacts) are NOT automatically reverted by `git revert`. Manual cleanup needed for full revert.

## README updates

Substantial — the project now has a two-layer architecture (system + user).

1. **Background paragraph** — append: "…and a system-level layer via nix-darwin managing brew casks (including the user's preferred Nerd Font), mas-installed apps (including Xcode), the login-shell declaration, and Xcode license acceptance."

2. **Profiles section** — restructure to document `darwinConfigurations` alongside `homeConfigurations`:
   - The existing "Profiles" section documents home-manager profiles.
   - Add a new "Darwin configurations" subsection: `darwinConfigurations."<profile>@<system>"` — macOS-only; currently only `default` is built. Used for system-level brew/cask/mas declarations, the login shell, and the Xcode license accept.

3. **`all`-layer parenthetical** — extend with the darwin scope.

4. **New "For the nix-darwin slice" sub-block** in the private-environment migration guide:

   ```markdown
   For the nix-darwin slice (homebrew + system-level state move into
   nix-darwin; bash plugins retire):

   1. **Bootstrap nix-darwin on each macOS machine** (one-time):

          sudo nix run nix-darwin -- switch --flake "$PWD/nix#default@aarch64-darwin"

      Subsequent applies use `darwin-rebuild switch` automatically via
      the nix plugin.

   2. **Update your private flake** to add your own darwin module if you
      have private casks/mas/brews:

          # ./darwin.nix
          { ... }: {
            homebrew = {
              casks = [
                # …your private casks…
              ];
              masApps = {
                # …your private mas apps…
              };
              brews = [
                # …escape-hatched formulas from custom taps, etc…
              ];
            };
          }

      Then wire it into your private flake's darwinConfiguration:

          darwinConfigurations."<profile>@<system>" = public.lib.mkDarwin {
            inherit system;
            modules = [
              public.darwinModules.default
              ./darwin.nix
            ];
          };

   3. **Delete your private `custom_environments/<env>/Brewfile`** entries
      that you've migrated. `homebrew.onActivation.cleanup = "uninstall"`
      will remove brews/casks not declared anywhere, so leaving stale
      Brewfile content while ALSO declaring it in nix-darwin is safe but
      redundant.

   4. **The `chsh` activation script from Slice 6 is gone.** nix-darwin's
      `users.users.<name>.shell` handles login-shell selection
      declaratively. No marker file; no interactive prompt.

   5. **Xcode license** is accepted automatically via
      `system.activationScripts.xcodeLicense`. The Xcode app itself
      installs via `homebrew.masApps.Xcode`.

   6. **Set iTerm's font** to "MesloLGS Nerd Font" (or your preferred
      Nerd Font) once after the cask installs: iTerm → Settings →
      Profiles → Text → Font. This fixes the placeholder glyph in
      starship's prompt.
   ```

5. **Backout section** — extend to cover nix-darwin: `darwin-uninstaller` exists but is awkward; cleanest revert is to drop the flake input + revert this slice's commits + (manually) restore the Brewfiles from the deleted state. Manual `/etc/passwd`/`/etc/shells` cleanup may be needed.

## Scope / Non-goals

**In scope:**

- Add `nix-darwin` flake input + `darwinConfigurations` + `lib.mkDarwin`.
- Create `nix/darwin/base.nix` + `nix/darwin/default/homebrew.nix`.
- Wire `plugins/nix/nix` to invoke `darwin-rebuild` after home-manager.
- Migrate every cask + mas + escape-hatched brew from the three public Brewfiles into nix-darwin.
- Add `font-meslo-lg-nerd-font` cask.
- Retire `plugins/{homebrew,homebrew_core,xcode}` entirely.
- Delete `environments/{all,default}/Brewfile`.
- Move `chshAndEtcShells` activation → `users.users.<name>.shell` + `environment.shells`.
- Move Xcode license → `system.activationScripts.xcodeLicense`.
- Remove `brewPathSetup` let-binding from `shells.nix`.
- Remove `-B` flag from `apply` script.
- README updates: Background + Profiles + `all`-layer + new private-env sub-block + Backout.

**Out of scope:**

- `environments/all/firstrun` migration — deferred to a follow-up slice (per user direction).
- `framework/compat`'s brew bootstrap — stays (still needed pre-nix-darwin).
- `framework/customize`'s `brew install gh/jq` fallbacks — stays (defensive pre-nix path).
- Bash bootstrap chicken-and-egg cleanup — deferred per memory `nix-bootstrap-bash-deferred`.
- Custom-environment work-Brewfile migration — user does this in their private repo using this slice as the template.
- Migrating mas/cask declarations to GitHub-organisation-tracked release notes — not a real concern; mas IDs are stable.
- Automated marker-file cleanup (`~/.shells-chsh.hm-migrated`) — leave on disk; harmless and provides historical context.

## Future phases

- **Slice 11: firstrun migration.** `environments/all/firstrun` → `system.defaults.*` + `system.activationScripts.firstrunBits`. Retire `framework/firstrun` mechanism.
- **Slice 12: bash bootstrap inversion.** Address the chicken-and-egg per memory `nix-bootstrap-bash-deferred`. Probably involves making the framework's `apply` script require nix as a pre-step and using nix's bash from the start.
- **Slice 13+: per-tool migrations.** `claude`, `vim`, `vscode`, misc rsync dotfiles. Each is small.

Once those land, the bash framework is essentially retired: only `framework/compat` (brew bootstrap pre-nix) + `framework/customize` (initial-setup wizard) + `plugins/nix` (nix install + activations) + `apply` (orchestration) remain.
