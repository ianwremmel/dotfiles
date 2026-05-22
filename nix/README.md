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

`./apply` runs the `nix` plugin, which installs Nix if absent and builds and
activates `homeConfigurations."<user>@<system>"` for the current machine. The
flake supports `aarch64-darwin`, `x86_64-darwin`, `x86_64-linux`, and
`aarch64-linux`.

- **macOS:** the full framework runs; Nix is installed via the Determinate
  Systems installer (daemon-based — macOS SIP requires it).
- **Linux:** `./apply` runs only the nix step (the macOS-only plugins are
  skipped). Nix is installed single-user with no daemon via the official
  installer.

To build/activate by hand after Nix is installed:

    flags="--extra-experimental-features 'nix-command flakes'"
    out="$(mktemp -d)/result"
    sys="$(nix $flags eval --impure --raw --expr builtins.currentSystem)"
    nix $flags build "path:$PWD#homeConfigurations.\"$(whoami)@$sys\".activationPackage" --out-link "$out"
    "$out/activate"

(On a fresh Linux single-user install flakes are not enabled by default, hence
the `--extra-experimental-features` flag.)

## Usage

Edit `home.nix` to add packages (`home.packages`) or program modules
(`programs.*`), then re-run `./apply` (or the manual build/activate above).

## Backout

- **Disable the slice:** set `DOTFILES_NIX_SKIP=1` before `./apply`.
- **Drop a managed file:** remove its lines from `home.nix` and re-activate;
  home-manager removes only symlinks it created.
- **Remove Nix entirely:** delete `plugins/nix/` and `nix/`, then uninstall Nix:
  - **macOS** (Determinate): `/nix/nix-installer uninstall`.
  - **Linux** (official single-user): `nix-env --uninstall nix`, then
    `rm -rf ~/.nix-profile ~/.nix-defexpr ~/.nix-channels /nix` and remove the
    nix lines from your shell rc.

## License

Same as the parent dotfiles repository.
