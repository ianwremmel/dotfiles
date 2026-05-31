# Environments symmetry implementation plan

## Metadata

```yaml
status: draft
plan_version: 1.0
spec_reference: docs/superpowers/specs/2026-05-29-environments-symmetry-design.md
last_updated: 2026-05-31
```

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
(matching the proven `work` flake, which today uses `?dir=nix`). At apply time
`lib/nix` overrides it to the local core with `--override-input public
path:<repo>/environments`, so the committed lock is only a fallback. **Testing
caveat:** a standalone `nix build environments/default#...` *without* the override
uses the locked GitHub core, not local edits — always pass the override (or use the
`lib/nix` path) when testing local changes. This caveat is the price of per-env
locks; it is already how `work` behaves.

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
     (`cli-tools.nix`, `git.nix`, `gpg.nix`, `shells.nix`, `vim.nix`, `home-files/`,
     `dotfilesrc-cleanup.nix`) keep their relative imports, so `all/home/default.nix`
     works unchanged.
   - Edit `environments/home.nix`: **remove** `imports = [ ./profiles/all ];`
     (line 12). `home.nix` is now base infra only (username, homeDirectory,
     stateVersion, `programs.home-manager.enable`). The `all` layer is composed by
     `lib.mkHome` in the flake, not by base. (Today both import it; nix dedupes.
     After this, only the flake adds it.)

3. Split the darwin layer.
   - Create `environments/darwin.nix` (`darwinModules.base`) holding the
     infrastructure from the current `darwin/base.nix`: `nix.enable = false`,
     `system.primaryUser = username`, the `users.users.${username}` block,
     `system.stateVersion = 5`. Keep its function signature
     `{ lib, pkgs, username, ... }:` as needed.
   - Create `environments/all/darwin/default.nix` (`darwinModules.all`) holding the
     universal *content* from the current `darwin/base.nix`: `programs.zsh.enable`,
     `environment.shells`, `environment.systemPath`, the `homebrew` block (enable,
     onActivation, universal `casks`/`masApps`/`brews`), and
     `system.activationScripts.xcodeLicense`. Add `imports = [ ./defaults.nix ];`.
   - `git mv environments/darwin/defaults.nix environments/all/darwin/defaults.nix`.
   - Delete the now-empty `environments/darwin/base.nix` and the `environments/darwin/`
     dir (its `default/` content moves in Phase 2).

4. Rewrite `environments/flake.nix` to a library only:
   - Drop `publicProfiles`, `darwinProfiles`, `supportedSystems`/`darwinSystems`
     iteration, and the `homeConfigurations`/`darwinConfigurations` outputs.
   - Keep/define `homeModules = { base = ./home.nix; all = ./all/home/default.nix; }`
     and `darwinModules = { base = ./darwin.nix; all = ./all/darwin/default.nix; }`.
   - `lib.mkHome = { system, username, modules ? [] }:` composes
     `[ self.homeModules.base self.homeModules.all ] ++ modules`.
   - `lib.mkDarwin = { system, username, modules ? [] }:` composes
     `[ self.darwinModules.base self.darwinModules.all ] ++ modules` (note: add
     `username` to the args and pass via `specialArgs`, since `darwin.nix` needs it).
   - Keep the `nixpkgs`/`home-manager`/`nix-darwin` inputs and `allowUnfree` config.
   - Remove the `host` import and the not-found `throw` — the core no longer reads
     `host.nix`; env flakes import it (Phase 2).

5. Shrink `environments/host.nix` to `{ username = "..."; }` (drop `profile`). Leave
   the generated file as-is for now; `lib/nix` is updated to write the new shape in
   Phase 3.

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
     then `git mv` its siblings (`claude.nix`, `claude/`, `cli-tools.nix`,
     `fonts.nix`, `git.nix`, `terminal.nix`, `patch-terminal-fonts.py`) into
     `environments/default/`. The relative imports inside `default/home.nix`
     (`./claude.nix` etc.) stay valid.
   - `git mv environments/profiles/agent/default.nix environments/agent/home.nix`
     (content is `{ }` today — fine).
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

3. Write `environments/agent/flake.nix`: same as `default` but `modules =
   [ ./home.nix ]` for home and **no `./darwin.nix` module** for darwin (the
   darwin config is the `base`+`all` layers only, via `mkDarwin` with `modules = []`).
   Still emit `darwinConfigurations."<system>"` for darwin systems so the platform —
   not the env — gates darwin (per spec).

4. Generate locks: `nix flake lock path:environments/default` and
   `nix flake lock path:environments/agent` (creates each `flake.lock`). Commit them.

**Verification (current system `$S = $(nix eval --impure --raw --expr builtins.currentSystem)`):**

- [ ] `nix build --no-link path:environments/default#homeConfigurations."$S".activationPackage
      --override-input public path:environments` succeeds.
- [ ] Same for `environments/agent`.
- [ ] On macOS: `nix build --no-link
      path:environments/default#darwinConfigurations."$S".system --override-input
      public path:environments` succeeds and the result includes personal casks
      (`visual-studio-code`, `docker`, `slack`).
- [ ] On macOS: same build for `environments/agent` succeeds and the result has the
      universal casks (`1password`, `google-chrome`) but **not** the personal ones.
- [ ] `nix eval path:environments/agent#darwinConfigurations --apply builtins.attrNames
      --override-input public path:environments` lists only darwin systems (no
      `x86_64-linux`/`aarch64-linux`), proving darwin is platform-gated.

### Phase 3: Bash layer (`lib/nix` + `framework/environment`)

**Goal:** one build path keyed on the directory rule, with fail-fast validation; the
prompt enumerates by the same rule with a TTY guard.

**Tasks:**

1. `framework/environment` — `environment_list_all_environments`:
   - Replace the body with: list basenames of `environments/*/` and
     `custom_environments/*/` that contain a `flake.nix`, deduped. Drop the legacy
     `[ -d "$DOTFILES_ROOT_DIR/environments" ] && ls …` branch entirely and the
     `grep -vx all` filter (`all/` has no `flake.nix`, so it is excluded by the rule;
     the top-level `environments/flake.nix` is not a subdir, so it is not a
     candidate). Keep Bash-3.2 compatibility (no `mapfile`, no `${var^^}`).

2. `framework/environment` — `environment_get_current` resolution order (spec
   "Prompt behavior and a TTY guard"):
   - If `DOTFILES_ENVIRONMENT` persisted → use it (unchanged).
   - Else if stdin is not a TTY (`[ ! -t 0 ]`) → `error` telling the caller to set
     `DOTFILES_ENVIRONMENT` (e.g. `=agent`/`=default`) and `return 1`. No silent
     `default`.
   - Else if exactly one candidate → use it.
   - Else → `select` prompt and persist.

3. `lib/nix` — `dotfiles_nix_apply`:
   - Resolve `flake_dir`: prefer `custom_environments/$profile/flake.nix`, else
     `environments/$profile/flake.nix`, else `error "environment '$profile' is not
     buildable: no environments/$profile/flake.nix and no
     custom_environments/$profile/flake.nix"; return 1`. (Drop the old
     `custom_environments/$profile/nix/flake.nix` path and the public-vs-private
     target split.)
   - Home build (all systems): `nix … build
     "path:$flake_dir#homeConfigurations.\"$system\".activationPackage"
     --override-input public "path:$DOTFILES_ROOT_DIR/environments"` → activate.
   - Darwin (macOS only, replacing the `darwin_target="default@${system}"` block):
     build/switch `path:$flake_dir#darwinConfigurations."$system"` with the same
     `--override-input public`. Keep the existing unchanged-system skip logic and
     `sudo -H` handling; only the flake ref and target change. Remove the
     `default@`-pinning comment and logic.
   - `host.nix` write: change the generated content to `{ username = "%s"; }` (drop
     `profile`) and the path to `$DOTFILES_ROOT_DIR/environments/host.nix`.
   - Update every `$DOTFILES_ROOT_DIR/nix` path to `$DOTFILES_ROOT_DIR/environments`.

**Verification:**

- [ ] `/bin/bash -n apply framework/environment framework/config framework/logging
      lib/nix framework/compat` all parse clean under stock 3.2.
- [ ] `shellcheck framework/environment lib/nix` clean (or no new findings).
- [ ] Dry resolution: with `DOTFILES_ENVIRONMENT` unset and stdin not a TTY,
      `environment_get_current </dev/null` fails with the set-the-variable message
      (test by sourcing the helpers in a scratch shell).
- [ ] Negative build path: temporarily set `DOTFILES_ENVIRONMENT=bogus` and confirm
      `lib/nix`'s resolver prints the two-paths-not-found error (read the code path;
      do not run a full apply yet).

### Phase 4: Docs and references

**Goal:** no stale `nix/` references; guides reflect the new layout.

**Tasks:**

1. `git mv nix/CLAUDE.md` is already done by Phase 1's tree move
   (`environments/CLAUDE.md`); rewrite its contents for the new layout (core +
   per-env flakes, the two-halves model, the darwin split). Same for
   `environments/README.md`.
2. `framework/CLAUDE.md` — update the `lib/nix` section (step 5: directory-rule flake
   selection, per-env darwin) and the `environment` helper description (directory
   rule, TTY-fail).
3. Root `CLAUDE.md` (`/Users/ian/projects/dotfiles/CLAUDE.md`) — update the structure
   bullet that names `nix/` to `environments/`.
4. Confirm `environments/.gitignore` still ignores `/host.nix` (moved by Phase 1; no
   edit needed — verify only).

**Verification:**

- [ ] `grep -rn "\bnix/" --include="*.md" . | grep -v environments/` returns no
      stale references to the old public `nix/` path (excluding intentional mentions
      of the Nix tool/daemon).
- [ ] `grep -rn "publicProfiles\|darwinProfiles\|profiles/all\|darwin/base.nix" .`
      returns nothing outside the spec/plan docs and git history.

### Phase 5: End-to-end on macOS

**Goal:** `./apply` works against the new layout on a real machine.

**Tasks:**

1. Run `DOTFILES_DEBUG=1 ./apply` on macOS with `DOTFILES_ENVIRONMENT=default`.
2. Observe: `host.nix` written as `{ username = …; }` under `environments/`; home
   build + activate succeeds; nix-darwin builds/switches `default`'s darwin config.

**Verification:**

- [ ] `./apply` completes without error.
- [ ] `readlink /run/current-system` matches a fresh
      `nix build environments/default#darwinConfigurations."$S".system` (the
      unchanged-skip logic still reconciles).
- [ ] A second `./apply` is a no-op for the darwin switch (skip logic intact).
- [ ] `home-manager` generation reflects `default`'s home half (e.g. `claude`
      config present).

## Testing strategy

No automated tests in this repo (per CLAUDE.md). Verification is the per-phase
checklists above: `nix eval`/`nix build` for the flake layers, `/bin/bash -n` +
`shellcheck` for the bash layer, and a real `./apply` in Phase 5. The cross-platform
darwin-gating check (Phase 2) and the negative build-path check (Phase 3) are the
two that guard the spec's headline behaviors.

## Risks

- **Intermediate non-evaluating tree (Phases 1–2).** The core is restructured before
  the env flakes exist, so the tree does not fully build until end of Phase 2. Do not
  run `./apply` mid-refactor. Mitigation: phase verifications use `nix flake check`
  on the core (Phase 1) and per-env builds (Phase 2), not a full apply.
- **`darwin.nix` needs `username`.** The split moves `users.users.${username}` and
  `system.primaryUser` into `darwin.nix` (`darwinModules.base`). `lib.mkDarwin` must
  pass `username` via `specialArgs` (the current flake already does this for the
  monolithic base). Verify the arg threads through.
- **`home.nix` double-import removal.** If `home.nix` keeps importing `./profiles/all`
  after the move, the path breaks (dir renamed) — Phase 1 task 2 removes that import.
  Forgetting it surfaces as an eval error pointing at `./profiles/all`.
- **Standalone build uses locked GitHub core, not local edits.** Always pass
  `--override-input public path:environments` when testing locally (see the `public`
  input convention above). Forgetting it produces confusing "my change didn't take"
  results.
- **`work` is out of scope but its contract changes.** The four `work`-side changes
  (spec "The rename" → references) are the user's to make in the private repo. After
  this lands, `work` will not build until migrated; that is expected and called out in
  the spec. Do not attempt to edit `custom_environments/` here.
- **Bash 3.2.** The new enumeration must avoid Bash-4 features. Use a `for`/`case`
  loop over `ls`, not `mapfile`/associative arrays. `/bin/bash -n` is the gate.
