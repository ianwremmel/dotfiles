# Nix VSCode Slice Design

**Date:** 2026-05-27
**Status:** Draft — pending user approval
**Branch:** `nix-vscode` (stacks on `nix-claude` / PR #73 → `nix-vim` / PR #72 → … → master)

## Goal

Retire the `vscode` bash plugin. The plugin's sole job is to symlink VS Code's `code` CLI helper onto PATH (`ln -s "/Applications/Visual Studio Code.app/.../bin/code" "$(brew --prefix)/bin/code"`). This is now redundant: the `visual-studio-code` Homebrew cask — declared in nix-darwin since slice 10 — lists `code` and `code-tunnel` as **binary artifacts**, so Homebrew symlinks them into `/opt/homebrew/bin/` (which is on PATH) when it installs the cask. The plugin is pure dead weight. This slice deletes it.

## Why this is a pure deletion (no nix code)

- **`code` is a cask artifact.** `brew info --cask visual-studio-code` lists:
  ```
  /Applications/Visual Studio Code.app/Contents/Resources/app/bin/code (Binary)
  /Applications/Visual Studio Code.app/Contents/Resources/app/bin/code-tunnel (Binary)
  ```
  Homebrew links `binary` artifacts into `$(brew --prefix)/bin/` on cask install. Since the cask is already declared in `nix/darwin/base.nix`, `code` is provided by the existing declarative homebrew layer — nothing new is needed.
- **Plugins are auto-discovered.** `framework/plugin`'s `plugin_list_plugins` iterates `plugins/*` (line 137); there is no explicit plugin registry to edit. Deleting the directory removes the plugin from the apply flow with zero framework changes.
- **No rsync content, no config, no state.** The plugin only ever created a symlink. There is nothing to migrate, no `home.file`, no activation, no move-aside.
- **No dependents.** `grep -rn vscode framework/ plugins/ environments/ apply` finds zero references outside `plugins/vscode/vscode` itself.

## Decisions (locked)

1. **Pure deletion — trust the cask.** Per user: delete `plugins/vscode/`; rely on the `visual-studio-code` cask's binary artifacts to provide `code`/`code-tunnel` on PATH. No declarative home-manager symlink (the belt-and-suspenders alternative was considered and rejected as redundant with the cask).
2. **Leave the existing `/opt/homebrew/bin/code` symlink in place.** It already exists and points at the app helper. Whether it was created by the old plugin or by brew, the cask's binary artifact owns that path going forward. `homebrew.onActivation.cleanup = "uninstall"` only removes undeclared casks/formulae/taps, not arbitrary bin symlinks, so it persists untouched. No cleanup needed.
3. **No nix files, no framework changes.** Auto-discovery handles removal.
4. **README migration guide block** documents the retirement and that `code` is cask-provided.
5. **No work-specific values.**

## Architecture

```text
MODIFIED FILES:
  nix/README.md            # +migration guide sub-block for nix-vscode slice

DELETED:
  plugins/vscode/          # whole dir (just the `vscode` script)

UNTOUCHED:
  nix/darwin/base.nix      # visual-studio-code cask already declared (slice 10); provides code/code-tunnel
  framework/               # auto-discovery; no registry to edit
  /opt/homebrew/bin/code   # existing symlink, now cask-owned, left as-is
  everything else
```

## Migration guide block in `nix/README.md`

Append after the "For the nix-claude slice" sub-block, paragraph-heading style:

```markdown
For the nix-vscode slice (`vscode` plugin retired; `code` CLI now provided by the cask):

The bash `vscode` plugin only symlinked VS Code's `code` CLI helper onto PATH.
That's now redundant: the `visual-studio-code` cask (declared in nix-darwin since
the nix-darwin slice) lists `code` and `code-tunnel` as binary artifacts, so
Homebrew links them into `/opt/homebrew/bin/` (on PATH) when it installs the
cask. The plugin is deleted with no replacement — Homebrew owns the symlink.

**One-time apply notes:**

- No action needed. If `code` ever goes missing after a VS Code reinstall, run
  `brew reinstall --cask visual-studio-code` to relink the binary artifacts, or
  use VS Code's "Shell Command: Install 'code' command in PATH" from the command
  palette.
```

## Testing

Per project convention (no automated tests), verification is manual:

1. **Pre-flight:** `command -v code` resolves to `/opt/homebrew/bin/code`; `plugins/vscode/` exists.
2. **After deletion + `./apply`:** `command -v code` still resolves (the symlink is untouched by deletion; the apply doesn't remove it). `code --version` runs.
3. **Framework:** `grep -rn vscode framework/ plugins/ environments/` returns nothing; `plugins/vscode/` is gone.
4. **Debug apply:** `DOTFILES_DEBUG=1 ./apply 2>&1 | grep -i vscode` returns nothing (the plugin no longer loads).

## Risk and rollback

**Risk:** Minimal. The only scenario where `code` could go missing is a fresh machine where brew's cask binary-linking didn't fire — but the artifact is declared, so `brew bundle` (run by nix-darwin) links it on install. If it ever doesn't, the README documents the one-line `brew reinstall` fix.

**Rollback:** `git revert` restores `plugins/vscode/`; the bash plugin's `ln -s` is idempotent and re-creates the symlink if absent.

## Out of scope

- **`programs.vscode` (settings/extensions/keybindings management).** The plugin never managed these; this slice does not start. A future slice could adopt `programs.vscode` if declarative settings/extensions are wanted — separate decision.
- **Removing the `/opt/homebrew/bin/code` symlink.** Left in place (cask-owned).

## Cross-references

- Master design: `docs/superpowers/specs/2026-05-22-nix-migration-design.md`
- Prior slice (nix-claude): `docs/superpowers/specs/2026-05-27-nix-claude-design.md`
- nix-darwin slice (declares the cask): `docs/superpowers/specs/2026-05-26-nix-darwin-design.md`
- Status doc (local, uncommitted): `docs/superpowers/nix-migration-status.md`
