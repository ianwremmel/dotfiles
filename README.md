# Dotfiles _(dotfiles)_

> Reasonable defaults with customizations

I ([@ianwremmel](https://github.com/ianwremmel)) forked
[Mathias Bynens's Dotfiles](https://github.com/mathiasbynens/dotfiles) many
years ago. My customizations got to the point where I made the repo private
because it was easier than dealing with non-public things that might be in my
git history. Eventually, I shared the repo with
[Riley Marsh](https://github.com/rimarsh) and we sort of managed to not step on
eachother's configs.

Our customizations have diverged enough (and we've had reason enough to share
with others) that this repo is a ground-up rewrite inspired by Mathias's
original work, but supporting per-user and per-machine personalization, a clean
history (no secrets from former employers in this repo!), and a first-run script
that can be copied-and-pasted from this very README.

## Install

```bash
git clone https://github.com/ianwremmel/dotfiles
```

## Usage

Apply the repo to your system (you may be prompted to pick an environment on
first run — see Environments).

```bash
cd dotfiles
./apply
```

Set `DOTFILES_DEBUG=1` for debug logging.

### Configuration

On first run, dotfiles will create `~/.dotfilesrc`. In general, this file should
not be edited directly, however, if you wish to change a setting, you may delete
that setting from the file to be reprompted on next run.

## Environments

An environment names the config for a computer (or category of computers) — e.g.
"home" or "work". An environment is any directory under `environments/` or
`custom_environments/` that contains a `flake.nix`. `./apply` lists those
candidates: with a persisted `DOTFILES_ENVIRONMENT` it uses that; with exactly
one candidate it uses it; with several it prompts on first run and persists the
choice in `~/.dotfilesrc`. A name with no matching flake fails the build.

Configuration lives in two layers:

- **Public** (`environments/`) — @ianwremmel's declarative config. A core library
  flake supplies the shared layers; each environment is its own flake that
  consumes the core (`default` for personal machines, `agent` for lean/headless
  boxes). See `environments/`.
- **Private** (`custom_environments/`) — git-ignored, typically a separate repo
  you clone here. Each environment is a flake at `custom_environments/<env>/`
  that consumes the public core and layers your machine-specific config on top; a
  private env wins over a public one of the same name. See
  `environments/README.md` for the template.

## How it works

`./apply` is a thin bootstrapper. It:

1. Resolves the active environment (see Environments) and picks its flake
   (`custom_environments/<env>/` if present, else `environments/<env>/`).
2. On macOS, ensures Homebrew is present (nix-darwin's homebrew module needs it).
3. Installs Nix (if needed), generates `environments/host.nix`, then builds and
   activates that environment's home-manager configuration and — on macOS — its
   nix-darwin system layer. This is where the configuration lives (see
   `environments/`). The nix-darwin layer is the selected environment's own
   darwin half; an environment with no `darwin.nix` still gets the universal
   system layer.

The bootstrap logic lives in `apply` plus a few small sourced helpers under
`framework/` (`logging`, `config`, `environment`, `compat`) and `lib/nix`. New
configuration belongs in `environments/`.

## Conventions

- Scripts are extensionless and rely on their shebang for interpreter.
- Environment variables and globals are all caps, with underscores as
  separators.
- Functions and local variables are snake case.
- `apply` and the `framework/*` helpers are sourced/run as a single process and
  must work on stock macOS Bash 3.2.57 — no Bash-4-only features (`local -n`
  namerefs, `${var^^}` case modification, associative arrays, etc.). Nix provides
  a general-purpose Bash 5 for everything else. shellcheck supports bash, not zsh.

## Contributing

PRs welcome, but please first open an issue for anything but the most trivial of
changes. While I'm very open to improvements, these are my customizations for my
personal machines, so you may be better off adding your own custom environment
rather than trying to make a change :)

## License

[MIT] &copy; Ian Remmel & Riley Marsh
