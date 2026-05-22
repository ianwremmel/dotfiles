# Nix-managed dotfiles (slice)

This directory is a [Nix flake](https://nixos.wiki/wiki/Flakes) that manages a
growing slice of the dotfiles via [home-manager](https://github.com/nix-community/home-manager),
activated automatically by the `nix` plugin during `./apply`.

## Background

The repo is mid-migration from the homegrown plugin framework toward Nix. See
`docs/superpowers/specs/2026-05-22-nix-migration-design.md` for the design and
planned phases. Today this manages only the `bat` package and its config, as a
proof of the install → build → activate loop.

## Install

`./apply` runs the `nix` plugin, which installs Nix (via the Determinate Systems
installer) if absent, then builds and activates `homeConfigurations.<user>`. The
first `./apply` is therefore the Nix bootstrap.

To build/activate by hand after Nix is installed:

    out="$(mktemp -d)/result"
    nix build "path:$PWD#homeConfigurations.ian.activationPackage" --out-link "$out"
    "$out/activate"

## Usage

Edit `home.nix` to add packages (`home.packages`) or program modules
(`programs.*`), then re-run `./apply` (or the manual build/activate above).

## Backout

- **Disable the slice:** set `DOTFILES_NIX_SKIP=1` before `./apply`.
- **Drop a managed file:** remove its lines from `home.nix` and re-activate;
  home-manager removes only symlinks it created.
- **Remove Nix entirely:** delete `plugins/nix/` and `nix/`, then run
  `/nix/nix-installer uninstall`.

## License

Same as the parent dotfiles repository.
