# Framework Collapse Slice Design

**Date:** 2026-05-28
**Status:** Draft — pending user approval
**Branch:** `framework-collapse` (stacks on `nix-terminal-fonts` / PR #76 → … → master)
**Slice:** 17

## Context / Goal

Close the **last public-side deferral** — the bash-bootstrap chicken-and-egg
(memory `nix-bootstrap-bash-deferred`) — **not** by inverting the boot order to
install Nix-bash first, but by removing the need for Bash 5 during `./apply`
altogether.

The Bash 5 gate exists for exactly one reason: the homegrown plugin framework
uses Bash-4-only features (`local -n` namerefs, `${var^^}` case modification) to
run a plugin **dependency graph** and **config-prompt** system. With 12 plugins
retired, only `nix` and `homedir` remain — both declare `DEPS=()` and define no
`CONFIG` array — so that entire machinery is now **vestigial**. An audit confirms
the Bash-4 features are confined to just two files:

| File | Bash-4+ construct | Purpose (now dead) |
| ---- | ----------------- | ------------------ |
| `framework/util` | `local -n` in `array_contains`, `array_map` | pass arrays to helpers |
| `framework/plugin` | `local -n` nameref + `${var^^}` (×5) | build `DOTFILES_<PLUGIN>_{DEPS,CONFIG}` var names |

Everything else on the live path (`apply`, `compat`, `config`, `environment`,
`customize`, `logging`, and both plugins) is already Bash-3.2-safe.

So instead of bootstrapping a modern Bash, we **collapse the framework** into a
flat, Bash-3.2.57-safe `./apply` that does only what's still needed, and delete
the plugin abstraction. Nix continues to provide a general-purpose Bash 5 for
scripting (already in `home.packages`), so nothing of value is lost.

**Outcome:** `./apply` runs on stock macOS `/bin/bash` (3.2.57). No `brew install
bash`. No bootstrap inversion needed. The deferral closes.

## What `./apply` actually still needs to do (the live functionality)

Distilled from a full trace of `framework_apply`:

1. Resolve `DOTFILES_ROOT_DIR`.
2. Ensure `~/.dotfilesrc` exists; resolve + persist `DOTFILES_ENVIRONMENT`
   (prompt once on first run). → `framework/{config,environment}`
3. (macOS) Ensure Homebrew is present — nix-darwin's `homebrew` module requires
   brew and does **not** install it (`nix/darwin/base.nix:52-56`). This is the
   side effect the Bash-5 gate quietly provided.
4. Install Nix; generate `nix/host.nix`; build + activate the home-manager
   config; (macOS) activate nix-darwin. → the `nix` logic
5. Rsync `environments/all/home/` + `custom_environments/<env>/home/` into
   `$HOME`. → the `homedir` logic (still serves `custom_environments/work/home`
   until the finale)

Everything else the framework carries — plugin discovery, the
dependency-ordering graph, the `DOTFILES_<PLUGIN>_CONFIG` prompt system,
`array_contains`/`array_map`/`function_exists`/`is_set`, the per-plugin
`prompt_string`/`DEPS` convention, **and the `customize` private-repo
bootstrap** — is dead weight for two zero-dependency, zero-config plugins and
goes away.

## Decisions (locked)

1. **Collapse `apply` into a flat, Bash-3.2-safe orchestrator** that sources the
   surviving helpers and calls the steps above directly. No plugin discovery, no
   dependency resolution. The macOS and Linux paths **unify** into one script
   with a few `if [ "$(uname -s)" = Darwin ]` guards (brew-ensure, sudo
   keepalive) — nix-darwin already self-guards on Darwin inside the nix logic.

2. **Delete the plugin machinery and its Bash-4 carriers, plus `customize`:**
   - `framework/plugin` (deleted — discovery/deps/config system)
   - `framework/util` (deleted — only ever served the plugin machinery)
   - `framework/framework` (deleted — `framework_apply`/`framework_init`
     orchestration folds into `apply`)
   - `framework/customize` (deleted — private `custom_environments` repo
     clone/pull + first-run prompt). **Consequence:** `custom_environments` is no
     longer auto-cloned/updated by `./apply`; it's set up manually (`git clone`
     into `custom_environments/`). Environment resolution still discovers it once
     present (`environment_list_all_environments` scans the dir). The
     `CUSTOMIZATION_SKIP_CUSTOMIZATION` key in `~/.dotfilesrc` becomes inert
     (harmless; left in place).
   - `plugins/` (deleted — the plugin concept goes; see decisions 4–5)

3. **Keep the small, 3.2-safe, load-bearing helpers** in `framework/`:
   - `framework/logging` (`log`/`debug`/`error` — called throughout)
   - `framework/config` (`config_load`/`config_read`/`config_write` for
     `~/.dotfilesrc`)
   - `framework/environment` (`environment_get_current`, `environment_map_func`,
     `environment_get_base_path`, `environment_get_path`)
   - Optional cleanup (non-blocking): prune obviously-dead `environment` helpers
     (`environment_get_item_path`, the unused `environment_list_environments`
     variant). Left out of scope unless trivial.

4. **Relocate the nix logic to `lib/nix`, sourced directly** (was
   `plugins/nix/nix`). The install/profile/build/activate/nix-darwin logic is
   unchanged in substance; drop the `DOTFILES_NIX_DEPS` declaration and the
   "plugin" framing. `apply` sources it and calls `dotfiles_nix_apply`.

5. **Fold the homedir rsync into `apply`** (was `plugins/homedir/homedir`) as a
   small function over `environment_map_func`. Functionality is preserved — it
   still rsyncs `custom_environments/<env>/home/` until the work-finale retires
   that content. Retiring the *plugin wrapper* now does **not** collide with the
   finale (which retires the rsync *content*). The homedir rsync runs on both
   macOS and Linux; on Linux this is effectively a no-op today (`all/home/` is
   empty since slice 15 and Linux has no `custom_environments`), a deliberate,
   low-impact unification rather than a behavior regression.

6. **Drop the Bash-5 gate; keep brew-ensure.** In `framework/compat`, delete
   `compat_ensure_modern_bash`. Retain `compat_ensure_homebrew`, now called
   explicitly on macOS to satisfy nix-darwin's brew prerequisite (decision 1,
   step 4). `apply` no longer re-execs itself under a different bash — it runs
   start-to-finish in the invoking shell, which may be `/bin/bash` 3.2.57.

7. **General-purpose Bash 5 comes from Nix; drop brew's bash.** `bash` is already
   in `home.packages` (`nix/profiles/all/cli-tools.nix:47`), so `~/.nix-profile/
   bin/bash` is on PATH for scripting. Remove `"bash"` and `"bash-completion@2"`
   from `homebrew.brews` (`nix/darwin/base.nix:116-119`); `cleanup = "uninstall"`
   removes them on next activation. Update the now-stale "stays in Brewfile"
   comments at `cli-tools.nix:47-48`.

8. **Repoint bash completion to Nix.** `nix/profiles/all/bash-completion.bash`
   currently sources completion only from brew's prefix
   (`$BREW_PREFIX/share/bash-completion/bash_completion`, lines 30-43). With
   brew's `bash-completion@2` removed, add sourcing of the nixpkgs
   `bash-completion` path (`$HOME/.nix-profile/share/bash-completion/
   bash_completion`). Keep the brew block as a harmless fallback. **Verify
   first** whether home-manager `programs.bash` (`shells.nix:84`) already enables
   completion via `enableCompletion` — if so, this may reduce to deleting the
   brew block. (nixpkgs `bash-completion` is the v2 series — same as the brew
   formula — so behavior is preserved.)

9. **No bootstrap inversion.** The `nix-bootstrap-bash-deferred` memory and the
   `nix-darwin` / `nix-brew-formulas` design specs framed a future "invert boot
   order" slice. This slice supersedes that approach — it's strictly simpler.
   Update the memory and the status doc to record the deferral as **closed by
   collapse**, not inversion.

10. **Docs.** Add a migration-guide sub-block to `nix/README.md` for this slice
    (brew `bash`/`bash-completion@2` are uninstalled on next apply; no
    private-flake change needed). Update `docs/superpowers/nix-migration-status.md`
    (slice 17; deferral #1 closed).

## Files touched

**New:**
- `lib/nix` (moved from `plugins/nix/nix`, de-pluginized)
- `docs/superpowers/specs/2026-05-28-framework-collapse-design.md` (this file)
- `docs/superpowers/plans/2026-05-28-framework-collapse.md` (plan, next step)

**Rewritten:**
- `apply` (flat orchestrator; unified OS paths; sources helpers + `lib/nix`;
  inlines the homedir rsync)
- `framework/compat` (drop `compat_ensure_modern_bash`; keep
  `compat_ensure_homebrew`)
- `nix/darwin/base.nix` (remove `bash`, `bash-completion@2` from `homebrew.brews`)
- `nix/profiles/all/cli-tools.nix` (update stale comments)
- `nix/profiles/all/bash-completion.bash` (source nix bash-completion)
- `nix/README.md`, `docs/superpowers/nix-migration-status.md` (docs)

**Deleted:**
- `framework/framework`, `framework/plugin`, `framework/util`, `framework/customize`
- `plugins/` (entire tree: `plugins/nix/`, `plugins/homedir/`)

**Unchanged but verified:**
- `framework/{logging,config,environment}` (already 3.2-safe)
- the nix flake outputs, home-manager profiles (no flake structure change)

## Verification

1. **Static (the crux):** `bash --version` of `/bin/bash` (confirm 3.2.57).
   `/bin/bash -n apply` and `/bin/bash -n` on each surviving `framework/*` and
   `lib/nix` — syntax-checks under the real 3.2 parser (namerefs / `${^^}` are
   parse-level features, so a clean `-n` proves no Bash-4 syntax remains).
   `grep -rn` for dangling references to deleted symbols (`framework_apply`,
   `plugin_`, `array_contains`, `array_map`, `DOTFILES_.*_DEPS`).
2. **Scaffolding under 3.2, no side effects:** `/bin/bash ./apply -A` (airplane
   mode skips nix install/build) — exercises env resolution, config persistence,
   customize, brew-ensure, and the homedir rsync entirely under 3.2.57 without
   touching the network or rebuilding nix.
3. **Full apply (this Mac):** `./apply` — completes home-manager + nix-darwin
   activation; confirm brew's `bash` / `bash-completion@2` are uninstalled on the
   nix-darwin pass; open a fresh shell and confirm `bash --version` is 5.x from
   `~/.nix-profile/bin/bash` and tab-completion still works.
4. **Linux:** run `./apply` in a Linux container (slice 2 surface) under its
   system bash; confirm nix install + home-manager activation still succeed and
   the homedir rsync is a no-op.
5. **Fresh-Mac simulation (best-effort):** since CI/fresh-Mac isn't available,
   confirm the brew-ensure path by reading `compat_ensure_homebrew` is reached
   before nix-darwin when `brew` is absent (static reasoning).

## Follow-up refinements (same branch, after initial implementation)

Two further simplifications landed on this branch once the collapse was in place:

- **Airplane mode removed.** The `-A` flag, `DOTFILES_AIRPLANE_MODE`, and the
  early-return guard in `lib/nix` are gone — it was only ever a way to skip the
  network-bound nix steps and carried no remaining value. (`DOTFILES_NIX_SKIP`
  still exists as the escape hatch.)
- **Homedir rsync removed entirely** (decision 5 superseded). Rather than keeping
  the inlined rsync, `_dotfiles_apply_home` and the supporting
  `environment_map_func` / `environment_get_path` / `environment_get_base_path` /
  `environment_list_environments` helpers were deleted; `framework/environment`
  now only does `environment_get_current` + `environment_list_all_environments`.
  Public `home/` content already lives in home-manager, and per-env overlays
  (`custom_environments/<env>/home/`) should be served by that env's private
  flake. **Caveat:** `custom_environments/work/home/`'s `.bash_profile`,
  `.gitconfig`, `.zshrc` are not yet in `work/nix` (only `bin/*` migrated), so
  they become unmanaged by `./apply` until the work-finale — accepted by the
  user.
