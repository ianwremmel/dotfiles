# Environments symmetry implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every environment (public `default`/`agent`, private `work`) a flake of one shape — a home half plus an optional darwin half — consuming one shared core flake, so a single directory rule drives prompt enumeration, build validation, and the build path.

**Architecture:** Rename `nix/` → `environments/`. The renamed `environments/flake.nix` becomes a library only (`lib.mkHome`, `lib.mkDarwin`, `homeModules.{base,all}`, `darwinModules.{base,all}`); each environment gets its own flake consuming it as input `public`. `lib/nix` and `framework/environment` switch to a `<dir>/flake.nix`-exists rule.

**Tech Stack:** Nix flakes, home-manager, nix-darwin (all `26.05`); Bash 3.2 for the bootstrap layer.

> **Granularity note:** This repo has no automated tests (per `CLAUDE.md`) and the work is a mechanical Nix/bash restructure, not a TDD feature build. Tasks are grouped into phases with `nix eval`/`nix build`, `/bin/bash -n`, and `shellcheck` as the per-phase verification gates instead of red/green test loops. The tree does not fully evaluate between Phase 1 and Phase 2 — see Risks.

```yaml
status: draft
plan_version: 1.0
spec_reference: docs/superpowers/specs/2026-05-29-environments-symmetry-design.md
last_updated: 2026-05-31
```

---

## Overview

Refactor the Nix configuration so every environment — public (`default`, `agent`)
and private (`custom_environments/work`) — is a flake with the same shape: a
home-manager half (every system) and an optional darwin half (macOS only), each
consuming one shared **core flake**. A single directory rule (`<dir>/flake.nix`
exists) then drives prompt enumeration, `lib/nix` validation, and the build path,
so the two enumerations that diverge today cannot drift. The public `nix/` tree is
renamed to `environments/` to restore the naming parallel with `custom_environments`.

See the spec for full design rationale. This plan is the mechanics.

## Architecture / approach

Today (`nix/flake.nix`): one flake holds `publicProfiles = ["default" "agent"]`
and emits `homeConfigurations."<profile>@<system>"` + a single
`darwinConfigurations."default@<system>"`. The prompt (`framework/environment`)
scans the filesystem independently. `lib/nix` bridges them with a public branch and
a separate private-flake branch.

After this change:

- `environments/flake.nix` is a **library only** — `lib.mkHome`, `lib.mkDarwin`,
  `homeModules.{base,all}`, `darwinModules.{base,all}`. It emits no
  `homeConfigurations`/`darwinConfigurations` of its own.
- Each environment is its own flake (`environments/default/flake.nix`,
  `environments/agent/flake.nix`, and privately `custom_environments/work/flake.nix`)
  consuming the core as input `public`, emitting `homeConfigurations."<system>"` for
  every supported system and `darwinConfigurations."<system>"` for darwin systems.
- `lib/nix` resolves the selected env to a flake dir via the directory rule, builds
  the home half always and the darwin half on macOS, both with
  `--override-input public path:<repo>/environments`.

Phases below leave the tree non-evaluating between Phase 1 and Phase 2 (the core is
restructured before the per-env flakes that consume it exist). The first full build
verification is at the end of Phase 2. Do not run `./apply` until Phase 5.

### `public` input convention (decision)

Every env flake declares `public.url = "github:ianwremmel/dotfiles?dir=environments"`
(matching the `work` flake, which today uses `?dir=nix`). At apply time `lib/nix`
overrides it to the local core with `--override-input public
path:<repo>/environments`, so the committed lock is only a fallback. **Testing
caveat:** a standalone `nix build environments/default#...` *without* the override
uses the locked GitHub core, not local edits — always pass the override (or use the
`lib/nix` path) when testing local changes. This caveat is the price of per-env
locks; it is how `work` behaves today.

## File structure

Created:

- `environments/darwin.nix` — `darwinModules.base` (darwin infra split out of the old `darwin/base.nix`).
- `environments/all/darwin/default.nix` — `darwinModules.all` (universal system content).
- `environments/default/flake.nix`, `environments/agent/flake.nix` — per-env flakes.

Moved (via `git mv`, preserving history):

- `nix/` → `environments/` (whole tree).
- `environments/profiles/all/` → `environments/all/home/` (`homeModules.all`).
- `environments/profiles/default/*` → `environments/default/` (`home.nix` + supporting files).
- `environments/profiles/agent/default.nix` → `environments/agent/home.nix`.
- `environments/darwin/default/homebrew.nix` → `environments/default/darwin.nix`.
- `environments/darwin/defaults.nix` → `environments/all/darwin/defaults.nix`.

Modified:

- `environments/flake.nix` — reduced to a library.
- `environments/home.nix` — comment-only update.
- `environments/host.nix` — `{ username; }` (drop `profile`); regenerated by `lib/nix`.
- `lib/nix`, `framework/environment` — directory-rule build + enumeration.
- `environments/CLAUDE.md`, `environments/README.md`, `framework/CLAUDE.md`, root `CLAUDE.md` — docs.

Deleted (after their content moves):

- `environments/darwin/base.nix`, `environments/darwin/` dir, `environments/profiles/` tree.

## Implementation phases

### Phase 1: Core flake + shared layers

**Goal:** `environments/` exists as the core library flake plus the shared `all`
layer and base infra. No per-env home/darwin configs in the core.

**Tasks:**

1. Rename the tree.
   - `git mv nix environments` (moves `flake.nix`, `flake.lock`, `host.nix`,
     `.gitignore`, `profiles/`, `darwin/`, `CLAUDE.md`, `README.md`).

2. Restructure the home layers.
   - `git mv environments/profiles/all environments/all/home` — the feature modules
     (`cli-tools.nix`, `git.nix`, `gpg.nix`, `shells.nix`, `vim.nix`, `home-files.nix`,
     `home-files/`, `dotfilesrc-cleanup.nix`, and the `*.bash`/`omz_*.zsh` sourced
     fragments) keep their relative imports, so `all/home/default.nix` works unchanged.
   - `environments/home.nix` needs **no import change** — it is already infra-only
     (`home.username`, `home.homeDirectory`, `home.stateVersion`,
     `programs.home-manager.enable`, `nixpkgs.config.allowUnfree`) and does not import
     `profiles/all`; the `all` layer is composed by `lib.mkHome` in the flake. Only
     update its trailing comment that references `profiles/all/default.nix` and
     `profiles/<name>/default.nix` to the new paths (`all/home/default.nix`,
     `<env>/home.nix`).

3. Split the darwin layer (current `darwin/base.nix` is 127 lines; it splits into
   infra vs content).
   - Create `environments/darwin.nix` (`darwinModules.base`), signature
     `{ pkgs, username, ... }:`, holding the **infrastructure** from `darwin/base.nix`:
     `system.stateVersion = 5`, `system.primaryUser = username`, `nix.enable = false`,
     the `users.users.${username}` block, and `security.pam.services.sudo_local`
     (Touch ID — infra, not app content).
   - Create `environments/all/darwin/default.nix` (`darwinModules.all`), holding the
     universal **content** from `darwin/base.nix`: `environment.systemPath`,
     `environment.shells`, `system.activationScripts.xcodeLicense`, and the whole
     `homebrew` block (`enable`, `onActivation`, universal `casks`/`masApps`/`brews`).
     Add `imports = [ ./defaults.nix ];` at its top.
   - `git mv environments/darwin/defaults.nix environments/all/darwin/defaults.nix`.
   - Delete `environments/darwin/base.nix`. Leave `environments/darwin/default/` for
     Phase 2 (its `homebrew.nix` moves then); the `environments/darwin/` dir is removed
     at the end of Phase 2 task 1.

4. Rewrite `environments/flake.nix` to a library only:
   - Drop `publicProfiles`, `darwinProfiles`, the `supportedSystems`/`darwinSystems`
     iteration, and the `homeConfigurations`/`darwinConfigurations` outputs.
   - Define `homeModules = { base = ./home.nix; all = ./all/home/default.nix; }` and
     `darwinModules = { base = ./darwin.nix; all = ./all/darwin/default.nix; }`.
   - `lib.mkHome = { system, username, modules ? [] }:` →
     `home-manager.lib.homeManagerConfiguration` with
     `extraSpecialArgs = { inherit username; }` and
     `modules = [ self.homeModules.base self.homeModules.all ] ++ modules`.
   - `lib.mkDarwin = { system, username, modules ? [] }:` →
     `nix-darwin.lib.darwinSystem` with `specialArgs = { inherit username; }` and
     `modules = [ self.darwinModules.base self.darwinModules.all ] ++ modules`.
     (Note: `mkDarwin` gains a `username` arg vs. today, since the env flake supplies
     it rather than the core reading `host.nix`.)
   - Keep the `nixpkgs`/`home-manager`/`nix-darwin` inputs.
   - Remove the `host` import and the not-found `throw` — the core no longer reads
     `host.nix`; env flakes import it (Phase 2). (`allowUnfree` stays in `home.nix`,
     so nothing to move.)

5. Shrink `environments/host.nix` to `{ username = "..."; }` (drop `profile`). The
   generated file is regenerated by `lib/nix` in Phase 3; editing the checked-in
   sample here just keeps it consistent.

**Verification:**

- [ ] `nix flake check path:environments --no-build` evaluates the library without
      error (it exposes `lib`, `homeModules`, `darwinModules`; no configs).
- [ ] `nix eval path:environments#homeModules.all --apply builtins.typeOf` returns
      a value (module path resolves).
- [ ] `git status` shows only renames/edits under `environments/`, no stray files.

### Phase 2: Per-environment flakes (default, agent)

**Goal:** `environments/default/` and `environments/agent/` are flakes consuming the
core, each emitting home configs for all systems and darwin configs for darwin
systems.

**Tasks:**

1. Move profile content into env dirs.
   - `git mv environments/profiles/default/default.nix environments/default/home.nix`,
     then `git mv` its siblings into `environments/default/`: `claude.nix`, `claude/`,
     `cli-tools.nix`, `terminal-fonts.nix`, `patch-terminal-fonts.py`. The relative
     imports inside `default/home.nix` (`./claude.nix`, `./cli-tools.nix`,
     `./terminal-fonts.nix`) stay valid.
   - `git mv environments/profiles/agent/default.nix environments/agent/home.nix`
     (content is `{ ... }: { }` today — fine as the home half).
   - `git mv environments/darwin/default/homebrew.nix environments/default/darwin.nix`.
   - Remove the now-empty `environments/profiles/` and `environments/darwin/` trees.

2. Write `environments/default/flake.nix`:
   - Inputs: `public.url = "github:ianwremmel/dotfiles?dir=environments";`
     `nixpkgs.follows = "public/nixpkgs";` `home-manager.follows =
     "public/home-manager";` `nix-darwin.follows = "public/nix-darwin";`.
   - `host = import (public + "/host.nix");` for the username.
   - `supportedSystems = [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux"
     "aarch64-linux" ];` and `darwinSystems = [ "aarch64-darwin" "x86_64-darwin" ];`.
   - `homeConfigurations` = one `"<system>"` per supportedSystem via
     `public.lib.mkHome { inherit system; inherit (host) username; modules =
     [ ./home.nix ]; }`.
   - `darwinConfigurations` = one `"<system>"` per darwinSystem via
     `public.lib.mkDarwin { inherit system; inherit (host) username; modules =
     [ ./darwin.nix ]; }`.

3. Write `environments/agent/flake.nix`: same inputs and `host` import as `default`;
   `homeConfigurations` via `mkHome { … modules = [ ./home.nix ]; }`;
   `darwinConfigurations` via `mkDarwin { … modules = []; }` (no `./darwin.nix` — the
   darwin config is `base`+`all` only). Still emit `darwinConfigurations."<system>"`
   for every darwinSystem so the *platform*, not the env, gates darwin (per spec).

4. Generate locks: `nix flake lock path:environments/default` and
   `nix flake lock path:environments/agent`. Commit both `flake.lock` files.

**Verification** (set `S="$(nix eval --impure --raw --expr builtins.currentSystem)"`):

- [ ] `nix build --no-link "path:environments/default#homeConfigurations.\"$S\".activationPackage"
      --override-input public path:environments` succeeds.
- [ ] Same for `environments/agent`.
- [ ] On macOS: `nix build --no-link
      "path:environments/default#darwinConfigurations.\"$S\".system" --override-input
      public path:environments` succeeds; grep the built Brewfile/store path for a
      personal cask (`webstorm`) to confirm `default`'s darwin half is present.
- [ ] On macOS: same build for `environments/agent` succeeds; confirm a universal cask
      (`1password`) is present but a personal one (`webstorm`) is **absent**.
- [ ] `nix eval "path:environments/agent#darwinConfigurations" --apply builtins.attrNames
      --override-input public path:environments` lists only darwin systems (no
      `x86_64-linux`/`aarch64-linux`), proving darwin is platform-gated.

### Phase 3: Bash layer (`lib/nix` + `framework/environment`)

**Goal:** one build path keyed on the directory rule, with fail-fast validation; the
prompt enumerates by the same rule with a TTY guard.

**Tasks:**

1. `framework/environment` — rewrite `environment_list_all_environments` to the
   directory rule: emit the basename of each `environments/*/` and
   `custom_environments/*/` directory that contains a `flake.nix`, deduped. Drop the
   legacy `[ -d "$DOTFILES_ROOT_DIR/environments" ] && ls …` branch and the
   `grep -vx all` filter (`all/` has no `flake.nix` so the rule excludes it; the
   top-level `environments/flake.nix` is not a subdir so it is not a candidate).
   Bash-3.2-safe: a `for d in "$DOTFILES_ROOT_DIR"/environments/*/
   "$DOTFILES_ROOT_DIR"/custom_environments/*/` loop with `[ -f "$d/flake.nix" ]`,
   `basename`, piped through `sort -u`. No `mapfile`, no associative arrays.

2. `framework/environment` — `environment_get_current` resolution order (spec
   "Prompt behavior and a TTY guard"):
   - If `DOTFILES_ENVIRONMENT` persisted → use it (unchanged).
   - Else if stdin is not a TTY (`[ ! -t 0 ]`) → `error` telling the caller to set
     `DOTFILES_ENVIRONMENT` (e.g. `=agent`/`=default`) and `return 1`. No silent
     `default`.
   - Else if exactly one candidate → use it.
   - Else → `select` prompt and persist (existing block).

3. `lib/nix` — `dotfiles_nix_apply`:
   - Resolve `flake_dir`: prefer `custom_environments/$profile/flake.nix`, else
     `environments/$profile/flake.nix`, else `error "environment '$profile' is not
     buildable: no environments/$profile/flake.nix and no
     custom_environments/$profile/flake.nix"; return 1`. (Drop the old
     `custom_environments/$profile/nix/flake.nix` path and the public-vs-private
     target split; the home target is always `homeConfigurations."$system"`.)
   - Home build (all systems): `nix "${nixflags[@]}" build
     "path:$flake_dir#homeConfigurations.\"$system\".activationPackage"
     --override-input public "path:$DOTFILES_ROOT_DIR/environments" --out-link …`
     → run `activate` (unchanged downstream).
   - Darwin (macOS only): replace the `darwin_target="default@${system}"` block.
     Target is `path:$flake_dir#darwinConfigurations."$system"` (the selected env's
     own darwin config), with `--override-input public
     "path:$DOTFILES_ROOT_DIR/environments"` on the bootstrap `nix run`, the
     unchanged-check `nix build …#….system`, and the `darwin-rebuild switch`. Keep
     the existing unchanged-system skip logic, `DOTFILES_DARWIN_FORCE`, and `sudo -H`.
     Remove the `default@`-pinning comment.
   - `host.nix` write: change the generated content to `{ username = "%s"; }` (drop
     `profile`) and the path to `$DOTFILES_ROOT_DIR/environments/host.nix`. The
     `profile` value is still resolved (it selects the flake dir) but no longer
     written into `host.nix`.
   - Update every remaining `$DOTFILES_ROOT_DIR/nix` literal to
     `$DOTFILES_ROOT_DIR/environments`.

**Verification:**

- [ ] `/bin/bash -n apply framework/environment framework/config framework/logging
      lib/nix framework/compat` all parse clean under stock 3.2.
- [ ] `shellcheck framework/environment lib/nix` shows no new findings.
- [ ] Dry resolution: in a scratch shell, source `framework/logging framework/config
      framework/environment`, set `DOTFILES_ROOT_DIR`, unset `DOTFILES_ENVIRONMENT`,
      and run `environment_get_current </dev/null` — it fails with the
      set-the-variable message (non-TTY branch).
- [ ] Negative build path: read the `lib/nix` resolver and confirm a `profile` with
      neither flake path prints the two-paths-not-found error and returns 1 (do not
      run a full apply yet).

### Phase 4: Docs and references

**Goal:** no stale `nix/` references; guides reflect the new layout.

**Tasks:**

1. Rewrite `environments/CLAUDE.md` (moved by Phase 1) for the new layout: core
   library + per-env flakes, the two-halves model, `all/{home,darwin}/`, the darwin
   split, and the directory rule. Update its "Where things go" paths
   (`profiles/all/*` → `all/home/*`, `darwin/base.nix` → `darwin.nix` +
   `all/darwin/default.nix`, `darwin/default/homebrew.nix` → `default/darwin.nix`).
2. Rewrite `environments/README.md` (moved by Phase 1): the per-env-flake model, the
   `?dir=environments` private template, and the build/backout commands.
3. `framework/CLAUDE.md` — update the `environment` helper description (directory rule,
   non-TTY fail) and the `lib/nix` section (step 5 directory-rule selection, per-env
   darwin, `host.nix` is `{ username; }` under `environments/`). Replace the closing
   "New configuration belongs in `nix/`" with `environments/`.
4. Root `CLAUDE.md` — update the structure bullets that name `nix/` to `environments/`
   (the `Structure` list and the `nix/CLAUDE.md` subtree-guide pointer).
5. Verify `environments/.gitignore` still ignores `/host.nix` (moved by Phase 1; no
   edit — confirm only).

**Verification:**

- [ ] `grep -rn "nix/CLAUDE\|nix/README\|nix/flake\|nix/profiles\|nix/darwin\|nix/home"
      --include="*.md" . | grep -v docs/superpowers` returns nothing (no stale public
      `nix/` path references in live docs; spec/plan history is allowed).
- [ ] `grep -rn "publicProfiles\|darwinProfiles\|profiles/all\|darwin/base.nix"
      --include="*.md" . | grep -v docs/superpowers` returns nothing.

### Phase 5: End-to-end on macOS

**Goal:** `./apply` works against the new layout on a real machine.

**Tasks:**

1. Run `DOTFILES_ENVIRONMENT=default DOTFILES_DEBUG=1 ./apply` on macOS.
2. Observe: `environments/host.nix` written as `{ username = …; }`; home build +
   activate succeeds; nix-darwin builds/switches `default`'s darwin config.

**Verification:**

- [ ] `./apply` completes without error.
- [ ] `readlink /run/current-system` matches a fresh
      `nix build "path:environments/default#darwinConfigurations.\"$S\".system"
      --override-input public path:environments --no-link --print-out-paths`.
- [ ] A second `./apply` logs "nix-darwin system unchanged; skipping switch" (skip
      logic intact).
- [ ] `home-manager` generation reflects `default`'s home half (e.g. `~/.claude/`
      seeded, personal CLI tools on PATH).

## Testing strategy

No automated tests in this repo (per `CLAUDE.md`). Verification is the per-phase
checklists above: `nix flake check`/`nix eval`/`nix build` for the flake layers,
`/bin/bash -n` + `shellcheck` for the bash layer, and a real `./apply` in Phase 5.
The cross-platform darwin-gating check (Phase 2) and the negative build-path check
(Phase 3) are the two that guard the spec's headline behaviors.

## Risks

- **Intermediate non-evaluating tree (Phases 1–2).** The core is restructured before
  the env flakes exist, so the tree does not fully build until end of Phase 2. Do not
  run `./apply` mid-refactor. Phase 1 verifies with `nix flake check` on the core;
  Phase 2 with per-env builds.
- **`darwin.nix` needs `username`.** The split moves `users.users.${username}` and
  `system.primaryUser` into `darwin.nix` (`darwinModules.base`). `lib.mkDarwin` must
  pass `username` via `specialArgs` (the current monolithic flake already does this).
  Verify the arg threads through after the split.
- **`home.nix` has no `profiles/all` import** (verified against the current file). The
  `all` layer is composed only by `lib.mkHome`. Do not add or "fix" an import here;
  the only `home.nix` change is the trailing-comment path update.
- **Standalone build uses the locked GitHub core, not local edits.** Always pass
  `--override-input public path:environments` when testing locally (see the `public`
  input convention). Forgetting it produces confusing "my change didn't take" results.
- **`work` is out of scope but its contract changes.** The four `work`-side changes
  (spec "The rename" → references) are the user's to make in the private repo. After
  this lands, `work` will not build until migrated; that is expected and called out in
  the spec. Do not edit `custom_environments/` here.
- **Bash 3.2.** The new enumeration must avoid Bash-4 features. Use a `for`/`case`
  glob loop, not `mapfile`/associative arrays. `/bin/bash -n` under stock
  `/bin/bash` is the gate.
