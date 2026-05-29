# Framework Collapse — Implementation Plan

**Spec:** `docs/superpowers/specs/2026-05-28-framework-collapse-design.md`
**Branch:** `framework-collapse` (stacks on `nix-terminal-fonts` / PR #76)
**Slice:** 17

Goal: make `./apply` run on stock macOS Bash 3.2.57 by collapsing the plugin
framework into a flat orchestrator, deleting the Bash-4-only plugin machinery
and `customize`, moving the nix logic to `lib/nix`, and folding the homedir
rsync into `apply`. Drop brew's `bash`/`bash-completion@2` (Nix already provides
Bash 5); repoint bash completion to Nix.

## Step 1 — Relocate nix logic to `lib/nix`

- `git mv plugins/nix/nix lib/nix`.
- Remove the `export DOTFILES_NIX_DEPS=()` line (line 3) — no plugin concept.
- Leave all `_dotfiles_nix_*` helpers and `dotfiles_nix_apply` otherwise intact
  (substance unchanged — install, profile-load, `host.nix`, build, activate HM,
  nix-darwin). It already only depends on `log`/`debug`/`error` and
  `DOTFILES_{ROOT_DIR,ENVIRONMENT,AIRPLANE_MODE,NIX_SKIP}` — all still provided.
- Confirm it is 3.2-safe (audit: only `local -a` with `=()` init, which is fine).

## Step 2 — Rewrite `apply` as the flat orchestrator

New `apply` (3.2-safe; runs entirely in the invoking shell — no self re-exec):

```bash
#!/usr/bin/env bash
set -euo pipefail

export DOTFILES_ROOT_DIR
DOTFILES_ROOT_DIR="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"

export DOTFILES_AIRPLANE_MODE=0
while getopts "Ah?" opt; do
  case $opt in
    A) DOTFILES_AIRPLANE_MODE=1 ;;
    ?) echo "Usage: $(basename "$0") [-A] [-h|-?]"; exit 2 ;;
  esac
done

source ./framework/logging
source ./framework/config
source ./framework/environment
source ./lib/nix

# ~/.dotfilesrc must exist for config_read/_write (mode 0600 = framework default)
[ -f "$HOME/.dotfilesrc" ] || install -m 0600 /dev/null "$HOME/.dotfilesrc"

environment_get_current      # prompt + persist DOTFILES_ENVIRONMENT (side effect)
config_load                  # export DOTFILES_ENVIRONMENT etc.

if [ "$(uname -s)" = Darwin ]; then
  echo 'Many of the following commands will need root access'
  echo 'Please enter your password to (hopefully) only be prompted once'
  sudo -v
  while true; do sudo -n true; sleep 30; kill -0 "$$" || exit; done 2>/dev/null &

  # nix-darwin's homebrew module requires brew present; it does not install it.
  source ./framework/compat
  compat_ensure_homebrew
fi

dotfiles_nix_apply           # install nix, host.nix, build+activate HM, nix-darwin

# Home-dir rsync (folded in from the retired homedir plugin). Serves
# environments/all/home (empty since slice 15) + custom_environments/<env>/home
# until the work-finale retires that content.
_dotfiles_apply_home () {
  local candidate
  candidate="$(environment_get_path "$CURRENT_ENVIRONMENT" home)"
  if [ -d "$candidate" ]; then
    debug "Rsyncing $candidate to $HOME"
    rsync --exclude ".DS_Store" --exclude ".git/" -av "$candidate/" "$HOME"
  fi
}
environment_map_func _dotfiles_apply_home

echo ''
echo 'Please reload your shell to apply changes'
echo ''
```

Notes:
- `environment_get_current` is called bare (output to terminal) — matches the
  current `framework_init` behavior; needed for the first-run `select` prompt and
  the `config_write` persist when multiple envs exist.
- The Linux and macOS paths are now one script; nix-darwin/brew/sudo are
  Darwin-guarded; the nix logic self-guards nix-darwin on Darwin.
- Drop the old `source ./framework/compat` at the top (no Bash-5 gate anymore).

## Step 3 — Trim `framework/compat`

- Delete `compat_ensure_modern_bash` and its bottom-of-file invocation
  (lines 39-46).
- Keep `compat_ensure_homebrew` (already 3.2-safe). The file now defines only
  that one function (sourced + called by `apply` on macOS).

## Step 4 — Delete the plugin machinery + customize

- `git rm framework/framework framework/plugin framework/util framework/customize`
- `git rm -r plugins/` (removes `plugins/nix/` — already moved — and
  `plugins/homedir/`).
- Prune dead `environment_get_item_path` from `framework/environment` (the
  `error`-debug + `[ -f ] || [ -f ]` bug function; unused). Keep
  `environment_list_environments` (used by `environment_map_func`).

## Step 5 — Drop brew's bash; repoint completion

- `nix/darwin/base.nix`: remove `"bash"` and `"bash-completion@2"` (and their
  bootstrap comment) from `homebrew.brews`. `cleanup = "uninstall"` removes them
  on the next nix-darwin activation.
- `nix/profiles/all/cli-tools.nix`: drop the "also stays in Brewfile per Decision
  4" comments on `bash` (line 47) and `bash-completion` (line 48); `bash` stays
  in `home.packages` (this is the general-purpose Bash 5).
- `nix/profiles/all/bash-completion.bash`: **first verify** whether
  `programs.bash` (`shells.nix:84`) sets `enableCompletion` (home-manager default
  is `true`, which sources the nix `bash-completion` profile automatically). 
  - If yes: the brew block (lines 30-43) becomes dead → delete it.
  - If no: add a block sourcing
    `$HOME/.nix-profile/share/bash-completion/bash_completion` (guard `[ -f ]`),
    and leave the brew block as a harmless fallback.

## Step 6 — Reference sweep

- `grep -rn` across the repo for dangling references to deleted symbols:
  `framework_apply`, `framework_init`, `plugin_`, `array_contains`, `array_map`,
  `function_exists`, `is_set`, `customize_main`, `DOTFILES_.*_DEPS`,
  `prompt_string`, `framework/framework`, `framework/plugin`, `framework/util`,
  `framework/customize`, `plugins/`. Fix any stragglers (READMEs, CLAUDE.md
  conventions block, comments).
- `CLAUDE.md` (repo) documents plugin conventions
  (`dotfiles_<plugin>_apply()`, `DOTFILES_<plugin>_DEPS`, etc.) — update that
  section to reflect the collapsed, plugin-free structure.

## Step 7 — Docs

- `nix/README.md`: add a migration-guide sub-block for the framework-collapse
  slice (brew `bash`/`bash-completion@2` uninstalled on next apply; no
  private-flake change needed; `custom_environments` now cloned manually).
- `docs/superpowers/nix-migration-status.md`: add slice 17 row; mark deferral #1
  (bash-bootstrap) **closed by collapse**; note `customize` removed and the
  plugin framework retired (only `lib/nix` + slim `framework/` helpers remain).

## Step 8 — Update memory

- Update `nix-bootstrap-bash-deferred` memory: deferral closed by the
  framework-collapse slice (not by boot-order inversion). Note the new structure.

## Verification

1. `/bin/bash --version` → confirm 3.2.57.
2. `/bin/bash -n apply`; `/bin/bash -n lib/nix`; `/bin/bash -n` each surviving
   `framework/*`. Clean parse under 3.2 proves no Bash-4 syntax remains.
3. `grep -rn` sweep (step 6) returns no dangling references.
4. `/bin/bash ./apply -A` — airplane mode: exercises arg parse, env resolution,
   config persist, brew-ensure path (macOS), and the homedir rsync under 3.2.57
   with no nix network/build side effects. Expect a clean run ending in the
   reload message.
5. `./apply` (full) on this Mac — home-manager + nix-darwin activate; verify
   `brew list | grep -E '^bash'` no longer shows `bash`/`bash-completion@2` after
   the nix-darwin pass; open a fresh shell, `command -v bash` →
   `~/.nix-profile/bin/bash`, `bash --version` → 5.x, tab-completion works.
6. Linux container (slice 2 surface): `./apply` under system bash — nix install +
   HM activate succeed; homedir rsync is a no-op.

## Risks / rollback

- **Fresh-Mac brew-ensure** can't be tested here (brew already present). Mitigate
  by static review of `compat_ensure_homebrew` ordering before nix-darwin.
- **bash-completion regression** — caught by step 5 (tab-completion check).
- Everything is on a feature branch; rollback = discard branch. No merge until
  per-slice approval.
