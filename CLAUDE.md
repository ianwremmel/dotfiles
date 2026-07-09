# Dotfiles Repository

Environment-aware dotfiles management. Configuration is declarative via
Nix + home-manager + nix-darwin (see `core/` and `environments/`); `./apply` is a thin bootstrapper
that resolves the active environment, installs Nix, and activates those
configurations.

## Structure

- `apply` - Flat entry script (Bash-3.2-safe; no plugin framework)
- `lib/nix` - Nix install + home-manager / nix-darwin activation logic (sourced by `apply`)
- `framework/` - Small sourced helpers: `logging`, `config` (`~/.dotfilesrc`), `environment` (resolve/persist the active environment), `compat` (ensure Homebrew on macOS)
- `core/` - The shared library flake plus the always-included `all/` layer; consumed by every environment. See `core/CLAUDE.md`.
- `environments/` - One flake per selectable environment (`default`, `agent`), each with a home half and an optional darwin half, consuming `core/`.
- `custom_environments/` - Git-ignored; a separate private repo (its own flake consuming the public one) supplying per-machine config

Subtree guides: `framework/CLAUDE.md` (bootstrap internals), `core/CLAUDE.md`
(where shared config goes + the layering model).

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
- New configuration belongs in `core/` (shared) or `environments/<env>/`
  (per-environment), not in new shell plugins — the plugin framework was retired.

## Keep the public repo public

This repository is public. `custom_environments/` is a git-ignored, separate
private repo that consumes this one. While working in `custom_environments/`
you will discover things — bugs, missing hooks, ergonomic gaps — that call for
a change here in the main repo. Make that change, but **never carry the private
context across the boundary**: nothing that may be proprietary or private to
`custom_environments/` (hostnames, machine names, employer/client names,
internal URLs, service names, credentials, private paths, or the specifics of
why the change was needed) may appear in a main-repo commit message, PR title
or body, code comment, or the code itself. Describe the change on its own
public terms — the generic capability it adds or the generic problem it fixes —
as if it had been found without ever seeing the private config.

## Testing

No automated tests. Manual testing via `./apply` (and `/bin/bash -n` parse-checks
under the 3.2 parser for the shell files).
