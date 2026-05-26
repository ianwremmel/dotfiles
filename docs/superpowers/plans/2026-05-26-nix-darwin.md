# Nix Darwin Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring `nix-darwin` into the flake as a system-level layer. Migrate every Brewfile entry (cask/mas/escape-hatched-brew) into nix-darwin's `homebrew.*` options. Retire `plugins/{homebrew,homebrew_core,xcode}`. Move `chshAndEtcShells` activation → `users.users.<name>.shell` + `environment.shells`. Move Xcode license → `system.activationScripts.xcodeLicense`. Remove `brewPathSetup` from `shells.nix`. Add `font-meslo-lg-nerd-font` cask.

**Architecture:** Single atomic feat commit creates `nix/darwin/{base,default/homebrew}.nix`, modifies `nix/flake.nix` (adds nix-darwin input + `darwinConfigurations` + `lib.mkDarwin`), modifies `plugins/nix/nix` (`darwin-rebuild switch` after home-manager activation), modifies `nix/profiles/all/shells.nix` (drops brewPathSetup + chshAndEtcShells), modifies `apply` (drops `-B` flag), and deletes `plugins/{homebrew,homebrew_core,xcode}/` + `environments/{all,default}/Brewfile`. A second commit updates `nix/README.md`. A third task is verification-only.

**Tech Stack:** Bash 5, Nix flakes, home-manager (`home-manager/release-26.05`), nix-darwin (`nix-darwin-26.05`), Homebrew (still the underlying installer for casks/mas).

---

## Notes for the executor

- **Reference spec:** `docs/superpowers/specs/2026-05-26-nix-darwin-design.md`.
- **No automated test framework.** "Tests" are verification commands with expected output.
- **Branch:** `nix-darwin`. Stacks on `nix-homebrew` (PR #69) → `nix-nodejs` (PR #68) → … → master. **Do NOT merge anything.**
- **Stacking machinery** (assumed working from prior slices): `homeModules.{all,default,agent}`, `lib.mkHome`, profile imports, `--override-input public path:…`, `nix/host.nix` (untracked) with `{ username; profile; }`.
- **Sandbox disable required for:** `nix`, `./apply`, `git commit` (gpg signing), `brew`, `sudo …`, anything touching `~/.nix-profile/`, `/opt/homebrew/`, or `/etc/`. Use `dangerouslyDisableSandbox: true`. If `nix` isn't on PATH, prepend `source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh`.
- **Run commands from repo root** (`/Users/ian/projects/dotfiles`).
- **Pre-existing local state:**
  - `nix/host.nix` = `{ username = "ian"; profile = "default"; }`, untracked.
  - `~/.dotfilesrc` contains `DOTFILES_ENVIRONMENT=default`.
  - Brew is installed at `/opt/homebrew/`.
  - All casks/mas from the Brewfiles currently brew-installed.
  - The four escape-hatched brews (`bash`, `bash-completion@2`, `watchman`, `argo`) currently brew-installed (slice 9).
  - The user's login shell is already `~/.nix-profile/bin/zsh` (from slice 6's chsh activation).
- **Conventional commits**, NO `Co-Authored-By: Claude` / `Generated with Claude Code` trailers.
- **No work-specific values.** Work-only Brewfile content stays in `custom_environments/work/Brewfile`.
- **Bootstrap path:** the first `./apply` after this slice will detect `darwin-rebuild` is absent and bootstrap nix-darwin via `sudo nix run nix-darwin -- switch --flake "$PWD/nix#default@$SYSTEM"`. The framework's sudo keep-alive carries auth through.

---

## Task 1: Atomic nix-darwin migration

Every change in one commit so the repo never sits in a partial-migration state where (e.g.) the bash plugins are deleted but `darwin-rebuild` isn't wired up yet.

**Files:**

- Create: `nix/darwin/base.nix`
- Create: `nix/darwin/default/homebrew.nix`
- Modify: `nix/flake.nix` (add nix-darwin input + darwinConfigurations + lib.mkDarwin)
- Modify: `nix/flake.lock` (via `nix flake lock --update-input` for nix-darwin)
- Modify: `plugins/nix/nix` (add darwin-rebuild invocation)
- Modify: `nix/profiles/all/shells.nix` (remove brewPathSetup + chshAndEtcShells + their consumers)
- Modify: `apply` (remove `-B` flag handling)
- Delete: `plugins/homebrew/{homebrew,Brewfile.erb}` + the directory
- Delete: `plugins/homebrew_core/{homebrew_core}` + the directory
- Delete: `plugins/xcode/{xcode,Brewfile,XcodeBrewfile}` + the directory
- Delete: `environments/all/Brewfile`
- Delete: `environments/default/Brewfile`

### Step-by-step

- [ ] **Step 1: Capture pre-flight state**

```bash
echo "=== current brew state ==="
brew list --cask | head -30
echo "(total $(brew list --cask | wc -l) casks)"
echo ""
brew list --formula | head -10
echo "(total $(brew list --formula | wc -l) formulas)"
echo ""
mas list 2>&1 | head -10
echo ""
echo "=== login shell ==="
dscl . -read "/Users/$USER" UserShell 2>&1
echo ""
echo "=== /etc/shells ==="
grep -E 'zsh|bash' /etc/shells
echo ""
echo "=== xcodebuild license ==="
xcodebuild -license check 2>&1 | head -3
echo ""
echo "=== darwin-rebuild absent? ==="
command -v darwin-rebuild 2>&1 || echo "(absent — bootstrap path will run)"
echo ""
echo "=== marker files from prior slices ==="
ls -la "$HOME"/.shells-chsh.hm-migrated "$HOME"/.shell-config.hm-migrated 2>&1 | head -3
```

Save the output. Steps 14-17's verification compares against it.

- [ ] **Step 2: Confirm starting file state**

```bash
ls plugins/homebrew/ plugins/homebrew_core/ plugins/xcode/
ls environments/all/Brewfile environments/default/Brewfile
wc -l nix/flake.nix nix/profiles/all/shells.nix plugins/nix/nix apply
grep -n 'brewPathSetup\|chshAndEtcShells\|DOTFILES_HOMEBREW_SKIP' nix/profiles/all/shells.nix apply plugins/nix/nix | head -20
```

Expected: all six paths exist; existing brewPathSetup + chshAndEtcShells references found.

- [ ] **Step 3: Create `nix/darwin/base.nix`**

```nix
{ pkgs, username, ... }: {
  # System state version — pins nix-darwin's behavior. Never bump casually.
  system.stateVersion = 5;

  # Enable Nix daemon (matches the Determinate installer's setup).
  nix.enable = true;

  # System-wide PATH for brew binaries. Casks ship CLI tools under
  # /opt/homebrew/bin/ (e.g., 1password-cli, aws-vault). The user's
  # ~/.nix-profile/bin/ stays ahead in PATH for interactive shells; this
  # is the system baseline. Replaces the brewPathSetup let-binding from
  # the previous shells.nix.
  environment.systemPath = [ "/opt/homebrew/bin" "/opt/homebrew/sbin" ];

  # Declarative login-shell management (replaces the chshAndEtcShells
  # home-manager activation). nix-darwin writes /etc/passwd via dscl and
  # ensures the shell is in /etc/shells. No marker file; no interactive
  # prompt; idempotent.
  environment.shells = [
    "/Users/${username}/.nix-profile/bin/zsh"
  ];
  users.users.${username} = {
    home  = "/Users/${username}";
    shell = "/Users/${username}/.nix-profile/bin/zsh";
  };

  # Xcode license acceptance (replaces plugins/xcode/xcode's license logic).
  # Runs as root during activation; xcodebuild short-circuits if the license
  # is already accepted, so it's idempotent. The `|| true` ensures activation
  # continues if Xcode isn't installed yet (e.g., first apply before
  # masApps.Xcode finishes downloading).
  system.activationScripts.xcodeLicense.text = ''
    if [ -x /usr/bin/xcodebuild ]; then
      /usr/bin/xcodebuild -license accept 2>/dev/null || true
    fi
  '';

  # Homebrew base settings; per-profile cask/mas/brew lists come from
  # nix/darwin/<profile>/homebrew.nix. nix-darwin's homebrew module
  # generates a Brewfile under the hood and runs `brew bundle` on activate
  # — brew itself must already be installed (framework/compat handles
  # the bash-side bootstrap on a fresh machine).
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;       # don't auto-update brew on every apply
      cleanup    = "uninstall"; # remove packages not declared (fully declarative)
      upgrade    = true;        # upgrade declared packages on apply
    };

    # Universal casks/mas/brews — every macOS machine gets these.
    casks = [
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
      # New: Nerd Font for starship's git-branch glyph (per memory
      # starship-glyph-fix-deferred). After install, set this as iTerm's
      # font in Settings → Profiles → Text → Font.
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
      # Escape-hatched (slice 9): nix's pkgs.watchman fails to compile
      # because the folly C++ dep doesn't build on aarch64-darwin in
      # the current nixpkgs.
      "watchman"
      # Bash bootstrap helpers — stay on brew per memory
      # nix-bootstrap-bash-deferred. The framework's compat layer needs
      # brew's bash before nix is installed on a fresh machine.
      "bash"
      "bash-completion@2"
    ];
  };
}
```

- [ ] **Step 4: Create `nix/darwin/default/homebrew.nix`**

```nix
{ ... }: {
  homebrew = {
    # Personal-machine casks — additive on top of base.nix's universal list.
    # nix-darwin's homebrew option is list-typed, so these concatenate.
    casks = [
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
      # Escape-hatched (slice 9): pkgs.argo absent from nixpkgs 26.05.
      "argo"
    ];
  };
}
```

- [ ] **Step 5: Modify `nix/flake.nix`**

Read the current file:

```bash
cat nix/flake.nix
```

Replace with:

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

      # Untracked, plugin-generated per-host values: { username; profile; }.
      host =
        if builtins.pathExists ./host.nix then import ./host.nix
        else throw "nix/host.nix not found — run ./apply (generates it) or create it: { username = \"<you>\"; profile = \"default\"; }";
    in {
      # ---------- home-manager (existing) ----------
      homeModules = {
        base    = ./home.nix;
        all     = ./profiles/all/default.nix;
        default = ./profiles/default/default.nix;
        agent   = ./profiles/agent/default.nix;
      };

      lib.mkHome = { system, username, modules ? [] }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          extraSpecialArgs = { inherit username; };
          modules = [ self.homeModules.base self.homeModules.all ] ++ modules;
        };

      homeConfigurations = builtins.listToAttrs (lib.concatMap (system:
        map (profile: {
          name  = "${profile}@${system}";
          value = self.lib.mkHome {
            inherit system;
            inherit (host) username;
            modules = [ self.homeModules.${profile} ];
          };
        }) publicProfiles
      ) supportedSystems);

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

- [ ] **Step 6: Update `nix/flake.lock` to add nix-darwin**

```bash
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
cd nix
nix --extra-experimental-features 'nix-command flakes' flake lock --update-input nix-darwin 2>&1 | tail -10 || \
  nix --extra-experimental-features 'nix-command flakes' flake update --commit-lockfile 2>&1 | tail -10
cd ..
```

If `--update-input nix-darwin` fails because the input wasn't previously locked, run plain `nix flake update` in `nix/`. The lock file now has `nix-darwin` alongside `nixpkgs` and `home-manager`.

Verify:

```bash
jq -r '.nodes | keys[]' nix/flake.lock
```

Expected: includes `nix-darwin` along with `nixpkgs`, `home-manager`, `root`.

- [ ] **Step 7: Modify `nix/profiles/all/shells.nix` — remove `brewPathSetup` let-binding**

Find the `let` block at the top of the module. It contains `sharedAliases` and `brewPathSetup`. Remove the entire `brewPathSetup` binding (the `brewPathSetup = '' … '';` definition). Keep `sharedAliases`.

Also find every use of `brewPathSetup` in `programs.bash.profileExtra` and `programs.zsh.profileExtra`. They look like `profileExtra = brewPathSetup + ''…'';` — replace with just `profileExtra = ''…'';` (drop the `brewPathSetup +` prefix). The `''` body itself stays.

- [ ] **Step 8: Modify `nix/profiles/all/shells.nix` — remove `chshAndEtcShells` activation**

Find the `home.activation.chshAndEtcShells = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''…''';` block. Remove it entirely.

The other `migrate*` activations (migrateLegacyShellConfig, migrateLegacyGitConfig, migrateLegacyGnupgConfig, migrateLegacyP10kConfig, installFnmDefaultNode) stay.

After Steps 7-8: `wc -l nix/profiles/all/shells.nix` should be ~70-80 lines shorter than before.

- [ ] **Step 9: Modify `plugins/nix/nix` — add `darwin-rebuild` invocation**

Read the current file:

```bash
cat plugins/nix/nix
```

Find `dotfiles_nix_apply()`. After the existing home-manager activation block (the part that runs `$out/activate`), and before the function's closing `}`, add:

```bash
  # nix-darwin: macOS-only system layer. Runs after home-manager so the
  # user-level setup is in place when nix-darwin tries to resolve user
  # shells, etc.
  if [ "$(uname -s)" = "Darwin" ]; then
    local darwin_system darwin_target
    darwin_system="$(nix --extra-experimental-features 'nix-command flakes' \
      eval --impure --raw --expr builtins.currentSystem)"
    darwin_target="${DOTFILES_ENVIRONMENT:-default}@${darwin_system}"

    if ! command -v darwin-rebuild >/dev/null 2>&1; then
      log "Bootstrapping nix-darwin (first apply on this machine; sudo required)"
      sudo nix --extra-experimental-features 'nix-command flakes' run \
        nix-darwin -- switch --flake "${DOTFILES_ROOT_DIR}/nix#${darwin_target}"
    else
      log "Activating nix-darwin (sudo required)"
      sudo darwin-rebuild switch --flake "${DOTFILES_ROOT_DIR}/nix#${darwin_target}"
    fi
  fi
```

The `DOTFILES_ROOT_DIR` env var is set by the framework's `apply` script and available here. The framework's `apply` also has a sudo keep-alive loop, so `sudo darwin-rebuild` doesn't re-prompt.

- [ ] **Step 10: Modify `apply` — remove `-B` flag handling**

Read the current `apply` script. Find the `-B` flag handling. Looks like:

```bash
while getopts ":BA" opt; do
  case ${opt} in
    B) export DOTFILES_HOMEBREW_SKIP=1 ;;
    A) export DOTFILES_AIRPLANE_MODE=1 ;;
    \?) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
  esac
done
```

Drop the `B)` case. The `getopts` string becomes `":A"`. The `export DOTFILES_HOMEBREW_SKIP=1` line goes away. Also drop any documentation reference to `-B`.

- [ ] **Step 11: Delete `plugins/homebrew/`**

```bash
git rm plugins/homebrew/homebrew plugins/homebrew/Brewfile.erb
rmdir plugins/homebrew 2>/dev/null || true
ls -d plugins/homebrew 2>&1 | head -1
```

Expected: `ls: cannot access 'plugins/homebrew'`.

- [ ] **Step 12: Delete `plugins/homebrew_core/`**

```bash
git rm plugins/homebrew_core/homebrew_core
rmdir plugins/homebrew_core 2>/dev/null || true
ls -d plugins/homebrew_core 2>&1 | head -1
```

- [ ] **Step 13: Delete `plugins/xcode/`**

```bash
git rm plugins/xcode/xcode plugins/xcode/Brewfile plugins/xcode/XcodeBrewfile
rmdir plugins/xcode 2>/dev/null || true
ls -d plugins/xcode 2>&1 | head -1
```

- [ ] **Step 14: Delete the empty Brewfiles**

```bash
git rm environments/all/Brewfile environments/default/Brewfile
ls environments/all/Brewfile environments/default/Brewfile 2>&1 | head -2
```

Expected: both report `No such file or directory`.

- [ ] **Step 15: Verify all Nix files parse + the flake evaluates**

```bash
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
nix-instantiate --parse nix/flake.nix >/dev/null && echo "flake parses"
nix-instantiate --parse nix/darwin/base.nix >/dev/null && echo "darwin/base parses"
nix-instantiate --parse nix/darwin/default/homebrew.nix >/dev/null && echo "darwin/default parses"
nix-instantiate --parse nix/profiles/all/shells.nix >/dev/null && echo "shells parses"

nix --extra-experimental-features 'nix-command flakes' eval \
  "path:$PWD/nix#darwinModules.base" --apply 'p: builtins.typeOf p' --raw; echo
nix --extra-experimental-features 'nix-command flakes' eval \
  "path:$PWD/nix#darwinConfigurations.\"default@$(nix --extra-experimental-features 'nix-command flakes' eval --impure --raw --expr builtins.currentSystem)\".system.outPath" --raw; echo

# Sanity-check home-manager outputs still work
nix --extra-experimental-features 'nix-command flakes' eval \
  "path:$PWD/nix#homeConfigurations.\"default@$(nix --extra-experimental-features 'nix-command flakes' eval --impure --raw --expr builtins.currentSystem)\".activationPackage.outPath" --raw; echo
```

Expected: all 4 parses succeed; `path` for the module; nix-store paths for both darwin and home configurations.

If `darwinConfigurations` eval fails because nix-darwin module options changed shape between versions (e.g., `system.stateVersion`, `homebrew.onActivation.cleanup`), check the nix-darwin docs for `release-26.05` and adjust the affected option name in `nix/darwin/base.nix`. Note any drift in your commit message.

- [ ] **Step 16: Run home-manager activation (no darwin yet)**

```bash
DOTFILES_ENVIRONMENT=default DOTFILES_ROOT_DIR="$PWD" bash -c '
  set -euo pipefail
  source framework/logging
  source plugins/nix/nix
  dotfiles_nix_apply
' 2>&1 | tail -30
```

Expected: full activation runs — first the home-manager part (cleaning orphan links, etc.) then the new "Bootstrapping nix-darwin" branch. Since `darwin-rebuild` is absent on first run, this triggers `sudo nix run nix-darwin -- switch --flake …`. The sudo prompt fires if the framework's keep-alive hasn't preceded this (in direct-invocation testing it may; the framework's `apply` script has the keep-alive — direct invocation does not).

If sudo prompts and the harness can't interact, run the bootstrap manually:

```bash
sudo nix --extra-experimental-features 'nix-command flakes' run \
  nix-darwin -- switch --flake "$PWD/nix#default@$(nix --extra-experimental-features 'nix-command flakes' eval --impure --raw --expr builtins.currentSystem)"
```

…then re-run `dotfiles_nix_apply` — the second invocation will find `darwin-rebuild` on PATH and use the steady-state branch (still sudo-required but already-authed via the manual bootstrap).

- [ ] **Step 17: Verify nix-darwin activated successfully**

```bash
echo "=== darwin-rebuild on PATH ==="
command -v darwin-rebuild

echo "=== current system generation ==="
ls -l /run/current-system 2>&1 | head -1

echo "=== homebrew declarations applied ==="
brew list --cask | sort | head -30
echo "(total $(brew list --cask | wc -l) casks; expected ~26 declared)"
echo ""
mas list

echo "=== Nerd Font installed ==="
ls -d "/Library/Fonts/MesloLGS NF Regular.ttf" "/Users/$USER/Library/Fonts/MesloLGS NF Regular.ttf" 2>&1 | head -2
fc-list 2>&1 | grep -i meslo | head -3 || echo "(fc-list unavailable — check /Library/Fonts/ manually)"

echo "=== login shell unchanged (declared via users.users.X.shell) ==="
dscl . -read "/Users/$USER" UserShell

echo "=== /etc/shells contains nix zsh ==="
grep nix-profile /etc/shells

echo "=== Xcode license accepted (no prompt) ==="
xcodebuild -license check 2>&1 | head -3
```

Expected:

- `darwin-rebuild` resolves to `/run/current-system/sw/bin/darwin-rebuild`.
- `/run/current-system` is a symlink into `/nix/store/…-darwin-system-…`.
- `brew list --cask` includes all 26 declared casks (16 from `base.nix` + 10 from `default/homebrew.nix`).
- `mas list` includes Xcode, Magnet, Slack, Byword, Tailscale.
- MesloLGS Nerd Font is installed.
- Login shell still `/Users/$USER/.nix-profile/bin/zsh`.
- `/etc/shells` contains the nix-profile zsh path.
- `xcodebuild -license check` passes silently.

- [ ] **Step 18: Cross-slice integrity check**

```bash
git config --get alias.fixup            # Slice 1
git config --get user.signingkey         # Slice 5
git config --get commit.gpgsign          # Slice 5
git --version                            # Slice 5's nixpkgs bump → 2.54.0
gpg --version | head -1                  # Slice 5
which starship                           # Slice 7
which fnm                                # Slice 8
node --version                           # Slice 8
which terraform                          # Slice 9
which kubectl                            # Slice 9
zsh -ic 'alias psgrep' 2>&1 | grep -v gitstatus  # Slice 6
bash -lic 'alias psgrep' 2>&1 | head -3  # Slice 6
```

Expected: all slices' contributions still working.

- [ ] **Step 19: Idempotency check**

```bash
DOTFILES_ENVIRONMENT=default DOTFILES_ROOT_DIR="$PWD" bash -c '
  source framework/logging
  source plugins/nix/nix
  dotfiles_nix_apply
' 2>&1 | tail -20
```

Expected: home-manager activation runs cleanly; nix-darwin reports "current generation already matches" or builds an identical generation that no-ops on activation. No errors. Sudo prompt if the auth has expired.

- [ ] **Step 20: Commit the atomic migration**

```bash
git add nix/flake.nix nix/flake.lock \
        nix/darwin/base.nix nix/darwin/default/homebrew.nix \
        nix/profiles/all/shells.nix \
        plugins/nix/nix apply
git status --porcelain
git -c gpg.program="$(which gpg)" commit -m "feat(nix): introduce nix-darwin; retire homebrew/homebrew_core/xcode plugins"
git log --oneline -1
```

Expected porcelain summary:

- 5 `M`: `nix/flake.nix`, `nix/flake.lock`, `nix/profiles/all/shells.nix`, `plugins/nix/nix`, `apply`
- 2 `A`: `nix/darwin/base.nix`, `nix/darwin/default/homebrew.nix`
- 8 `D`: `plugins/homebrew/homebrew`, `plugins/homebrew/Brewfile.erb`, `plugins/homebrew_core/homebrew_core`, `plugins/xcode/xcode`, `plugins/xcode/Brewfile`, `plugins/xcode/XcodeBrewfile`, `environments/all/Brewfile`, `environments/default/Brewfile`

Commit succeeds, GPG-signed, no `Co-Authored-By` trailer.

---

## Task 2: README updates

Substantial. New "For the nix-darwin slice" sub-block; Background paragraph adds nix-darwin scope; Profiles section gains a "Darwin configurations" subsection; `all`-layer parenthetical extends; Backout section expands.

**Files:**

- Modify: `nix/README.md`

- [ ] **Step 1: Locate insertion points**

```bash
grep -n '^For the brew-formulas slice' nix/README.md
grep -n '^## Background' nix/README.md
grep -n '^### Public profiles and layers' nix/README.md
grep -n '^## Backout' nix/README.md
```

Expected: the brew-formulas sub-block is the most recent; the new sub-block goes after its item 5 and before `The same shape applies to future slices`.

- [ ] **Step 2: Insert the "For the nix-darwin slice" sub-block**

In `nix/README.md`, find where the brew-formulas slice's item 5 ends (around the `bat`/`ripgrep` demo-package note ending with `…ordinary \`home.packages\` entries.`). Immediately AFTER that paragraph and BEFORE the line beginning `The same shape applies to future slices`, insert this block:

```markdown
For the nix-darwin slice (homebrew + system-level state move into
nix-darwin; bash plugins retire):

1. **Bootstrap nix-darwin on each macOS machine** (one-time). The first
   `./apply` after this slice detects `darwin-rebuild` is absent and
   bootstraps automatically (sudo required; the framework's keep-alive
   covers it). If running outside `./apply`:

       sudo nix run nix-darwin -- switch --flake "$PWD/nix#default@aarch64-darwin"

   Subsequent applies use `sudo darwin-rebuild switch --flake …`
   automatically via the nix plugin.

2. **Update your private flake** to add your own darwin module if you
   have private casks/mas/brews. Add a `darwin.nix` (or whatever name)
   to your private repo:

       # ./darwin.nix
       { ... }: {
         homebrew = {
           casks = [
             # …your private casks…
           ];
           masApps = {
             # …your private mas apps by App Store ID…
           };
           brews = [
             # …escape-hatched formulas from custom taps, etc…
           ];
         };
       }

   Then wire it into your private flake's `darwinConfigurations`:

       darwinConfigurations."<profile>@<system>" = public.lib.mkDarwin {
         inherit system;
         modules = [
           public.darwinModules.default
           ./darwin.nix
         ];
       };

3. **Delete your private `custom_environments/<env>/Brewfile`** entries
   that you've migrated. `homebrew.onActivation.cleanup = "uninstall"`
   removes brews/casks not declared anywhere, so leaving stale Brewfile
   content while ALSO declaring it in nix-darwin is redundant but safe.

4. **The `chshAndEtcShells` activation from slice 6 is gone.** nix-darwin's
   `users.users.<name>.shell` + `environment.shells` handle login-shell
   selection declaratively. No marker file; no interactive prompt. The
   `~/.shells-chsh.hm-migrated` marker on existing machines is harmless
   leftover state; you can `rm` it if you want.

5. **Xcode license** is accepted automatically via
   `system.activationScripts.xcodeLicense`. The Xcode app itself
   installs via `homebrew.masApps.Xcode = 497799835;` in
   `nix/darwin/base.nix`.

6. **Set iTerm's font** to "MesloLGS Nerd Font" (or another Nerd Font)
   once after the cask installs: iTerm → Settings → Profiles → Text →
   Font. This fixes the placeholder glyph in starship's prompt.

```

(Note the trailing blank line.)

- [ ] **Step 3: Refresh the Background paragraph**

Find the `So far this manages:` sentence in `## Background`. Append before the period of the final clause:

```
; and a system-level layer via nix-darwin managing brew casks (including a Nerd Font for starship), mas-installed apps (including Xcode), the login-shell declaration, and Xcode license acceptance
```

- [ ] **Step 4: Add "Darwin configurations" subsection under Profiles**

After the existing `### Public profiles and layers` content and before `### Private profiles`, add a new subsection:

```markdown
### Darwin configurations (macOS system layer)

In addition to home-manager (user-level), this flake exposes
`darwinConfigurations.<profile>@<system>` outputs (system-level, macOS-only)
via nix-darwin. The active profile selects which module from
`nix/darwin/<profile>/` is included alongside the universal `nix/darwin/base.nix`.

Currently only `default` has a darwin module (`nix/darwin/default/homebrew.nix`).
The `agent` profile is Linux-only and has no darwin counterpart.

System-level concerns owned by nix-darwin (not home-manager):

- Homebrew casks, mas apps, and escape-hatched brews — `homebrew.{casks,masApps,brews}`
- Login shell declaration — `users.users.<name>.shell` + `environment.shells`
- System PATH baseline including `/opt/homebrew/{bin,sbin}` — `environment.systemPath`
- Xcode license acceptance — `system.activationScripts.xcodeLicense`
- Nix daemon enabled at system level — `nix.enable`

nix-darwin activations are sudo-required and managed by the `nix` plugin
(macOS-only branch). On a fresh machine the plugin auto-bootstraps via
`sudo nix run nix-darwin -- switch …`; on subsequent applies it uses
`sudo darwin-rebuild switch …`.
```

- [ ] **Step 5: Refresh the `all`-layer parenthetical**

Find the bullet beginning `- \`all\` — always included via \`mkHome\`;`. Append to its parenthetical the system-layer scope:

```
…AND a system-level layer via nix-darwin managing brew casks (a Nerd Font included), mas apps (including Xcode), the login shell declaration, and Xcode license acceptance)
```

(The parenthetical was getting long even before this slice; consider whether to leave it as one block or break the bullet into multiple lines. Implementer's call.)

- [ ] **Step 6: Expand the Backout section**

Find the `## Backout` section. Add a new bullet covering nix-darwin:

```markdown
- **Remove nix-darwin entirely:** more involved than home-manager rollback.
  - `sudo darwin-rebuild --rollback` reverts to the previous nix-darwin generation but doesn't uninstall.
  - To fully uninstall: `sudo /nix/var/nix/profiles/system/sw/bin/darwin-uninstaller`. This removes `/etc/static/` symlinks and the system profile; it does NOT touch your installed casks/mas (manage those via brew directly).
  - `git revert` of this slice's commits restores the bash plugins (homebrew/homebrew_core/xcode) but does NOT revert nix-darwin's system-state changes. Manual `/etc/passwd`/`/etc/shells` cleanup may be needed.
```

- [ ] **Step 7: Verify the changes**

```bash
grep -n 'For the nix-darwin slice' nix/README.md
grep -n 'a system-level layer via nix-darwin' nix/README.md
grep -n '^### Darwin configurations' nix/README.md
grep -n 'sudo darwin-rebuild --rollback' nix/README.md
echo "=== fence balance ==="
grep -c '^```' nix/README.md
```

Expected: each grep returns at least one match; fence count is 0 or even.

- [ ] **Step 8: Commit**

```bash
git add nix/README.md
git -c gpg.program="$(which gpg)" commit -m "docs(nix): document nix-darwin slice + private-env migration + backout"
git log --oneline -3
```

Expected: commit succeeds. Top commits: this docs commit + the feat commit + earlier spec/plan commits.

---

## Task 3: End-to-end verification (throwaway override + Linux container)

No commits.

**Files:** none committed.

- [ ] **Step 1: Throwaway private-flake darwin override (macOS)**

```bash
mkdir -p custom_environments/throwaway/nix
cat > custom_environments/throwaway/nix/flake.nix <<'EOF'
{
  description = "Throwaway test profile (darwin homebrew additive)";

  inputs = {
    public.url = "github:ianwremmel/dotfiles?dir=nix";
    nixpkgs.follows      = "public/nixpkgs";
    home-manager.follows = "public/home-manager";
    nix-darwin.follows   = "public/nix-darwin";
  };

  outputs = { self, public, ... }:
    let
      host = import (public + "/host.nix");
      supportedSystems = [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ];
      darwinSystems    = [ "aarch64-darwin" "x86_64-darwin" ];

      mkHomeConfig = system: public.lib.mkHome {
        inherit system;
        inherit (host) username;
        modules = [ public.homeModules.default ];
      };

      mkDarwinConfig = system: public.lib.mkDarwin {
        inherit system;
        modules = [
          public.darwinModules.default
          ./throwaway-darwin.nix
        ];
      };
    in {
      homeConfigurations = builtins.listToAttrs (map
        (system: { name = system; value = mkHomeConfig system; })
        supportedSystems);

      darwinConfigurations = builtins.listToAttrs (map
        (system: { name = system; value = mkDarwinConfig system; })
        darwinSystems);
    };
}
EOF

cat > custom_environments/throwaway/nix/throwaway-darwin.nix <<'EOF'
{ ... }: {
  # Add a small additional cask to verify private-flake additivity.
  # `monodraw` is a harmless ASCII-art editor; small download.
  homebrew.casks = [ "monodraw" ];
}
EOF

( cd custom_environments/throwaway/nix \
    && git init -q \
    && git add . \
    && git -c user.email=t@e -c user.name=t -c commit.gpgsign=false commit -q -m init )

( cd custom_environments/throwaway/nix \
    && nix --extra-experimental-features 'nix-command flakes' flake lock \
        --override-input public "path:$OLDPWD/nix" )

DOTFILES_ENVIRONMENT=throwaway DOTFILES_ROOT_DIR="$PWD" bash -c '
  set -euo pipefail
  source framework/logging
  source plugins/nix/nix
  dotfiles_nix_apply
' 2>&1 | tail -15

echo "=== throwaway cask installed ==="
brew list --cask | grep monodraw && echo "monodraw: yes (correct)" || echo "monodraw: NO (additivity broken)"

echo "=== public-layer casks still present ==="
brew list --cask | grep -E '^(docker|firefox|font-meslo-lg-nerd-font)$' | head -3
```

Expected: throwaway activation succeeds; monodraw installs; public-layer casks (docker, firefox, MesloLGS Nerd Font) all still present. Additivity verified.

- [ ] **Step 2: Tear down**

```bash
rm -rf custom_environments/throwaway

DOTFILES_ENVIRONMENT=default DOTFILES_ROOT_DIR="$PWD" bash -c '
  set -euo pipefail
  source framework/logging
  source plugins/nix/nix
  dotfiles_nix_apply
' 2>&1 | tail -10

echo "=== monodraw uninstalled (cleanup = uninstall) ==="
brew list --cask | grep monodraw && echo "monodraw: still present (BUG)" || echo "monodraw: gone (correct)"

echo "=== public-layer casks still present ==="
brew list --cask | grep -E '^(docker|firefox|font-meslo-lg-nerd-font)$' | head -3

echo "=== working tree clean ==="
git status --porcelain
```

Expected: monodraw is uninstalled by the `cleanup = "uninstall"` policy when it's no longer declared. Public casks intact. Working tree clean.

- [ ] **Step 3: Linux container verification (aarch64-linux, agent profile)**

```bash
docker run --rm --platform linux/arm64 -v "$PWD":/src:ro ubuntu:24.04 bash -c '
  set -euo pipefail
  apt-get update -qq && apt-get install -y -qq curl xz-utils ca-certificates git gnupg sudo locales >/dev/null
  locale-gen en_US.UTF-8 >/dev/null 2>&1
  cp -r /src /dotfiles
  cd /dotfiles
  install -m 0600 /dev/null "$HOME/.dotfilesrc"
  echo "DOTFILES_ENVIRONMENT=agent" > "$HOME/.dotfilesrc"
  ./apply 2>&1 | tail -15

  echo "=== nix-darwin NOT invoked on Linux ==="
  ls /run/current-system 2>&1 | head -1 || echo "(no /run/current-system — correct; Linux skips nix-darwin)"
  ! grep -q "nix-darwin" /tmp/apply.log 2>/dev/null && echo "(no nix-darwin invocation logged)"

  echo "=== home-manager still activated ==="
  ls -l "$HOME/.nix-profile/bin/git" 2>&1 | head -1
  bash -lic "git --version" 2>&1 | head -1

  echo "=== no Brewfiles on Linux ==="
  ls environments/all/Brewfile environments/default/Brewfile 2>&1 | head -2 || echo "(correct: Brewfiles gone)"
'
```

Expected: container runs the Linux branch of `./apply` (only the nix plugin); home-manager activates; nix-darwin never invoked (the `uname -s = "Darwin"` check short-circuits). git is on PATH via nix. No Brewfile errors.

- [ ] **Step 4: Final state check**

```bash
git log --oneline master..nix-darwin | head -10
git status --porcelain
echo ""
echo "=== nix-darwin generation present ==="
ls -l /run/current-system 2>&1 | head -1
echo ""
echo "=== homebrew declarations applied ==="
echo "Casks: $(brew list --cask | wc -l) installed (expected ~27 with MesloLGS Nerd Font)"
echo "Mas:   $(mas list | wc -l) installed (expected ~5: Xcode + Magnet + Slack + Byword + Tailscale)"
echo "Brews (escape-hatched): $(brew list --formula | wc -l) installed (expected: 4 = bash + bash-completion@2 + watchman + argo, plus transitive deps)"
echo ""
echo "=== bash plugins fully retired ==="
ls plugins/homebrew plugins/homebrew_core plugins/xcode 2>&1 | head -3
```

Expected: branch has slice commits on top of prior stack. Working tree clean. nix-darwin's current-system symlink exists. Declared cask/mas/brew counts match. All three bash plugins gone.

---

## Self-review (completed by plan author)

- **Spec coverage:**
  - Decision 1 (mega-slice): Task 1 atomic commit covers all 9 sub-areas ✓
  - Decision 2 (nix-darwin + home-manager coexist): plugins/nix/nix runs both sequentially ✓
  - Decision 3 (`darwinConfigurations` only for `default` profile): `darwinProfiles = [ "default" ];` in Step 5 ✓
  - Decision 4 (`onActivation.cleanup = "uninstall"`): Step 3 (base.nix) ✓
  - Decision 5 (`bash` + `bash-completion@2` in `homebrew.brews`): Step 3 includes both ✓
  - Decision 6 (`font-meslo-lg-nerd-font` cask): Step 3 includes it ✓
  - Decision 7 (chsh migration to declarative): Steps 3 (base.nix `users.users` + `environment.shells`) + 8 (remove chshAndEtcShells from shells.nix) ✓
  - Decision 8 (Xcode license → `system.activationScripts`): Step 3 (base.nix) + Step 13 (delete plugin) ✓
  - Decision 9 (framework/compat brew bootstrap stays): plan doesn't modify framework/compat ✓
  - Decision 10 (framework/customize fallbacks stay): same ✓
  - Decision 11 (firstrun deferred): plan doesn't touch environments/all/firstrun or framework/firstrun ✓
  - Decision 12 (no work-specific values): Brewfile content migrated is from public Brewfiles only; README pattern-based ✓
  - Architecture deletions (plugins + Brewfiles): Steps 11-14 ✓
  - `nix/flake.nix` changes: Steps 5-6 ✓
  - `plugins/nix/nix` changes: Step 9 ✓
  - `shells.nix` cleanup (brewPathSetup + chshAndEtcShells): Steps 7-8 ✓
  - `apply` cleanup (-B flag): Step 10 ✓
  - README updates: Task 2 ✓
  - Throwaway + Linux container verification: Task 3 ✓

- **Placeholder scan:** every step has concrete commands or code. No TBDs. The "if X fails do Y" guidance for Step 15 (nix-darwin option drift) and Step 16 (sudo interactivity) is concrete fallback handling, not placeholders.

- **Type/name consistency:**
  - `darwinModules.{base,default}`, `lib.mkDarwin`, `darwinConfigurations.<profile>@<system>` — consistent throughout.
  - `homebrew.casks` (list-typed), `homebrew.masApps` (attrset), `homebrew.brews` (list-typed) — consistent.
  - `system.activationScripts.xcodeLicense` — consistent.
  - `users.users.${username}.shell`, `environment.shells` — consistent.
  - `darwinProfiles = [ "default" ]` (separate from `publicProfiles`) — consistent.

- **Atomicity:** Task 1 is one commit (5 modified + 2 added + 8 deleted = 15 files). Task 2 is one commit (1 file). Task 3 has no commits. Total: 2 feat/docs commits on top of the spec + plan docs commits.
