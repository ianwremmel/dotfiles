# Nix Shells Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate the `shells` plugin (chsh + `/etc/shells`) and all 22 rsync-managed shell-config files into home-manager: `programs.bash`, `programs.zsh`, `home.file.".inputrc"`, plus two activation scripts (legacy-backup migration + chsh).

**Architecture:** `nix/profiles/all/default.nix` is split into per-feature submodules (`bat.nix`, `git.nix`, `gpg.nix`) in a behavior-preserving prep commit, then a new `shells.nix` is added in the same atomic commit that deletes `plugins/shells/` and the 22 rsync sources. Shell content goes into typed home-manager options where available (`programs.{bash,zsh}.shellAliases`, `home.sessionVariables`, `programs.bash.history*`, `programs.zsh.history`) and into `*Extra` text options where logic is required. The chsh activation runs once per machine, marker-gated, interactive-tty-aware (skips on container builds).

**Tech Stack:** Bash 5, Nix flakes, home-manager (`programs.bash`, `programs.zsh`, `home.file`, `home.sessionVariables`, `lib.hm.dag.entryBefore`), zsh + bash, readline (`.inputrc`).

---

## Notes for the executor

- **Reference spec:** `docs/superpowers/specs/2026-05-25-nix-shells-design.md`.
- **No automated test framework.** "Tests" are verification commands with expected output. Observe failing state → implement → observe passing state → commit.
- **Branch:** work is on `nix-shells`. Branch stacks on `nix-commit-signing` (PR #65) → `nix-git` (PR #64) → `nix-profiles` (PR #63) → `nix-cross-platform` (PR #62) → `master`. **Do NOT merge anything** without explicit user approval.
- **Stacking machinery** (assumed working from prior slices): `homeModules.{base,all,default,agent}`, `lib.mkHome`, `homeConfigurations."<profile>@<system>"`, profile-module layering, `--override-input public path:…` private-flake idiom, `home.activation.*` style migrations, `nix/host.nix` (untracked) with `{ username; profile; }`.
- **Sandbox disable required for:** `nix` (talks to the daemon), `./apply`, `git commit` (gpg signing), `chsh`, `sudo tee /etc/shells`, modifying `~/.{bash*,zsh*,profile,inputrc}*` or `~/.{bash_profile,zshrc}.d/`. Use `dangerouslyDisableSandbox: true`. If `nix` isn't on PATH, prepend: `source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh`.
- **Run commands from repo root** (`/Users/ian/projects/dotfiles`) unless noted.
- **Pre-existing local state assumed:**
  - `nix/host.nix` = `{ username = "ian"; profile = "default"; }`, untracked.
  - `~/.dotfilesrc` contains `DOTFILES_ENVIRONMENT=default`.
  - All 22 source files exist as real files (rsync'd from `environments/all/home/`).
  - `~/.shell-config.hm-migrated` and `~/.shells-chsh.hm-migrated` markers do NOT exist.
  - Current login shell is `/opt/homebrew/bin/zsh` (brew zsh, not the system default).
  - `/etc/shells` contains `/opt/homebrew/bin/zsh` (added by the old plugin); does NOT contain `~/.nix-profile/bin/zsh` yet.
- **No work-specific values** in any committed file. Work signing keys, work emails, enterprise hosts, language-version PATH additions, work-tooling init — all stay in the user's private `custom_environments/<env>/` repo.
- **Conventional commits**, NO `Co-Authored-By: Claude` / `Generated with Claude Code` trailers.
- **Testing pattern from prior slices:** direct plugin invocation (`source plugins/nix/nix; dotfiles_nix_apply`) rather than full `./apply` — exercises home-manager activation without rerunning unrelated framework plugins.
- **Verbatim source content from all 22 files** is included as a "Source files reference" section at the END of this plan. Step 6 of Task 2 instructs you to paste each source's content into the right Nix block; the reference section gives you the bytes.

---

## Task 1: Refactor — split `nix/profiles/all/default.nix` into per-feature modules

**Behavior-preserving prep commit.** Splits the existing monolithic `nix/profiles/all/default.nix` into per-feature submodules so the shells migration in Task 2 lands in its own focused file. After this task, `default.nix` is just an `imports` list. The activated home-manager generation must be byte-identical to before (no behavior change).

**Files:**

- Create: `nix/profiles/all/bat.nix`
- Create: `nix/profiles/all/git.nix`
- Create: `nix/profiles/all/gpg.nix`
- Modify (replace): `nix/profiles/all/default.nix` — becomes the imports list.

- [ ] **Step 1: Capture pre-refactor activated generation for diff comparison**

Run (sandbox disabled):
```bash
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
PRE_OUT=$(mktemp -d)/result
nix --extra-experimental-features 'nix-command flakes' build \
  "path:$PWD/nix#homeConfigurations.\"default@$(nix --extra-experimental-features 'nix-command flakes' eval --impure --raw --expr builtins.currentSystem)\".activationPackage" \
  --out-link "$PRE_OUT"
echo "PRE_OUT=$PRE_OUT"
ls -la "$PRE_OUT/home-files/" | head -20
sha256sum "$PRE_OUT/home-files/.config/git/config" "$PRE_OUT/home-files/.gnupg/gpg.conf" "$PRE_OUT/home-files/.gnupg/gpg-agent.conf" "$PRE_OUT/home-files/.config/bat/config" 2>&1
```
Save the SHA-256 lines. Step 7 compares against them.

- [ ] **Step 2: Read the current `nix/profiles/all/default.nix`**

Run: `cat nix/profiles/all/default.nix | head -60; echo '---'; wc -l nix/profiles/all/default.nix`
Expected: ~150 lines containing `programs.bat`, `programs.git`, `programs.gpg`, `services.gpg-agent`, `migrateLegacyGitConfig`, `migrateLegacyGnupgConfig`.

- [ ] **Step 3: Create `nix/profiles/all/bat.nix`** (extract the `programs.bat` block)

```nix
{ ... }: {
  programs.bat = {
    enable = true;          # installs bat (the package half of the slice)
    config.theme = "ansi";  # writes ~/.config/bat/config (the dotfile half)
  };
}
```

- [ ] **Step 4: Create `nix/profiles/all/git.nix`** (extract `programs.git` + `migrateLegacyGitConfig`)

```nix
{ lib, ... }: {
  programs.git = {
    enable = true;

    # Preserves `[include] path = .gitconfig.custom` from both source
    # .gitconfigs so user-managed local overrides keep working.
    includes = [ { path = "~/.gitconfig.custom"; } ];

    # `settings` replaces the older `aliases` + `extraConfig` options
    # (renamed in home-manager; the old names emit a deprecation warning).
    settings = {
      alias = {
        autosquash = "!GIT_SEQUENCE_EDITOR=true git rebase -i --autosquash";
        fixup      = "commit --fixup";
        pfl        = "push --force-with-lease";
      };

      branch = {
        sort = "-committerdate";
        main.rebase = true;
        master.rebase = true;
      };

      color = {
        ui = "auto";
        branch = { current = "yellow reverse"; local = "yellow"; remote = "green"; };
        diff   = { frag = "magenta bold"; meta = "yellow bold"; new = "green bold"; old = "red bold"; };
        status = { added = "yellow"; changed = "green"; untracked = "cyan"; };
      };

      core = {
        attributesfile    = "~/.gitattributes";
        excludesfile      = "~/.gitignore";
        precomposeunicode = false;
        trustctime        = false;
        whitespace        = "space-before-tab,indent-with-non-tab,trailing-space";
      };

      diff = {
        algorithm       = "histogram";
        indentHeuristic = true;
        renames         = "copies";
      };

      init.defaultBranch = "main";

      merge = {
        conflictstyle = "zdiff3";
        keepbackup    = false;
        log           = true;
        tool          = "opendiff";
      };

      push.default = "upstream";

      rebase = {
        autoStash  = true;
        updateRefs = true;
      };

      rerere = {
        autoupdate = true;
        enabled    = 1;
      };
    };
  };

  home.activation.migrateLegacyGitConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # One-time migration from Slice 1: move pre-migration ~/.gitconfig aside
    # so it stops shadowing the home-manager-managed ~/.config/git/config.
    # The marker file makes this idempotent — necessary because before the
    # commit-signing slice, the commit_signing plugin ran *before* nix on
    # macOS and would recreate ~/.gitconfig with signing fields, which
    # without the marker would cause the guard to re-move the file every
    # apply. commit_signing is now retired, but the marker guard remains so
    # machines that already migrated in Slice 1 don't re-trigger the
    # backup logic on subsequent applies.
    if [ -f "$HOME/.gitconfig" ] \
         && [ ! -L "$HOME/.gitconfig" ] \
         && [ ! -e "$HOME/.gitconfig.hm-migrated" ]; then
      run mv "$HOME/.gitconfig" "$HOME/.gitconfig.legacy-backup"
      run touch "$HOME/.gitconfig.hm-migrated"
      # Use bare echo (not verboseEcho) so this one-time event is visible in
      # a normal ./apply run without requiring DOTFILES_DEBUG / $VERBOSE.
      echo "Moved legacy ~/.gitconfig → ~/.gitconfig.legacy-backup (one-time migration)"
    fi
  '';
}
```

- [ ] **Step 5: Create `nix/profiles/all/gpg.nix`** (extract `programs.gpg` + `services.gpg-agent` + `migrateLegacyGnupgConfig`)

```nix
{ lib, pkgs, ... }: {
  # ~/.gnupg/gpg.conf
  programs.gpg = {
    enable = true;  # also installs pkgs.gnupg into the profile.
    settings = {
      auto-key-retrieve = true;
      no-emit-version   = true;
    };
  };

  # ~/.gnupg/gpg-agent.conf — pinentry is per-OS; cache TTLs match the old
  # plugin's prior behavior (10-minute default, 2-hour max).
  services.gpg-agent = {
    enable = true;
    pinentry.package =
      if pkgs.stdenv.isDarwin then pkgs.pinentry_mac
      else                         pkgs.pinentry-tty;
    defaultCacheTtl = 600;
    maxCacheTtl     = 7200;
  };

  # Note: this uses entryBefore [ "checkLinkTargets" ] rather than
  # entryAfter [ "writeBoundary" ] (which the migrateLegacyGitConfig in
  # git.nix uses). checkLinkTargets runs *before* writeBoundary and aborts
  # if it finds a real file where a managed symlink should go — and
  # programs.gpg / services.gpg-agent place managed symlinks at
  # ~/.gnupg/gpg.conf and ~/.gnupg/gpg-agent.conf. So the legacy real files
  # must be moved aside before checkLinkTargets runs, not after
  # writeBoundary. The Slice 1 git migration didn't face this because
  # home-manager symlinks at ~/.config/git/config, not ~/.gitconfig — no
  # target-path collision.
  home.activation.migrateLegacyGnupgConfig = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    if [ ! -e "$HOME/.gnupg.hm-migrated" ]; then
      for f in gpg.conf gpg-agent.conf; do
        if [ -f "$HOME/.gnupg/$f" ] && [ ! -L "$HOME/.gnupg/$f" ]; then
          run mv -n "$HOME/.gnupg/$f" "$HOME/.gnupg/$f.legacy-backup"
          echo "Moved legacy ~/.gnupg/$f → ~/.gnupg/$f.legacy-backup (one-time migration)"
        fi
      done
      run touch "$HOME/.gnupg.hm-migrated"
    fi
  '';
}
```

- [ ] **Step 6: Replace `nix/profiles/all/default.nix` with the imports list**

```nix
{ ... }: {
  # `all` is composed into every config by `lib.mkHome`, regardless of which
  # profile is active or whether a private flake overlays on top — anything
  # *every* machine should get goes here. Split into per-feature submodules
  # so each feature stays focused and reviewable.
  imports = [
    ./bat.nix
    ./git.nix
    ./gpg.nix
  ];
}
```

- [ ] **Step 7: Verify the refactor is behavior-preserving**

Run (sandbox disabled):
```bash
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
nix-instantiate --parse nix/profiles/all/default.nix >/dev/null && echo "default parses"
nix-instantiate --parse nix/profiles/all/bat.nix >/dev/null && echo "bat parses"
nix-instantiate --parse nix/profiles/all/git.nix >/dev/null && echo "git parses"
nix-instantiate --parse nix/profiles/all/gpg.nix >/dev/null && echo "gpg parses"

# Build the post-refactor generation
POST_OUT=$(mktemp -d)/result
nix --extra-experimental-features 'nix-command flakes' build \
  "path:$PWD/nix#homeConfigurations.\"default@$(nix --extra-experimental-features 'nix-command flakes' eval --impure --raw --expr builtins.currentSystem)\".activationPackage" \
  --out-link "$POST_OUT"

# Compare critical files byte-by-byte with the pre-refactor generation
echo "=== post-refactor hashes ==="
sha256sum "$POST_OUT/home-files/.config/git/config" "$POST_OUT/home-files/.gnupg/gpg.conf" "$POST_OUT/home-files/.gnupg/gpg-agent.conf" "$POST_OUT/home-files/.config/bat/config"
echo "=== compare with Step 1's PRE_OUT hashes ==="
```
Expected: all four parse; SHA-256 hashes of each file MATCH the Step 1 captures. If any file's hash differs, the refactor introduced unintended behavior change — re-check the extracted content matches what was in the original `default.nix` before commit.

- [ ] **Step 8: Activate to confirm the running system is unchanged**

Run (sandbox disabled):
```bash
DOTFILES_ENVIRONMENT=default DOTFILES_ROOT_DIR="$PWD" bash -c '
  set -euo pipefail
  source framework/logging
  source plugins/nix/nix
  dotfiles_nix_apply
' 2>&1 | tail -10
echo "=== verify still-functional sanity checks ==="
git config --get alias.fixup
gpg --version | head -1
bat --version | head -1
```
Expected: activation succeeds with exit 0. `git config --get alias.fixup` returns `commit --fixup`. gpg + bat versions report unchanged. No "Moved legacy …" output (both markers already exist from prior slices, scripts short-circuit).

- [ ] **Step 9: Commit the refactor**

```bash
git add nix/profiles/all/default.nix nix/profiles/all/bat.nix nix/profiles/all/git.nix nix/profiles/all/gpg.nix
git status --porcelain
git -c gpg.program="$(which gpg)" commit -m "refactor(nix): split all/default.nix into per-feature modules"
git log --oneline -1
```
Expected: `git status --porcelain` shows `M nix/profiles/all/default.nix` + 3 `A` lines for the new submodules. Commit succeeds, GPG-signed. Conventional commit message, no `Co-Authored-By` trailer.

---

## Task 2: Atomic shells migration

Adds `nix/profiles/all/shells.nix` (programs.bash + programs.zsh + home.file.".inputrc" + 2 activation scripts), updates `default.nix` to import it, deletes `plugins/shells/`, deletes 21 rsync sources (7 top-level shell files + 5 `.bash_profile.d/*` + 9 `.zshrc.d/*`) under `environments/all/home/`. Atomic — every change in one commit so the repo never sits in a partially-migrated state.

**Files:**

- Create: `nix/profiles/all/shells.nix`
- Modify: `nix/profiles/all/default.nix` — append `./shells.nix` to the imports list.
- Delete: `plugins/shells/shells` (and the empty `plugins/shells/` directory).
- Delete: `environments/all/home/.bashrc`, `.bash_profile`, `.profile`, `.bash_profile.d/{aliases,completion,exports,path,prompt}` (+ now-empty `.bash_profile.d/` dir), `.zshenv`, `.zprofile`, `.zshrc`, `.zshrc.d/{aliases.zsh,omz_keybindings.zsh,omz_ls-colors.zsh,omz_nvm.sh,omz_termsupport.zsh,prompt.zsh,rbenv.zsh,ssh.zsh,ulimit.zsh}` (+ now-empty `.zshrc.d/` dir), `.inputrc`.

- [ ] **Step 1: Capture pre-flight state for later regression checks**

Run (sandbox disabled):
```bash
echo "=== home dotfiles (real files vs symlinks) ==="
for f in .bashrc .bash_profile .profile .zshrc .zshenv .zprofile .inputrc; do
  if [ -e "$HOME/$f" ]; then
    [ -L "$HOME/$f" ] && echo "$f: symlink → $(readlink "$HOME/$f")" || echo "$f: real file ($(wc -l < "$HOME/$f") lines)"
  else
    echo "$f: absent"
  fi
done
echo ""
echo "=== modular dirs ==="
ls -la "$HOME/.bash_profile.d/" 2>&1 | head -10
ls -la "$HOME/.zshrc.d/" 2>&1 | head -15
echo ""
echo "=== login shell + /etc/shells ==="
dscl . -read "/Users/$USER" UserShell
grep -E 'zsh|bash' /etc/shells
echo ""
echo "=== aliases + env vars ==="
zsh -ic 'alias psgrep; alias xo; alias https; alias r2; echo EDITOR=$EDITOR; echo GPG_TTY=$GPG_TTY; echo AWS_VAULT_KEYCHAIN_NAME=$AWS_VAULT_KEYCHAIN_NAME' 2>&1 | grep -v 'gitstatus'
bash -lic 'alias psgrep; type ssh-add; ulimit -n; echo EDITOR=$EDITOR' 2>&1
echo ""
echo "=== markers (should both be absent) ==="
ls -la "$HOME/.shell-config.hm-migrated" "$HOME/.shells-chsh.hm-migrated" 2>&1
```
Save the output. Step 11 compares against it for sanity.
Expected: all 7 top-level files real (not symlinks); `.bash_profile.d/` has 5 files; `.zshrc.d/` has 9 files; login shell = `/opt/homebrew/bin/zsh`; `/etc/shells` contains `/opt/homebrew/bin/zsh`; zsh aliases return their defs; bash aliases return their defs; both markers absent.

- [ ] **Step 2: Read all 22 source files (one-shot batch)**

Run: `for f in environments/all/home/.bashrc environments/all/home/.bash_profile environments/all/home/.profile environments/all/home/.zshenv environments/all/home/.zprofile environments/all/home/.zshrc environments/all/home/.inputrc environments/all/home/.bash_profile.d/* environments/all/home/.zshrc.d/*; do echo "=== $f ==="; cat "$f"; done | head -200`
Expected: see verbatim content of each file. The "Source files reference" section at the END of this plan reproduces this content for reference; the implementer uses that to know what to paste into the Nix blocks in Step 5.

- [ ] **Step 3: Update `nix/profiles/all/default.nix` to import `./shells.nix`**

Replace the file with:

```nix
{ ... }: {
  imports = [
    ./bat.nix
    ./git.nix
    ./gpg.nix
    ./shells.nix
  ];
}
```

- [ ] **Step 4: Create `nix/profiles/all/shells.nix` — outer scaffolding**

Create the file with the following Nix structure. Steps 5a–5d fill in the per-block content (the verbatim shell content from the source files in the "Source files reference" section).

The full file is large. Build it in this order: programs.bash, programs.zsh, home.file.".inputrc", migrateLegacyShellConfig, chshAndEtcShells.

```nix
{ lib, pkgs, ... }:

let
  # Shared static aliases. Both shells get them as typed attrsets via
  # programs.{bash,zsh}.shellAliases. Conditional / OS-specific aliases
  # (md5sum, sha1sum, pbcopy/pbpaste on non-Darwin) live in
  # programs.bash.profileExtra/bashrcExtra since the typed option can't
  # express conditionals.
  sharedAliases = {
    psgrep = "ps -A | grep -v /Applications | grep -v /System | grep";
    xo     = "xargs open";
    https  = "http --default-scheme=https";
    r2     = "env /usr/bin/arch -x86_64";
  };

  # Brew-prefix-and-PATH setup shared between programs.bash.profileExtra
  # and programs.zsh.profileExtra. Both files used to have a near-identical
  # block (.bash_profile.d/path and .zprofile); DRY them with a let-binding.
  brewPathSetup = ''
    export PATH

    # Add Homebrew. We probably don't have much of a path at this point, so,
    # start with the brew command, but fall back to its well-known locations
    # if it can't be found on $PATH.
    if command -v brew > /dev/null 2>&1; then
      BREW_PREFIX=$(brew --prefix)
    elif command -v /opt/homebrew/bin/brew > /dev/null 2>&1; then
      BREW_PREFIX=$(/opt/homebrew/bin/brew --prefix)
    elif command -v /usr/local/bin/brew > /dev/null 2>&1; then
      BREW_PREFIX=$(/usr/local/bin/brew --prefix)
    else
      BREW_PREFIX=""
    fi

    if [ "$BREW_PREFIX" != "" ]; then
      # Put brew binaries at the start of PATH so they override system binaries
      PATH=$BREW_PREFIX/bin:$BREW_PREFIX/sbin:$PATH

      # Put all of the gnubin binaries in front of system binaries
      for FILE in "$BREW_PREFIX"/opt/*/libexec/gnubin; do
        PATH=$FILE:$PATH
      done
    fi

    # Add Java
    if command -v /usr/libexec/java_home > /dev/null 2>&1 ; then
      PATH=$PATH:$(/usr/libexec/java_home)/bin
    fi

    # User-private bin
    PATH="$HOME/bin:$PATH"

    # Native Claude binary
    PATH="$HOME/.local/bin:$PATH"
  '';
in {
  # ---------- Cross-shell environment vars (apply to both bash and zsh) ----------
  home.sessionVariables = {
    EDITOR                  = "vim";
    GIT_EDITOR              = "vim";
    AWS_VAULT_KEYCHAIN_NAME = "login";
    LANG                    = "en_US.UTF-8";
    LC_ALL                  = "en_US.UTF-8";
    CLICOLOR                = "1";
    LSCOLORS                = "Gxfxcxdxbxegedabagacad";
    LS_COLORS               = "Gxfxcxdxbxegedabagacad";
  };

  # ---------- ~/.inputrc ----------
  home.file.".inputrc".text = ''
    # PASTE VERBATIM CONTENTS OF environments/all/home/.inputrc HERE
    # (see "Source files reference" section in the plan; 40 lines)
  '';

  # ---------- Bash ----------
  programs.bash = {
    enable = true;

    shellAliases = sharedAliases // {
      # Bash-additional static aliases (from .bash_profile.d/aliases that
      # don't have shell-side conditionals).
      sudo   = "sudo ";
      grep   = "/usr/bin/grep --color=auto";
      nopush = ''git add . && git commit --allow-empty -m "#no-push" -n && git push && git reset HEAD^'';
      ubuntu = "docker run -it --rm -v $(pwd):/workspace --workdir=/workspace ubuntu bash";
    };

    # History (from .bash_profile.d/exports HISTFILESIZE/HISTSIZE/HISTCONTROL/HISTIGNORE).
    historyControl   = [ "ignoreboth" ];
    historyIgnore    = [ "ls" "pwd" "date" "git reset HEAD^" ];
    # Empty HISTFILESIZE/HISTSIZE = unlimited in bash. Home-manager's typed
    # historyFileSize and historySize don't have an "unlimited" sentinel,
    # so we set them via initExtra below.

    # .bash_profile body (excluding the load_profile_file function and the
    # FILES loop — those are gone since nothing lives in .bash_profile.d/
    # anymore). Includes: ulimit, ssh-add, nvm-load, histappend, shopt
    # autocd/globstar, rbenv. Plus PATH from .bash_profile.d/path. Plus the
    # remaining shell-logic exports from .bash_profile.d/exports (HISTFILESIZE,
    # HISTSIZE empty for unlimited; GPG_TTY).
    profileExtra = brewPathSetup + ''

      # ---- from .bash_profile body ----

      # Set a reasonable ulimit because Apple
      ulimit -n 8192

      # Load SSH keys
      ssh-add --apple-use-keychain > /dev/null 2> /dev/null

      # ---- from .bash_profile.d/exports — shell-logic exports ----

      # bash empty = unlimited; home-manager's typed historySize/historyFileSize
      # don't have an unlimited sentinel so we set them here.
      export HISTFILESIZE=
      export HISTSIZE=

      # GPG_TTY needs shell logic; can't live in home.sessionVariables.
      export GPG_TTY
      GPG_TTY=$(tty)

      # ---- conditional macOS-only aliases (from .bash_profile.d/aliases) ----

      # OS X has no `md5sum`, so use `md5` as a fallback
      command -v md5sum > /dev/null || alias md5sum='md5'
      # macOS has no `sha1sum`, so use `shasum` as a fallback
      command -v sha1sum > /dev/null || alias sha1sum="shasum"

      # Non-Darwin clipboard aliases
      if [ "$(uname)" != 'Darwin' ]; then
        alias pbcopy='xsel --clipboard --input'
        alias pbpaste='xsel --clipboard --output'
      fi

      # ---- non-interactive tail of .bash_profile (interactive guard below) ----

      # Setup nvm and node so prompt can use it
      if [ -d "$HOME/.nvm" ]; then
        source "$HOME/.nvm/nvm.sh"
      fi

      # If not interactive, stop further processing
      [ -z "$PS1" ] && return

      # Append rather than overwrite bash history
      shopt -s histappend

      # Enable some Bash 4 features when possible:
      # * `autocd` — `**/qux` enters `./foo/bar/baz/qux`
      # * Recursive globbing — `echo **/*.txt`
      for option in autocd globstar; do
        shopt -s "$option" 2> /dev/null
      done

      # Configure rbenv
      if command -v rbenv >/dev/null 2>&1; then
        eval "$(rbenv init -)"
      fi
    '';

    # .bashrc + .bash_profile.d/{completion,prompt}. Interactive content;
    # lands in ~/.bashrc.
    bashrcExtra = ''
      # macOS handles bash_profile and bashrc differently from Linux. .bashrc
      # may be sourced where .bash_profile wasn't; defer in that case.
      # The home-manager-generated .bash_profile sources .bashrc, so we guard
      # against double-sourcing in this slice via $BASH_PROFILE_SOURCED if
      # needed. (For now, the home-manager-generated .bash_profile auto-
      # includes bashrc content; this block is for raw `bash -i` invocations
      # where only .bashrc is read.)
      [ -n "$PS1" ] || return

      # ---- from .bash_profile.d/completion (115 lines) ----
      # PASTE VERBATIM CONTENTS OF environments/all/home/.bash_profile.d/completion
      # HERE (see "Source files reference" section in the plan; 115 lines).

      # ---- from .bash_profile.d/prompt (58 lines) ----
      # PASTE VERBATIM CONTENTS OF environments/all/home/.bash_profile.d/prompt
      # HERE (see "Source files reference" section in the plan; 58 lines).
    '';
  };

  # ---------- Zsh ----------
  programs.zsh = {
    enable = true;

    shellAliases = sharedAliases;  # Just the 4 shared aliases; no zsh-specific ones.

    # History settings (from .zshrc body).
    history = {
      size         = 10000;
      save         = 10000;
      path         = "$HOME/.zsh_history";
      extended     = false;
      ignoreAllDups = true;
      share        = true;  # shares history across terminals (sharehistory)
      append       = true;  # appends, doesn't overwrite (appendhistory)
    };

    # Anything from .zshenv with shell logic (GPG_TTY). The static .zshenv
    # vars live in home.sessionVariables above.
    envExtra = ''
      # Avoid issues with gpg as installed via Homebrew.
      # https://stackoverflow.com/a/42265848/96656
      export GPG_TTY
      GPG_TTY=$(tty)
    '';

    # .zprofile content (PATH setup; macOS-specific brew + Java + ~/bin).
    profileExtra = brewPathSetup;

    # Powerlevel10k instant prompt — MUST be at the very top of .zshrc.
    # The original .zshrc gates this on ~/powerlevel10k existing; preserved.
    # Slice 6 (prompt) will replace this when p10k moves to home-manager.
    initExtraFirst = ''
      if [ -d "$HOME/powerlevel10k" ]; then
        # Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
        # Initialization code that may require console input (password prompts, [y/n]
        # confirmations, etc.) must go above this block; everything else may go below.
        if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
          source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
        fi
      fi
    '';

    # Body of .zshrc + all 9 .zshrc.d/* files in alphabetical order
    # (matches the original `for FILE ($HOME/.zshrc.d/*)` glob order).
    # Each block is commented with its origin file.
    initExtra = ''
      # ---- from .zshrc body ----

      # extendedglob: support **/* globs
      setopt extendedglob
      # error on unmatched globs
      setopt nomatch
      # unbreak git caret selector caused by 'nomatch'
      setopt no_nomatch
      # Don't beep
      unsetopt autocd beep notify
      # emacs keybindings (turns out that's what I've been using for years)
      bindkey -e

      # ---- from .zshrc.d/aliases.zsh (handled via shellAliases above) ----

      # ---- from .zshrc.d/omz_keybindings.zsh (69 lines) ----
      # PASTE VERBATIM CONTENTS OF environments/all/home/.zshrc.d/omz_keybindings.zsh
      # HERE (see "Source files reference" section).

      # ---- from .zshrc.d/omz_ls-colors.zsh (40 lines) ----
      # PASTE VERBATIM CONTENTS OF environments/all/home/.zshrc.d/omz_ls-colors.zsh
      # HERE.

      # ---- from .zshrc.d/omz_nvm.sh (8 lines; retired in Slice 7) ----
      # Set NVM_DIR if it isn't already defined
      [[ -z "$NVM_DIR" ]] && export NVM_DIR="$HOME/.nvm"
      # Load nvm if it exists
      [[ -f "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"

      # ---- from .zshrc.d/omz_termsupport.zsh (86 lines) ----
      # PASTE VERBATIM CONTENTS OF environments/all/home/.zshrc.d/omz_termsupport.zsh
      # HERE.

      # ---- from .zshrc.d/prompt.zsh (52 lines; replaced in Slice 6) ----
      # PASTE VERBATIM CONTENTS OF environments/all/home/.zshrc.d/prompt.zsh
      # HERE.

      # ---- from .zshrc.d/rbenv.zsh (5 lines) ----
      if command -v rbenv >/dev/null 2>&1; then
        eval "$(rbenv init --no-rehash - zsh)"
      fi

      # ---- from .zshrc.d/ssh.zsh (3 lines) ----
      ssh-add --apple-use-keychain > /dev/null 2> /dev/null

      # ---- from .zshrc.d/ulimit.zsh (4 lines) ----
      # Set a reasonable ulimit because Apple
      ulimit -n 8192

      # ---- p10k tail of .zshrc (replaced in Slice 6) ----
      if [ -d "$HOME/powerlevel10k" ]; then
        source ~/powerlevel10k/powerlevel10k.zsh-theme
      fi

      # To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
      [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
    '';
  };

  # ---------- Activation: legacy-backup migration ----------
  home.activation.migrateLegacyShellConfig = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    # One-time migration: move pre-existing rsync'd shell-config files
    # (and the .bash_profile.d/ and .zshrc.d/ modular-config dirs) aside so
    # programs.bash / programs.zsh / home.file can take over those paths.
    # Marker is a sibling to ~/ (not inside any 0700-mode tree).
    if [ ! -e "$HOME/.shell-config.hm-migrated" ]; then
      # Top-level files
      for f in .zshrc .zshenv .zprofile .bash_profile .bashrc .profile .inputrc; do
        if [ -f "$HOME/$f" ] && [ ! -L "$HOME/$f" ]; then
          run mv -n "$HOME/$f" "$HOME/$f.legacy-backup"
          echo "Moved legacy ~/$f → ~/$f.legacy-backup (one-time migration)"
        fi
      done
      # Modular-config directories: move the whole dir aside.
      for d in .bash_profile.d .zshrc.d; do
        if [ -d "$HOME/$d" ] && [ ! -L "$HOME/$d" ]; then
          run mv -n "$HOME/$d" "$HOME/$d.legacy-backup"
          echo "Moved legacy ~/$d/ → ~/$d.legacy-backup/ (one-time migration)"
        fi
      done
      run touch "$HOME/.shell-config.hm-migrated"
    fi
  '';

  # ---------- Activation: chsh + /etc/shells ----------
  home.activation.chshAndEtcShells = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    # One-time chsh + /etc/shells setup replacing the retired `shells` plugin.
    # Marker-gated. Interactive-tty-aware (so non-interactive container
    # builds skip cleanly). Sudo prompt goes to the apply terminal.
    if [ -e "$HOME/.shells-chsh.hm-migrated" ]; then
      return 0
    fi
    if [ ! -t 0 ]; then
      echo "chshAndEtcShells: non-interactive shell, skipping (run ./apply in a terminal to complete chsh setup)"
      return 0
    fi

    target="$HOME/.nix-profile/bin/zsh"
    if [ ! -x "$target" ]; then
      echo "chshAndEtcShells: $target missing; programs.zsh.enable should have installed it. Skipping."
      return 0
    fi

    # Register in /etc/shells if absent
    if ! grep -qxF "$target" /etc/shells; then
      echo "chshAndEtcShells: adding $target to /etc/shells (sudo prompt incoming)"
      echo "$target" | sudo tee -a /etc/shells >/dev/null
    fi

    # chsh only if current login shell is a system default OR brew's zsh
    # (preserves explicit user choices)
    current="$(dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}' || getent passwd "$USER" | cut -d: -f7)"
    case "$current" in
      /bin/zsh|/bin/bash|/opt/homebrew/bin/zsh|/usr/local/bin/zsh)
        echo "chshAndEtcShells: changing login shell from $current to $target"
        chsh -s "$target"
        ;;
      *)
        echo "chshAndEtcShells: login shell already user-managed ($current); leaving alone"
        ;;
    esac

    run touch "$HOME/.shells-chsh.hm-migrated"
  '';
}
```

**Important:** the `# PASTE VERBATIM CONTENTS OF …` comments in the above are NOT placeholders — Step 5 instructs you to do the actual pasting. The "Source files reference" section at the END of this plan provides the verbatim content of each referenced file.

Nix-string-escape gotchas to watch for when pasting:
- `${VAR}` → `''${VAR}` (Nix interprets `${}` as antiquotation)
- `''` (two single quotes) inside a `''...''` block → `'''` (escapes one)
- Backslashes are fine; no escaping needed.

- [ ] **Step 5a: Paste `.inputrc` content into the `home.file.".inputrc".text` block**

Open `nix/profiles/all/shells.nix` and replace the `# PASTE VERBATIM CONTENTS OF environments/all/home/.inputrc HERE` comment with the file's contents (see "Source files reference" → `.inputrc`). No `${VAR}` substitutions; paste as-is.

- [ ] **Step 5b: Paste `.bash_profile.d/completion` and `.bash_profile.d/prompt` content into the `programs.bash.bashrcExtra` block**

Replace the two `# PASTE VERBATIM …` comments inside `bashrcExtra`. The `completion` file has no `${VAR}` substitutions. The `prompt` file uses `\$(prompt_git)` etc. inside double-quoted PS1 — verify the literal `$` characters get escaped to `''$` (or use single quotes around PS1 if the Nix-escape syntax becomes ugly).

- [ ] **Step 5c: Paste `.zshrc.d/omz_keybindings.zsh`, `.zshrc.d/omz_ls-colors.zsh`, `.zshrc.d/omz_termsupport.zsh`, `.zshrc.d/prompt.zsh` content into the `programs.zsh.initExtra` block**

Replace the four `# PASTE VERBATIM …` comments. Critical escape: the termsupport script uses `${langinfo[CODESET]}`, `${#str}`, `$str[i]`, `$opts[(r)-P]`, etc. — every `${...}` and `$(...)` MUST be escaped as `''${...}` and `''$(...)` (or use a different Nix string syntax to avoid escaping every variable).

**Pragmatic alternative:** if escaping every variable in the 86-line termsupport script becomes error-prone, drop the verbatim approach for that file and use `(builtins.readFile ./omz_termsupport.zsh)` instead — copy the file into `nix/profiles/all/` as a sibling and reference it. This preserves byte-identical content without Nix-string escaping. Decide during implementation; either approach is acceptable.

- [ ] **Step 6: Delete the `shells` plugin**

```bash
git rm plugins/shells/shells
rmdir plugins/shells 2>/dev/null || true
ls -d plugins/shells 2>&1 | head -1
```
Expected: `ls: cannot access 'plugins/shells'`. `git status --porcelain plugins/shells/` shows one `D` line.

- [ ] **Step 7: Delete the 21 rsync source files (plus 2 now-empty `.d/` dirs)**

```bash
git rm environments/all/home/.bashrc environments/all/home/.bash_profile environments/all/home/.profile
git rm environments/all/home/.zshenv environments/all/home/.zprofile environments/all/home/.zshrc
git rm environments/all/home/.inputrc
git rm environments/all/home/.bash_profile.d/aliases environments/all/home/.bash_profile.d/completion environments/all/home/.bash_profile.d/exports environments/all/home/.bash_profile.d/path environments/all/home/.bash_profile.d/prompt
git rm environments/all/home/.zshrc.d/aliases.zsh environments/all/home/.zshrc.d/omz_keybindings.zsh environments/all/home/.zshrc.d/omz_ls-colors.zsh environments/all/home/.zshrc.d/omz_nvm.sh environments/all/home/.zshrc.d/omz_termsupport.zsh environments/all/home/.zshrc.d/prompt.zsh environments/all/home/.zshrc.d/rbenv.zsh environments/all/home/.zshrc.d/ssh.zsh environments/all/home/.zshrc.d/ulimit.zsh

rmdir environments/all/home/.bash_profile.d environments/all/home/.zshrc.d 2>/dev/null || true
ls -d environments/all/home/.bash_profile.d environments/all/home/.zshrc.d 2>&1 | head -2
```
Expected: both directories gone. `git status --porcelain` shows 21 `D` lines (no `M` for the now-removed `.d/` directories themselves, since git tracks files).

- [ ] **Step 8: Verify Nix files parse and the flake still evaluates**

Run (sandbox disabled):
```bash
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
nix-instantiate --parse nix/profiles/all/default.nix >/dev/null && echo "default parses"
nix-instantiate --parse nix/profiles/all/shells.nix >/dev/null && echo "shells parses"

nix --extra-experimental-features 'nix-command flakes' eval \
  "path:$PWD/nix#homeModules.all" --apply 'p: builtins.typeOf p' --raw; echo
nix --extra-experimental-features 'nix-command flakes' eval \
  "path:$PWD/nix#homeConfigurations.\"default@$(nix --extra-experimental-features 'nix-command flakes' eval --impure --raw --expr builtins.currentSystem)\".activationPackage.outPath" --raw; echo
```
Expected: both parses; `path` for the module; an `/nix/store/…-home-manager-generation` path for the activation. If parsing errors mention `${...}` antiquotation, you have an un-escaped `$` in pasted shell content — fix it.

- [ ] **Step 9: Run the plugin end-to-end (triggers both activations)**

Run (sandbox disabled — full home-manager activation; expect interactive sudo + chsh prompts):
```bash
DOTFILES_ENVIRONMENT=default DOTFILES_ROOT_DIR="$PWD" bash -c '
  set -euo pipefail
  source framework/logging
  source plugins/nix/nix
  dotfiles_nix_apply
' 2>&1 | tee /tmp/claude/shells-activation.log | tail -40
```
Expected (in `/tmp/claude/shells-activation.log`):
- `Resolved profile: default` log line.
- `Building public profile 'default' for aarch64-darwin`.
- `Activating home-manager configuration`.
- **9 "Moved legacy …" lines** (7 top-level files + 2 dirs), exactly once.
- **`chshAndEtcShells: adding /Users/ian/.nix-profile/bin/zsh to /etc/shells (sudo prompt incoming)`** — followed by interactive sudo prompt.
- **`chshAndEtcShells: changing login shell from /opt/homebrew/bin/zsh to /Users/ian/.nix-profile/bin/zsh`** — followed by interactive chsh password prompt.
- Exit 0.

If sudo or chsh times out (e.g., harness can't interact), the activation will fail. In that case, run the prompt+chsh manually:
```bash
echo "$HOME/.nix-profile/bin/zsh" | sudo tee -a /etc/shells
chsh -s "$HOME/.nix-profile/bin/zsh"
touch "$HOME/.shells-chsh.hm-migrated"
```
…and re-run the activation. The legacy-backup migration MUST succeed regardless.

- [ ] **Step 10: Verify both markers and 9 backups**

Run:
```bash
echo "=== markers ==="
ls -l "$HOME/.shell-config.hm-migrated" "$HOME/.shells-chsh.hm-migrated"
echo ""
echo "=== top-level backups (7) ==="
ls -l "$HOME/.bashrc.legacy-backup" "$HOME/.bash_profile.legacy-backup" "$HOME/.profile.legacy-backup" "$HOME/.zshrc.legacy-backup" "$HOME/.zshenv.legacy-backup" "$HOME/.zprofile.legacy-backup" "$HOME/.inputrc.legacy-backup"
echo ""
echo "=== dir backups (2) ==="
ls -ld "$HOME/.bash_profile.d.legacy-backup" "$HOME/.zshrc.d.legacy-backup"
ls "$HOME/.bash_profile.d.legacy-backup/" "$HOME/.zshrc.d.legacy-backup/"
```
Expected: 2 markers exist; 7 `.legacy-backup` files exist; 2 `.legacy-backup` directories exist with their original contents (5 files + 9 files = 14 inner files preserved verbatim).

- [ ] **Step 11: Verify home-manager now owns the 7 top-level files**

Run:
```bash
echo "=== should all be symlinks into /nix/store/…-home-manager-files/ ==="
for f in .bashrc .bash_profile .zshrc .zshenv .zprofile .inputrc; do
  ls -l "$HOME/$f"
done
echo ""
echo "=== ~/.profile should be ABSENT (dropped, not migrated) ==="
[ -e "$HOME/.profile" ] && echo "WARN: .profile still exists" || echo "absent (correct)"
echo ""
echo "=== old .d/ dirs should be absent (moved to .legacy-backup) ==="
[ -d "$HOME/.bash_profile.d" ] && echo "WARN: ~/.bash_profile.d/ still present" || echo "absent (correct)"
[ -d "$HOME/.zshrc.d" ] && echo "WARN: ~/.zshrc.d/ still present" || echo "absent (correct)"
```
Expected: 6 files symlinked into `/nix/store/…-home-manager-files/`; `~/.profile` absent (we dropped it; the Step 10 backup preserved the legacy comment file); both old `.d/` dirs absent.

- [ ] **Step 12: Verify chsh and /etc/shells**

Run (sandbox disabled):
```bash
echo "=== /etc/shells contains nix's zsh ==="
grep -F "$HOME/.nix-profile/bin/zsh" /etc/shells || echo "MISSING"
echo ""
echo "=== login shell is nix's zsh ==="
dscl . -read "/Users/$USER" UserShell
echo ""
echo "=== readlink resolves to the nix store ==="
readlink "$HOME/.nix-profile/bin/zsh"
```
Expected: `/etc/shells` contains the path (resolved to `/Users/$USER/.nix-profile/bin/zsh`); `dscl` returns `UserShell: /Users/$USER/.nix-profile/bin/zsh`; readlink shows `/nix/store/…-zsh-*/bin/zsh`.

- [ ] **Step 13: Verify zsh content (aliases, env vars, history, keybindings)**

Run (sandbox disabled):
```bash
zsh -ic 'alias psgrep; alias xo; alias https; alias r2; echo EDITOR=$EDITOR; echo GPG_TTY=$GPG_TTY; echo AWS_VAULT_KEYCHAIN_NAME=$AWS_VAULT_KEYCHAIN_NAME; echo HISTSIZE=$HISTSIZE; echo SAVEHIST=$SAVEHIST; bindkey -L emacs | head -3' 2>&1 | grep -v 'gitstatus'
```
Expected: 4 alias definitions present; EDITOR=vim; GPG_TTY=/dev/ttys… (or similar); AWS_VAULT_KEYCHAIN_NAME=login; HISTSIZE=10000; SAVEHIST=10000; emacs keybindings active.

- [ ] **Step 14: Verify bash content**

Run (sandbox disabled):
```bash
bash -lic 'alias psgrep; alias sudo; alias grep; alias nopush; type ssh-add; ulimit -n; shopt globstar; echo EDITOR=$EDITOR; echo HISTCONTROL=$HISTCONTROL; echo LANG=$LANG; type prompt_git; echo PS1="$PS1"' 2>&1 | head -20
```
Expected: aliases for psgrep, sudo, grep, nopush present; ssh-add available; ulimit 8192; globstar on; EDITOR=vim; HISTCONTROL=ignoreboth; LANG=en_US.UTF-8; `prompt_git` is a function; PS1 includes git/node prompt segments.

- [ ] **Step 15: Verify the p10k integration still loads (no error in a fresh zsh)**

Run:
```bash
echo "=== fresh zsh, no error output ==="
zsh -ic 'echo $POWERLEVEL9K_INSTANT_PROMPT' 2>&1 | head -5
echo ""
echo "=== ~/.p10k.zsh still sourced if present ==="
[ -f "$HOME/.p10k.zsh" ] && echo "~/.p10k.zsh present ($(wc -l < $HOME/.p10k.zsh) lines)" || echo "~/.p10k.zsh absent — fine in this slice"
```
Expected: no error output; if p10k is present, instant-prompt variable is set or empty (depending on p10k internals).

- [ ] **Step 16: Verify cross-slice intact**

Run:
```bash
git config --get alias.fixup            # Slice 1
git config --get user.signingkey         # Slice 4 commit-signing
git config --get commit.gpgsign          # Slice 4
git --version | head -1                  # Slice 4's nixpkgs bump → 2.54.0
gpg --version | head -1                  # Slice 4
bat --version | head -1                  # Slice 1's bat
```
Expected: `commit --fixup`, `C9DA1EE9CCF21B28`, `true`, `git version 2.54.0`, `gpg (GnuPG) 2.5.x` (or similar), `bat 0.x`.

- [ ] **Step 17: Activation idempotency check**

Run (sandbox disabled):
```bash
DOTFILES_ENVIRONMENT=default DOTFILES_ROOT_DIR="$PWD" bash -c '
  source framework/logging
  source plugins/nix/nix
  dotfiles_nix_apply
' 2>&1 | grep -E 'Moved legacy|chshAndEtcShells:' || echo "(no migration/chsh output — guards short-circuited, as expected)"
```
Expected: `(no migration/chsh output — guards short-circuited, as expected)`. Both markers prevent re-firing.

- [ ] **Step 18: Confirm host-state files untouched**

Run:
```bash
cat nix/host.nix
git status --porcelain nix/host.nix
```
Expected: `nix/host.nix` still `{ username = "ian"; profile = "default"; }`, still untracked.

- [ ] **Step 19: Commit the atomic migration**

Run:
```bash
git add nix/profiles/all/default.nix nix/profiles/all/shells.nix
# Also stage any sibling files copied in by Step 5c (if you used builtins.readFile for omz_termsupport.zsh)
git status --porcelain
git -c gpg.program="$(which gpg)" commit -m "feat(nix): migrate shells plugin + shell-config to programs.{bash,zsh}"
git log --oneline -1
```
Expected: porcelain shows `M nix/profiles/all/default.nix` + `A nix/profiles/all/shells.nix` + `D plugins/shells/shells` + 21 `D environments/all/home/...` lines. Commit succeeds, GPG-signed. No `Co-Authored-By` trailer.

---

## Task 3: README updates

Three changes to `nix/README.md`, parallel to the structure used by Slices 1, 4, and 5.

**Files:**

- Modify: `nix/README.md`

- [ ] **Step 1: Locate insertion points**

Run:
```bash
grep -n '^For the commit-signing slice' nix/README.md
grep -n '^## Background\|^## Install' nix/README.md
grep -n '^### Public profiles and layers' nix/README.md
grep -n 'currently `bat`' nix/README.md
```
Expected: `For the commit-signing slice` is the most recent sub-block (added in Slice 4); the new "For the shells slice" block goes immediately AFTER it, BEFORE the `The same shape applies to future slices` paragraph.

- [ ] **Step 2: Insert the "For the shells slice" sub-block**

In `nix/README.md`, immediately AFTER the `## 3. **First \`./apply\` after this slice** runs the … keyring … is never touched.` paragraph of the commit-signing block, and BEFORE the line beginning `The same shape applies to future slices`, insert this block:

```markdown
For the shells slice (`shells` plugin retired; all rsync-managed shell
dotfiles migrated; `programs.bash`, `programs.zsh`, `home.file.".inputrc"`
and two activation scripts take over):

1. **Update your private flake** to append work-specific shell content
   (extra PATH entries, env vars, tooling init shell hooks) via the
   `lines`-typed `*Extra` options. These CONCATENATE across layers — no
   `lib.mkForce` needed:

       { lib, pkgs, ... }: {
         programs.zsh.initExtra = ''
           # work-specific zsh init: extra PATH entries, tooling init, …
         '';
         programs.bash.profileExtra = ''
           # work-specific bash profile init: same idea
         '';
         home.sessionVariables = {
           # work-specific cross-shell env vars (no overlap with public ones)
         };
       }

2. **Delete the now-orphaned rsync sources** from your private repo:

       git rm custom_environments/<env>/home/.zshrc \
              custom_environments/<env>/home/.zshenv \
              custom_environments/<env>/home/.zprofile \
              custom_environments/<env>/home/.bash_profile \
              custom_environments/<env>/home/.bashrc \
              custom_environments/<env>/home/.profile \
              custom_environments/<env>/home/.inputrc
       git rm -r custom_environments/<env>/home/.zshrc.d \
                 custom_environments/<env>/home/.bash_profile.d
       git commit -m "remove rsync'd shell config (now managed via nix)"

3. **First `./apply` after this slice** runs the `migrateLegacyShellConfig`
   activation, which moves any pre-existing real shell dotfiles aside to
   `.legacy-backup` siblings once, AND `chshAndEtcShells` activation, which
   registers `~/.nix-profile/bin/zsh` in `/etc/shells` and chshes the user
   to it (interactive sudo + password prompts in the apply terminal). The
   second activation is interactive-tty-aware — it skips on container
   builds and leaves its marker absent so a later interactive apply can
   complete it. You can `rm ~/.{zshrc,zshenv,zprofile,bash_profile,bashrc,
   profile,inputrc}.legacy-backup` and `rm -rf ~/.{zshrc,bash_profile}.d.
   legacy-backup` whenever you're satisfied with the migration.

```

(Note the trailing blank line — it separates this sub-block from the next paragraph.)

- [ ] **Step 3: Refresh the Background paragraph**

Find the `So far this manages:` sentence in `## Background`. Replace with:

```
So far this manages: `bat` (shared in the `all` layer); `ripgrep` (in the `default` profile); the full git config (aliases, body, identity, includes) via `programs.git` plus a one-time activation that retires the legacy rsync-managed `~/.gitconfig`; commit signing — `programs.gpg` + `services.gpg-agent` with per-OS pinentry (`pinentry-mac` on macOS, `pinentry-tty` on Linux), `programs.git.settings.user.signingkey` + `commit.gpgsign` in the personal profile, and a one-time activation that retires the old plugin-written `~/.gnupg/*.conf`; and shell config — bash and zsh via `programs.bash` + `programs.zsh` (with the prior `.zshrc.d/` and `.bash_profile.d/` modular content folded into the relevant typed options), `.inputrc` via `home.file`, and a one-time activation that retires the rsync-managed shell dotfiles plus the `shells` plugin's chsh / /etc/shells logic.
```

- [ ] **Step 4: Refresh the `all`-layer parenthetical under `### Public profiles and layers`**

Find the bullet beginning `- \`all\` — always included via \`mkHome\`;` and its parenthetical. Replace the parenthetical with:

```
(currently `bat`, the shared git config — aliases, body, includes — via `programs.git`, GPG/agent setup with per-OS pinentry: `pinentry-mac` on macOS, `pinentry-tty` on Linux, AND bash + zsh via `programs.bash` + `programs.zsh` plus `.inputrc` via `home.file`)
```

- [ ] **Step 5: Verify the changes**

Run:
```bash
grep -n 'For the shells slice' nix/README.md
grep -n 'shell config — bash and zsh' nix/README.md
grep -n 'AND bash + zsh via' nix/README.md
echo "=== fence balance (must be even or zero — README uses indented blocks) ==="
grep -c '^```' nix/README.md
```
Expected: each grep returns exactly one match; fence count is even (probably 0 since the README uses indented blocks throughout).

- [ ] **Step 6: Commit**

```bash
git add nix/README.md
git -c gpg.program="$(which gpg)" commit -m "docs(nix): document shells slice + private-env migration"
git log --oneline -3
```
Expected: commit succeeds, GPG-signed. The three most recent commits are this docs commit, the shells migration, and the refactor.

---

## Task 4: End-to-end verification (throwaway private override + Linux container)

Verification only — no commits. Confirms (a) a private profile can append shell content with concatenation (not override), (b) Linux activation in an aarch64-linux container produces a working bash/zsh setup with the chsh activation correctly skipping.

**Files:** none committed (throwaway scaffold lives under gitignored `custom_environments/`).

- [ ] **Step 1: Throwaway private-profile additive override (macOS)**

```bash
mkdir -p custom_environments/throwaway/nix
cat > custom_environments/throwaway/nix/flake.nix <<'EOF'
{
  description = "Throwaway test profile (shell-content additive override)";

  inputs = {
    public.url = "github:ianwremmel/dotfiles?dir=nix";
    nixpkgs.follows      = "public/nixpkgs";
    home-manager.follows = "public/home-manager";
  };

  outputs = { self, public, ... }:
    let
      host = import (public + "/host.nix");
      supportedSystems = [ "aarch64-darwin" "x86_64-linux" "aarch64-linux" ];
      mkConfig = system: public.lib.mkHome {
        inherit system;
        inherit (host) username;
        modules = [
          public.homeModules.default
          ./throwaway.nix
        ];
      };
    in {
      homeConfigurations = builtins.listToAttrs (map
        (system: { name = system; value = mkConfig system; })
        supportedSystems);
    };
}
EOF

cat > custom_environments/throwaway/nix/throwaway.nix <<'EOF'
{ lib, ... }: {
  # Concatenated, not lib.mkForce — verify lines-typed options stack.
  programs.zsh.initExtra      = "export ZSH_WORK_TEST=zsh_throwaway";
  programs.bash.profileExtra  = "export BASH_WORK_TEST=bash_throwaway";
  home.sessionVariables = {
    SHARED_WORK_TEST = "throwaway";
  };
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
' 2>&1 | tail -10

echo "=== zsh sees both public and private content ==="
zsh -ic 'echo ZSH_WORK_TEST=$ZSH_WORK_TEST; echo SHARED_WORK_TEST=$SHARED_WORK_TEST; alias psgrep' 2>&1 | grep -v gitstatus
echo ""
echo "=== bash sees both public and private content ==="
bash -lic 'echo BASH_WORK_TEST=$BASH_WORK_TEST; echo SHARED_WORK_TEST=$SHARED_WORK_TEST; alias psgrep' 2>&1
```
Expected: throwaway activation succeeds. `zsh -ic` shows `ZSH_WORK_TEST=zsh_throwaway`, `SHARED_WORK_TEST=throwaway`, and the `psgrep` alias from `all`. `bash -lic` shows `BASH_WORK_TEST=bash_throwaway`, `SHARED_WORK_TEST=throwaway`, and the `psgrep` alias. Concatenation worked.

- [ ] **Step 2: Tear down**

```bash
rm -rf custom_environments/throwaway

DOTFILES_ENVIRONMENT=default DOTFILES_ROOT_DIR="$PWD" bash -c '
  set -euo pipefail
  source framework/logging
  source plugins/nix/nix
  dotfiles_nix_apply
' 2>&1 | tail -8

echo "=== private vars gone ==="
zsh -ic 'echo ZSH_WORK_TEST=$ZSH_WORK_TEST' 2>&1 | grep -v gitstatus
bash -lic 'echo BASH_WORK_TEST=$BASH_WORK_TEST' 2>&1
echo ""
echo "=== working tree clean? ==="
git status --porcelain
```
Expected: private vars empty; `git status --porcelain` clean (custom_environments is gitignored).

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
  echo "=== home dotfiles state ==="
  for f in .bashrc .bash_profile .zshrc .zshenv .zprofile .inputrc; do
    if [ -L "$HOME/$f" ]; then
      echo "$f: symlink (managed)"
    elif [ -e "$HOME/$f" ]; then
      echo "$f: real file (BUG)"
    else
      echo "$f: absent"
    fi
  done
  echo ""
  echo "=== chsh activation should have skipped (non-tty) ==="
  ls -la "$HOME/.shells-chsh.hm-migrated" 2>&1 | head -1
  ls -la "$HOME/.shell-config.hm-migrated" 2>&1 | head -1
  echo ""
  echo "=== bash aliases + env vars ==="
  bash -lic "alias psgrep; echo EDITOR=\$EDITOR; echo LANG=\$LANG; ulimit -n" 2>&1
  echo ""
  echo "=== zsh aliases + env vars ==="
  zsh -ic "alias psgrep; echo EDITOR=\$EDITOR; echo SAVEHIST=\$SAVEHIST" 2>&1 | grep -v gitstatus
  echo ""
  echo "=== which gpg, git, bat resolve to nix store ==="
  which gpg git bat
'
```
Expected:
- Container builds; agent profile activates.
- All 6 top-level files are symlinks (not real); `.profile` absent.
- `.shells-chsh.hm-migrated` ABSENT (chsh skipped on non-tty); `.shell-config.hm-migrated` present (legacy migration ran — though backups are empty on a clean container).
- bash and zsh aliases work; EDITOR=vim; LANG=en_US.UTF-8; ulimit reflects bash defaults (Linux doesn't have the macOS ulimit issue, so 8192 may or may not be active).
- `gpg`, `git`, `bat` all resolve into `/nix/store/`.

- [ ] **Step 4: Final state check**

```bash
git log --oneline master..nix-shells | head -6
git status --porcelain
echo "=== ~/.zshrc, ~/.bash_profile, etc. on user's mac ==="
for f in .bashrc .bash_profile .zshrc .zshenv .zprofile .inputrc; do
  ls -l "$HOME/$f"
done
echo "=== legacy backups still there ==="
ls "$HOME"/.{bashrc,bash_profile,zshrc,zshenv,zprofile,inputrc}.legacy-backup 2>&1
ls -d "$HOME"/.bash_profile.d.legacy-backup "$HOME"/.zshrc.d.legacy-backup 2>&1
```
Expected: branch contains the slice's 3 commits (refactor + feat + docs) on top of the prior stack. Working tree clean. All 6 files are home-manager symlinks. All 7 legacy-backup files exist; 2 dir backups exist.

---

## Source files reference

Verbatim content of every source file. Used during Task 2 Step 5 to paste into the right Nix block. This section is for the implementer's reference only — when you commit Task 2, none of these source files remain in the repo (they've been replaced by their home-manager translations).

### `environments/all/home/.inputrc`

```text
# Make Tab autocomplete regardless of filename case
set completion-ignore-case off

# Immediately add a trailing slash when autocompleting symlinks to directories
set mark-symlinked-directories on

# Use the text that has already been typed as the prefix for searching through
# commands (i.e. more intelligent Up/Down behavior)
"\e[B": history-search-forward
"\e[A": history-search-backward

# Do not autocomplete hidden files unless the pattern explicitly begins with a
# dot
set match-hidden-files off

# Show all autocomplete results at once
#set page-completions off

# If there are more than 200 possible completions for a word, ask to show them
# all
set completion-query-items 200

# Show extra file information when completing, like `ls -F` does
set visible-stats on

# Be more intelligent when autocompleting by also looking at the text after
# the cursor. For example, when the current line is "cd ~/src/mozil", and
# the cursor is on the "z", pressing Tab will not autocomplete it to "cd
# ~/src/mozillail", but to "cd ~/src/mozilla". (This is supported by the
# Readline used by Bash 4.)
set skip-completed-text on

# Allow UTF-8 input and output, instead of showing stuff like $'\0123\0456'
set input-meta on
set output-meta on
set convert-meta off

# Use Alt/Meta + Delete to delete the preceding word
"\e[3;3~": kill-word
```

### `environments/all/home/.bash_profile.d/completion`

```bash
#!/usr/bin/env bash

# Add tab completion for SSH hostnames based on ~/.ssh/config, ignoring
# wildcards
[ -e "$HOME/.ssh/config" ] && complete -o "default" -o "nospace" -W "$(grep "^Host" ~/.ssh/config | grep -v "[?*]" | cut -d " " -f2)" scp sftp ssh

if [ "$(uname)" == 'Darwin' ]; then
  # Add tab completion for `defaults read|write NSGlobalDomain`
  complete -W "NSGlobalDomain" defaults

  # Add `killall` tab completion for common apps
  complete -o "nospace" -W "Contacts Calendar Dock Finder Mail Safari iTunes SystemUIServer Terminal Twitter" killall
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash_bashrc and /etc/profile
# sources /etc/bash_bashrc).
if [ -f /etc/bash_completion ] && ! shopt -oq posix; then
  # shellcheck disable=SC1091
  source /etc/bash_completion
fi

# Bash completion in Home folder
if [ -d "$HOME/.bash_completion.d" ]; then
	for FILE in "$HOME/.bash_completion.d"/*
	do
    # shellcheck disable=SC1090
		source "$FILE"
	done
fi

# Homebrew bash completion
if hash brew 2>/dev/null ; then
  BREW_PREFIX=$(brew --prefix)

  if [ -f "$BREW_PREFIX/etc/bash_completion" ]; then
    # shellcheck disable=SC1090
   source "$BREW_PREFIX/etc/bash_completion"
  fi

  if [ -f "$BREW_PREFIX/share/bash-completion/bash_completion" ]; then
    # shellcheck disable=SC1090
    source "$BREW_PREFIX/share/bash-completion/bash_completion"
  fi
fi

if hash npm 2> /dev/null; then
  # shellcheck disable=SC2046 disable=SC2034 disable=SC2162

  ###-begin-npm-completion-###
  #
  # npm command completion script
  #
  # Installation: npm completion >> ~/.bashrc  (or ~/.zshrc)
  # Or, maybe: npm completion > /usr/local/etc/bash_completion.d/npm
  #

  if type complete &>/dev/null; then
    _npm_completion () {
      local words cword
      if type _get_comp_words_by_ref &>/dev/null; then
        _get_comp_words_by_ref -n = -n @ -n : -w words -i cword
      else
        cword="$COMP_CWORD"
        words=("${COMP_WORDS[@]}")
      fi

      local si="$IFS"
      # shellcheck disable=SC2207
      IFS=$'\n' COMPREPLY=($(COMP_CWORD="$cword" \
                            COMP_LINE="$COMP_LINE" \
                            COMP_POINT="$COMP_POINT" \
                            npm completion -- "${words[@]}" \
                            2>/dev/null)) || return $?
      IFS="$si"
      if type __ltrim_colon_completions &>/dev/null; then
        __ltrim_colon_completions "${words[cword]}"
      fi
    }
    complete -o default -F _npm_completion npm
  elif type compdef &>/dev/null; then
    _npm_completion() {
      local si=$IFS
      compadd -- $(COMP_CWORD=$((CURRENT-1)) \
                  COMP_LINE=$BUFFER \
                  COMP_POINT=0 \
                  npm completion -- "${words[@]}" \
                  2>/dev/null)
      IFS=$si
    }
    compdef _npm_completion npm
  elif type compctl &>/dev/null; then
    _npm_completion () {
      local cword line point words si
      read -Ac words
      read -cn cword
      # shellcheck disable=SC2219
      let cword-=1
      read -l line
      read -ln point
      si="$IFS"
      # shellcheck disable=SC2207
      IFS=$'\n' reply=($(COMP_CWORD="$cword" \
                        COMP_LINE="$line" \
                        COMP_POINT="$point" \
                        npm completion -- "${words[@]}" \
                        2>/dev/null)) || return $?
      IFS="$si"
    }
    compctl -K _npm_completion npm
  fi
  ###-end-npm-completion-###

fi
```

### `environments/all/home/.bash_profile.d/prompt`

```bash
#!/usr/bin/env bash
# @gf3's Sexy Bash Prompt, inspired by "Extravagant Zsh Prompt"
# Shamelessly copied from https://github.com/gf3/dotfiles
# Screenshot: http://i.imgur.com/s0Blh.png

# Enable color if possible
if [[ $COLORTERM = gnome-* && $TERM = xterm ]] && infocmp gnome-256color >/dev/null 2>&1; then
  export TERM='gnome-256color';
elif infocmp xterm-256color >/dev/null 2>&1; then
  export TERM='xterm-256color';
fi;

# Git status.
function prompt_git() {

  local status output flags

  status="$(command git status 2>/dev/null)"
  EXIT_CODE=$?
  # If we're not in a git repo, don't do anything
  [[ "$EXIT_CODE" != "0" ]] && return;

  output="$(echo "$status" | awk '/# Initial commit/ {print "(init)"}')"

  # Determine branch name
  [[ "$output" ]] || output="$(command git branch | perl -ne '/^\* (.*)/ && print $1')"

  # Determine flags
  flags="$(
    echo "$status" | awk 'BEGIN {r=""}
      /Changes to be committed:/        {r=r "+"}
      /Changes not staged for commit:/  {r=r "!"}
      /Untracked files:/                {r=r "?"}
      END {print r}'
  )"
  if [[ "$flags" ]]; then
    output="$output$flags"
  fi

  stashes=$(git stash list | wc -l | sed 's/ *//')
  if [[ $stashes ]]; then
    output="$output $stashes"
  fi

  echo "on $output "
}

# Node version
function prompt_node() {
  if hash node 2> /dev/null; then
    node --version
  fi
}

# shellcheck disable=SC1117
PS1="\u@\h \t \w \$(prompt_git)\$(prompt_node)\\$ "
export PS1
```

### `environments/all/home/.zshrc.d/omz_keybindings.zsh`

```bash
# shellcheck disable

# http://zsh.sourceforge.net/Doc/Release/Zsh-Line-Editor.html
# http://zsh.sourceforge.net/Doc/Release/Zsh-Line-Editor.html#Zle-Builtins
# http://zsh.sourceforge.net/Doc/Release/Zsh-Line-Editor.html#Standard-Widgets

# Make sure that the terminal is in application mode when zle is active, since
# only then values from $terminfo are valid
if (( ${+terminfo[smkx]} )) && (( ${+terminfo[rmkx]} )); then
  function zle-line-init() {
    echoti smkx
  }
  function zle-line-finish() {
    echoti rmkx
  }
  zle -N zle-line-init
  zle -N zle-line-finish
fi

bindkey -e                                            # Use emacs key bindings

bindkey '^r' history-incremental-search-backward      # [Ctrl-r] - Search backward incrementally for a specified string. The string may begin with ^ to anchor the search to the beginning of the line.

# start typing + [Up-Arrow] - fuzzy find history forward
if [[ "${terminfo[kcuu1]}" != "" ]]; then
  autoload -U up-line-or-beginning-search
  zle -N up-line-or-beginning-search
  bindkey "${terminfo[kcuu1]}" up-line-or-beginning-search
fi
# start typing + [Down-Arrow] - fuzzy find history backward
if [[ "${terminfo[kcud1]}" != "" ]]; then
  autoload -U down-line-or-beginning-search
  zle -N down-line-or-beginning-search
  bindkey "${terminfo[kcud1]}" down-line-or-beginning-search
fi

if [[ "${terminfo[khome]}" != "" ]]; then
  bindkey "${terminfo[khome]}" beginning-of-line      # [Home] - Go to beginning of line
fi
if [[ "${terminfo[kend]}" != "" ]]; then
  bindkey "${terminfo[kend]}"  end-of-line            # [End] - Go to end of line
fi

bindkey ' ' magic-space                               # [Space] - do history expansion

bindkey '^[[1;5C' forward-word                        # [Ctrl-RightArrow] - move forward one word
bindkey '^[[1;5D' backward-word                       # [Ctrl-LeftArrow] - move backward one word

if [[ "${terminfo[kcbt]}" != "" ]]; then
  bindkey "${terminfo[kcbt]}" reverse-menu-complete   # [Shift-Tab] - move through the completion menu backwards
fi

bindkey '^?' backward-delete-char                     # [Backspace] - delete backward
if [[ "${terminfo[kdch1]}" != "" ]]; then
  bindkey "${terminfo[kdch1]}" delete-char            # [Delete] - delete forward
else
  bindkey "^[[3~" delete-char
  bindkey "^[3;5~" delete-char
  bindkey "\e[3~" delete-char
fi

# Edit the current command line in $EDITOR
autoload -U edit-command-line
zle -N edit-command-line
bindkey '\C-x\C-e' edit-command-line

# file rename magick
bindkey "^[m" copy-prev-shell-word
```

### `environments/all/home/.zshrc.d/omz_ls-colors.zsh`

```bash
# shellcheck disable

# Enable ls colors
export LSCOLORS="Gxfxcxdxbxegedabagacad"

# TODO organise this chaotic logic

if [[ "$DISABLE_LS_COLORS" != "true" ]]; then
  # Find the option for using colors in ls, depending on the version
  if [[ "$OSTYPE" == netbsd* ]]; then
    # On NetBSD, test if "gls" (GNU ls) is installed (this one supports colors);
    # otherwise, leave ls as is, because NetBSD's ls doesn't support -G
    gls --color -d . &>/dev/null && alias ls='gls --color=tty'
  elif [[ "$OSTYPE" == openbsd* ]]; then
    # On OpenBSD, "gls" (ls from GNU coreutils) and "colorls" (ls from base,
    # with color and multibyte support) are available from ports.  "colorls"
    # will be installed on purpose and can't be pulled in by installing
    # coreutils, so prefer it to "gls".
    gls --color -d . &>/dev/null && alias ls='gls --color=tty'
    colorls -G -d . &>/dev/null && alias ls='colorls -G'
  elif [[ "$OSTYPE" == darwin* ]]; then
    # this is a good alias, it works by default just using $LSCOLORS
    ls -G . &>/dev/null && alias ls='ls -G'

    # only use coreutils ls if there is a dircolors customization present ($LS_COLORS or .dircolors file)
    # otherwise, gls will use the default color scheme which is ugly af
    [[ -n "$LS_COLORS" || -f "$HOME/.dircolors" ]] && gls --color -d . &>/dev/null && alias ls='gls --color=tty'
  else
    # For GNU ls, we use the default ls color theme. They can later be overwritten by themes.
    if [[ -z "$LS_COLORS" ]]; then
      (( $+commands[dircolors] )) && eval "$(dircolors -b)"
    fi

    ls --color -d . &>/dev/null && alias ls='ls --color=tty' || { ls -G . &>/dev/null && alias ls='ls -G' }

    # Take advantage of $LS_COLORS for completion as well.
    zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
  fi
fi
```

### `environments/all/home/.zshrc.d/omz_termsupport.zsh`

```bash
# shellcheck disable

# Required for $langinfo
zmodload zsh/langinfo

local function omz_urlencode() {
  emulate -L zsh
  zparseopts -D -E -a opts r m P

  local in_str=$1
  local url_str=""
  local spaces_as_plus
  if [[ -z $opts[(r)-P] ]]; then spaces_as_plus=1; fi
  local str="$in_str"

  # URLs must use UTF-8 encoding; convert str to UTF-8 if required
  local encoding=$langinfo[CODESET]
  local safe_encodings
  safe_encodings=(UTF-8 utf8 US-ASCII)
  if [[ -n $encoding && -z ${safe_encodings[(r)$encoding]} ]]; then
    str=$(echo -E "$str" | iconv -f $encoding -t UTF-8)
    if [[ $? != 0 ]]; then
      echo "Error converting string from $encoding to UTF-8" >&2
      return 1
    fi
  fi

  # Use LC_CTYPE=C to process text byte-by-byte
  local i byte ord LC_ALL=C
  export LC_ALL
  local reserved=';/?:@&=+$,'
  local mark='_.!~*''()-'
  local dont_escape="[A-Za-z0-9"
  if [[ -z $opts[(r)-r] ]]; then
    dont_escape+=$reserved
  fi
  # $mark must be last because of the "-"
  if [[ -z $opts[(r)-m] ]]; then
    dont_escape+=$mark
  fi
  dont_escape+="]"

  # Implemented to use a single printf call and avoid subshells in the loop,
  # for performance (primarily on Windows).
  local url_str=""
  for (( i = 1; i <= ${#str}; ++i )); do
    byte="$str[i]"
    if [[ "$byte" =~ "$dont_escape" ]]; then
      url_str+="$byte"
    else
      if [[ "$byte" == " " && -n $spaces_as_plus ]]; then
        url_str+="+"
      else
        ord=$(( [##16] #byte ))
        url_str+="%$ord"
      fi
    fi
  done
  echo -E "$url_str"
}

# Keep Apple Terminal.app's current working directory updated
# Based on this answer: https://superuser.com/a/315029
# With extra fixes to handle multibyte chars and non-UTF-8 locales

if [[ "$TERM_PROGRAM" == "Apple_Terminal" ]] && [[ -z "$INSIDE_EMACS" ]]; then
  # Emits the control sequence to notify Terminal.app of the cwd
  # Identifies the directory using a file: URI scheme, including
  # the host name to disambiguate local vs. remote paths.
  function update_terminalapp_cwd() {
    emulate -L zsh

    # Percent-encode the pathname.
    local URL_PATH="$(omz_urlencode -P $PWD)"
    [[ $? != 0 ]] && return 1

    # Undocumented Terminal.app-specific control sequence
    printf '\e]7;%s\a' "file://$HOST$URL_PATH"
  }

  # Use a precmd hook instead of a chpwd hook to avoid contaminating output
  precmd_functions+=(update_terminalapp_cwd)
  # Run once to get initial cwd set
  update_terminalapp_cwd
fi
```

**STRONG RECOMMENDATION:** the `omz_termsupport.zsh` file has 30+ `${...}` and `$(...)` patterns that would all need to be escaped as `''${...}` / `''$(...)` inside a Nix `''...''` string. This is error-prone. Use `builtins.readFile` instead:

1. Copy `environments/all/home/.zshrc.d/omz_termsupport.zsh` to `nix/profiles/all/omz_termsupport.zsh` (sibling to `shells.nix`) BEFORE the rsync-source deletion in Step 7.
2. In `shells.nix`'s `initExtra`, replace the `# PASTE …` comment with: `(builtins.readFile ./omz_termsupport.zsh)`.
3. Wrap it appropriately: `initExtra = (… text before …) + (builtins.readFile ./omz_termsupport.zsh) + (… text after …);`.

Apply the same `builtins.readFile` pattern to `omz_keybindings.zsh`, `omz_ls-colors.zsh`, and `prompt.zsh` if their escaping becomes burdensome.

### `environments/all/home/.zshrc.d/prompt.zsh`

```bash
# shellcheck disable

autoload -U colors && colors

function git_branch_name() {
  local ref
  ref=$(command git symbolic-ref HEAD 2> /dev/null) || \
  ref=$(command git rev-parse --short HEAD 2> /dev/null) || return 0
  echo "${ref#refs/heads/}"
}

function git_flags() {
  echo "$(command git status 2>/dev/null)" | awk 'BEGIN {r=""}
    /Changes to be committed:/        {r=r "+"}
    /Changes not staged for commit:/  {r=r "!"}
    /Untracked files:/                {r=r "?"}
    END {print r}'
}

function git_stash_count() {
  local count
  count="$(git stash list | wc -l | sed 's/ *//')"
  if [[ "$count" != "0" ]]; then
    local color
    if [[ $count -gt 5 ]]; then
      color="%{$fg_bold[red]%}"
    fi
    echo " ${color}($count)%{$reset_color%}"
  fi
}

function git_prompt_info() {
  local EXIT_CODE
  git branch > /dev/null 2>&1
  EXIT_CODE=$?

  if [[ "$EXIT_CODE" == "0" ]]; then
    echo "$(git_branch_name)$(git_flags)$(git_stash_count) "
  fi
}

if [ ! -d "$HOME/powerlevel10k" ]; then
  # Interpret prompt string after each command
  setopt PROMPT_SUBST

  local USER_AT_MACHINE="%n@%M"
  local TIMESTAMP="%T"
  local WORKING_DIRECTORY="%{$fg[cyan]%}%~%{$reset_color%}"
  local SUCCESS_INDICATOR="%(?:%{$fg_bold[green]%}➜ :%{$fg_bold[red]%}➜ )"
  PROMPT='${SUCCESS_INDICATOR} ${TIMESTAMP} ${USER_AT_MACHINE} ${WORKING_DIRECTORY} $(git_prompt_info)%# '
fi
```

(Same `builtins.readFile` recommendation as for termsupport — the `${...}` and `$(...)` content here would also benefit from being read from a sibling file rather than inlined.)

---

## Self-review (completed by plan author)

- **Spec coverage:**
  - Decisions 1–12 from the spec: all addressed.
    - 1 (scope): Tasks 1 + 2 cover plugin retirement and all 22 source files.
    - 2 (shells plugin retired): Task 2 Step 6.
    - 3 (chsh target = `~/.nix-profile/bin/zsh`): Task 2 Step 4 (chshAndEtcShells block).
    - 4 (bash full home-manager): Task 2 Step 5 (programs.bash block).
    - 5 (.zshrc.d/ + .bash_profile.d/ collapse): Task 2 Step 5 (all sub-files folded into `initExtra` / `profileExtra` / `bashrcExtra`).
    - 6 (.profile dropped): Task 2 Step 5 (not added to programs.bash); Step 7 deletes the rsync source; Step 11 verifies absent.
    - 7 (.inputrc via home.file): Task 2 Step 5a.
    - 8 (powerlevel10k stays in initExtra): Task 2 Step 5 (initExtraFirst + initExtra tail blocks).
    - 9 (NVM lazy loader stays): Task 2 Step 5 (omz_nvm.sh content inlined).
    - 10 (all content in `all`): the entire `shells.nix` lives in `nix/profiles/all/`.
    - 11 (DAG: `entryBefore checkLinkTargets`): both activation scripts use it.
    - 12 (no work-specific values in public): the README sub-block is pattern-only; no work keys, hosts, or paths appear.
  - Two activation scripts (migrateLegacyShellConfig + chshAndEtcShells): Task 2 Step 5.
  - README updates (sub-block + Background + all-layer): Task 3.
  - Throwaway + Linux container verification: Task 4.
- **Placeholder scan:** every step has concrete commands or code. The four `# PASTE VERBATIM …` markers in Task 2 Step 4's Nix template are NOT placeholders — Task 2 Step 5a/5b/5c instructs the actual paste action, and the "Source files reference" section at the end of the plan provides the verbatim content. The recommendation to use `builtins.readFile` for the `${...}`-heavy zsh files is a concrete alternative, not a TBD.
- **Type/name consistency:**
  - `programs.bash.shellAliases`, `programs.bash.history{Control,Ignore,FileSize,Size}`, `programs.bash.profileExtra`, `programs.bash.bashrcExtra` — consistent throughout.
  - `programs.zsh.shellAliases`, `programs.zsh.history.{size,save,path,extended,ignoreAllDups,share,append}`, `programs.zsh.envExtra`, `programs.zsh.profileExtra`, `programs.zsh.initExtraFirst`, `programs.zsh.initExtra` — consistent.
  - `home.file.".inputrc".text` — referenced uniformly.
  - `home.activation.{migrateLegacyShellConfig,chshAndEtcShells}` — referenced uniformly.
  - Marker filenames (`.shell-config.hm-migrated`, `.shells-chsh.hm-migrated`) — consistent.
  - `lib.hm.dag.entryBefore [ "checkLinkTargets" ]` — consistent with Slice 4's GPG migration pattern.
- **Atomicity:** Task 1 (refactor) is one commit; Task 2 (shells migration) bundles the create + 21 deletions in one commit; Task 3 (README) is one commit. 3 commits total on the slice. No mid-state where the repo could be partially migrated.
- **Cross-slice integrity check:** Task 2 Step 16 explicitly re-verifies Slices 1, 4 (git/identity, signing, GPG, bat, nixpkgs bump) still functional after the shells changes.
