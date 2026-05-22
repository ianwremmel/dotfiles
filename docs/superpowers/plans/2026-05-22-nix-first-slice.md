# Nix First Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate Nix into the existing dotfiles framework via a thin `nix` plugin that — as a side effect of `./apply` — installs Nix (Determinate installer) and activates a standalone home-manager config managing the `bat` package plus its config file. Fully reversible, leaving all existing plugins untouched.

**Architecture:** A new git-tracked `nix/` flake holds `flake.nix` (inputs: nixpkgs + home-manager, output: one `homeConfigurations.<user>`) and `home.nix` (the managed slice). A new `plugins/nix/nix` plugin, following the framework's `dotfiles_<name>_apply()` convention, ensures Nix is installed, sources the daemon profile so `nix` is usable inside the non-login `bash -c` subshell the framework uses, then builds and activates the home-manager generation via a `path:` flake reference. The **first `./apply` run is the bootstrap**: the plugin installs Nix and activates. Thereafter `nix` is on `PATH` for direct iteration.

**Tech Stack:** Bash 5 (framework), Nix (flakes, `nix-command`), home-manager (standalone), the Determinate Systems Nix installer.

---

## Notes for the executor

- **Reference spec:** `docs/superpowers/specs/2026-05-22-nix-migration-design.md`.
- **No automated test framework** exists in this repo (`CLAUDE.md`: "Manual testing via `./apply`"). "Tests" here are **verification commands** with expected output. The rhythm is: observe the current failing state → implement → observe the passing state → commit.
- **Installation is never a standalone step.** Nix gets installed only by the `nix` plugin during `./apply`. The executor never runs the raw installer.
- **Two steps require the user's own terminal** (interactive `sudo`): the two `./apply` runs (Task 2 and Task 4). These cannot run in a sandboxed/non-interactive agent. When you reach them, present the exact command and ask the user to run it (they can use the `! <command>` prefix in Claude Code) and paste the result back. **Do not proceed past Task 2 until the user confirms Nix is installed**, since later tasks depend on it.
- **Run all `nix`/`git` commands from the repo root** (`/Users/ian/projects/dotfiles`) unless stated otherwise.
- **Release branch:** this plan pins `nixos-25.11` / `release-25.11` with `home.stateVersion = "25.11"`. If the first `./apply` fails because that branch no longer exists, substitute the current stable branch (e.g. `nixos-26.05`) consistently in `flake.nix` and `home.stateVersion`.
- **Conventional commits**, no `Co-Authored-By`/`Generated with` trailers (per `~/.claude/CLAUDE.md`).
- **Commits may need the sandbox disabled** for gpg signing (the keyring lives outside the sandbox). If `git commit` fails with `gpg: ... Operation not permitted`, re-run the commit with the sandbox disabled.

---

## Task 1: Create the `nix` plugin and a minimal flake

Create all the files. No Nix build happens here (Nix is not installed yet) — that is the job of the first `./apply` in Task 2. We can still verify the plugin parses and that its skip paths short-circuit before any Nix use.

**Files:**
- Create: `plugins/nix/nix`
- Create: `nix/flake.nix`
- Create: `nix/home.nix`

- [ ] **Step 1: Verify none of the files exist yet (failing state)**

Run:
```bash
ls plugins/nix/nix nix/flake.nix nix/home.nix 2>/dev/null || echo "nix slice not present"
```
Expected: `nix slice not present`.

- [ ] **Step 2: Create `plugins/nix/nix`**

```bash
#!/usr/bin/env bash

export DOTFILES_NIX_DEPS=()

# The Determinate installer lays down a daemon profile and a nix binary symlink
# here. We detect installation by store path rather than `command -v nix`
# because the framework runs apply hooks in a non-login `bash -c` subshell that
# does not source login rc files (so nix would not be on PATH even when present).
_dotfiles_nix_profile_script='/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
_dotfiles_nix_store_binary='/nix/var/nix/profiles/default/bin/nix'

_dotfiles_nix_is_installed () {
  command -v nix >/dev/null 2>&1 || [ -e "$_dotfiles_nix_store_binary" ]
}

_dotfiles_nix_load_profile () {
  if ! command -v nix >/dev/null 2>&1 && [ -f "$_dotfiles_nix_profile_script" ]; then
    # The profile script may reference unset vars; relax `set -u` while sourcing.
    set +u
    # shellcheck disable=SC1090
    source "$_dotfiles_nix_profile_script"
    set -u
  fi
}

dotfiles_nix_apply () {
  if [ "${DOTFILES_NIX_SKIP:-0}" -eq 1 ]; then
    log 'DOTFILES_NIX_SKIP set; skipping nix'
    return 0
  fi

  if [ "${DOTFILES_AIRPLANE_MODE:-0}" -eq 1 ]; then
    log 'Airplane mode; skipping nix (install and build require network)'
    return 0
  fi

  if _dotfiles_nix_is_installed; then
    debug 'nix already installed'
  else
    log 'Installing Nix via the Determinate Systems installer'
    curl -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm
  fi

  _dotfiles_nix_load_profile

  if ! command -v nix >/dev/null 2>&1; then
    error 'nix is not available after install; aborting nix plugin'
    return 1
  fi

  local out
  out="$(mktemp -d)/result"

  log 'Building home-manager configuration'
  nix build "path:$DOTFILES_ROOT_DIR/nix#homeConfigurations.$(whoami).activationPackage" \
    --out-link "$out"

  log 'Activating home-manager configuration'
  "$out/activate"
}
```

- [ ] **Step 3: Create `nix/flake.nix`**

```nix
{
  description = "ianwremmel dotfiles — nix-managed slice";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
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

- [ ] **Step 4: Create `nix/home.nix` (minimal — no packages yet)**

```nix
{ ... }:
{
  home.username = "ian";
  home.homeDirectory = "/Users/ian";
  home.stateVersion = "25.11"; # pins home-manager behavior; never bump casually
  programs.home-manager.enable = true; # home-manager manages itself
}
```

- [ ] **Step 5: Verify the plugin parses**

Run:
```bash
bash -n plugins/nix/nix && echo "syntax OK"
```
Expected: `syntax OK`.

- [ ] **Step 6: Verify the airplane-mode skip path (no Nix needed)**

Run:
```bash
DOTFILES_ROOT_DIR="$PWD" DOTFILES_AIRPLANE_MODE=1 bash -c '
  set -euo pipefail
  source framework/logging
  source plugins/nix/nix
  dotfiles_nix_apply
'
```
Expected: prints `Airplane mode; skipping nix (install and build require network)`, exits 0, performs no install or build.

- [ ] **Step 7: Verify the skip-flag path (no Nix needed)**

Run:
```bash
DOTFILES_ROOT_DIR="$PWD" DOTFILES_NIX_SKIP=1 bash -c '
  set -euo pipefail
  source framework/logging
  source plugins/nix/nix
  dotfiles_nix_apply
'
```
Expected: prints `DOTFILES_NIX_SKIP set; skipping nix`, exits 0.

- [ ] **Step 8: Commit**

```bash
git add plugins/nix/nix nix/flake.nix nix/home.nix
git commit -m "feat(nix): add nix plugin and minimal home-manager flake"
```

---

## Task 2: First `./apply` — install Nix and activate (user-run)

The first `./apply` triggers the `nix` plugin, which installs Nix as a side effect and activates the minimal config. This both bootstraps Nix and verifies the flake skeleton builds. **User-run** (interactive `sudo`).

**Files:**
- Create (generated by the build): `nix/flake.lock`

- [ ] **Step 1: Confirm Nix is not yet installed**

Run:
```bash
ls /nix/var/nix/profiles/default/bin/nix 2>/dev/null || echo "nix absent"
```
Expected: `nix absent`.

- [ ] **Step 2: User runs `./apply` (their terminal)**

Ask the user to run (the `-B` skips the slow brew bundle; the `nix` plugin still runs):
```bash
./apply -B
```
Expected: the run prints `Installing Nix via the Determinate Systems installer` (prompts for `sudo`), then `Building home-manager configuration` and `Activating home-manager configuration`, and finishes without error. **Wait for the user to confirm success before continuing.**

- [ ] **Step 3: Verify Nix and the home-manager generation exist**

Run (in a fresh shell, or after sourcing the daemon profile):
```bash
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
nix --version
ls -l "$HOME/.nix-profile/bin/home-manager" && "$HOME/.nix-profile/bin/home-manager" --version
```
Expected: `nix --version` prints `nix (Nix) 2.x`; the `home-manager` symlink exists and prints a version — confirming the profile was built and activated.

- [ ] **Step 4: Verify the lockfile was generated**

Run:
```bash
ls -l nix/flake.lock && echo "lockfile present"
```
Expected: `nix/flake.lock` exists (created by the build) — this is the reproducibility pin.

- [ ] **Step 5: Commit the lockfile**

```bash
git add nix/flake.lock
git commit -m "build(nix): pin flake.lock"
```

---

## Task 3: Manage the `bat` package and its config (Nix now installed)

Nix is now on `PATH`, so the agent builds and activates directly — no `./apply` round-trip needed. Add the actual first slice: `bat` installed and `~/.config/bat/config` managed.

**Files:**
- Modify: `nix/home.nix`

- [ ] **Step 1: Verify bat and its config are absent (failing state)**

Run:
```bash
ls "$HOME/.nix-profile/bin/bat" 2>/dev/null || echo "no bat"
ls "$HOME/.config/bat/config" 2>/dev/null || echo "no bat config"
```
Expected: `no bat` and `no bat config`.

- [ ] **Step 2: Replace `nix/home.nix` with the bat module added**

```nix
{ ... }:
{
  home.username = "ian";
  home.homeDirectory = "/Users/ian";
  home.stateVersion = "25.11"; # pins home-manager behavior; never bump casually
  programs.home-manager.enable = true; # home-manager manages itself

  programs.bat = {
    enable = true;          # installs bat (the package half of the slice)
    config.theme = "ansi";  # writes ~/.config/bat/config (the dotfile half)
  };
}
```

- [ ] **Step 3: Build and activate directly**

Run:
```bash
out="$(mktemp -d)/result"
nix build "path:$PWD/nix#homeConfigurations.ian.activationPackage" --out-link "$out"
"$out/activate"
```
Expected: build + activation succeed with no errors. (If `nix` is not found in this shell, first run `source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh`.)

- [ ] **Step 4: Verify the package is on the profile**

Run:
```bash
ls -l "$HOME/.nix-profile/bin/bat" && "$HOME/.nix-profile/bin/bat" --version
```
Expected: symlink into `/nix/store` exists; prints `bat 0.x`.

- [ ] **Step 5: Verify home-manager owns the config file**

Run:
```bash
readlink "$HOME/.config/bat/config"
"$HOME/.nix-profile/bin/bat" --config-file
cat "$HOME/.config/bat/config"
```
Expected: `readlink` points into `/nix/store`; `--config-file` prints `/Users/ian/.config/bat/config`; `cat` shows `--theme="ansi"`.

- [ ] **Step 6: Commit**

```bash
git add nix/home.nix nix/flake.lock
git commit -m "feat(nix): manage bat package and config via home-manager"
```

---

## Task 4: Confirm idempotency via `./apply`, plus docs and backout

Confirm the plugin runs idempotently through the real entry point and document the slice and backout. The `./apply` run is **user-run**.

**Files:**
- Create: `nix/README.md`

- [ ] **Step 1: User re-runs `./apply` to confirm idempotency**

Ask the user to run:
```bash
./apply -B
```
Expected: completes without error; the `nix` plugin reports `nix already installed` (debug) and rebuilds to the same store path / re-activates as a no-op (no file changes reported).

- [ ] **Step 2: Verify nothing the rsync owns was disturbed**

Run:
```bash
readlink "$HOME/.config/bat/config"   # /nix/store/... → home-manager owns it
ls -la "$HOME/.zshrc"                 # still a normal file, not a nix symlink
```
Expected: only the bat config is a `/nix/store` symlink; rsync-managed files like `.zshrc` remain regular files. (home-manager only touches files it created.)

- [ ] **Step 3: Create `nix/README.md`**

```markdown
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
```

- [ ] **Step 4: Commit**

```bash
git add nix/README.md
git commit -m "docs(nix): document nix slice and backout"
```

---

## Self-review (completed by plan author)

- **Spec coverage:** thin `nix` plugin that installs Nix as a side effect of `./apply` (Task 1 plugin, Task 2 bootstrap) ✓; flake + home-manager standalone layout (Task 1) ✓; Determinate installer, upstream Nix (Task 1 plugin) ✓; bat package + config (Task 3) ✓; airplane-mode + `DOTFILES_NIX_SKIP` skip (Task 1 steps 6–7) ✓; `path:` flake reference and store-path install detection (Task 1 plugin) ✓; idempotency + backout + verification (Task 4) ✓; existing plugins untouched ✓.
- **Placeholder scan:** no TBD/TODO; all code blocks complete; release-branch substitution is an explicit verified fallback, not a placeholder.
- **Type/name consistency:** `homeConfigurations.ian` (flake) matches `$(whoami)` = `ian` (plugin) and `home.username = "ian"`; `_dotfiles_nix_profile_script` / `_dotfiles_nix_store_binary` / `_dotfiles_nix_is_installed` / `_dotfiles_nix_load_profile` referenced consistently; `--out-link "$out"` pattern identical across plugin and Task 3.
- **Bootstrap ordering:** no standalone install step; Nix arrives only via the plugin on the first `./apply` (Task 2), and all build/verify steps that need Nix come after it.
