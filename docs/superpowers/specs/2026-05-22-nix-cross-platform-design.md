# Nix Cross-Platform (Linux + macOS) Slice Design

**Date:** 2026-05-22
**Status:** Approved (design); pending implementation plan
**Branch:** `nix-cross-platform` (off `master`, which contains the merged first slice from PR #61)

## Goal

Make the Nix/home-manager setup work on Linux as well as macOS. The flake becomes
multi-system, `./apply` learns to run the nix step on Linux, and we validate a
real home-manager activation inside a Linux container. Linux agent environments
are one motivating use case, but the goal is simply Linux + macOS support.

This builds on the first slice (`docs/superpowers/specs/2026-05-22-nix-migration-design.md`),
which established the `nix` plugin, the `nix/` flake, and the untracked
plugin-generated `nix/host.nix`.

## Decisions (locked)

1. **Both Linux arches supported:** `x86_64-linux` and `aarch64-linux`, alongside
   the existing `aarch64-darwin`.
2. **Multi-system strategy: enumeration with `<user>@<system>` naming** (the
   conventional home-manager pattern). The flake enumerates supported systems and
   exposes one `homeConfigurations."<user>@<system>"` per system. Chosen over
   storing the system in `host.nix` because it lets every system's config be
   evaluated/shown/cross-built from any machine (useful for CI and `nix flake
   show`).
3. **Provisioning: reuse the plugin flow, install mode per-OS.** The `nix` plugin
   installs Nix at runtime and activates home-manager — no prebuilt image. macOS
   uses the Determinate installer (daemon/multi-user; required because SIP forces
   `/nix` onto its own APFS volume). Linux uses the **official installer in
   single-user `--no-daemon` mode** — store owned by the one user, no daemon, no
   build sandbox. This removes the container daemon problem entirely; the skipped
   sandbox is irrelevant when only prebuilt packages are fetched from the cache.
4. **No new entry point — `./apply` changes.** `./apply` stays the single entry
   point. On Linux it runs *only* the nix step (the macOS-only plugins like
   `homebrew`/`xcode` never run there); on macOS it runs the full framework as
   today. This is a small OS branch in `apply`, not a rewrite of the framework.
5. **Content stays minimal:** `bat` remains the canary. A curated cross-platform
   toolset is an explicit follow-up, not part of this slice.

## Architecture

```text
apply             OS branch: macOS → framework_apply; Linux → nix step only
nix/flake.nix     supportedSystems = [aarch64-darwin x86_64-linux aarch64-linux]
                  homeConfigurations."<user>@<system>"  (one per system)
nix/home.nix      cross-platform: home directory derived from OS + user
nix/host.nix      untracked, plugin-generated: { username = "..."; } (unchanged)
plugins/nix/nix   builds "<whoami>@<currentSystem>"; per-OS install (mac daemon / linux single-user)
```

The `nix` plugin is the shared unit invoked by `./apply` on both platforms; it
builds the `<user>@<system>` config for the current machine.

## `./apply` change

`apply` keeps its current option parsing and macOS path. It gains an OS branch:
on Linux it runs the nix plugin directly (sourcing only `framework/logging`),
skipping the macOS-centric init/configure/firstrun stages and all macOS plugins:

```bash
if [ "$(uname -s)" = Linux ]; then
  /usr/bin/env bash -c '
    set -euo pipefail
    export DOTFILES_ROOT_DIR; DOTFILES_ROOT_DIR="$(pwd)"
    source ./framework/logging
    source ./plugins/nix/nix
    dotfiles_nix_apply
  '
else
  /usr/bin/env bash -c 'source ./framework/framework && framework_apply'
fi
```

The already-exported `DOTFILES_AIRPLANE_MODE` (and `DOTFILES_NIX_SKIP` via its
default) carry into the Linux subshell, so `-A` and the skip flag still work.

## Flake (`nix/flake.nix`)

```nix
outputs = { nixpkgs, home-manager, ... }:
  let
    supportedSystems = [ "aarch64-darwin" "x86_64-linux" "aarch64-linux" ];

    # Untracked per-host username (out of git), as established in the first slice.
    host =
      if builtins.pathExists ./host.nix then import ./host.nix
      else throw "nix/host.nix not found — run ./apply (generates it) or create it: { username = \"<you>\"; }";

    mkHome = system: home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.${system};
      modules = [ ./home.nix ];
      extraSpecialArgs = { inherit (host) username; };
    };
  in {
    homeConfigurations = builtins.listToAttrs (map
      (system: { name = "${host.username}@${system}"; value = mkHome system; })
      supportedSystems);
  };
```

`host.nix` is unchanged from the first slice — it carries only
`{ username = "..."; }`. The system is selected by which enumerated config is
built, not stored per host.

## Cross-platform `home.nix`

The home-directory prefix differs by OS, and the Linux `root` user is a special
case (its home is `/root`, not `/home/root`):

```nix
{ pkgs, username, ... }:
{
  home.username = username;
  home.homeDirectory =
    if pkgs.stdenv.isDarwin then "/Users/${username}"
    else if username == "root" then "/root"
    else "/home/${username}";
  home.stateVersion = "25.11";
  programs.home-manager.enable = true;

  programs.bat = { enable = true; config.theme = "ansi"; };
}
```

## Plugin changes (`plugins/nix/nix`)

**(a) Build the `<user>@<system>` target.** Determine the current system with Nix
itself and build the matching config:

```bash
local system target
system="$(nix eval --impure --raw --expr 'builtins.currentSystem')"
target="$(whoami)@$system"
nix build "path:$DOTFILES_ROOT_DIR/nix#homeConfigurations.\"$target\".activationPackage" \
  --out-link "$tmpdir/result"
```

This also runs on macOS (`ian@aarch64-darwin`), so `./apply` keeps working; the
macOS path is re-verified as a regression check.

**(b) Per-OS install.** macOS needs the daemon-based Determinate install
(SIP/APFS); Linux uses the official single-user installer, which has no daemon:

```bash
if [ "$(uname -s)" = Darwin ]; then
  curl -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm
else
  curl -L https://nixos.org/nix/install | sh -s -- --no-daemon
fi
```

**(c) Per-OS detection and profile sourcing (no daemon to manage).** A
single-user Linux install keeps its `nix` binary and profile script under
`~/.nix-profile`, not the multi-user daemon paths macOS uses, so install
detection and profile sourcing branch by OS:

```bash
_dotfiles_nix_profile_script () {
  if [ "$(uname -s)" = Darwin ]; then
    echo /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  else
    echo "$HOME/.nix-profile/etc/profile.d/nix.sh"
  fi
}

_dotfiles_nix_is_installed () {
  command -v nix >/dev/null 2>&1 \
    || [ -e /nix/var/nix/profiles/default/bin/nix ] \
    || [ -e "$HOME/.nix-profile/bin/nix" ]
}
```

There is no daemon to start in either case — macOS's is launchd-managed and
Linux single-user has none — so the earlier daemon bring-up step is gone. Call
order in `dotfiles_nix_apply`: skip checks → install → load profile → verify
`nix` available → generate `host.nix` → compute target → build → activate. The
official Linux installer's non-interactive behavior is confirmed against a real
container during implementation.

## Testing

- **Primary:** an `aarch64-linux` Docker container (native and fast on the
  user's Apple-Silicon Mac). Copy the repo into the container — do **not** mount
  it, so the generated `host.nix` does not pollute the host repo — and run
  `./apply` (which does a single-user, daemonless Nix install on Linux). The
  default container user is `root`, which `home.nix` now handles
  (`/root`); a non-root user with passwordless sudo is the alternative. Verify:
  - `bat` resolves on the profile (`~/.nix-profile/bin/bat`),
  - `~/.config/bat/config` is a `/nix/store` symlink containing `--theme=ansi`,
  - the home directory matches the user (`/root` for root, `/home/<user>` else).
- **x86_64-linux:** deferred to a real or CI x86 environment; emulated Docker is
  too slow for the inner loop. The enumerated flake already supports it.
- **Measure** the cold install+build time in-container — the data point that
  informs whether a prebuilt image (the deferred provisioning approach) is worth
  doing next.
- **Regression:** re-run `./apply` on macOS to confirm the `<user>@<system>`
  retarget and the OS branch did not break the Mac path.

## Scope / Non-goals

**In scope:** multi-system flake (3 systems), cross-platform `home.nix`
(including Linux `root`), per-OS plugin install (macOS daemon via Determinate;
Linux single-user via the official installer) with OS-branched detection/profile
sourcing, the `./apply` OS branch, a validated aarch64-linux activation, a
measured cold-start time.

**Out of scope (future phases):** prebuilt Docker image; OS-gating the rest of
the framework's plugins; a curated cross-platform toolset (ripgrep/fd/shell/
etc.); local x86_64-linux testing; nix-darwin; profiles; secrets.
