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
activates `homeConfigurations."<profile>@<system>"` for the current machine
(or a private-flake config if one is set up — see Profiles). The flake
supports `aarch64-darwin`, `x86_64-darwin`, `x86_64-linux`, and
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
    profile="${DOTFILES_ENVIRONMENT:-default}"
    nix $flags build "path:$PWD#homeConfigurations.\"${profile}@${sys}\".activationPackage" --out-link "$out"
    "$out/activate"

(On a fresh Linux single-user install flakes are not enabled by default, hence
the `--extra-experimental-features` flag.)

## Usage

Edit `home.nix` to add packages (`home.packages`) or program modules
(`programs.*`), then re-run `./apply` (or the manual build/activate above).

## Profiles

Per-machine profiles select which extra modules layer on top of the shared
base. Selection reuses the framework's `DOTFILES_ENVIRONMENT` value — no new
variable — and is loaded the same way on both platforms (`./apply` runs
`environment_get_current` + `config_load` from the framework). The
plugin-generated `nix/host.nix` carries both `username` and `profile`.

(Each profile module also sets a `DOTFILES_PROFILE` shell-session variable as
a runtime sentinel — handy for quick verification with `echo $DOTFILES_PROFILE`
after activation. It is a Nix-activated reflection of the same value
`DOTFILES_ENVIRONMENT` holds in `~/.dotfilesrc`, not an independent setting.)

### Public profiles and layers

`nix/home.nix` is infrastructure (username, homeDirectory, stateVersion,
`programs.home-manager.enable`). `lib.mkHome` always composes it with the
**always-included `all` layer** (shared content every machine gets), plus
whichever selectable profile is active:

- `all` — always included via `mkHome`; shared content for every machine
  regardless of profile or private overlay (currently `bat`).
- `default` — selectable profile; matches the framework's default
  `DOTFILES_ENVIRONMENT=default` and adds `ripgrep`.
- `agent` — selectable profile for headless / agent boxes; lean.

The public flake exposes them as a module library
(`homeModules.{base,all,default,agent}` + a `lib.mkHome` helper) and as
ready-made `homeConfigurations."<profile>@<system>"` outputs (one per
selectable profile × system). When no private flake matches the active
profile, the plugin builds the matching public config directly.

### Private profiles

Private/sensitive profiles live in your separate `custom_environments/` repo
as **flakes** at `custom_environments/<env>/nix/flake.nix`. The private flake
consumes the public flake as an input, composes on top of it, and exposes
`homeConfigurations."<system>"` (one per supported system; no profile prefix
because the env is implicit in the flake's location).

**Two things to know before authoring one:**

1. **`path:` flake refs require git-tracked files.** When the `nix` plugin
   builds your private flake, it uses `path:custom_environments/<env>/nix`.
   Because that path lives inside a git repo (typically your private
   `custom_environments` repo set up by `framework/customize`), Nix's path
   fetcher applies git-tree semantics — only files tracked in that repo are
   visible. **Commit your private flake files** to your private repo before
   the first `./apply`. (For one-off throwaway testing without the private
   repo, `git init` inside `custom_environments/<env>/nix/` and commit the
   files there works.)
2. **Override public option values with `lib.mkForce`.** If you import
   `public.homeModules.default` and then want to change something the public
   module already set (for example,
   `home.sessionVariables.DOTFILES_PROFILE`), wrap the new value with
   `lib.mkForce`. Without it, home-manager's module system reports a
   conflict.

Template:

    {
      description = "Private profile for <env>";

      inputs = {
        # Default points at the published public repo so `nix flake check`
        # works in this private repo standalone. The dotfiles `nix` plugin
        # overrides this to a local `path:` at apply time, so day-to-day
        # builds use whatever local public source is current — including
        # its untracked host.nix.
        public.url = "github:ianwremmel/dotfiles?dir=nix";
        nixpkgs.follows      = "public/nixpkgs";
        home-manager.follows = "public/home-manager";
      };

      outputs = { self, public, ... }:
        let
          host = import (public + "/host.nix");
          supportedSystems = [ "aarch64-darwin" "x86_64-linux" ];
          mkConfig = system: public.lib.mkHome {
            inherit system;
            inherit (host) username;
            modules = [
              public.homeModules.default
              ./work.nix
            ];
          };
        in {
          homeConfigurations = builtins.listToAttrs (map
            (system: { name = system; value = mkConfig system; })
            supportedSystems);
        };
    }

Where `./work.nix` (or any name) is a normal home-manager module living
alongside `flake.nix` and may import siblings. Example override of a public
option:

    # ./work.nix
    { lib, ... }: {
      home.sessionVariables.DOTFILES_PROFILE = lib.mkForce "work";
      # …work-specific packages, modules, etc.
    }

The private flake also has its own `flake.lock` (committed to your private
repo) for standalone reproducibility.

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
