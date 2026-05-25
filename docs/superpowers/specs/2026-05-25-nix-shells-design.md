# Nix Shells Slice Design

**Date:** 2026-05-25
**Status:** Draft — pending user approval
**Branch:** `nix-shells` (stacks on `nix-commit-signing` / PR #65 → `nix-git` / PR #64 → `nix-profiles` / PR #63 → `nix-cross-platform` / PR #62)

## Goal

Migrate the framework's `plugins/shells` (chsh + `/etc/shells` automation) and
all 22 rsync-managed shell-config files (`.bashrc`, `.bash_profile`,
`.profile`, `.bash_profile.d/*`, `.zshenv`, `.zprofile`, `.zshrc`,
`.zshrc.d/*`, `.inputrc`) into home-manager: `programs.bash`, `programs.zsh`,
`home.file.".inputrc"`, plus two activation scripts — one moves the legacy
rsync'd files aside; one performs the one-time `chsh` + `/etc/shells`
registration that the `shells` plugin used to do.

This is **Slice 5** in the Nix migration sequence and the largest by file
count to date. The next slices in the shell ecosystem are:

- Slice 6: prompt (`powerlevel` plugin + `.p10k.zsh`); may include a
  starship-vs-p10k decision.
- Slice 7: `nvm` + `node` plugins.

Together those three slices retire all interactive-shell automation.

## Decisions (locked)

1. **Scope: shells + base+modular shell init.** Migrate `plugins/shells`
   (retired entirely; chsh moves to an activation script) plus every
   shell-config file under `environments/all/home/` except the prompt-
   specific ones (`.p10k.zsh` stays — Slice 6 handles it). That is:
   `.bash_profile`, `.bashrc`, `.profile`, `.bash_profile.d/*` (5 files),
   `.zshenv`, `.zprofile`, `.zshrc`, `.zshrc.d/*` (9 files), `.inputrc`.
   22 files total.
2. **`shells` plugin retires.** Its chsh + `/etc/shells` automation moves
   into a new `home.activation.chshAndEtcShells` script (marker-gated,
   interactive-tty-aware, sudo-prompts-in-terminal).
3. **chsh target: `~/.nix-profile/bin/zsh`** (Nix's zsh via the stable
   `~/.nix-profile` symlink). Brew zsh stays installed for the time being
   (brew retires in a future slice); the active login shell flips to Nix's
   zsh in this slice. The symlink target rotates with nixpkgs updates, but
   the `/etc/passwd` value never changes (it stays `~/.nix-profile/bin/zsh`).
4. **Bash gets full home-manager treatment.** Bash is used for shebang
   scripts and as the login shell on some Linux systems; `programs.bash` is
   enabled with `bashrcExtra`, `profileExtra`, `shellAliases`,
   `sessionVariables`.
5. **`.zshrc.d/` and `.bash_profile.d/` collapse.** The modular-config
   directories disappear in this slice. Their content folds into the
   relevant `programs.{zsh,bash}.*` options (`shellAliases`,
   `sessionVariables`, `initExtra`, `bashrcExtra`, `profileExtra`).
   Activation moves both directories aside as `.legacy-backup` siblings.
6. **`.profile` is dropped, not migrated.** The current `.profile` is three
   lines of comment that defers to `.bash_profile`. The migration activation
   moves any pre-existing `~/.profile` to `.legacy-backup` and the new
   `programs.bash`-managed config no longer needs the `source .profile`
   line in `.bash_profile`.
7. **`.inputrc` via `home.file`.** Home-manager has no readline module.
   `home.file.".inputrc".text = ''…verbatim…''`.
8. **Powerlevel10k stays in `.zshrc` as-is (this slice).** The two tail-end
   lines of the current `.zshrc` that source `~/powerlevel10k/…` and
   `~/.p10k.zsh` (conditional on the files existing) get preserved verbatim
   inside `programs.zsh.initExtra`. Slice 6 replaces them with proper
   home-manager prompt config.
9. **NVM lazy loader stays in `.zshrc` as-is (this slice).** The content of
   the old `.zshrc.d/omz_nvm.sh` folds into `programs.zsh.initExtra`. Slice
   7 (`nvm`/`node`) retires it.
10. **All content lives in `nix/profiles/all/default.nix`.** Every machine
    needs a working interactive shell; agent boxes included. `default` and
    `agent` profile modules unchanged in this slice. Work overrides apply
    via the private flake by stacking content on `lines`-typed options
    (`initExtra`, `bashrcExtra`, `profileExtra`) — concatenation, not
    `lib.mkForce`.
11. **DAG ordering: `entryBefore [ "checkLinkTargets" ]` for the file
    migration; same for the chsh script.** home-manager's `checkLinkTargets`
    aborts if managed-symlink targets are occupied by real files. The same
    asymmetry-with-Slice-1 documented in the GPG slice applies here. See
    `migrateLegacyGnupgConfig` precedent.
12. **No work-specific values in the public repo.** Work signing keys, work
    emails, enterprise hosts, language-version PATH additions, work tooling
    init — all stay
    private. Spec, plan, README, code reference patterns abstractly.

## Architecture

```text
DELETIONS (committed in this slice):
  plugins/shells/                                  # whole dir (bash plugin)
  environments/all/home/.bashrc
  environments/all/home/.bash_profile
  environments/all/home/.profile
  environments/all/home/.bash_profile.d/aliases
  environments/all/home/.bash_profile.d/completion
  environments/all/home/.bash_profile.d/exports
  environments/all/home/.bash_profile.d/path
  environments/all/home/.bash_profile.d/prompt
  environments/all/home/.zshenv
  environments/all/home/.zprofile
  environments/all/home/.zshrc
  environments/all/home/.zshrc.d/aliases.zsh
  environments/all/home/.zshrc.d/omz_keybindings.zsh
  environments/all/home/.zshrc.d/omz_ls-colors.zsh
  environments/all/home/.zshrc.d/omz_nvm.sh
  environments/all/home/.zshrc.d/omz_termsupport.zsh
  environments/all/home/.zshrc.d/prompt.zsh
  environments/all/home/.zshrc.d/rbenv.zsh
  environments/all/home/.zshrc.d/ssh.zsh
  environments/all/home/.zshrc.d/ulimit.zsh
  environments/all/home/.inputrc

ADDITIONS / MODIFICATIONS in nix/profiles/all/default.nix:
  programs.bash.enable + .shellAliases + .sessionVariables
    + .profileExtra (from .bash_profile + .bash_profile.d/{path,exports})
    + .bashrcExtra (from .bashrc + .bash_profile.d/{completion,prompt})
  programs.zsh.enable + .shellAliases + .sessionVariables + .history
    + .completionInit (case-insensitive)
    + .envExtra (from .zshenv)
    + .profileExtra (from .zprofile)
    + .initExtraFirst (p10k instant prompt header from .zshrc)
    + .initExtra (.zshrc body + .zshrc.d/* modular content)
  home.file.".inputrc".text = (from .inputrc, verbatim)
  home.activation.migrateLegacyShellConfig  # moves 22 files + 2 dirs aside
  home.activation.chshAndEtcShells          # chsh + /etc/shells, one-time

UNTOUCHED IN THIS SLICE:
  plugins/powerlevel/                              # Slice 6
  plugins/nvm/                                     # Slice 7
  plugins/node/                                    # Slice 7
  environments/all/home/.p10k.zsh                  # Slice 6
  nix/profiles/{default,agent}/default.nix         # no new per-profile content

PRIVATE-REPO CLEANUP (documented in README, not committed here):
  Work flake gains programs.zsh.initExtra + programs.bash.profileExtra
  with work-specific snippets (concatenated, not lib.mkForce).
  Delete custom_environments/work/home/.zshrc + .bash_profile +
  .zshenv + .zprofile after this slice merges.
```

## `programs.bash` translation

In `nix/profiles/all/default.nix`:

```nix
programs.bash = {
  enable = true;  # installs Nix's bash; writes ~/.bashrc + ~/.bash_profile

  # `.bash_profile.d/aliases` content. All four aliases land here as a
  # native typed attrset rather than text. Same on both shells (see also
  # programs.zsh.shellAliases).
  shellAliases = {
    psgrep = "ps aux | grep -v grep | grep";
    xo     = "xargs open";
    https  = "http --default-scheme=https";
    r2     = "curl -fsSL https://r2.example/ |";  # (or whatever)
  };

  # `.bash_profile.d/exports` plain `VAR=value` lines collapse to a typed
  # attrset; any shell logic (conditionals, $(brew --prefix)) goes into
  # profileExtra below.
  sessionVariables = {
    EDITOR              = "vim";
    GIT_EDITOR          = "vim";
    # …others from .bash_profile.d/exports examined during implementation…
  };

  # .bash_profile + .bash_profile.d/{path,exports-with-logic}. Login-shell-
  # only content. The `load_profile_file` function from the old .bash_profile
  # is DELETED — nothing left to load after this slice.
  profileExtra = ''
    # ~/.bash_profile.d/path — runtime-guarded PATH additions.
    # macOS Homebrew detection
    if [ -d /opt/homebrew ]; then
      export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
    elif [ -d /usr/local/Homebrew ]; then
      export PATH="/usr/local/bin:/usr/local/sbin:$PATH"
    fi
    # …rest of path content, verbatim from .bash_profile.d/path…

    # From the original .bash_profile: ulimit, ssh-add, nvm, histappend,
    # shopt autocd/globstar, rbenv. Inlined here in order.
    ulimit -n 8192
    ssh-add --apple-use-keychain >/dev/null 2>&1 || true
    if [ -d "$HOME/.nvm" ]; then
      . "$HOME/.nvm/nvm.sh"
    fi
    shopt -s histappend
    for option in autocd globstar; do shopt -s "$option" 2>/dev/null; done
    if command -v rbenv >/dev/null 2>&1; then
      eval "$(rbenv init -)"
    fi
  '';

  # .bashrc (interactive defer shim) + .bash_profile.d/completion +
  # .bash_profile.d/prompt. Interactive content; lands in ~/.bashrc.
  bashrcExtra = ''
    # macOS interactive shells get .bashrc, not .bash_profile, so defer.
    # (No-op when .bash_profile already ran in this session.)
    if [ -n "$PS1" ] && [ -z "$BASH_PROFILE_SOURCED" ]; then
      export BASH_PROFILE_SOURCED=1
      # Inline .bash_profile.d/completion content
      # …verbatim from .bash_profile.d/completion…

      # Inline .bash_profile.d/prompt content
      # …verbatim from .bash_profile.d/prompt…
    fi
  '';
};
```

**Notes:**

- The `load_profile_file` function with its three-location lookup is gone.
  Every file is either inlined here verbatim or translated to a typed option.
  Future "drop in a file" usage moves to per-host modules or `home.file`.
- `.profile` source line removed from `.bash_profile`. The current
  `.profile` is comment-only; nothing breaks.
- `~/.bash_profile.d/` directory itself is moved aside by the migration
  activation (see below). Users with stray local files get them backed up.

## `programs.zsh` translation

In `nix/profiles/all/default.nix`:

```nix
programs.zsh = {
  enable = true;  # installs Nix's zsh; writes ~/.zshrc + ~/.zshenv + ~/.zprofile

  shellAliases = {
    # Same as programs.bash.shellAliases — duplicated so each shell has them
    # as native typed options. (Could DRY via `let aliases = { … }; in {
    # programs.bash.shellAliases = aliases; programs.zsh.shellAliases =
    # aliases; }` — decide during implementation.)
    psgrep = "ps aux | grep -v grep | grep";
    xo     = "xargs open";
    https  = "http --default-scheme=https";
    r2     = "curl -fsSL https://r2.example/ |";  # (or whatever)
  };

  # .zshenv → environment variables. POSIX-portable; programs.zsh writes
  # these to ~/.zshenv (read by every zsh invocation, including non-login
  # non-interactive). `GPG_TTY=$(tty)` has shell logic, so it's in envExtra
  # below; the static ones use sessionVariables.
  sessionVariables = {
    AWS_VAULT_KEYCHAIN_NAME = "login";
    EDITOR                   = "vim";
    GIT_EDITOR               = "vim";
  };

  # Anything in .zshenv with shell logic (currently just GPG_TTY).
  envExtra = ''
    export GPG_TTY=$(tty)
  '';

  # .zprofile → login-shell PATH setup. Identical macOS-vs-Linux story to
  # programs.bash.profileExtra; existing runtime `[ -d ]` guards make the
  # content cross-platform-safe.
  profileExtra = ''
    # …content from environments/all/home/.zprofile, verbatim:
    # homebrew detection, /opt/homebrew bin/sbin to PATH, GNU coreutils
    # to PATH if installed, Java, ~/bin and ~/.local/bin, macOS
    # /etc/zprofile PATH-tampering workaround.
  '';

  # History settings — native typed config.
  history = {
    size         = 10000;
    save         = 10000;
    extended     = true;
    ignoreAllDups = true;
    # path defaults to ~/.zsh_history (home-manager's default).
  };

  # Case-insensitive completion. Maps cleanly via completionInit.
  completionInit = ''
    zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
    autoload -Uz compinit && compinit
  '';

  # Powerlevel10k instant prompt — MUST be at the very top of .zshrc.
  # Verbatim from the head of the current .zshrc (lines 1-7).
  initExtraFirst = ''
    if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
      source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
    fi
  '';

  # Body of .zshrc (after the .zshrc.d for-loop, before the p10k tail) PLUS
  # all 9 .zshrc.d/* files in alphabetical order (matching the original
  # for-loop's behavior). Each file's content gets a comment marker showing
  # its origin to aid future tracing.
  initExtra = ''
    # ----- from .zshrc.d/aliases.zsh (handled via shellAliases above; nothing here) -----

    # ----- from .zshrc.d/omz_keybindings.zsh -----
    # …verbatim 68 lines of keybindings…

    # ----- from .zshrc.d/omz_ls-colors.zsh -----
    # …verbatim 39 lines of LS_COLORS…

    # ----- from .zshrc.d/omz_nvm.sh (retired in Slice 7) -----
    if [ -s "$HOME/.nvm/nvm.sh" ]; then
      export NVM_DIR="$HOME/.nvm"
      . "$NVM_DIR/nvm.sh"
    fi

    # ----- from .zshrc.d/omz_termsupport.zsh -----
    # …verbatim 85 lines of terminal-title escape sequences…

    # ----- from .zshrc.d/prompt.zsh (replaced in Slice 6) -----
    # …verbatim 51 lines of fallback prompt (active only when p10k is absent)…

    # ----- from .zshrc.d/rbenv.zsh -----
    if command -v rbenv >/dev/null 2>&1; then
      eval "$(rbenv init -)"
    fi

    # ----- from .zshrc.d/ssh.zsh -----
    ssh-add --apple-use-keychain >/dev/null 2>&1 || true

    # ----- from .zshrc.d/ulimit.zsh -----
    ulimit -n 8192

    # ----- from .zshrc body (history settings handled via .history above;
    # completion via .completionInit; emacs keybindings + beep-disable
    # inlined here) -----
    bindkey -e
    setopt no_beep

    # ----- p10k integration tail (preserved as-is; replaced in Slice 6) -----
    if [ -d "$HOME/powerlevel10k" ]; then
      source "$HOME/powerlevel10k/powerlevel10k.zsh-theme"
    fi
    [ -f "$HOME/.p10k.zsh" ] && source "$HOME/.p10k.zsh"
  '';
};
```

**Notes:**

- The `for FILE ($HOME/.zshrc.d/*) source $FILE` loop from the original
  `.zshrc` is GONE — there's nothing left in `~/.zshrc.d/` to source after
  the rsync sources are deleted and the activation moves the dir aside.
- Order inside `initExtra` matches the original `.zshrc.d/*` shell-glob
  order (alphanumeric) so behavior stays byte-identical to today.
- The p10k integration tail stays. Slice 6 cleans it up.

## `.inputrc` translation

```nix
home.file.".inputrc".text = ''
  # 39 lines verbatim from environments/all/home/.inputrc:
  # case-insensitive completion, history search with up/down, symlink
  # trailing-slash, hidden-file matching, pager settings.
'';
```

No home-manager module exists for readline. `home.file` writes a real
managed file (with the same symlink-into-/nix/store treatment as other
home-manager-managed dotfiles).

## Activation scripts

Two new scripts in `nix/profiles/all/default.nix`. Both use
`entryBefore [ "checkLinkTargets" ]` (same DAG-edge rationale as Slice 5's
GPG migration — `checkLinkTargets` aborts on real-file-occupies-target).

### `migrateLegacyShellConfig`

```nix
home.activation.migrateLegacyShellConfig = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
  # One-time migration: move pre-existing shell-config files (rsync'd by
  # the old framework) aside so home-manager's programs.bash / programs.zsh
  # / home.file can take over the same paths. Marker outside any GPG-style
  # 0700-mode dir; idempotent on subsequent applies.
  if [ ! -e "$HOME/.shell-config.hm-migrated" ]; then
    # Top-level files
    for f in .zshrc .zshenv .zprofile .bash_profile .bashrc .profile .inputrc; do
      if [ -f "$HOME/$f" ] && [ ! -L "$HOME/$f" ]; then
        run mv -n "$HOME/$f" "$HOME/$f.legacy-backup"
        echo "Moved legacy ~/$f → ~/$f.legacy-backup (one-time migration)"
      fi
    done
    # Modular-config directories: move the whole dir aside as a sibling
    # backup. User-dropped files inside are preserved verbatim.
    for d in .bash_profile.d .zshrc.d; do
      if [ -d "$HOME/$d" ] && [ ! -L "$HOME/$d" ]; then
        run mv -n "$HOME/$d" "$HOME/$d.legacy-backup"
        echo "Moved legacy ~/$d/ → ~/$d.legacy-backup/ (one-time migration)"
      fi
    done
    run touch "$HOME/.shell-config.hm-migrated"
  fi
'';
```

**Properties:**

- **One-time effective.** `~/.shell-config.hm-migrated` marker short-circuits
  subsequent applies.
- **Non-destructive.** `mv -n` guards against silent backup-overwrite on a
  hypothetical crashed-mid-loop re-run. Real files preserved as
  `.legacy-backup` siblings. Directories preserved as `.legacy-backup`
  siblings with all original contents.
- **Linux-safe.** All paths are user-home POSIX paths; no macOS-specific
  syscalls. The per-file `[ -f … ] && [ ! -L … ]` and per-dir `[ -d … ] &&
  [ ! -L … ]` guards make the migration a no-op on Linux machines that
  never had the rsync-managed files.
- **User-content preservation.** If the user dropped extra files into
  `~/.zshrc.d/` or `~/.bash_profile.d/` (custom additions), they ride
  along inside the `.legacy-backup` dir. Nothing is deleted.

### `chshAndEtcShells`

```nix
home.activation.chshAndEtcShells = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
  # One-time chsh + /etc/shells setup replacing the retired `shells` plugin.
  # Marker-gated. Interactive-tty-aware (so non-interactive container builds
  # skip cleanly). Sudo prompt goes to the apply terminal.
  if [ -e "$HOME/.shells-chsh.hm-migrated" ]; then
    exit 0
  fi
  if [ ! -t 0 ]; then
    echo "chshAndEtcShells: non-interactive shell, skipping (run ./apply in a terminal to complete chsh setup)"
    exit 0
  fi

  target="$HOME/.nix-profile/bin/zsh"
  if [ ! -x "$target" ]; then
    echo "chshAndEtcShells: $target missing; programs.zsh.enable should have installed it. Skipping."
    exit 0
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
```

**Properties:**

- **One-time effective + interactive-aware.** Marker-gated; no-op on already-
  done. Non-tty runs (CI, container builds) skip with a friendly message
  and leave the marker absent so a future interactive `./apply` can finish.
- **Stable chsh target.** `~/.nix-profile/bin/zsh` is a symlink that survives
  nixpkgs bumps; `/etc/passwd` content never changes.
- **User-choice preservation.** Only chshes if current shell is a system
  default or brew's zsh. Explicit choices (e.g., user manually chsh'd to a
  custom path) are left alone.
- **Cross-platform.** `dscl` for macOS; `getent passwd` fallback for Linux.
  The `case` statement matches Linux system shells (`/bin/zsh`, `/bin/bash`)
  too.
- **Sudo prompt routing.** `sudo tee` prompts on stderr inside the apply
  terminal. User enters password once.

## Cross-profile concerns

- **All shell content goes in `all`.** Every machine — agent boxes included
  — needs a working interactive shell. `programs.{bash,zsh}.enable = true`
  and the content blocks live in `nix/profiles/all/default.nix`.
- **`default` profile unchanged in this slice.** Identity, signing key, and
  ripgrep remain its only content.
- **`agent` profile stays lean.** No new content. The `chshAndEtcShells`
  activation's non-interactive escape hatch handles the container case.
- **Work private flake.** Stacks content onto the `lines`-typed options
  (`programs.zsh.initExtra`, `programs.bash.profileExtra`) via concatenation.
  No `lib.mkForce` needed for the additive case. README migration sub-block
  shows the pattern abstractly.

## Testing

- **Pre-flight (macOS):** capture
  - `cat ~/.zshrc ~/.zshenv ~/.zprofile` (existing rsync-managed content)
  - `cat ~/.bash_profile ~/.bashrc` (existing rsync-managed content)
  - `ls -la ~/.bash_profile.d/ ~/.zshrc.d/`
  - `cat ~/.inputrc`
  - `dscl . -read /Users/$USER UserShell` (current login shell)
  - `cat /etc/shells | grep -E 'zsh|bash'` (registered shells)
  - `echo $SHELL` (parent shell's `$SHELL` env var)
  - `alias psgrep xo https r2` (existing aliases)
  - `echo $EDITOR $GPG_TTY $AWS_VAULT_KEYCHAIN_NAME`

- **Activation: legacy-backup migration.** Run the plugin direct
  (`DOTFILES_ENVIRONMENT=default`). Confirm:
  - 22 "Moved legacy …" lines once (7 files + 5 .bash_profile.d files +
    9 .zshrc.d files + 1 .inputrc = 22 total moves; plus 2 dir-move
    lines for the two `.d/` directories — actually 7 files + 2 dirs = 9
    legacy-backup operations total, since the `.d/` content rides along
    inside the dir move).
  - **Re-count corrected:** the activation script moves 7 top-level files
    (`.zshrc`, `.zshenv`, `.zprofile`, `.bash_profile`, `.bashrc`,
    `.profile`, `.inputrc`) plus 2 directories (`.bash_profile.d/`,
    `.zshrc.d/`) — 9 total moves, 9 echo lines. The 14 files inside the
    two `.d/` directories preserve byte-identical inside the
    `.d.legacy-backup/` directories.
  - `~/.shell-config.hm-migrated` marker exists.

- **Activation: chshAndEtcShells.** Confirm:
  - `/etc/shells` now contains `~/.nix-profile/bin/zsh` (resolved to the
    full path).
  - `dscl . -read /Users/$USER UserShell` returns
    `/Users/$USER/.nix-profile/bin/zsh`.
  - `~/.shells-chsh.hm-migrated` marker exists.

- **Verify file ownership.** All 7 top-level files now symlinks into
  `/nix/store/…-home-manager-files/`. `~/.bash_profile.d/` and
  `~/.zshrc.d/` directories no longer exist (only the `.legacy-backup`
  variants do).

- **Verify zsh content.** `zsh -ic 'alias; echo $EDITOR; echo $HISTSIZE;
  echo $GPG_TTY; bindkey -L | head -3'` — aliases present, env vars set,
  history active, emacs keybindings active.

- **Verify bash content.** `bash -lic 'alias; echo $EDITOR; type ssh-add;
  ulimit -n; shopt globstar'` — aliases present, env vars set, ssh-add
  available, ulimit 8192, globstar enabled.

- **p10k instant prompt loads.** Open a fresh terminal (not a `-ic`
  subshell). No errors. Instant prompt visible if `~/.p10k.zsh` exists.

- **Cross-slice intact:**
  - `git config alias.fixup` returns `commit --fixup` (Slice 1 git config).
  - `git config commit.gpgsign` returns `true` (Slice 5 signing).
  - `git --version` returns `2.54.0` (slice-5 nixpkgs bump).
  - `gpg --version` resolves to Nix store.

- **Activation idempotency.** Re-run the plugin. No "Moved legacy …"
  lines; no chsh action; markers unchanged.

- **Throwaway private-override.** Scratch flake adds

  ```nix
  programs.zsh.initExtra   = "export WORK_TEST=zsh_throwaway";
  programs.bash.profileExtra = "export WORK_TEST=bash_throwaway";
  ```

  Activate. Verify:
  - `zsh -ic 'echo $WORK_TEST'` returns `zsh_throwaway`.
  - `bash -lic 'echo $WORK_TEST'` returns `bash_throwaway`.
  - All `all`-layer aliases and env vars still work (concatenation, not
    override).
  Tear down. Verify env vars gone.

- **Linux container (aarch64-linux, agent profile).** `./apply` runs:
  - programs.zsh + programs.bash activate; symlinks land.
  - `chshAndEtcShells` prints the non-interactive-skip line; marker stays
    absent.
  - `zsh -ic 'alias psgrep'` returns the expected definition.
  - `bash -lic 'alias psgrep'` ditto.

- **Backout drill (documented in README, not part of automated tests):**
  delete `~/.shell-config.hm-migrated`, restore one `.legacy-backup` to its
  real name (e.g., `mv ~/.zshrc.legacy-backup ~/.zshrc`), re-apply. The
  activation re-detects the real file and re-moves it aside. Confirms the
  recovery path works.

## README updates

Three changes to `nix/README.md`:

1. **New "For the shells slice" sub-block** in the existing private-environment
   migration guide, parallel to the git and commit-signing sub-blocks.
   Pattern-based; explains how to extend `programs.zsh.initExtra` and
   `programs.bash.profileExtra` in the private flake with work-specific
   content (extra PATH entries, env vars, tooling init shell hooks), and
   how to delete the
   now-orphaned `.zshrc`/`.bash_profile`/`.zshenv`/`.zprofile`/`.zshrc.d/`/
   `.bash_profile.d/` rsync sources from the private repo.

2. **Refresh the Background paragraph** to add shells:
   `…and shell config — bash and zsh via programs.bash + programs.zsh
   (with the prior .zshrc.d/ and .bash_profile.d/ modular content folded
   into the relevant typed options), .inputrc via home.file, and a one-
   time activation that retires the rsync-managed shell dotfiles plus
   the shells plugin's chsh / /etc/shells logic.`

3. **Refresh the `all`-layer parenthetical** under `### Public profiles and
   layers` to add the new content:
   `(currently bat, the shared git config — aliases, body, includes — via
   programs.git, GPG/agent setup with per-OS pinentry, AND bash + zsh via
   programs.bash + programs.zsh plus .inputrc via home.file)`

## Scope / Non-goals

**In scope:**

- Retire `plugins/shells/` entirely (chsh + /etc/shells move to a
  marker-gated activation script).
- Migrate 7 top-level shell-config files + 9 `.zshrc.d/*` + 5
  `.bash_profile.d/*` = 21 rsync sources, plus `.inputrc` = 22 total.
- `programs.bash.enable = true`, `programs.zsh.enable = true`, all
  `shellAliases`/`sessionVariables`/`history`/`completionInit`/
  `envExtra`/`profileExtra`/`initExtraFirst`/`initExtra`/`bashrcExtra`
  options populated.
- `home.file.".inputrc".text` for readline.
- `migrateLegacyShellConfig` activation (moves 7 files + 2 dirs aside).
- `chshAndEtcShells` activation (chsh + /etc/shells, marker-gated).
- Cross-platform: macOS + aarch64-linux container verified.
- Throwaway private-flake additive-override test.
- README sub-block + Background refresh + `all`-layer refresh.

**Out of scope (handled by later slices):**

- Powerlevel10k retirement (`plugins/powerlevel/` + `.p10k.zsh`) — Slice 6.
- NVM + node retirement (`plugins/nvm/` + `plugins/node/`) — Slice 7.
- Brewfile retirement (`environments/all/Brewfile` etc.) — much later.
- Other rsync sources not shell-related (`.wgetrc`, `.gemrc`, `.vimrc`,
  `.screenrc`, etc.) — separate per-tool slices.
- Switch from emacs to vi keybindings, or any preference changes — this
  slice preserves current behavior byte-for-byte.
- DRY-ing the duplicated `shellAliases` between bash and zsh — decided
  during implementation (not a spec-locked decision).

## Future phases

After this slice, the next two slices retire the rest of the shell
ecosystem: Slice 6 (prompt: `powerlevel` plugin + `.p10k.zsh`, with a
possible starship migration) and Slice 7 (`nvm` + `node` plugins). Beyond
those, the per-tool slices (`vim`, `vscode`, `xcode`, `claude`,
`homebrew_core`) follow the same patterns established here.
