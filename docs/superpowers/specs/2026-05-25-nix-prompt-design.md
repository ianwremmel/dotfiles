# Nix Prompt Slice Design

**Date:** 2026-05-25
**Status:** Draft — pending user approval
**Branch:** `nix-prompt` (stacks on `nix-shells` / PR #66 → `nix-commit-signing` / PR #65 → `nix-git` / PR #64 → `nix-profiles` / PR #63 → `nix-cross-platform` / PR #62)

## Goal

Retire the `plugins/powerlevel` plugin and the 1443-line `environments/all/home/.p10k.zsh` rsync source by switching the interactive shell prompt from Powerlevel10k to [Starship](https://starship.rs), managed declaratively via home-manager's `programs.starship.enable`. Slice 6 left three temporary p10k-related blocks inside `nix/profiles/all/shells.nix`'s `initContent` (the instant-prompt header, the `~/powerlevel10k/` theme source, and the `~/.p10k.zsh` source); this slice removes all three.

This is **Slice 7** in the Nix migration. The next slice retires `nvm`/`node` (Slice 8). Together Slices 6, 7, 8 retire the entire shell ecosystem.

## Decisions (locked)

1. **Switch from Powerlevel10k to Starship.** Loses p10k's instant-prompt (sub-second startup paint) and built-in transient-prompt. Gains cross-shell support (bash + zsh + fish + others), simpler nix-managed config (typed Nix attrset → TOML), no manual git clone, and roughly 1300 fewer lines of prompt config in the public repo.
2. **Starship defaults, no overrides.** `programs.starship.enable = true` with an empty `settings = { }`. No attempt to recreate the visual fidelity of the existing p10k "lean" config — iterate post-merge if a default module is undesirable. Smaller blast radius; faster slice.
3. **Retire `plugins/powerlevel/` entirely.** The plugin's only job was the `git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$HOME/powerlevel10k"` install. Nothing else references it.
4. **Move `~/.p10k.zsh` aside, not delete.** A `migrateLegacyP10kConfig` activation script moves any pre-existing real `~/.p10k.zsh` to `~/.p10k.zsh.legacy-backup`, marker-gated by `~/.p10k.hm-migrated`. Same pattern as `migrateLegacyShellConfig` and `migrateLegacyGnupgConfig`.
5. **Leave `~/powerlevel10k/` (the cloned theme repo) alone.** With nothing sourcing it, it's an inert 228-entry directory in `$HOME`. README documents the cleanup one-liner (`rm -rf ~/powerlevel10k`) for when the user is ready. The activation script does not touch it — that's a 600MB-ish git repo and accidentally moving it would be heavy-handed.
6. **All content in `nix/profiles/all/shells.nix`.** No new submodule; this slice adds ~12 lines (starship enable + the activation script) and removes ~10 lines (the temp p10k blocks). The `shells.nix` file is already focused on shell config; the prompt slots in naturally.
7. **`entryBefore [ "checkLinkTargets" ]` DAG ordering.** Same rationale as Slice 5 and Slice 6's other migrations: home-manager's checkLinkTargets would not actually conflict here (starship writes `~/.config/starship.toml`, not `~/.p10k.zsh`), but using the same DAG edge keeps the activation patterns consistent across all migrations.
8. **No work-specific values in the public repo.** No work-specific starship settings. The README sub-block is pattern-only.

## Architecture

```text
DELETIONS (committed in this slice):
  plugins/powerlevel/                              # whole dir (bash plugin)
  environments/all/home/.p10k.zsh                  # 1443-line rsync source

REMOVED FROM nix/profiles/all/shells.nix:
  initContent's instant-prompt-header block        # `if [ -d "$HOME/powerlevel10k" ]` at top
  initContent's theme-source block                 # `source ~/powerlevel10k/powerlevel10k.zsh-theme`
  initContent's .p10k.zsh-source line              # `[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh`

ADDITIONS in nix/profiles/all/shells.nix:
  programs.starship.enable = true; settings = { };
  home.activation.migrateLegacyP10kConfig          # one-time, marker-gated

UNTOUCHED IN THIS SLICE:
  ~/powerlevel10k/                                 # cloned repo stays on disk, just unused
  ~/.config/starship.toml                          # home-manager writes this only if settings != {}
  plugins/nvm/                                     # Slice 8
  plugins/node/                                    # Slice 8

PRIVATE-REPO CLEANUP (documented in README, not committed here):
  Delete custom_environments/<env>/home/.p10k.zsh if present (none in current public template).
  Add programs.starship.settings overrides to private flake if per-env customization needed.
```

## `programs.starship` block in `shells.nix`

Added alongside the existing `programs.bash` and `programs.zsh` blocks. Placement: after `programs.zsh`, before the activation scripts.

```nix
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
```

**enableBashIntegration / enableZshIntegration** default to `true`; rely on them. Home-manager injects the `eval "$(starship init bash)"` / `eval "$(starship init zsh)"` lines into the generated `.bashrc` / `.zshrc`.

## Removed content in `shells.nix`'s `initContent`

Three blocks come out:

```nix
# REMOVE this from initExtraFirst-equivalent (top of initContent):
if [ -d "$HOME/powerlevel10k" ]; then
  if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
    source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
  fi
fi

# REMOVE this from end-of-initContent:
if [ -d "$HOME/powerlevel10k" ]; then
  source ~/powerlevel10k/powerlevel10k.zsh-theme
fi

# REMOVE this:
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
```

After removal, the `zshrc-d-prompt.zsh` sibling file (which contains the fallback prompt that ran only when p10k was absent) is also dead code. **Delete the sibling file** and remove its `builtins.readFile` reference from `initContent`.

## `migrateLegacyP10kConfig` activation script

```nix
home.activation.migrateLegacyP10kConfig = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
  # One-time migration: starship replaces p10k. The old rsync'd ~/.p10k.zsh
  # is no longer sourced; move it aside as a backup. ~/powerlevel10k/ (the
  # cloned theme repo) is left in place — inert without sourcing; user can
  # `rm -rf` it manually.
  if [ ! -e "$HOME/.p10k.hm-migrated" ]; then
    if [ -f "$HOME/.p10k.zsh" ] && [ ! -L "$HOME/.p10k.zsh" ]; then
      run mv -n "$HOME/.p10k.zsh" "$HOME/.p10k.zsh.legacy-backup"
      echo "Moved legacy ~/.p10k.zsh → ~/.p10k.zsh.legacy-backup (one-time migration)"
    fi
    run touch "$HOME/.p10k.hm-migrated"
  fi
'';
```

**Properties:**

- **One-time effective.** `~/.p10k.hm-migrated` marker short-circuits subsequent applies.
- **Non-destructive.** `mv -n` (no-clobber) guards against accidental backup-overwrite on a hypothetical crashed-mid-loop re-run.
- **Linux-safe.** The per-file `[ -f … ] && [ ! -L … ]` guard makes this a no-op on Linux machines that never had `.p10k.zsh` from the macOS-only powerlevel plugin. The marker still gets touched, so subsequent Linux runs short-circuit silently.
- **Leaves `~/powerlevel10k/` alone.** Not in scope. Documented in the README sub-block as a manual `rm -rf` if/when the user wants the disk space back.

## Cross-profile concerns

- **`programs.starship` goes in `all`.** Every machine — agent boxes included — benefits from a prompt. Starship is cross-shell so it works regardless of which shell is active.
- **`default` profile** unchanged in this slice.
- **`agent` profile** stays lean; gets starship via `all`.
- **Work private flake** can override via `programs.starship.settings = lib.mkForce { … };` (override the empty default) or via `lib.recursiveUpdate` to merge attrs from multiple layers. Documented abstractly in the README sub-block.

## Testing

- **Pre-flight (macOS):**
  - `ls -la "$HOME/.p10k.zsh" "$HOME/powerlevel10k/" | head -10`
  - `cat "$HOME/.p10k.zsh" | wc -l` (expected: 1443)
  - `[ -L "$HOME/.p10k.zsh" ] && echo "already symlink" || echo "real file"`
  - `command -v starship; starship --version 2>&1 || echo "starship absent"` (expected: absent or maybe brew-installed)
  - `ls -la "$HOME/.p10k.hm-migrated" 2>&1 | head -1` (expected: absent)

- **Activation: legacy backup.** Run the plugin direct. Confirm:
  - One "Moved legacy …" line.
  - `~/.p10k.hm-migrated` marker exists.
  - `~/.p10k.zsh.legacy-backup` exists, byte-identical to pre-flight content.
  - `~/.p10k.zsh` is absent (the move happened; no home-manager-managed file replaces it, since the new code doesn't write `.p10k.zsh`).

- **Verify starship is installed and on PATH.**
  - `command -v starship` resolves into `~/.nix-profile/bin/starship`.
  - `starship --version` reports a version (likely 1.x).
  - `[ -f "$HOME/.config/starship.toml" ] && echo "config written" || echo "no config (defaults active)"` — either is acceptable. With `settings = { }`, home-manager may or may not write an empty TOML file; the prompt still works either way.

- **Verify generated `~/.zshrc` and `~/.bashrc` source starship init.**
  - `grep -n 'starship init' "$HOME/.zshrc"` returns one match (HM-injected `eval "$(starship init zsh)"`).
  - `grep -n 'starship init' "$HOME/.bashrc"` returns one match.
  - `grep -n 'powerlevel\|p10k' "$HOME/.zshrc" "$HOME/.bashrc"` returns NOTHING (all temp p10k blocks gone).

- **Verify fresh-shell prompt is starship.**
  - Open a fresh terminal. The prompt is starship's default (`directory $git_branch $git_status\n$character`) — NOT p10k's lean style.
  - No "p10k.zsh: file not found" or "powerlevel10k.zsh-theme: file not found" errors.
  - No instant-prompt warning (instant-prompt is a p10k concept; starship doesn't emit one).
  - `bash -lic exit` shows the starship prompt then exits.

- **Activation idempotency.** Re-run activation; no "Moved legacy …" line; marker preserved; `.p10k.zsh.legacy-backup` mtime unchanged.

- **Cross-slice intact.** `git config alias.fixup` returns `commit --fixup`; `git config commit.gpgsign` returns `true`; `git --version` returns `2.54.0`; shell aliases (`psgrep`, `xo`) work; `gpg --version` resolves to nix store; `bat --version` works.

- **Throwaway private override.** Scratch flake sets `programs.starship.settings = lib.mkForce { add_newline = false; };`. Activate; `cat ~/.config/starship.toml` contains `add_newline = false`. `starship explain` (or just observe the prompt) confirms the override is active. Tear down; default behavior restored.

- **Linux container (aarch64-linux, agent profile).** `./apply` runs; starship installs into the nix profile; `bash -lic 'echo prompt-test'` shows starship prompt; `~/.p10k.hm-migrated` marker present (touched even on Linux despite no `.p10k.zsh` to move); no `.p10k.zsh.legacy-backup` (clean container had nothing to backup).

- **Backout drill (documented in README, not automated):** delete `~/.p10k.hm-migrated`, restore `~/.p10k.zsh.legacy-backup` to `~/.p10k.zsh`, re-apply. The activation re-detects the real file and re-moves it aside. Confirms recovery.

## README updates

Three changes to `nix/README.md`:

1. **New "For the prompt slice" sub-block** in the existing private-environment migration guide:

   ```markdown
   For the prompt slice (`powerlevel` plugin retired; `.p10k.zsh`
   dropped; starship via `programs.starship.enable` takes over):

   1. If your private flake had a `custom_environments/<env>/home/.p10k.zsh`
      override (none in the public template), `git rm` it from your private
      repo and commit. Starship reads no such file; the rsync source is
      orphaned.

   2. To customize starship per-environment, add to your private flake:

          { lib, pkgs, ... }: {
            programs.starship.settings = lib.mkForce {
              # …your starship.toml content as a Nix attrset…
            };
          }

      Use `lib.mkForce` because the public profile sets `settings = { };` —
      the typed attrset would conflict without it. Alternatively, use
      `lib.recursiveUpdate` if you want to merge with potential future
      public defaults.

   3. **First `./apply` after this slice** runs `migrateLegacyP10kConfig`,
      which moves any pre-existing `~/.p10k.zsh` aside to `.legacy-backup`.
      The cloned `~/powerlevel10k/` repo is left in place (~600MB-ish
      inert directory); `rm -rf ~/powerlevel10k` when satisfied.
   ```

2. **Refresh the Background paragraph** to add the prompt entry. Append to the existing "and shell config …" segment:

   `…and a prompt — starship via \`programs.starship\` (replacing the retired powerlevel plugin and its rsync'd \`.p10k.zsh\`).`

3. **Refresh the `all`-layer parenthetical** under `### Public profiles and layers`:

   `(currently \`bat\`, the shared git config — aliases, body, includes — via \`programs.git\`, GPG/agent setup with per-OS pinentry: \`pinentry-mac\` on macOS, \`pinentry-tty\` on Linux, bash + zsh via \`programs.bash\` + \`programs.zsh\` plus \`.inputrc\` via \`home.file\`, AND starship as the prompt)`

## Scope / Non-goals

**In scope:**

- Retire `plugins/powerlevel/` entirely (the bash plugin and its `git clone` install).
- Delete `environments/all/home/.p10k.zsh` (the 1443-line rsync source).
- Remove three p10k-related blocks from `nix/profiles/all/shells.nix`'s `initContent`.
- Delete the `zshrc-d-prompt.zsh` sibling file and its `builtins.readFile` reference (the fallback prompt was already conditional on p10k absence; with p10k retired, the fallback never runs anyway).
- Add `programs.starship.enable = true` with `settings = { }` to `shells.nix`.
- Add `migrateLegacyP10kConfig` activation (moves `~/.p10k.zsh` to `.legacy-backup`, marker-gated).
- README sub-block + Background refresh + `all`-layer refresh.

**Out of scope:**

- Recreating the visual fidelity of the existing p10k "lean" config in starship. (Use defaults; iterate post-merge.)
- Cleaning up `~/powerlevel10k/` automatically. (User runs `rm -rf` manually.)
- Restoring an instant-prompt-equivalent feature. (Starship doesn't have one; if startup feels slow, profile zsh init separately.)
- Supporting a transient-prompt-equivalent. (Possible with starship's `right_format` + custom modules; not in this slice.)
- Switching between starship and p10k on a per-profile basis. (One prompt for all.)
- Removing the temporary `if [ -d "$HOME/powerlevel10k" ]` guards before Slice 6 (they're already in `shells.nix`; this slice removes them).
- Brewfile cleanup of any p10k brew dependencies. (None — powerlevel10k was installed via git, not brew.)

## Future phases

Slice 8 (`nvm`/`node` plugins) follows the same pattern: retire the bash plugin, remove the temporary nvm-load block from `shells.nix`'s `initContent`, switch to `programs.nodejs` or similar home-manager option. With Slice 8 complete, the entire shell ecosystem (Slices 6 + 7 + 8) is migrated.

Beyond the shell ecosystem: per-tool slices for `vim`, `claude`, `vscode`, `xcode`, and eventually the homebrew retirement (which would let `chshAndEtcShells` drop the brew-zsh-coexistence case).
