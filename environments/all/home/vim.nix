{ pkgs, lib, ... }: {
  programs.vim = {
    enable = true;

    plugins = with pkgs.vimPlugins; [
      vim-javascript          # pangloss (replaces unmaintained jelera/vim-javascript-syntax)
      vim-colors-solarized
      editorconfig-vim
    ];

    extraConfig = ''
      " Make Vim readable
      set background=dark

      " Enable Vim stuff (supposedly not necessary if this file exists)
      set nocompatible

      " Centralize backups, swapfiles and undo history
      set backupdir=~/.vim/backups
      set directory=~/.vim/swaps
      if exists("&undodir")
      	set undodir=~/.vim/undo
      endif

      " Enable line numbers
      set number

      " Enable syntax highlighting
      syntax on

      " Disable error bells
      set noerrorbells

      " Show the cursor position
      set ruler

      " Ignore case of searches
      set ignorecase

      " Make tabs appear shorter
      set tabstop=2

      " Use spaces instead of tabs
      set expandtab

      " Automatic commands
      if has("autocmd")
      	" Enable file type detection
      	filetype on
      	" Treat .json files as .js
      	autocmd BufNewFile,BufRead *.json setfiletype json syntax=javascript
      	" Indent automatically
      	filetype plugin indent on
      endif

      " Disable arrow keys
      map <up> <nop>
      map <down> <nop>
      map <left> <nop>
      map <right> <nop>
      imap <up> <nop>
      imap <down> <nop>
      imap <left> <nop>
      imap <right> <nop>

      let g:solarized_termcolors=256
      let g:solarized_termtrans=1
      colorscheme solarized

      " 2 Tab Indent
      set expandtab
      set shiftwidth=2
      set softtabstop=2
    '';
  };

  # Empty .keep files so home-manager creates the state directories
  # declaratively. Vim writes real backup/swap/undo files into these dirs at
  # runtime; those files are unmanaged user state.
  home.file = {
    ".vim/backups/.keep".text = "";
    ".vim/swaps/.keep".text   = "";
    ".vim/undo/.keep".text    = "";
  };

  # Move-aside legacy rsync residue on first apply. Runs before
  # `checkLinkTargets` so home-manager's link-conflict check sees a clean
  # slate. Idempotent — each block skips paths that no longer exist or
  # are already a symlink (defensive: don't clobber a user-managed link).
  home.activation.migrateLegacyVimRsync =
    lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
      # Use home-manager's `run` (honors dry-run) instead of calling /bin/mv
      # directly, and `-n` so a leftover *.legacy-backup from a partial prior
      # migration isn't clobbered. (No marker file here: the guards are
      # self-idempotent — a source that's already gone or already a symlink is
      # skipped — and a `-n` no-op surfaces loudly at checkLinkTargets.)
      if [ -f "$HOME/.vimrc" ] && [ ! -L "$HOME/.vimrc" ]; then
        run mv -n "$HOME/.vimrc" "$HOME/.vimrc.legacy-backup"
      fi
      if [ -d "$HOME/.vim/autoload" ] && [ ! -L "$HOME/.vim/autoload" ]; then
        run mv -n "$HOME/.vim/autoload" "$HOME/.vim/autoload.legacy-backup"
      fi
      if [ -d "$HOME/.vim/bundle" ] && [ ! -L "$HOME/.vim/bundle" ]; then
        run mv -n "$HOME/.vim/bundle" "$HOME/.vim/bundle.legacy-backup"
      fi
    '';
}
