# Nix Vim Slice Design

**Date:** 2026-05-27
**Status:** Draft — pending user approval
**Branch:** `nix-vim` (stacks on `nix-firstrun` / PR #71 → `nix-darwin` / PR #70 → `nix-homebrew` / PR #69 → `nix-nodejs` / PR #68 → `nix-prompt` / PR #67 → `nix-shells` / PR #66 → `nix-commit-signing` / PR #65 → `nix-git` / PR #64 → `nix-profiles` / PR #63 → `nix-cross-platform` / PR #62)

## Goal

Retire the `vim` bash plugin (which `git clone`s three pathogen-style bundles at apply time into a rsync source) and the rsynced `~/.vimrc` + `~/.vim/` tree. Replace with home-manager's `programs.vim`: plugins sourced from nixpkgs, config inline, pathogen dropped entirely (home-manager uses vim's native `packpath` mechanism). Move-aside legacy rsynced content on first apply per the established slice convention; preserve `~/.vim/{backups,swaps,undo}/` user state untouched.

## Decisions (locked)

1. **`programs.vim`, not neovim.** Match current behavior. Neovim is a future option, not a side effect of this migration.
2. **Plugins from nixpkgs.** Three plugins:
   - `vimPlugins.vim-javascript` (pangloss) — replaces the unmaintained `jelera/vim-javascript-syntax`. Active upstream; broader ES coverage. Minor risk of subtle highlighting differences.
   - `vimPlugins.vim-colors-solarized` — same as today.
   - `vimPlugins.editorconfig-vim` — same as today.
3. **No pathogen.** Home-manager loads plugins via vim's native `packpath` (drops them under `pack/home-manager/start/`). The `execute pathogen#infect()` line is removed from the migrated config. The standalone `~/.vim/autoload/pathogen.vim` becomes dead code on disk and gets moved aside.
4. **Vim config body migrates verbatim** (minus pathogen line) into `programs.vim.extraConfig`. Includes `set backupdir=~/.vim/backups`, `set directory=~/.vim/swaps`, `set undodir=~/.vim/undo`, `colorscheme solarized`, the disable-arrow-keys mappings, and the autocmd block. No semantic changes.
5. **State directories created via `home.file`.** Three placeholder files:
   ```nix
   home.file = {
     ".vim/backups/.keep".text = "";
     ".vim/swaps/.keep".text   = "";
     ".vim/undo/.keep".text    = "";
   };
   ```
   Home-manager creates the directories declaratively via the `.keep` files; the directories themselves are not "managed" in any way that would interfere with vim writing real state files into them. Existing files in `~/.vim/backups/` etc. on a current machine are untouched by home-manager (it only manages the `.keep` symlinks).
6. **Move-aside migration for legacy rsync residue.** A `home.activation.migrateLegacyVimRsync` script runs idempotently on every `home-manager switch`. Move-aside-not-delete is the established slice convention (slice 6 shells, slice 10 nix-darwin):
   - `~/.vimrc` (regular file, not symlink) → `~/.vimrc.legacy-backup`
   - `~/.vim/autoload/` (carries old `pathogen.vim`) → `~/.vim/autoload.legacy-backup/`
   - `~/.vim/bundle/` (carries the three git-cloned plugin dirs) → `~/.vim/bundle.legacy-backup/`
   - **`~/.vim/{backups,swaps,undo}/` untouched** — these contain live user state (vim backup files, swap files, undo history). Destroying these on any user's machine would be data loss.
7. **Activation ordering.** The move-aside script runs with `lib.hm.dag.entryBefore [ "checkLinkTargets" ]` so it executes before home-manager's link-conflict check; otherwise `checkLinkTargets` would refuse to clobber the existing plain `~/.vimrc` file.
8. **`vim` removed from `DOTFILES_HOMEDIR_DEPS`** in `plugins/homedir/homedir` (currently `('claude' 'vim')` → `('claude')`). The homedir plugin's run order no longer waits on the now-deleted vim plugin.
9. **No editor-default change.** This slice does NOT set `EDITOR`, does NOT add `vim` to git's `core.editor`, does NOT touch how shells launch editors. Pure plugin retirement.
10. **No work-specific values.** All vim content lives entirely under `environments/all/`. No private-flake additions required.
11. **No `claude` plugin interaction.** The homedir plugin's `DOTFILES_HOMEDIR_DEPS` line keeps `claude` (because claude has a "build" step per its own comment); only `vim` is removed from the dependency list.
12. **Single file: `nix/profiles/all/vim.nix`.** Matches the per-feature submodule pattern established by `git.nix`, `gpg.nix`, `cli-tools.nix`, `shells.nix`, `dotfilesrc-cleanup.nix`.
13. **No airplane-mode special-casing.** The bash plugin skipped `git clone` in airplane mode. With nixpkgs, plugins are baked into the build at evaluation time — there's no network call at apply time, so airplane mode is naturally a non-issue.

## Architecture

```text
NEW FILES:
  nix/profiles/all/vim.nix                  # programs.vim + home.file state dirs +
                                            #   migrateLegacyVimRsync activation

MODIFIED FILES:
  nix/profiles/all/default.nix              # imports ./vim.nix
  plugins/homedir/homedir                   # DOTFILES_HOMEDIR_DEPS: drop 'vim'
  nix/README.md                             # +migration guide sub-block for nix-vim slice

DELETED:
  plugins/vim/                              # whole dir (vim bash plugin)
  environments/all/home/.vim/               # whole tree (autoload/pathogen.vim + bundle/* +
                                            #   empty colors/ syntax/ + empty state dirs)
  environments/all/home/.vimrc              # rsynced config (body migrated to extraConfig)

UNTOUCHED:
  framework/                                # no framework changes; bash loader stays
  environments/all/firstrun                 # already deleted in slice 11
  Other slices' nix files                   # no cross-slice coupling
  ~/.vim/{backups,swaps,undo}/ on user machines  # live user state, preserved by activation
```

## `nix/profiles/all/vim.nix` (full content)

```nix
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
  # slate. Idempotent — each block guards on existence and ensures the
  # target isn't already a symlink (which would indicate home-manager
  # already owns it).
  home.activation.migrateLegacyVimRsync =
    lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
      if [ -f "$HOME/.vimrc" ] && [ ! -L "$HOME/.vimrc" ]; then
        /bin/mv "$HOME/.vimrc" "$HOME/.vimrc.legacy-backup"
      fi
      if [ -d "$HOME/.vim/autoload" ] && [ ! -L "$HOME/.vim/autoload" ]; then
        /bin/mv "$HOME/.vim/autoload" "$HOME/.vim/autoload.legacy-backup"
      fi
      if [ -d "$HOME/.vim/bundle" ] && [ ! -L "$HOME/.vim/bundle" ]; then
        /bin/mv "$HOME/.vim/bundle" "$HOME/.vim/bundle.legacy-backup"
      fi
    '';
}
```

## `plugins/homedir/homedir` change

The current top of the file:

```bash
# Needs to come after claude because claude has a "build" step
export DOTFILES_HOMEDIR_DEPS=('claude' 'vim')
```

Becomes:

```bash
# Needs to come after claude because claude has a "build" step
export DOTFILES_HOMEDIR_DEPS=('claude')
```

The dependency on `vim` is removed because the `vim` plugin no longer exists. The comment is preserved as-is (the claude justification is still accurate).

## `nix/profiles/all/default.nix` change

Add `./vim.nix` to the imports list (alphabetical placement after `./shells.nix`):

```nix
{ ... }: {
  imports = [
    ./cli-tools.nix
    ./dotfilesrc-cleanup.nix
    ./git.nix
    ./gpg.nix
    ./shells.nix
    ./vim.nix
  ];
}
```

## Deletion list

- `plugins/vim/vim` (the bash plugin script)
- `plugins/vim/` (the directory itself, since it only contains `vim`)
- `environments/all/home/.vim/autoload/pathogen.vim` (no longer needed)
- `environments/all/home/.vim/autoload/` (only contained pathogen.vim)
- `environments/all/home/.vim/bundle/editorconfig/` (was git-cloned at apply time; now Nix-managed)
- `environments/all/home/.vim/bundle/vim-colors-solarized/` (same)
- `environments/all/home/.vim/bundle/vim-javascript-syntax/` (same)
- `environments/all/home/.vim/bundle/` (only contained the cloned plugins)
- `environments/all/home/.vim/colors/` (empty in source tree)
- `environments/all/home/.vim/syntax/` (empty in source tree)
- `environments/all/home/.vim/backups/`, `swaps/`, `undo/` (empty placeholders in source tree; the user-machine versions hold real state and are untouched by the deletion of the source-tree versions)
- `environments/all/home/.vim/` (the whole tree)
- `environments/all/home/.vimrc`

If the bundle directories are gitignored (they're git-cloned at apply time), `git rm -rf` will skip them and the directory deletion is sufficient. If they're tracked, `git rm -rf` removes them cleanly. Either way, no manual gitignore changes are needed.

## Migration guide block in `nix/README.md`

Append after the existing "For the nix-firstrun slice" sub-block, following the established paragraph-heading style:

```markdown
For the nix-vim slice (`vim` plugin retired; `~/.vim/` and `~/.vimrc` now home-manager managed via `programs.vim`):

This slice migrates the bash `vim` plugin (which `git clone`d three pathogen
bundles at apply time) and the rsynced `~/.vimrc` + `~/.vim/` content into
home-manager's `programs.vim`. Plugins now come from nixpkgs at build time:
`vim-javascript` (pangloss — replaces unmaintained `jelera/vim-javascript-syntax`),
`vim-colors-solarized`, `editorconfig-vim`. Pathogen is no longer used; vim's
native `packpath` mechanism handles plugin loading.

**One-time apply notes:**

- On first apply, the activation moves your existing `~/.vimrc` to
  `~/.vimrc.legacy-backup`, `~/.vim/autoload/` (containing the old
  `pathogen.vim`) to `~/.vim/autoload.legacy-backup/`, and `~/.vim/bundle/`
  (the three git-cloned plugins) to `~/.vim/bundle.legacy-backup/`. Once
  you've confirmed vim still works the way you want, you can delete the
  `.legacy-backup` paths at your leisure.

- `~/.vim/{backups,swaps,undo}/` are NOT touched by the migration. They
  contain real vim state (backup copies of files you've edited, swap files
  for recovery, undo history). The slice creates these directories
  declaratively via `home.file` `.keep` placeholders so a fresh machine
  has them, but never manages their contents.

- If you had local edits to `~/.vimrc` or any of the bundle plugins, look
  for them in the `.legacy-backup` paths and reapply manually if needed —
  the slice's `programs.vim.extraConfig` matches the legacy `.vimrc` body
  minus the `pathogen#infect()` line.

**Private flake update (only if you have one):**

If your private flake adds `programs.vim.plugins` or `programs.vim.extraConfig`
entries, Nix module merging handles them additively on top of the public
baseline. Conflicting keys (e.g., overriding the colorscheme) need
`lib.mkForce` in the private module.
```

## Open questions resolved during plan / implementation

1. **`programs.vim`'s on-disk vimrc path.** home-manager's `programs.vim` writes to `~/.vim/vimrc` on some versions and `~/.vimrc` on others (and may write to both, with `~/.vimrc` sourcing the inner one). The plan verifies which path is actually used at the current home-manager pin (`release-26.05`) and the migration script targets whichever path it would conflict with. If both paths get linked, the migration script needs to move-aside both pre-existing forms.

2. **`vimPlugins.vim-javascript` attribute name.** Verify at the pinned nixpkgs revision (`nixos-26.05`) that the plugin is named `vim-javascript`. If pangloss/vim-javascript ships under a different attribute name (e.g., `vim-javascript-pangloss`), adjust the import accordingly.

3. **Wrapper script and `command -v vim`.** home-manager's `programs.vim` creates a wrapped binary at `~/.nix-profile/bin/vim`. Verify that `command -v vim` still works the way other plugins/shells expect (`/Users/<user>/.nix-profile/bin/vim`). Should be fine since `~/.nix-profile/bin` is on PATH for interactive shells, but confirm during the plan's apply step.

## Testing

Per project convention (no automated tests), verification is manual. The implementation plan will include:

1. **Pre-apply snapshot.** Capture:
   - `ls -la ~/.vimrc ~/.vim/autoload ~/.vim/bundle ~/.vim/backups ~/.vim/swaps ~/.vim/undo`
   - `vim --version | head -1` (confirms which vim binary is in use today)
   - `vim -c 'echo &runtimepath' -c quit 2>&1 | tail -5` (current runtimepath)

2. **After `./apply`:**
   - `ls -la ~/.vimrc.legacy-backup ~/.vim/autoload.legacy-backup ~/.vim/bundle.legacy-backup` — all three exist.
   - `ls -la ~/.vimrc` — symlink into Nix store (or whatever home-manager generates).
   - `ls -la ~/.vim/backups ~/.vim/swaps ~/.vim/undo` — directories still exist; `.keep` files present.
   - `command -v vim` — points at `~/.nix-profile/bin/vim` (home-manager's wrapper).
   - `vim --version | head -1` — version present (sanity check).
   - `vim -c 'echo &runtimepath' -c quit 2>&1 | tail -5` — runtimepath includes the three plugin paths under `/nix/store/.../pack/home-manager/start/`.

3. **Functional checks (open vim against a few files):**
   - `vim test.js` → syntax highlighting on, JavaScript filetype detected, pangloss highlighting visible (e.g., `=>` arrow function syntax).
   - `vim test.json` → autocmd treats it as JSON-as-JavaScript per the legacy `.vimrc` autocmd block.
   - Colorscheme: `:colorscheme` reports `solarized`. Background dark.
   - Arrow keys: `<Up>` etc. are no-ops in normal and insert mode (matching legacy behavior).
   - EditorConfig: open a file in a directory with `.editorconfig` setting tab_width=4; vim respects it.
   - Backup/swap: edit and save a file in a temp dir; confirm a backup file lands in `~/.vim/backups/` (not next to the source file).

4. **Idempotence:**
   - Run `./apply` a second time.
   - The move-aside activation finds the targets already symlinked or already moved, no-ops.
   - `~/.vimrc.legacy-backup` is not overwritten on the second run.

5. **Verify bash framework cleanup:**
   - `grep -rn vim plugins/` — no matches (except the gitignored `plugins/.DS_Store` etc.).
   - `grep -rn DOTFILES_HOMEDIR_DEPS plugins/homedir/` — line shows `('claude')` only.

## Risk and rollback

**Risk profile:** Low. The change is contained:
- Plugins come from a different source (nixpkgs vs git clone) but provide the same functionality.
- Pathogen is unnecessary noise being removed (no behavioral change visible to the user — plugin loading still works).
- The legacy rsync content moves aside, not destroyed.

**Main user-visible risk:** subtle javascript-syntax-highlighting differences from swapping jelera → pangloss. Recoverable by swapping the plugin attribute back if the user notices.

**Rollback:**

1. `git revert` the slice's commits and re-`./apply` — home-manager activation reverts, but the moved-aside backups are still in `~/.vim*.legacy-backup`.
2. Manually restore: `mv ~/.vimrc.legacy-backup ~/.vimrc` and `mv ~/.vim/bundle.legacy-backup ~/.vim/bundle` etc.
3. The `plugins/vim/` bash plugin is recoverable from `git show`.

No data loss possible — all live user state (backups/swaps/undo) is preserved by the activation.

## Out of scope

- **Neovim migration.** Possible future slice; not coupled to this one.
- **Other vim plugins.** If the user wants more plugins later, they're a one-line addition to the `plugins` list — not a slice.
- **`EDITOR` env var management.** Not currently set anywhere; not added by this slice.
- **`core.editor` git setting.** Not currently set; not added.
- **`vscode` plugin retirement.** Separate plugin; future slice.
- **`claude` plugin retirement.** Separate plugin; future slice.
- **`homedir` rsync residue audit.** Separate investigation; once vim and claude are migrated, the only remaining homedir content is whatever's left.

## Cross-references

- Master design: `docs/superpowers/specs/2026-05-22-nix-migration-design.md`
- Prior slice (nix-firstrun): `docs/superpowers/specs/2026-05-26-nix-firstrun-design.md`
- Status doc: `docs/superpowers/nix-migration-status.md` (vim plugin listed under "Candidate future slices")
- Migration guide: `nix/README.md` (will gain a "For the nix-vim slice" sub-block in this slice)
