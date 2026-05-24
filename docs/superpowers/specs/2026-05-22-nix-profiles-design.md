# Nix Profiles Slice Design

**Date:** 2026-05-22
**Status:** Draft — pending user approval
**Branch:** `nix-profiles` (off `nix-cross-platform`, which contains the open PR #62)

## Goal

Add per-machine profile support to the Nix slice so a single repo can produce
different home-manager configurations for personal / work / agent / etc.
machines — using the framework's existing `DOTFILES_ENVIRONMENT` as the
selector, and supporting **hidden profiles defined in the private
`custom_environments/` repo** so machine-specific config (e.g. `work`) never
lands in the public dotfiles repo.

This builds on the prior slices: the first established the `nix` plugin, the
`nix/` flake, and the untracked `nix/host.nix`
(`docs/superpowers/specs/2026-05-22-nix-migration-design.md`); the second made
the flake multi-system and Linux-capable
(`docs/superpowers/specs/2026-05-22-nix-cross-platform-design.md`).

**This slice stacks on top of PR #62** (the cross-platform slice). Among other
things, it renames the public flake's output attribute from
`homeConfigurations."<user>@<system>"` (introduced in PR #62) to
`homeConfigurations."<profile>@<system>"`, and updates the plugin's build
target accordingly — that rename is part of this slice's diff against the
`nix-cross-platform` base.

**Terminology:** *profile* and *environment* refer to the same string. The
framework's `DOTFILES_ENVIRONMENT` value is what the user sets; the public
flake calls it a *profile* in attribute names (`homeModules.<profile>`,
`homeConfigurations."<profile>@<system>"`); the private side lives under
`custom_environments/<env>/`, which is the framework's existing terminology
for the same per-host string. No mapping; the value passes through verbatim.

## Decisions (locked)

1. **Selector: `DOTFILES_ENVIRONMENT`, with identical UX on macOS and Linux.**
   Reuse the framework's existing per-host environment value rather than
   introducing a new variable. The Linux branch of `./apply` is extended to
   source `framework/logging`, `framework/config`, and `framework/environment`,
   then call `environment_get_current` and `config_load` — the same order
   `framework_init` runs them on macOS. This means the framework's existing
   first-run selection prompt (`select` over detected environments) fires on
   Linux too when multiple environments are present, persists the choice to
   `~/.dotfilesrc` via `config_write`, and `config_load` then exports
   `DOTFILES_ENVIRONMENT` for the plugin to read. There is no per-platform
   fallback in the plugin and no separate Linux selection mechanism.
   **Implication:** `./apply` on Linux is not designed to run
   non-interactively in this slice — non-TTY contexts (Docker containers,
   CI/automation) must **pre-seed `~/.dotfilesrc`** with the desired
   `DOTFILES_ENVIRONMENT` before invoking `./apply`. Passing the value as an
   env var (`DOTFILES_ENVIRONMENT=foo ./apply`) does *not* skip the prompt,
   because `environment_get_current` only consults the file (via
   `config_read`), and `config_load` would overwrite any pre-set env var with
   the file's value anyway. Deeper OS-gating of every plugin via the framework
   remains out of scope here.
2. **Profile name = `DOTFILES_ENVIRONMENT` value, verbatim.** No mapping.
   The framework's default environment is `default`, so on this Mac the active
   profile is `default`. `work` → `work`, `agent` → `agent`. The public flake
   exposes a `default` profile module (the everyday baseline) and an `agent`
   profile module; private envs (e.g. `work`) live as flakes in
   `custom_environments/<env>/nix/` per Decision 4.
3. **Profile lives in `host.nix`, plugin-resolved per machine.** Exactly
   analogous to `username`: the plugin determines the profile each run and
   writes it into the untracked `nix/host.nix` as `{ username; profile; }`.
4. **Composition is inverted: the *private* flake consumes the *public* flake
   as a flake input** (not the other way around). The public flake exposes
   building blocks (`homeModules`, a `lib.mkHome` helper, plus ready-made
   `homeConfigurations` for public-only profiles); private flakes — one per
   environment in `custom_environments/<env>/nix/` — declare the public flake
   as their `inputs.public` and compose on top. This dissolves the
   per-machine-optional-input problem (a private flake only *exists* on
   machines that have the private repo, so its inputs are by construction only
   evaluated where they need to be) and removes any need for the plugin to
   materialize or shadow private content inside the public flake. The private
   flake's `inputs.public` defaults to the github: URL of the public repo (so
   `nix flake check` works in the private repo standalone); **the plugin
   passes `--override-input public path:$DOTFILES_ROOT_DIR/nix` at build
   time**, so every apply builds against the current local public source —
   including its untracked `host.nix` — without touching the private's lock
   file. The lock stays pinned to the remote default; the override redirects
   only the build.
5. **One convention for module organization:** every profile module is a
   directory with `default.nix` as its entry. Public profiles live at
   `nix/profiles/<name>/default.nix`. A private *flake* lives at
   `custom_environments/<env>/nix/` with its own `flake.nix` and whatever
   module files it wants (`default.nix`, helpers, etc.).
6. **Demonstrator: per-profile packages.** Real "what tools" curation comes
   as plugins migrate; this slice ships a small per-profile package
   difference to prove the layer is composed correctly.
7. **Output naming.** Public flake exposes
   `homeConfigurations."<profile>@<system>"` for each public profile × system.
   Private flakes expose `homeConfigurations."<system>"` (the env is implicit
   in the flake's location, so the profile name is not part of the attribute).
   The plugin builds whichever attribute matches the active situation.

## Architecture

```text
nix/host.nix                       untracked, plugin-generated:
                                     { username = "..."; profile = "..."; }
nix/flake.nix                      PUBLIC flake — exposes homeModules + lib.mkHome
                                     + homeConfigurations."<profile>@<system>"
nix/home.nix                       shared base module (bat, home dir) — unchanged
nix/profiles/all/default.nix       always-included shared content (bat, etc.)
nix/profiles/default/default.nix   public profile: matches DOTFILES_ENVIRONMENT=default
nix/profiles/agent/default.nix     public profile: lean for agent envs
plugins/nix/nix                    resolves profile, writes host.nix, then builds
                                     EITHER public#<profile>@<system> OR
                                     private (custom_environments/<env>/nix)#<system>

custom_environments/<env>/nix/flake.nix   PRIVATE flake — declares inputs.public
                                     pointing to the public flake; composes
                                     public.lib.mkHome with its own modules and
                                     any public.homeModules.* it wants to layer on
custom_environments/<env>/nix/flake.lock  private's own lockfile
custom_environments/<env>/nix/...         private profile modules (default.nix, helpers)
```

There is no `nix/profiles/.private/` shadow tree and no plugin-side
materialization step. Each side owns its own source.

## Profile selection (reuses `DOTFILES_ENVIRONMENT`)

With Decision 1 in place, environment selection runs identically on both
platforms: `environment_get_current` prompts on first run when multiple
environments are detected (or auto-picks when only one non-`all` environment
exists), persists the choice to `~/.dotfilesrc`, and `config_load` exports
`DOTFILES_ENVIRONMENT` for the plugin. The plugin's resolver is therefore
trivial:

1. Read `$DOTFILES_ENVIRONMENT`.
2. If empty, default to `default`.

No mapping, no per-platform fallback. The resolved name is what the rest of
the system sees. To override in non-interactive contexts, write
`DOTFILES_ENVIRONMENT=<value>` directly to `~/.dotfilesrc` before `./apply` —
the env var alone is not honored (see Decision 1).

## Public flake (`nix/flake.nix`)

The public flake's job is to publish building blocks plus ready-made
configurations for public-only profiles. It knows nothing about private
content.

```nix
{
  description = "ianwremmel dotfiles — public nix slice";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager, ... }:
    let
      supportedSystems = [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ];
      publicProfiles   = [ "default" "agent" ];
      inherit (nixpkgs) lib;

      host =
        if builtins.pathExists ./host.nix then import ./host.nix
        else throw "nix/host.nix not found — run ./apply (generates it) or create it: { username = \"<you>\"; profile = \"default\"; }";
    in {
      # Building blocks — module library a downstream (private) flake can consume.
      # `base` is infrastructure; `all` is always-included shared content;
      # `default`/`agent` are selectable profiles.
      homeModules = {
        base    = ./home.nix;
        all     = ./profiles/all/default.nix;
        default = ./profiles/default/default.nix;
        agent   = ./profiles/agent/default.nix;
      };

      # Helper: build a homeConfiguration with the shared base + always-on
      # `all` layer + caller's extras.
      lib.mkHome = { system, username, modules ? [] }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          extraSpecialArgs = { inherit username; };
          modules = [ self.homeModules.base self.homeModules.all ] ++ modules;
        };

      # Ready-made configs for the no-private-overlay case, one per public profile × system.
      homeConfigurations = builtins.listToAttrs (lib.concatMap (system:
        map (profile: {
          name  = "${profile}@${system}";
          value = self.lib.mkHome {
            inherit system;
            inherit (host) username;
            modules = [ self.homeModules.${profile} ];
          };
        }) publicProfiles
      ) supportedSystems);
    };
}
```

`host.nix` stays exactly where it was — plugin-generated, gitignored, read by
the public flake at eval time.

## Private flake template (`custom_environments/<env>/nix/flake.nix`)

The contract a private flake follows:

- Declares `inputs.public` pointing to the public flake (relative `path:` for
  local-dev, or a `github:…?dir=nix` URL for pinned remote).
- Uses `follows` to align nixpkgs/home-manager with the public flake — avoids
  version drift.
- Exposes `homeConfigurations."<system>"` for each system that env supports
  (just the system, no profile prefix — the env is implicit in the location).
- Reads `host.username` from the public flake's untracked `host.nix` so
  per-machine identity stays in one place.

```nix
{
  description = "Private profile for <env>";

  inputs = {
    # The default points to the published public repo so `nix flake check`
    # works in this private repo standalone. Day-to-day, the dotfiles `nix`
    # plugin overrides this to a local `path:` at build time (see "Plugin
    # changes"), so every apply pulls in the current local public source —
    # including its untracked host.nix — without touching this lock file.
    public.url = "github:ianwremmel/dotfiles?dir=nix";
    nixpkgs.follows      = "public/nixpkgs";
    home-manager.follows = "public/home-manager";
  };

  outputs = { self, public, ... }:
    let
      host = import (public + "/host.nix");
      supportedSystems = [ "aarch64-darwin" "x86_64-linux" ];   # whatever this env runs on
      mkConfig = system: public.lib.mkHome {
        inherit system;
        inherit (host) username;
        modules = [
          public.homeModules.default    # optional: start from a public profile…
          ./work.nix                    # …and layer this env's module(s) on top
        ];
      };
    in {
      homeConfigurations = builtins.listToAttrs (map
        (system: { name = system; value = mkConfig system; })
        supportedSystems);
    };
}
```

The `./work.nix` (or any name) is a normal home-manager module living next to
`flake.nix` inside the private repo. The private flake also has its own
`flake.lock` (committed to the private repo) for reproducibility on the private
side.

## Apply changes (`apply`)

The Linux branch of `./apply` (added in the cross-platform slice) currently
sources only `framework/logging` and the plugin. To match the macOS
environment-selection UX (Decision 1), it now sources `framework/logging`,
`framework/config`, and `framework/environment`, then runs the same two
framework calls macOS's `framework_init` makes:

```bash
if [ "$(uname -s)" = Linux ]; then
  /usr/bin/env bash -c '
    set -euo pipefail
    export DOTFILES_ROOT_DIR; DOTFILES_ROOT_DIR="$(pwd)"
    source ./framework/logging
    source ./framework/config
    source ./framework/environment
    # The framework expects ~/.dotfilesrc to exist (config_read/_write).
    # Mode 0600 matches the framework first-run permissions.
    [ -f "$HOME/.dotfilesrc" ] || install -m 0600 /dev/null "$HOME/.dotfilesrc"
    environment_get_current   # may prompt + persist; same call framework_init makes
    config_load               # exports DOTFILES_ENVIRONMENT etc. from ~/.dotfilesrc
    source ./plugins/nix/nix
    dotfiles_nix_apply
  '
else
  /usr/bin/env bash -c "source ./framework/framework && framework_apply"
fi
```

The macOS branch is unchanged — `framework_init` already runs
`environment_get_current` → `customize_main` → `config_load` → the rest of
the framework. After this Linux change, the environment-selection UX
(including the `select` prompt and persistence to `~/.dotfilesrc`) is
identical on both platforms. `customize_main` (which manages the private
`custom_environments/` repo via `gh` on macOS) is intentionally not pulled
into the Linux branch — it relies on macOS-specific tooling and isn't part
of environment-selection UX.

## Plugin changes (`plugins/nix/nix`)

Two changes from the cross-platform slice. The `host.nix` generation is
extended to include `profile`; and the build step branches on whether a
matching private flake exists.

Add helpers (before `dotfiles_nix_apply`):

```bash
_dotfiles_nix_resolve_profile () {
  # Both macOS and Linux populate DOTFILES_ENVIRONMENT via the framework's
  # config_load before this runs (see Apply changes), so no per-platform
  # fallback is needed.
  echo "${DOTFILES_ENVIRONMENT:-default}"
}
```

In `dotfiles_nix_apply`, replace the existing `host.nix`-generation +
build-target block with this:

```bash
local profile
profile="$(_dotfiles_nix_resolve_profile)"
log "Resolved profile: $profile"   # surfaces typos in $DOTFILES_ENVIRONMENT

printf '# Generated by the nix plugin — host-specific, not tracked in git.\n{ username = "%s"; profile = "%s"; }\n' \
  "$(whoami)" "$profile" > "$DOTFILES_ROOT_DIR/nix/host.nix"

# (`nixflags` is already declared earlier in `dotfiles_nix_apply` from the
# cross-platform slice; reuse it rather than redeclaring.)
local system
system="$(nix "${nixflags[@]}" eval --impure --raw --expr 'builtins.currentSystem')"

local flake_ref target
local priv_flake="$DOTFILES_ROOT_DIR/custom_environments/$profile/nix"
local -a extra_args=()
if [ -f "$priv_flake/flake.nix" ]; then
  # Private overlay path: build the private flake, redirecting its `public`
  # input to the current local public source (so untracked host.nix is visible
  # and no public-side relock is needed).
  flake_ref="path:$priv_flake"
  target="homeConfigurations.\"$system\".activationPackage"
  extra_args=(--override-input public "path:$DOTFILES_ROOT_DIR/nix")
  log "Building private profile '$profile' for $system (overriding public→local)"
else
  # Public-only path: build the public flake's <profile>@<system> directly.
  flake_ref="path:$DOTFILES_ROOT_DIR/nix"
  target="homeConfigurations.\"$profile@$system\".activationPackage"
  log "Building public profile '$profile' for $system"
fi

local tmpdir
tmpdir="$(mktemp -d)"
nix "${nixflags[@]}" build "$flake_ref#$target" "${extra_args[@]}" --out-link "$tmpdir/result"
log 'Activating home-manager configuration'
"$tmpdir/result/activate"
rm -rf "$tmpdir"
```

If a profile is set with neither a public module nor a private flake, the `nix
build` errors with a clear "attribute not found" message naming the missing
config — acceptable feedback, no special-case needed.

## Public profile content (the demonstrator)

Minimal and non-conflicting:

```nix
# nix/profiles/default/default.nix
{ pkgs, ... }: {
  home.packages = [ pkgs.ripgrep ];
}

# nix/profiles/agent/default.nix
{ ... }: {
  # Intentionally lean: no extra packages beyond the shared base.
}
```

## Docs (`nix/README.md`)

Add a "Profiles" section covering:

- How selection works (`DOTFILES_ENVIRONMENT`, loaded uniformly via the framework's `config_load` on both platforms, persisted into `host.nix`).
- The public vs private split: public profiles live at `nix/profiles/<name>/default.nix`; private envs live as **flakes** at `custom_environments/<env>/nix/flake.nix`.
- The private-flake contract: declare `inputs.public`, follow `public/nixpkgs` and `public/home-manager`, expose `homeConfigurations."<system>"`.
- An example: a copy-pasteable private `flake.nix` skeleton (the template above), plus instructions for `inputs.public.url` (local `path:` vs pinned `github:`).

## Testing

- **macOS default (this Mac, `DOTFILES_ENVIRONMENT=default`):** run the
  plugin; expect the log line `Resolved profile: default`, `host.nix` to read
  `{ username = "ian"; profile = "default"; }`, the plugin to take the
  **public-only path** (no `custom_environments/default/nix/flake.nix`
  exists), build `homeConfigurations."default@aarch64-darwin"` from the
  public flake, activate it. `ripgrep` resolves on the profile.
- **Force a private profile via a throwaway private flake:** in a scratch
  `custom_environments/throwaway/nix/`, create a `flake.nix` from the
  template, a `throwaway.nix` module imported by the flake, and a sibling
  `helpers.nix` that `throwaway.nix` `import`s (e.g. adds a distinct package
  list) — exercising multi-file private modules. Run `nix flake lock` once
  inside the private dir (against the github: default) to produce its
  `flake.lock`. **Pre-seed `~/.dotfilesrc`** with the chosen environment
  (back up the existing value first), since `DOTFILES_ENVIRONMENT=foo ./apply`
  does not bypass the framework prompt:

  ```bash
  cp ~/.dotfilesrc ~/.dotfilesrc.bak
  sed -i.tmp 's/^DOTFILES_ENVIRONMENT=.*/DOTFILES_ENVIRONMENT=throwaway/' ~/.dotfilesrc
  ./apply
  mv ~/.dotfilesrc.bak ~/.dotfilesrc
  ```

  Confirm the plugin takes the **private path**, the build command includes
  `--override-input public path:.../nix`, the build succeeds, and activation
  applies the layered (base + throwaway + helpers) modules. Confirm
  `nix flake check` succeeds when run standalone inside the throwaway dir
  (proving the github: default is reachable). After restoring
  `~/.dotfilesrc`, confirm the next `./apply` takes the public path again.
  **Direct-source tests** (`bash -c 'source framework/logging; source
  plugins/nix/nix; dotfiles_nix_apply'`) bypass `environment_get_current`
  and `config_load`, so they must export `DOTFILES_ENVIRONMENT` themselves
  to exercise non-default profiles.
- **Linux container:** the container has no TTY, so `environment_get_current`
  would block on the `select` prompt if multiple environments are detected.
  Pre-seed `~/.dotfilesrc` inside the container and then run `./apply`:

  ```bash
  docker run --rm --platform linux/arm64 -v "$PWD":/src:ro ubuntu:24.04 bash -c '
    set -euo pipefail
    apt-get update -qq && apt-get install -y -qq curl xz-utils ca-certificates >/dev/null
    cp -r /src /dotfiles
    cd /dotfiles
    install -m 0600 /dev/null "$HOME/.dotfilesrc"
    echo "DOTFILES_ENVIRONMENT=agent" > "$HOME/.dotfilesrc"
    ./apply
    # …verifications…
  '
  ```

  Expect profile `agent`, public-only path, lean package set.
- **Regression:** the macOS `./apply` end-to-end keeps working; rsync-managed
  dotfiles remain untouched by home-manager.

## Validation risks to confirm during implementation

The `--override-input public path:$DOTFILES_ROOT_DIR/nix` pattern dissolves
the narHash-churn problem that an earlier draft of this design had (no longer
relying on the private's lock to track public's content). Two adjacent
assumptions still need empirical confirmation in the plan:

1. **Untracked file inclusion via `path:` override.** The cross-platform slice
   already proved that `nix build "path:$DOTFILES_ROOT_DIR/nix"` includes the
   untracked `host.nix`. The same path fetcher serves `--override-input`, so
   the private flake's `import (public + "/host.nix")` is expected to resolve.
   The throwaway-private test exercises this end-to-end.
2. **Standalone `nix flake check` in the private repo.** With the github:
   default, the private flake should evaluate in isolation (resolving
   `inputs.public` from GitHub) without the plugin or any local-public
   present. The plan verifies this from inside the throwaway env.

If either expectation fails, the documented fallback is to have the plugin
write the override path into the private's `flake.lock` itself (via
`nix flake update --override-input public ...`) on each apply, OR to refactor
`host.nix` to live outside the public flake's source tree.

## Scope / Non-goals

**In scope:** profile selection from `DOTFILES_ENVIRONMENT`,
`host.nix` carrying `profile`, public flake exposing
`homeModules` + `lib.mkHome` + `homeConfigurations."<profile>@<system>"`,
plugin if/else between the public-only and private-overlay paths, two public
profiles (`default`, `agent`) with the package demonstrator, a
documented private-flake template, README update, and tests on macOS + an
aarch64-linux container.

**Out of scope:** non-interactive (no-TTY) `./apply` on Linux — the framework's
`environment_get_current` prompts via `select` when multiple environments are
detected, so non-TTY contexts (Docker containers, automation) must pre-seed
`~/.dotfilesrc` with the desired `DOTFILES_ENVIRONMENT` before invoking
`./apply`; an env-var override that bypasses the prompt is *not* added in
this slice; migrating git identity into profiles (collides with the
not-yet-migrated `git` plugin on macOS — separate phase); secrets per profile
(sops-nix/agenix — separate phase); curated production toolsets per profile.

## Future phases (relation to this slice)

This slice ships the *plumbing*. Later phases will fill the profile modules
with real content as plugins migrate:

- `shells` plugin migration → profiles can layer shell aliases / prompt bits.
- `git` plugin migration → profile-specific `programs.git.userEmail` etc.
- nix-darwin → macOS system defaults can also branch by profile.
- secrets → per-profile encrypted values via sops-nix/agenix.
