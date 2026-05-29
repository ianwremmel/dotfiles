# Bootstrap layer (`apply`, `framework/`, `lib/nix`)

`./apply` (repo root) is a flat bootstrapper that resolves the active
environment, ensures prerequisites, and hands off to Nix. It sources these
helpers in order; they share one process and mutate its globals, so they are
sourced, not executed.

## Hard constraint: Bash 3.2

`apply` and every `framework/*` helper must run on stock macOS
`/bin/bash` (3.2.57) with no re-exec. **No Bash-4+ features**: no `local -n`
namerefs, no `${var^^}`/`${var,,}` case modification, no associative arrays,
no `mapfile`/`readarray`. Nix provides a general-purpose Bash 5 for everything
else. `shellcheck` lints these (bash only — it can't check zsh). Parse-check
with `/bin/bash -n <file>`.

## Flow (`apply`)

1. Export `DOTFILES_ROOT_DIR` (the repo dir).
2. Source `logging`, `config`, `environment`, then `lib/nix`.
3. Create `~/.dotfilesrc` (mode 0600) if missing.
4. `environment_get_current` (echoes the active environment; persists the
   selection only when the prompt runs — see the helper below) → `config_load`
   (exports every `~/.dotfilesrc` key as an env var).
5. macOS only: source `compat`; `compat_ensure_homebrew`.
6. `dotfiles_nix_apply` — the handoff to Nix.

`apply` itself never elevates; the `sudo` calls live downstream
(`compat_ensure_homebrew`'s `installer`, the Nix installer, and `lib/nix`'s
`sudo -H` nix-darwin activation), each prompting as needed.

## Helpers

- **`logging`** — `log` (stdout), `error` (stderr), `debug` (stderr, only when
  `DOTFILES_DEBUG` is non-empty).
- **`config`** — read/write `~/.dotfilesrc` (`config_read`, `config_write`,
  `config_load`); path overridable via `DOTFILES_CONFIG_FILE`. `config_load`
  exports every non-comment `KEY=value` line.
- **`environment`** — `environment_get_current` returns the persisted
  `DOTFILES_ENVIRONMENT` if set; otherwise lists candidate environments
  (`custom_environments/*`, plus the legacy `environments/` dir if present,
  excluding `all`). If the only candidate is `default` (or there are none) it
  uses `default` without prompting or persisting; if any other env exists
  (even one) it prompts and persists the choice.
- **`compat`** (macOS) — ensure Homebrew exists (nix-darwin's homebrew module
  drives `brew` but won't install it) and disable its analytics.

## `lib/nix`

`dotfiles_nix_apply`:

1. Bail early if `DOTFILES_NIX_SKIP=1`.
2. Install Nix if absent — Determinate installer on macOS (daemon; SIP
   requires it), official single-user installer on Linux — then source its
   profile script onto PATH.
3. Write **`nix/host.nix`** (untracked): `{ username; profile; }`. The flake
   refuses to build without it.
4. `nix eval … builtins.currentSystem` → `$system`.
5. Pick the flake: if `custom_environments/<profile>/nix/flake.nix` exists,
   build that private flake with `--override-input public path:.../nix` and
   target `homeConfigurations."<system>"`; otherwise build the public flake's
   `homeConfigurations."<profile>@<system>"`. Build to a temp out-link, run
   its `activate`.
6. macOS only: activate nix-darwin —
   `darwinConfigurations."default@<system>"` (only `default` has a darwin
   module). First run bootstraps via `sudo -H nix run nix-darwin -- switch`;
   later runs use `sudo -H darwin-rebuild switch`. **`-H` is required** so
   nix-darwin writes state under root, not the invoking user's `$HOME`. The
   flake ref is `path:.../nix` (non-git fetcher) so untracked `host.nix` is
   visible.

## Env vars

`DOTFILES_ENVIRONMENT` (persisted; selects profile), `DOTFILES_DEBUG` (verbose
logging), `DOTFILES_NIX_SKIP=1` (skip Nix entirely), `DOTFILES_ROOT_DIR` (set
by `apply`).

New configuration belongs in `nix/`, not here — see `../nix/CLAUDE.md`.
