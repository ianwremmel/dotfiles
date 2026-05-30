# Environments symmetry: one flake per environment, one source of truth

## Problem

Two enumerations describe "which environments exist" and they are populated from
different sources that never check each other:

- **The selection prompt** (`framework/environment` →
  `environment_list_all_environments`) scans the filesystem: `custom_environments/*`
  plus a legacy `environments/*`, minus `all`.
- **The buildable public profiles** (`nix/flake.nix` →
  `publicProfiles = [ "default" "agent" ]`) are a hardcoded Nix list, bridged by
  `lib/nix`: selected env → private flake if `custom_environments/<env>/nix/flake.nix`
  exists, else public `homeConfigurations."<env>@<system>"`.

Two failures fall out:

1. **`agent` is buildable but unselectable.** It is a real public profile, but the
   prompt never offers it (no `custom_environments/agent` dir). The only way to land
   on it is to hand-edit `DOTFILES_ENVIRONMENT` in `~/.dotfilesrc`.
2. **A custom env without a private flake is offered but unbuildable.** Pick a
   `custom_environments/foo` that has only `home/` and no flake, and `lib/nix` falls
   through to `homeConfigurations."foo@<system>"`, which does not exist → opaque Nix
   error.

The flake cannot fix this alone: it is pure and cannot see `custom_environments/`
(git-ignored, separate repo). Reconciliation has to live in the bash layer, which
can read both the flake's directory tree and the filesystem.

A second, structural issue sits underneath: the public side is *N profiles inside
one flake*, while each private side is *one flake per environment*. That asymmetry
is why the two enumerations diverge in the first place, and why `lib/nix` carries a
public branch and a separate private branch.

## Goals

- `agent` (and any future public profile) is selectable at the prompt.
- A selected environment that resolves to nothing buildable fails fast with a clear
  message naming what was looked for.
- Public and private environments share one shape, so enumeration, validation, and
  the build path are a single rule with no second list to keep in sync.
- Restore the public/private naming parallel: rename `nix/` → `environments/` (the
  name `custom_environments` was coined against a public `environments`).
- Close the private-darwin deferral (status doc item #1): every environment — public
  or private — can carry a macOS system (darwin) half, activated only on macOS. There
  is no special-cased single darwin config and no env that can't ship system state.

## Non-goals

- Migrating `custom_environments/work`'s *content* into Nix. That is a separate,
  user-led effort in the private repo. This spec fixes the contract that repo builds
  against (flake path, `public` input target, and the new darwin half) and makes the
  private-darwin layer *possible*; it does not author `work`'s casks.
- Changing what any profile installs. Module *content* moves between directories but
  is not rewritten.

## Design

### The model: every environment is a flake consuming a shared core

There is one **core flake** at `environments/flake.nix` that exposes a library and
no buildable system/home configs of its own:

- `lib.mkHome` — composes `homeModules.base` + `homeModules.all` + the env's own
  home modules.
- `lib.mkDarwin` — composes `darwinModules.base` + `darwinModules.all` + the env's
  own darwin modules.
- `homeModules.{ base, all }` — `base` = `home.nix` infrastructure (username,
  homeDirectory, stateVersion); `all` = the always-included home layer
  (`environments/all/home/`).
- `darwinModules.{ base, all }` — `base` = darwin infrastructure (`system.stateVersion`,
  `nix.enable = false`, username plumbing); `all` = the always-included system layer
  (`environments/all/darwin/`: homebrew base, login shell, system PATH, Xcode license,
  `system.defaults`).

An environment is a flake with **two halves**: a home-manager half (every system)
and an optional darwin half (macOS only). It consumes the core as its `public` input
and produces `homeConfigurations."<system>"` for every supported system, plus
`darwinConfigurations."<system>"` for darwin systems. Because `lib.mkHome`/`mkDarwin`
always fold in `base` + `all`, even an env with no darwin module of its own yields a
darwin config equal to the universal `all` layer.

```
environments/
  flake.nix              # core/library: lib.mkHome, lib.mkDarwin,
                         #   homeModules.{base,all}, darwinModules.{base,all}
  home.nix               # homeModules.base  — home infra
  darwin.nix             # darwinModules.base — darwin infra
  all/
    home/                # homeModules.all   — git, gpg, shells, cli, dotfiles (every machine)
    darwin/              # darwinModules.all  — homebrew base, login shell, system PATH,
                         #   Xcode license, system.defaults (every macOS machine)
  default/
    flake.nix            # consumes public; exposes home + darwin configs
    home.nix             # default's home half (claude, personal cli, fonts, git identity)
    darwin.nix           # default's darwin half (personal casks/mas/brews)
    claude/ …            # moved from profiles/default/
  agent/
    flake.nix            # consumes public; lean — home half only, no darwin half
    home.nix
custom_environments/     # private, separate repo
  work/
    flake.nix            # identical shape; top-level, no nix/ subdir
    home.nix             # work's home half
    darwin.nix           # work's darwin half (private casks/mas/brews)
```

This is the shape the existing `custom_environments/work/nix/flake.nix` already uses
(declares a `public` input, builds via `public.lib.*`, exposes per-system configs).
The public `default`/`agent` flakes become thin versions of that same proven pattern,
extended with the darwin half.

Module content for a public env lives in its own directory and is imported locally
by that env's flake. A private env that wants to layer on a public env's content can
path-import it via `public + "/<env>"` (the core source is materialized at the
`public` input), so composition stays possible without the core flake-exporting each
env (which would cycle).

### One directory rule drives everything

An environment **is a directory containing a `flake.nix`**, under either
`environments/` or `custom_environments/`. That single predicate is the source of
truth for all three consumers:

- **Enumeration** (`framework/environment`): candidate set = basenames of
  `environments/*/` and `custom_environments/*/` that contain a `flake.nix`, deduped.
  `all/` is the core-internal always-included layer (its `home/` and `darwin/`
  subdirs are the two halves every env gets), **not** an environment: it has no
  `flake.nix`, so the rule excludes it and it is never offered as a choice. The
  top-level core `flake.nix` is not a subdir, so it is not a candidate either.
  `agent` appears because `environments/agent/flake.nix` exists.
- **Validation** (`lib/nix`): the selected env is buildable iff
  `environments/<env>/flake.nix` or `custom_environments/<env>/flake.nix` exists.
  Same predicate as enumeration — they cannot disagree.
- **The flake** no longer carries `publicProfiles`/`darwinProfiles` lists at all;
  there is nothing to enumerate in Nix because each env is its own flake.

Adding `environments/foo/flake.nix` makes `foo` selectable, valid, and buildable in
one move. There is no second list to update.

### `lib/nix`: one build path

The public/private branch collapses. After resolving `profile` (the selected env):

```
if   [ -f "$ROOT/custom_environments/$profile/flake.nix" ]; then flake_dir=…custom_environments/$profile
elif [ -f "$ROOT/environments/$profile/flake.nix" ];        then flake_dir=…environments/$profile
else error "environment '$profile' is not buildable: no
           environments/$profile/flake.nix and no
           custom_environments/$profile/flake.nix"; return 1
fi
```

Then, uniformly for every environment, the home half (every system):

```
nix build "path:$flake_dir#homeConfigurations.\"$system\".activationPackage" \
  --override-input public "path:$ROOT/environments"
```

and, on macOS only, the darwin half from the same `$flake_dir` (see the Darwin
section), with the same `--override-input public`.

`--override-input public path:.../environments` points each env's `public` input at
the local core (so untracked `host.nix` is visible without invalidating the env's
lock) — the same trick `lib/nix` already uses for the private flake today. Because
`public` is always overridden to local, an env flake's own locked `public` is moot
at apply time; only its `nixpkgs`/`home-manager` follows matter, and those resolve
through the local core. Effectively one lock (the core's) governs an apply, matching
today's single-lock behavior. This is already proven for `work`.

### Darwin: the second half of every environment

The darwin half is not special-cased to one environment — it is built the same way
as the home half, from the same per-env flake, and gated on the platform rather than
on the env. On macOS, `lib/nix` activates the **selected env's**
`darwinConfigurations."<system>"`. On Linux it skips the darwin step entirely (as it
does today, gated on `uname -s = Darwin`), so the darwin half is never evaluated
there.

Because `lib.mkDarwin` always folds in `darwinModules.base` + `darwinModules.all`,
every env flake exposes a darwin config for darwin systems — even one with no darwin
module of its own. So `lib/nix` builds `<env>#darwinConfigurations."<system>"`
unconditionally on macOS; there is no per-env existence probe.

- `all/darwin/` carries the universal system layer (homebrew base, login shell,
  system PATH, Xcode license, `system.defaults`). Every macOS machine gets it,
  whatever env is selected.
- `default/darwin.nix` adds personal casks/mas/brews on top.
- `agent/` ships no darwin module, so on macOS it gets exactly the `all` system
  layer — the universal base, without `default`'s personal casks. This is a behavior
  change: today `agent` on macOS inherits `default@`'s full system layer (personal
  casks included); now it gets only the universal base. Intended — `agent` is lean.
- `work/darwin.nix` carries private casks/mas/brews. This is what **closes the
  private-darwin deferral** (status doc item #1): the private env is no longer barred
  from shipping system state, because the darwin half is now per-env by construction.

The hardcoded `darwin_target="default@${system}"` pin in `lib/nix` is removed; the
target becomes `<selected-env>` like the home build.

One consequence to flag: `homebrew.onActivation.cleanup = "uninstall"` lives in the
`all` system layer, so an `agent` macOS box will have brew cleanup active with no
declared casks — any imperatively-installed brew package is removed on apply. That is
the existing declarative-only policy applied consistently, not a new rule, but it now
reaches `agent` boxes that previously rode `default`'s cask list.

### Prompt behavior and a TTY guard

Because `default` and `agent` now always exist as candidates, an interactive fresh
machine sees a `default`/`agent` choice (previously it silently used `default`).
Resolution order:

- If `DOTFILES_ENVIRONMENT` is persisted/preset → use it (unchanged; short-circuits
  first).
- Else if stdin is not a TTY → **fail** with a message telling the caller to set
  `DOTFILES_ENVIRONMENT` (e.g. `=agent` for agent boxes, `=default` for a personal
  machine). A non-interactive apply must declare its environment explicitly; it
  never silently assumes `default`. This is the behavior change for headless/agent
  boxes — they were already expected to set `DOTFILES_ENVIRONMENT`, and now it is
  enforced rather than defaulted.
- Else (interactive TTY) if exactly one candidate → use it.
- Else → prompt and persist the choice.

The legacy `environments/*` enumeration branch (`framework/environment` line 57) is
removed. It guards a directory that no longer exists, and after the rename that name
would otherwise resurrect with the core's contents (`flake.nix`, `all/`)
masquerading as environments. The `grep -vx all` filter is also dropped — `all/` has
no `flake.nix` so it is excluded by the directory rule.

### `host.nix`

`host.nix` shrinks to `{ username; }`. The `profile` field is unused by the flake
(only referenced in a comment and the not-found `throw` message); the active env is
selected by which flake `lib/nix` builds, not by a value read inside the flake. It
moves to `environments/host.nix`; `lib/nix` writes it there.

### The rename

`git mv nix environments`, then the internal restructure above:

- `profiles/all/` → `all/home/`. `darwin/base.nix` **splits**: its infrastructure
  (`system.stateVersion`, `nix.enable = false`, username plumbing) → `darwin.nix`
  (`darwinModules.base`); its universal content (homebrew base, login shell, system
  PATH, Xcode license) plus `darwin/defaults.nix` → `all/darwin/` (`darwinModules.all`).
  Together `all`'s two halves are the universal home and system layers.
- `profiles/<env>/` → `<env>/home.nix` (+ supporting dirs like `claude/`) and a new
  per-env `flake.nix`; `darwin/default/homebrew.nix` → `default/darwin.nix`.
- `agent/` gets a `flake.nix` and `home.nix`, no darwin module.

References to update:

- `lib/nix` — every `$DOTFILES_ROOT_DIR/nix` path; the private path drops its `/nix`
  segment (`custom_environments/<env>/flake.nix`, top-level).
- `framework/environment` — new directory rule; remove legacy branch.
- `framework/CLAUDE.md`, `nix/CLAUDE.md` → `environments/CLAUDE.md`,
  `nix/README.md` → `environments/README.md`, root `CLAUDE.md` mention.
- `.gitignore` — ensure `environments/host.nix` is ignored (today `nix/host.nix` is
  generated/untracked but has no explicit ignore entry; add one under the new path).
- The private `work` flake (user-owned repo) has three contract changes to make
  when migrating, all out of scope to edit here but noted so they are not surprises:
  1. `public.url` `?dir=nix` → `?dir=environments`.
  2. The flake moves to `custom_environments/work/flake.nix` (top-level, no `nix/`).
  3. `public.homeModules.default` no longer exists on the core (the core exports only
     `base` + `all`). To layer on `default`'s content, path-import it:
     `import (public + "/default/home.nix")` instead of `public.homeModules.default`.
  4. `work` gains a darwin half: it exposes `darwinConfigurations."<darwin-system>"`
     built via `public.lib.mkDarwin` with `./darwin.nix` (its private casks/mas/brews).
     This is the layer that closes the private-darwin deferral.

## Trade-offs

- **More `flake.lock` files** (core + one per public env). Mitigated by the
  override-input-to-local design: only the core's pins govern an apply, exactly as
  for `work` today. Standalone `nix build environments/agent` without the override
  uses that env's own lock.
- **Public vs private content placement differs slightly**: a public env's module
  content sits in `environments/<env>/`, the core's shared layers in the core; a
  private env is fully self-contained. The *flake shape* is identical, which is what
  enumeration, validation, and the build path depend on.
- **Behavior changes**, all intended: interactive fresh machine now prompts
  `default`/`agent`; a non-interactive apply with no `DOTFILES_ENVIRONMENT` now
  fails fast instead of silently using `default`; `agent` on macOS now gets the
  universal `all` system layer instead of `default`'s full layer (it loses
  `default`'s personal casks, keeps the universal base).

## Testing

No automated tests in this repo. Manual verification:

- `/bin/bash -n` parse-checks (stock 3.2 parser) on `apply`, `framework/*`,
  `lib/nix`.
- `nix build path:environments/default#homeConfigurations."<system>".activationPackage`
  and the same for `agent`, on the current system.
- Darwin: dry build of `environments/default#darwinConfigurations."<system>".system`
  (includes personal casks) and `environments/agent#darwinConfigurations."<system>".system`
  (equals the `all` base — confirm it builds and carries no `default` casks).
- Cross-platform decoupling: `nix eval` an env's `darwinConfigurations` for a Linux
  system (absent — darwin systems only) while its `homeConfigurations` for that same
  Linux system is present, proving the home half is per-system and the darwin half is
  macOS-only.
- `./apply` end-to-end on macOS (the real check).
- Negative case: select a bogus env and confirm `lib/nix` errors with the
  two-paths-not-found message instead of an opaque Nix failure.
