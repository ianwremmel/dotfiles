# Nix First Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate Nix into the existing dotfiles framework via a thin `nix` plugin that installs Nix (Determinate installer) and activates a standalone home-manager config managing the `bat` package plus its config file — fully reversible, leaving all existing plugins untouched.

**Architecture:** A new git-tracked `nix/` flake holds `flake.nix` (inputs: nixpkgs + home-manager, output: one `homeConfigurations.<user>`) and `home.nix` (the managed slice). A new `plugins/nix/nix` plugin, following the framework's `dotfiles_<name>_apply()` convention, ensures Nix is installed, sources the daemon profile so `nix` is usable inside the non-login `bash -c` subshell the framework uses, then builds and activates the home-manager generation via a `path:` flake reference.

**Tech Stack:** Bash 5 (framework), Nix (flakes, `nix-command`), home-manager (standalone), the Determinate Systems Nix installer.

---

## Notes for the executor

- **Reference spec:** `docs/superpowers/specs/2026-05-22-nix-migration-design.md`.
- **No automated test framework** exists in this repo (`CLAUDE.md`: "Manual testing via `./apply`"). "Tests" here are **verification commands** with expected output. The TDD rhythm is: observe the current failing state → implement → observe the passing state → commit.
- **Two steps require the user's own terminal** (interactive `sudo`, system changes): installing Nix (Task 1) and running `./apply` (Task 5). These cannot run in a sandboxed/non-interactive agent. When you reach them, present the exact command and ask the user to run it (they can use the `! <command>` prefix in Claude Code) and paste the result back.
- **Run all `nix`/`git` commands from the repo root** (`/Users/ian/projects/dotfiles`) unless stated otherwise.
- **Release branch:** this plan pins `nixos-25.11` / `release-25.11`. In Task 2, verify that branch resolves; only change it if 25.11 no longer exists.
- **Conventional commits**, no `Co-Authored-By`/`Generated with` trailers (per `~/.claude/CLAUDE.md`).
- **Commits may need the sandbox disabled** for gpg signing (the keyring lives outside the sandbox). If `git commit` fails with `gpg: ... Operation not permitted`, re-run the commit with the sandbox disabled.

---

## Task 1: Bootstrap Nix (user-run install + verify)

Installing Nix creates an APFS volume and a daemon and needs `sudo`; the **user runs the installer**, the agent verifies afterward. This also validates the exact installer invocation the plugin will use.

**Files:** none (system-level bootstrap; nothing committed).

- [ ] **Step 1: Confirm Nix is not yet installed**

Run:
```bash
command -v nix || echo "nix absent"
ls /nix/var/nix/profiles/default/bin/nix 2>/dev/null || echo "no nix store profile"
```
Expected: `nix absent` and `no nix store profile`.

- [ ] **Step 2: User installs Nix (their terminal)**

Ask the user to run this in their terminal (it will prompt for `sudo`):
```bash
curl -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm
```
Expected: installer finishes with a success message and instructs opening a new shell. This installs **upstream Nix** (no `--determinate` flag), with flakes enabled by default.

- [ ] **Step 3: Verify the binary and profile exist**

Run:
```bash
ls -l /nix/var/nix/profiles/default/bin/nix
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
nix --version
```
Expected: the symlink exists; `nix --version` prints `nix (Nix) 2.x`.

- [ ] **Step 4: Verify flakes + nix-command are enabled**

Run:
```bash
nix flake --help >/dev/null && echo "flakes OK"
```
Expected: `flakes OK` (no "experimental feature" error). If it errors, the Determinate installer's default config is missing — add `experimental-features = nix-command flakes` to `/etc/nix/nix.conf` and re-test.

(No commit — nothing in the repo changed.)

---

## Task 2: Flake skeleton + activate an empty home config

Prove the build→activate loop with the smallest possible config (no packages, no files yet).

**Files:**
- Create: `nix/flake.nix`
- Create: `nix/home.nix`
- Create (generated): `nix/flake.lock`

- [ ] **Step 1: Verify the flake does not yet exist (failing state)**

Run:
```bash
nix build "path:$PWD/nix#homeConfigurations.ian.activationPackage" 2>&1 | head -3
```
Expected: failure such as `error: path '.../nix' does not exist` (or `does not contain a 'flake.nix'`).

- [ ] **Step 2: Verify the pinned release branch resolves**

Run:
```bash
nix flake metadata "github:NixOS/nixpkgs/nixos-25.11" >/dev/null && echo "nixos-25.11 OK"
```
Expected: `nixos-25.11 OK`. If this fails because the branch no longer exists, substitute the current stable branch (e.g. `nixos-26.05`) consistently in `flake.nix` and in `home.stateVersion` below.

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

- [ ] **Step 4: Create `nix/home.nix` (minimal)**

```nix
{ ... }:
{
  home.username = "ian";
  home.homeDirectory = "/Users/ian";
  home.stateVersion = "25.11"; # pins home-manager behavior; never bump casually
  programs.home-manager.enable = true; # home-manager manages itself
}
```

- [ ] **Step 5: Build the activation package**

Run:
```bash
out="$(mktemp -d)/result"
nix build "path:$PWD/nix#homeConfigurations.ian.activationPackage" --out-link "$out"
echo "built: $out" && ls -l "$out"
```
Expected: build succeeds (downloads from cache), `nix/flake.lock` is created, and `$out` is a symlink into `/nix/store` containing an `activate` script.

- [ ] **Step 6: Activate the generation**

Run:
```bash
"$out/activate"
```
Expected: output like `Starting Home Manager activation` / `Creating home file links` and no errors.

- [ ] **Step 7: Verify home-manager installed itself**

Run:
```bash
ls -l "$HOME/.nix-profile/bin/home-manager" && "$HOME/.nix-profile/bin/home-manager" --version
```
Expected: the symlink exists and a version prints — confirms the profile was built and linked.

- [ ] **Step 8: Commit**

```bash
git add nix/flake.nix nix/home.nix nix/flake.lock
git commit -m "feat(nix): add home-manager flake skeleton"
```

---

## Task 3: Manage the `bat` package and its config via home-manager

Add the actual first slice: `bat` installed and `~/.config/bat/config` managed.

**Files:**
- Modify: `nix/home.nix`

- [ ] **Step 1: Verify bat and its config are absent (failing state)**

Run:
```bash
ls "$HOME/.nix-profile/bin/bat" 2>/dev/null || echo "no bat"
ls "$HOME/.config/bat/config" 2>/dev/null || echo "no bat config"
```
Expected: `no bat` and `no bat config`.

- [ ] **Step 2: Edit `nix/home.nix` to add the bat module**

Replace the entire file with:
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

- [ ] **Step 3: Build and activate**

Run:
```bash
out="$(mktemp -d)/result"
nix build "path:$PWD/nix#homeConfigurations.ian.activationPackage" --out-link "$out"
"$out/activate"
```
Expected: build + activation succeed with no errors.

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

## Task 4: Create the `nix` plugin

Add the framework plugin that installs Nix (idempotently), makes it usable in the framework's non-login subshell, and activates the config. Verify it in isolation by sourcing it directly (Nix is already installed from Task 1, so the install branch is skipped).

**Files:**
- Create: `plugins/nix/nix`

- [ ] **Step 1: Verify the plugin does not exist (failing state)**

Run:
```bash
ls plugins/nix/nix 2>/dev/null || echo "no nix plugin"
```
Expected: `no nix plugin`.

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

- [ ] **Step 3: Verify the plugin activates when invoked directly**

Run:
```bash
DOTFILES_ROOT_DIR="$PWD" bash -c '
  set -euo pipefail
  source framework/logging
  source plugins/nix/nix
  dotfiles_nix_apply
'
```
Expected: logs `Building home-manager configuration` then `Activating home-manager configuration`, exits 0, and `bat` is still present (`ls "$HOME/.nix-profile/bin/bat"`). This exercises the load-profile + build + activate path with the install branch skipped.

- [ ] **Step 4: Verify airplane mode skips cleanly**

Run:
```bash
DOTFILES_ROOT_DIR="$PWD" DOTFILES_AIRPLANE_MODE=1 bash -c '
  set -euo pipefail
  source framework/logging
  source plugins/nix/nix
  dotfiles_nix_apply
'
```
Expected: prints `Airplane mode; skipping nix (install and build require network)`, exits 0, performs no build.

- [ ] **Step 5: Verify the skip flag disables the plugin**

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

- [ ] **Step 6: Commit**

```bash
git add plugins/nix/nix
git commit -m "feat(nix): add nix plugin to install nix and activate home-manager"
```

---

## Task 5: End-to-end via `./apply`, idempotency, and docs

Confirm the plugin runs as part of the real entry point, is idempotent, and document the slice and backout. The `./apply` runs require the user's terminal (interactive `sudo`).

**Files:**
- Create: `nix/README.md`

- [ ] **Step 1: User runs the full apply (their terminal)**

Ask the user to run (the `-B` skips the slow brew bundle; the nix plugin still runs):
```bash
./apply -B
```
Expected: completes without error, including the `Building home-manager configuration` / `Activating home-manager configuration` log lines from the nix plugin.

- [ ] **Step 2: User re-runs apply to confirm idempotency**

Ask the user to run again:
```bash
./apply -B
```
Expected: completes again with no errors; the nix step rebuilds to the same store path and re-activates as a no-op (no file changes reported).

- [ ] **Step 3: Verify nothing the rsync owns was disturbed**

Run:
```bash
readlink "$HOME/.config/bat/config"   # /nix/store/... → home-manager owns it
ls -la "$HOME/.zshrc"                 # still a normal file, not a nix symlink
```
Expected: only the bat config is a `/nix/store` symlink; rsync-managed files like `.zshrc` remain regular files. (home-manager only touches files it created.)

- [ ] **Step 4: Create `nix/README.md`**

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
installer) if absent, then builds and activates `homeConfigurations.<user>`.

To build/activate by hand:

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

- [ ] **Step 5: Commit**

```bash
git add nix/README.md
git commit -m "docs(nix): document nix slice and backout"
```

---

## Self-review (completed by plan author)

- **Spec coverage:** flake + plugin layout (Task 2, 4) ✓; Determinate installer (Task 1, 4) ✓; bat package + config (Task 3) ✓; airplane-mode + `DOTFILES_NIX_SKIP` skip (Task 4) ✓; `path:` flake reference and store-path install detection (Task 4) ✓; idempotency + backout + verification (Task 5) ✓; standalone home-manager only, existing plugins untouched ✓.
- **Placeholder scan:** no TBD/TODO; all code blocks are complete; release-branch substitution is an explicit verified fallback, not a placeholder.
- **Type/name consistency:** `homeConfigurations.ian` (flake) matches `$(whoami)` = `ian` (plugin) and `home.username = "ian"`; `_dotfiles_nix_profile_script` / `_dotfiles_nix_store_binary` / `_dotfiles_nix_is_installed` / `_dotfiles_nix_load_profile` referenced consistently; `--out-link "$out"` pattern identical across tasks.
