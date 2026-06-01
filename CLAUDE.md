# Dotfiles Repository

Environment-aware dotfiles management. Configuration is declarative via
Nix + home-manager + nix-darwin (see `environments/`); `./apply` is a thin bootstrapper
that resolves the active environment, installs Nix, and activates those
configurations.

## Structure

- `apply` - Flat entry script (Bash-3.2-safe; no plugin framework)
- `lib/nix` - Nix install + home-manager / nix-darwin activation logic (sourced by `apply`)
- `framework/` - Small sourced helpers: `logging`, `config` (`~/.dotfilesrc`), `environment` (resolve/persist the active environment), `compat` (ensure Homebrew on macOS)
- `environments/` - The declarative configuration: a core library flake plus one flake per environment (`default`, `agent`), each with a home half and an optional darwin half. See `environments/CLAUDE.md`.
- `custom_environments/` - Git-ignored; a separate private repo (its own flake consuming the public one) supplying per-machine config

Subtree guides: `framework/CLAUDE.md` (bootstrap internals), `environments/CLAUDE.md`
(where config goes + the layering model).

## Running

```bash
./apply              # Full application
DOTFILES_DEBUG=1 ./apply  # Verbose logging
```

## Conventions

- `apply` and `framework/*` must run on stock macOS Bash 3.2.57 (no Bash-4-only
  features: no `local -n` namerefs, no `${var^^}` case modification, etc.). Nix
  provides a general-purpose Bash 5 for everything else.
- Config persisted to `~/.dotfilesrc`. `DOTFILES_ENVIRONMENT` is written only
  when the env prompt runs (some env besides bare `default` exists); the
  selection — which may be `default` — is stored. With only `default`/none,
  it's used implicitly and nothing is persisted.
- The macOS system layer (nix-darwin) is built from the *selected* environment's
  own darwin half; an environment with no `darwin.nix` (e.g. `agent`) still gets
  the universal `base` + `all` system layer, and a private env can ship its own
  system state via its `darwin.nix`.
- New configuration belongs in `environments/` (home-manager / nix-darwin), not
  in new shell plugins — the plugin framework was retired.

## Testing

No automated tests. Manual testing via `./apply` (and `/bin/bash -n` parse-checks
under the 3.2 parser for the shell files).
