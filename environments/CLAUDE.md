# Nix configuration (`environments/`)

This directory (renamed from `nix/`) holds the whole Nix configuration. The
core `flake.nix` here is a *library* — it has no configs of its own. Each
environment is its own flake that consumes the core and emits the actual
home / darwin configurations. `./apply` only bootstraps the build (see
`../framework/CLAUDE.md`). User-level state is home-manager; macOS system-level
state is nix-darwin. New configuration goes here — not in shell scripts.

For the human-facing tour (install, manual build, private-flake template,
backout) see `README.md` in this directory. This file is the map for *editing*
the config.

## Layering

The core `flake.nix` exposes shared layers and two builder functions; it emits
no `homeConfigurations`/`darwinConfigurations`. Each environment flake folds the
shared layers in via `lib.mkHome` / `lib.mkDarwin` and adds its own modules.

Core library (`flake.nix`):

- **`homeModules.base`** (`home.nix`) — base home infrastructure: username,
  homeDirectory, stateVersion, `allowUnfree`. Rarely edited.
- **`homeModules.all`** (`all/home/default.nix`) — composed into *every* home
  config: anything every machine should get. Split per-feature: `cli-tools`
  `git` `gpg` `shells` `vim` `home-files` `dotfilesrc-cleanup`.
- **`darwinModules.base`** (`darwin.nix`) — base system infrastructure:
  `system.stateVersion`, `primaryUser`, login user, Touch ID, `nix.enable =
  false`.
- **`darwinModules.all`** (`all/darwin/default.nix`) — the universal system
  layer composed into *every* darwin config: system PATH, login shell, Xcode
  license, and the base homebrew block (universal casks/mas/brews). macOS
  `defaults` come from `all/darwin/defaults.nix`.
- **`lib.mkHome { system, username, modules ? [] }`** — builds a home-manager
  config from `homeModules.base` + `homeModules.all` + the env's `modules`.
- **`lib.mkDarwin { system, username, modules ? [] }`** — builds a nix-darwin
  config from `darwinModules.base` + `darwinModules.all` + the env's `modules`.

Per-environment flakes (`<env>/flake.nix`):

Every environment is a flake with two halves. The **home half** (`<env>/home.nix`
→ `mkHome`) emits `homeConfigurations."<system>"` for all four systems
(`aarch64-darwin x86_64-darwin x86_64-linux aarch64-linux`). The optional
**darwin half** (`<env>/darwin.nix` → `mkDarwin`) emits
`darwinConfigurations."<system>"` for the two darwin systems. Output keys are
bare `"<system>"`, not `"<profile>@<system>"`.

Darwin is gated by *platform*, not by environment. Because `mkDarwin` always
folds in `base` + `all`, even an environment with no own darwin module still
yields a darwin config on macOS — it just equals the universal `all` system
layer. The two shipped environments:

- **`default`** — personal machine. Both halves: `default/home.nix` (Claude
  config, personal CLI tools, terminal fonts, git identity + signing) and
  `default/darwin.nix` (personal casks/mas/brews).
- **`agent`** — headless. Home half only (`agent/home.nix`, intentionally lean,
  nothing beyond the shared base). It has no `darwin.nix`, so on macOS it gets
  the `base` + `all` system layer only — universal casks, no personal ones.

The active environment is selected by which env flake `lib/nix` builds (from
`DOTFILES_ENVIRONMENT`), not by a value inside `host.nix`. The untracked
`host.nix` carries only `{ username; }`; every env flake imports it for the
username.

## Where things go

- **A universal CLI tool** → `home.packages` in `all/home/cli-tools.nix` (every
  machine).
- **A default-only CLI tool** → `home.packages` in `default/cli-tools.nix`.
- **A program with home-manager support** → `programs.<name>` in the matching
  `all/home/*.nix`.
- **A dotfile** → drop it under `all/home/home-files/home/` — every file there
  is auto-symlinked to `$HOME` 1:1 (files under `bin/` become executable). No
  module edit needed.
- **A macOS preference** → `system.defaults.*` in `all/darwin/defaults.nix`; if
  the key has no typed option, use `system.defaults.CustomUserPreferences`.
- **A universal macOS app** → `homebrew.{casks,masApps,brews}` in
  `all/darwin/default.nix` (every macOS machine).
- **A default-only macOS app** → `homebrew.{casks,masApps,brews}` in
  `default/darwin.nix`. A private environment can ship its own system state the
  same way, via its own `darwin.nix`.
- **Claude Code config** → `default/claude/` — files under
  `agents/ skills/ commands/ rules/ guides/` auto-map to `~/.claude/`.
  `settings.json` is generated from the attrset in `default/claude.nix`, but
  Claude Code rewrites that file at runtime, so it can't be a read-only store
  symlink: the `seedClaudeSettings` activation script seeds a writable copy and
  on later applies deep-merges the Nix-declared keys over the live file (ours
  win; Claude's `permissions.allow` and other runtime keys survive). A declared
  key changed interactively (e.g. `defaultMode`) reverts to the Nix value on the
  next apply.

## Conventions

- **Escape hatch for nix-unfriendly packages** → `homebrew.brews` (e.g.
  `watchman` in `all/darwin/default.nix`, `argo` in `default/darwin.nix`).
  Comment why.
- **`homebrew.onActivation.cleanup = "uninstall"`** removes any brew package
  not declared in the flake — there is no Brewfile. Declared-only.
- **One-time migrations** are `home.activation` scripts that retire pre-Nix
  state so home-manager can take over. They vary: most (git, gpg, shells)
  move the old file to `*.legacy-backup`, some marker-gated (`.hm-migrated`)
  and some relying on self-idempotent guards (vim, claude); `home-files`
  deletes exact tracked rsync residue outright (no backup — git has it). They
  concern existing pre-Nix machines only; fresh installs skip them. Match the
  existing style when adding one.
- **`~/.claude/` is managed file-by-file, never as a directory**, so live
  Claude Code state survives. Same pattern for any dir with live state.
- **`nix.enable = false`** in `darwin.nix` — Determinate's installer owns the
  daemon; nix-darwin must not fight it.
- **Private flakes** (`custom_environments/<env>/flake.nix`, top-level) consume
  this core as the `public` input
  (`public.url = "github:ianwremmel/dotfiles?dir=environments"`) and override
  scalars with `lib.mkForce`. A private env can carry its own `darwin.nix`, so
  sensitive system state has a declarative home. Note any private-side update in
  `README.md` when migrating something here.

## Pins

`flake.lock` pins nixpkgs (`nixos-26.05`), home-manager (`release-26.05`), and
nix-darwin (`nix-darwin-26.05`); `home.stateVersion` is `25.11` and
nix-darwin's `system.stateVersion` is `5`. Don't bump these casually — `./apply`
after a bump rebuilds everything.
