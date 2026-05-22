# Nix Migration — First Slice Design

**Date:** 2026-05-22
**Status:** Approved (design); pending implementation plan

## Goal

Begin migrating this plugin-driven, macOS-only dotfiles system toward Nix, with
an eye toward eventual cross-platform support (Linux + macOS) and per-profile
environments (personal / work / AI-agent). This document covers only the **first
slice**: a minimal, fully reversible integration that proves the end-to-end loop
(install Nix → build → activate → tools on PATH and a managed dotfile) while
leaving the existing framework untouched.

Larger goals (nix-darwin, cross-platform configs, profile mapping, migrating
existing plugins) are explicitly **out of scope** for this slice and noted as
future phases.

## Context

The current system (`./apply`) is a homegrown Bash framework:

- Plugins in `plugins/<name>/<name>` with `dotfiles_<name>_apply()` and
  `DOTFILES_<NAME>_DEPS` conventions; the framework resolves dependency order.
- Environment layering via `environments/all` (shared) → `default`/custom
  (machine), applied last-wins by rsync into `$HOME`.
- macOS-only: Homebrew, `/Applications`, `xcode-select`, Rosetta, `mas`.
- No secrets management, no dry-run, no rollback.

Target machine for this slice: personal Mac, `aarch64-darwin`, Nix not yet
installed.

## Decisions (locked)

1. **Coupling:** A thin `nix` plugin inside the existing framework. `./apply`
   stays the single entry point and orchestrates Nix as one step. (Chosen over
   side-by-side manual invocation.)
2. **First slice scope:** home-manager manages a couple of things — the `bat`
   package **and** a new `~/.config/bat/config` file. The config file is new and
   not owned by the rsync, so there is zero conflict. (Verified: no `bat` config
   exists anywhere in `environments/`, and `bat` is not installed.)
3. **Installer:** Determinate Systems installer in default mode — installs
   **upstream Nix** (no `--determinate` flag). Chosen for reliable macOS APFS
   volume/daemon setup, flakes enabled by default, and a clean one-command
   uninstall that satisfies the "must be able to back out" requirement.
4. **Scope boundary:** Standalone **home-manager only**. No nix-darwin in this
   slice. Existing plugins (`homebrew`, `homedir`, `git`, etc.) are untouched.

## Architecture & File Layout

```text
dotfiles/
  apply                    # unchanged
  framework/               # unchanged
  plugins/
    nix/nix                # NEW: thin plugin (install Nix, activate home-manager)
  nix/                     # NEW: the flake, version-controlled
    flake.nix              # inputs (nixpkgs, home-manager) + outputs
    flake.lock             # pinned versions (generated on first build)
    home.nix               # the home-manager module = first slice
```

## The `nix` Plugin

`plugins/nix/nix` follows existing conventions: defines `dotfiles_nix_apply()`
and `DOTFILES_NIX_DEPS=()` (no dependencies on other plugins — it is
independent). On each `./apply`:

1. **Ensure Nix is installed.** If `nix` is not found on PATH, run the
   Determinate installer non-interactively:

   ```sh
   curl -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm
   ```

   Volume/daemon setup needs sudo, which `apply` already primes.
2. **Make Nix usable in the current process.** A fresh install only edits
   `/etc/zshrc` (etc.), so the running `apply` shell cannot see `nix` yet. The
   plugin sources the daemon profile script
   (`/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh`) before
   continuing.
3. **Build and activate the home-manager generation** directly from the flake —
   no separate `home-manager` CLI install required:

   ```sh
   nix build "$DOTFILES_ROOT_DIR/nix#homeConfigurations.$(whoami).activationPackage" \
     --out-link "$tmp/result"
   "$tmp/result/activate"
   ```

   Pinned via `flake.lock` and idempotent: re-running with no changes is a no-op
   that confirms the current generation.

**Airplane mode (`-A`):** install and build both require network, so the plugin
**skips with a logged warning** when offline, mirroring how `homebrew` handles
`-B`. A `DOTFILES_NIX_SKIP=1` flag also disables the plugin entirely.

The flake config is keyed by `$(whoami)` for now (single `homeConfigurations.<you>`).
Mapping `DOTFILES_ENVIRONMENT` (personal / work / agent) to named flake configs
is a future phase, not in this slice.

## Nix Content

### `nix/flake.nix`

```nix
{
  description = "ianwremmel dotfiles — nix-managed slice";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";        # pinned stable release
    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";          # one nixpkgs, shared
  };

  outputs = { nixpkgs, home-manager, ... }:
    let
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      homeConfigurations.ian = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ ./home.nix ];
      };
    };
}
```

`system` is hardcoded to `aarch64-darwin` for now; emitting a Linux config too is
a future phase.

### `nix/home.nix`

```nix
{ pkgs, ... }:
{
  home.username = "ian";
  home.homeDirectory = "/Users/ian";
  home.stateVersion = "25.11";          # never bump casually; pins HM behavior
  programs.home-manager.enable = true;  # home-manager manages itself

  home.packages = [ pkgs.bat ];         # the package half of the slice

  programs.bat.config.theme = "ansi";   # writes ~/.config/bat/config (the dotfile half)
}
```

Notes:

- **`programs.bat` vs raw file:** the idiomatic home-manager module is used
  rather than a raw `xdg.configFile."bat/config"`. It generates the same
  `~/.config/bat/config` file but demonstrates home-manager's typed-options value.
- **`25.11`** is the assumed current stable release; confirm the exact latest
  stable branch at implementation time and match `stateVersion` to it.

## Backout Plan

In increasing severity:

1. **Disable the slice:** set `DOTFILES_NIX_SKIP=1`; `./apply` ignores Nix
   entirely. Nothing else changes.
2. **Remove the managed file:** delete the `programs.bat` line from `home.nix`
   and re-activate; home-manager removes only the symlink it owns. Rsync'd
   dotfiles are never at risk because home-manager only touches files it created.
3. **Full uninstall:** remove the `nix` plugin and `nix/` dir, then
   `/nix/nix-installer uninstall` to cleanly reverse the entire Nix install
   (volume, daemon, shell edits).

## Verification

- `which bat` resolves into the Nix profile (`~/.nix-profile/bin/bat`) —
  confirms PATH wiring.
- `readlink ~/.config/bat/config` points into `/nix/store` — confirms
  home-manager owns the file.
- `bat --config-file` shows the managed path and the `--theme=ansi` setting is
  live.
- Re-run `./apply` → the nix step is a no-op (idempotency) and no rsync'd file is
  clobbered.

## Future Phases (out of scope here)

- nix-darwin for macOS system settings + declarative Homebrew (casks / `mas`).
- Parametrize `system` and emit a Linux home config for agent environments;
  validate the cross-platform path and its speed (binary cache / prebuilt image).
- Map `DOTFILES_ENVIRONMENT` → named flake configs (personal / work / agent).
- Migrate existing plugins (shells, git, vim, node) into home-manager modules
  with `mkDefault`/`mkForce` layering replacing rsync last-wins.
- Secrets via sops-nix or agenix.
