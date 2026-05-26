{ lib, pkgs, ... }:

let
  # Shared static aliases. Both shells get them as typed attrsets via
  # programs.{bash,zsh}.shellAliases. Conditional / OS-specific aliases
  # (md5sum, sha1sum, pbcopy/pbpaste on non-Darwin) live in
  # programs.bash.profileExtra since the typed option can't express
  # conditionals.
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

      # (The previous `for FILE in $BREW_PREFIX/opt/*/libexec/gnubin` loop is
      # gone: GNU coreutils/findutils/sed/grep moved from brew to nix in the
      # brew-formulas slice. nix's versions live in ~/.nix-profile/bin/, which
      # is already at the front of PATH, so they shadow macOS's BSD variants
      # without the gnubin PATH-shim. The glob also failed under zsh's
      # `setopt nomatch` once the brew formulas providing those libexec/gnubin
      # dirs were uninstalled.)
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
    # BSD `ls -G` palette (macOS). Note: deliberately NOT setting GNU $LS_COLORS
    # to this value — it's a different format, and a non-empty $LS_COLORS makes
    # omz_ls-colors.zsh switch macOS to `gls --color=tty`, which would then
    # mis-parse this BSD string. Leaving $LS_COLORS unset keeps `ls -G` on macOS
    # and lets `dircolors` provide GNU defaults on Linux.
    LSCOLORS                = "Gxfxcxdxbxegedabagacad";
  };

  # ---------- ~/.inputrc ----------
  home.file.".inputrc".text = ''
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
    historyControl = [ "ignoreboth" ];
    historyIgnore  = [ "ls" "pwd" "date" "git reset HEAD^" ];
    # Empty HISTFILESIZE/HISTSIZE = unlimited in bash. Set both HM options to
    # null so HM emits no HISTFILESIZE/HISTSIZE line at all; our exports below
    # (in bashrcExtra, which runs after HM's generated block) set them to empty
    # (= unlimited). profileExtra exports are redundant for interactive shells
    # but kept for non-interactive login shells.
    historyFileSize = null;
    historySize     = null;

    # .bash_profile body (excluding the load_profile_file function and the
    # FILES loop — those are gone since nothing lives in .bash_profile.d/
    # anymore). Includes: ulimit, ssh-add, histappend, shopt
    # autocd/globstar, rbenv. Plus PATH from .bash_profile.d/path. Plus the
    # remaining shell-logic exports from .bash_profile.d/exports (HISTFILESIZE,
    # HISTSIZE empty for unlimited; GPG_TTY). (Slice 6 had `nvm-load` here too;
    # Slice 8 retired nvm in favour of fnm — see below.)
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
      [ -n "$PS1" ] || return

      # ---- from .bash_profile.d/completion ----
    '' + (builtins.readFile ./bash-completion.bash) + ''

      # ---- from .bash_profile.d/prompt ----
    '' + (builtins.readFile ./bash-prompt.bash) + ''

      # Bash empty = unlimited history. We set historyFileSize/historySize to
      # null above so HM emits no HISTFILESIZE/HISTSIZE; these exports at the
      # end of bashrcExtra guarantee the unlimited values survive for every
      # interactive shell (login and non-login alike).
      export HISTFILESIZE=
      export HISTSIZE=

      # ---- fnm (Node.js version manager) ----
      # `--use-on-cd` auto-switches the active node version when entering a
      # directory containing .nvmrc or .node-version.
      eval "$(${pkgs.fnm}/bin/fnm env --use-on-cd --shell bash)"
    '';
  };

  # ---------- Zsh ----------
  programs.zsh = {
    enable = true;

    shellAliases = sharedAliases;  # Just the 4 shared aliases; no zsh-specific ones.

    # History settings (from .zshrc body).
    history = {
      size          = 10000;
      save          = 10000;
      path          = "$HOME/.zsh_history";
      extended      = false;
      ignoreAllDups = true;
      share         = true;  # shares history across terminals (sharehistory)
      append        = true;  # appends, doesn't overwrite (appendhistory)
    };

    # Anything from .zshenv with shell logic (GPG_TTY). The static .zshenv
    # vars live in home.sessionVariables above.
    envExtra = ''
      # Avoid issues with gpg as installed via Homebrew.
      # https://stackoverflow.com/a/42265848/96656
      export GPG_TTY
      GPG_TTY=$(tty)
    '';

    # Case-insensitive completion (improvement over the original .zshrc which
    # only set the OMZ-style CASE_SENSITIVE="true" variable that did nothing
    # without oh-my-zsh actually installed).
    completionInit = ''
      zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
      autoload -Uz compinit && compinit
    '';

    # .zprofile content (PATH setup; macOS-specific brew + Java + ~/bin).
    profileExtra = brewPathSetup;

    # Full .zshrc content: the .zshrc body followed by the surviving
    # .zshrc.d/* content in alphabetical order (matches the original
    # `for FILE ($HOME/.zshrc.d/*)` glob order). Each block is commented
    # with its origin file. Starship's prompt setup is injected by
    # home-manager separately (via programs.starship.enableZshIntegration)
    # so we don't need to source it here.
    # initExtraFirst / initExtra were deprecated in favour of initContent.
    # Since this module owns all the zsh init content, ordering is not needed.
    initContent = ''
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

      # ---- from .zshrc.d/omz_keybindings.zsh ----
    '' + (builtins.readFile ./omz_keybindings.zsh) + ''

      # ---- from .zshrc.d/omz_ls-colors.zsh ----
    '' + (builtins.readFile ./omz_ls-colors.zsh) + ''

      # ---- from .zshrc.d/omz_termsupport.zsh ----
    '' + (builtins.readFile ./omz_termsupport.zsh) + ''

      # ---- from .zshrc.d/rbenv.zsh ----
      if command -v rbenv >/dev/null 2>&1; then
        eval "$(rbenv init --no-rehash - zsh)"
      fi

      # ---- from .zshrc.d/ssh.zsh ----
      ssh-add --apple-use-keychain > /dev/null 2> /dev/null

      # ---- from .zshrc.d/ulimit.zsh ----
      # Set a reasonable ulimit because Apple
      ulimit -n 8192

      # ---- fnm (Node.js version manager) ----
      # `--use-on-cd` auto-switches the active node version when entering a
      # directory containing .nvmrc or .node-version.
      eval "$(${pkgs.fnm}/bin/fnm env --use-on-cd --shell zsh)"

    '';
  };

  # ---------- Starship prompt ----------
  programs.starship = {
    enable = true;
    # No settings overrides — opt in to starship's defaults. The default
    # prompt shows directory + git status + character on one line; works
    # cleanly with both bash and zsh; ~10ms init overhead. Iterate post-
    # merge if a default module is undesirable (override via the typed
    # `settings` attrset, which serializes to ~/.config/starship.toml).
    settings = { };
  };

  # ---------- fnm (Node.js version manager) ----------
  # home-manager release-26.05 does not ship a programs.fnm module, so we
  # install fnm via home.packages. Shell integration is added directly in the
  # programs.bash.bashrcExtra and programs.zsh.initContent blocks above.
  home.packages = [ pkgs.fnm ];

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
          # Don't use `mv -n`: it silently no-ops if a .legacy-backup already
          # exists, yet the marker below would still be written — leaving the
          # real file to fail checkLinkTargets forever with no retry. Fail
          # loudly so a pre-existing backup is resolved by hand.
          if [ -e "$HOME/$f.legacy-backup" ]; then
            echo "ERROR: $HOME/$f.legacy-backup already exists; refusing to overwrite. Move it aside, then re-run ./apply." >&2
            exit 1
          fi
          run mv "$HOME/$f" "$HOME/$f.legacy-backup"
          echo "Moved legacy ~/$f → ~/$f.legacy-backup (one-time migration)"
        fi
      done
      # Modular-config directories: move the whole dir aside.
      for d in .bash_profile.d .zshrc.d; do
        if [ -d "$HOME/$d" ] && [ ! -L "$HOME/$d" ]; then
          if [ -e "$HOME/$d.legacy-backup" ]; then
            echo "ERROR: $HOME/$d.legacy-backup already exists; refusing to overwrite. Move it aside, then re-run ./apply." >&2
            exit 1
          fi
          run mv "$HOME/$d" "$HOME/$d.legacy-backup"
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
    # Note: home-manager activation scripts run inline (not in a function),
    # so `return` is not valid — use nested if-blocks for early exits.
    #
    # All work runs inside a subshell so the PATH prepend (needed to find
    # sudo / chsh / dscl / getent / tee, which live in /usr/bin or /bin on
    # both macOS and Linux but aren't on home-manager's stripped activation
    # PATH) doesn't leak to subsequent activation steps. Some HM steps
    # (e.g., checkLinkTargets) rely on the nix-shipped GNU coreutils
    # winning the PATH race for `readlink -e`; if we prepended globally,
    # macOS's BSD readlink would shadow it and break those steps.
    if [ ! -e "$HOME/.shells-chsh.hm-migrated" ]; then
      if [ ! -t 0 ]; then
        echo "chshAndEtcShells: non-interactive shell, skipping (run ./apply in a terminal to complete chsh setup)"
      else
        (
          PATH="/usr/bin:/bin:$PATH"

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

          touch "$HOME/.shells-chsh.hm-migrated"
        )
      fi
    fi
  '';

  # ---------- Activation: legacy .p10k.zsh backup (prompt slice) ----------
  home.activation.migrateLegacyP10kConfig = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    # One-time migration: starship replaces p10k. The old rsync'd ~/.p10k.zsh
    # is no longer sourced; move it aside as a backup. ~/powerlevel10k/ (the
    # cloned theme repo) is left in place — inert without sourcing; user can
    # `rm -rf` it manually.
    if [ ! -e "$HOME/.p10k.hm-migrated" ]; then
      if [ -f "$HOME/.p10k.zsh" ] && [ ! -L "$HOME/.p10k.zsh" ]; then
        # Don't use `mv -n`: it silently no-ops if a .legacy-backup already
        # exists, yet the marker below would still be written — leaving the
        # real file in place. Fail loudly so a pre-existing backup is resolved
        # by hand. (Matches the migrateLegacyShellConfig hardening.)
        if [ -e "$HOME/.p10k.zsh.legacy-backup" ]; then
          echo "ERROR: $HOME/.p10k.zsh.legacy-backup already exists; refusing to overwrite. Move it aside, then re-run ./apply." >&2
          exit 1
        fi
        run mv "$HOME/.p10k.zsh" "$HOME/.p10k.zsh.legacy-backup"
        echo "Moved legacy ~/.p10k.zsh → ~/.p10k.zsh.legacy-backup (one-time migration)"
      fi
      run touch "$HOME/.p10k.hm-migrated"
    fi
  '';

  # ---------- Activation: bootstrap default LTS node via fnm ----------
  home.activation.installFnmDefaultNode = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # One-time bootstrap: install the LTS node version via fnm so a fresh
    # machine has node available without manual `fnm install`. Marker-gated.
    # Activation scripts run with a stripped PATH; use the absolute store
    # path for fnm to avoid PATH gymnastics. Network call; failures leave
    # the marker absent so a later apply can retry.
    if [ ! -e "$HOME/.fnm-default-node.hm-migrated" ]; then
      # Prefix with $DRY_RUN_CMD so `home-manager switch -n` doesn't actually
      # download the LTS or move the `default` alias (the surrounding `run`
      # helpers already honor dry-run, but these two were invoked directly).
      if $DRY_RUN_CMD ${pkgs.fnm}/bin/fnm install --lts && \
         $DRY_RUN_CMD ${pkgs.fnm}/bin/fnm default lts-latest; then
        run touch "$HOME/.fnm-default-node.hm-migrated"
        echo "Installed default LTS node via fnm (one-time bootstrap)"
      else
        echo "fnm bootstrap failed; will retry on next ./apply"
      fi
    fi
  '';
}
