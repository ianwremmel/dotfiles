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

Apply the repo to your system. You'll be prompted on first run.

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

Environments define config for a particular computer (or category of computers).
For example, you might have an environment called "home" and an environment
called "work".

There are two special environment names with extra behavior. Configuration in
the `all` environment gets applied to every device regardless of any other
environment name being set. `default` gets applied on any device that doesn't
have a specific environment set. It's entirely possible (likely, even) that
these are the only environments you'll need.

Environments are are defined in two place:

- `environments` - these are defined in this reposity. These are @ianwremmel's
  custom dotfiles. You may be happy with them or you may wish to customize them.
  They tend to change regularly (particularly his brewfile, so you'll likely
  want to copy `all` and `default` to your `custom_environments`)
- `custom_environments` - This folder is gitignored. You can choose to put your
  environments here and not track them, but you'll probably want to create a
  separate repo that you checkout to this folder. If you create a folder called
  e.g. `all` in `custom_environments`, it will be used exclusively in place of
  the `all` in `environments`. If that folder is empty, you'll be working from a
  completely clean slate (other than the Nix-managed configuration)

## How it works

`./apply` is a thin bootstrapper. It:

1. Resolves the active environment (prompting once when more than one exists) and
   persists it to `~/.dotfilesrc`. The environment selects the home-manager
   profile and any private flake under `custom_environments/<env>/nix`.
2. On macOS, ensures Homebrew is present (nix-darwin's homebrew module needs it).
3. Installs Nix (if needed), generates `nix/host.nix`, then builds and activates
   the home-manager configuration and — on macOS — the nix-darwin system layer.
   This is where the configuration lives (see `nix/`).

The bootstrap logic lives in `apply` plus a few small sourced helpers under
`framework/` (`logging`, `config`, `environment`, `compat`) and `lib/nix`. The
homegrown plugin framework that predated the Nix migration has been retired; new
configuration belongs in `nix/`.

## Conventions

- Scripts are extensionless and rely on their shebang for interpreter.
- Environment variables and globals are all caps, with underscores as
  separaters.
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
