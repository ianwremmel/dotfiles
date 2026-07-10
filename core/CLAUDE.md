# Nix core library (`core/`)

This directory holds the shared Nix library. The core `flake.nix` here is a
*library* — it has no configs of its own. Each environment lives in its own
flake under `../environments/<env>/`, consumes this core, and emits the actual
home / darwin configurations. `./apply` only bootstraps the build (see
`../framework/CLAUDE.md`). User-level state is home-manager; macOS system-level
state is nix-darwin. New shared configuration goes here; per-environment config
goes in the matching `environments/<env>/` flake — not in shell scripts.

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
- **`homeModules.<bundle>`** (`common/<bundle>/`) — shared-but-optional bundles.
  Unlike `all`, these are *not* folded in automatically; an environment opts in
  by adding `public.homeModules.<bundle>` to its own `modules` list. See the
  bundle conventions below; `homeModules.{agent,claude,pairing}` are the
  shipped bundles.
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
layer. The three shipped environments:

- **`default`** — personal machine. Both halves: `default/home.nix` (Claude
  config, personal CLI tools, terminal fonts, git identity + signing) and
  `default/darwin.nix` (personal casks/mas/brews).
- **`agent-interactive`** — an SSH-in agent host. Home half only, Linux only:
  the `agent` bundle plus cluster CLIs, `repos.txt` clones, credential restore,
  and tmux auto-attach.
- **`agent-autonomous`** — an unattended agent host. The `agent` bundle and
  nothing else. Both halves, since it still yields the universal darwin layer
  on macOS.

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
- **Shared-but-optional content** → a bundle under `core/common/<name>`, opted
  into per environment via its flake's `modules` list (see bundle conventions
  below). Use this when several environments — but not all — want the same
  content; putting it in `all/` would force it on every environment instead.
- **Claude Code config** → the `common/claude` bundle. Shared content
  (`files/{rules,guides,agents}/`, the base `CLAUDE.md`) and the
  `settings.json` seed/merge machinery live there; a profile customizes via
  `dotfiles.claude.*` (see below). Claude Code rewrites `settings.json` at
  runtime, so it can't be a read-only store symlink: the `seedClaudeSettings`
  activation script seeds a writable copy and on later applies deep-merges the
  Nix-declared keys over the live file (ours win; Claude's `permissions.allow`
  and other runtime keys survive). A declared key changed interactively (e.g.
  `defaultMode`) reverts to the Nix value on the next apply.
- **A Claude Code plugin every machine should have** → `enabledPlugins` in
  `core/common/claude/plugins.nix`, with its marketplace in the
  `extraKnownMarketplaces` attrset beside it. The file is spliced into both the
  user `settings.json` seed and the agent managed-settings policy.

## Common bundles (`common/`)

A bundle is shared-but-optional content. It lives under `core/common/<name>`,
is exposed from `flake.nix` as `homeModules.<name>`, and an environment opts in
by adding `public.homeModules.<name>` to the `modules` list it passes to
`mkHome` — the same list that already carries `./home.nix`. Leaving it out means
the environment never sees it. Two flavors:

- **Simple bundle** — a plain module (`home.packages` / `programs.*`), on or
  off. No options. Add it to an environment's `modules` list to enable it.
- **Configurable bundle** — an option-bearing module: it declares
  `options.dotfiles.<name>.*` with `mkOption` and reads them in `config`. A
  profile opts in via the `modules` list and customizes by setting those options
  anywhere in its module set. `common/claude` is the worked example: it declares
  `dotfiles.claude.{settings,extraTrees,claudeMd}`. `settings` is typed
  `lib.types.anything` so several modules can each contribute keys and they
  deep-merge; the bundle's base content can be overridden because an option
  `default` (e.g. `claudeMd`) is the lowest merge priority.
  `default/claude.nix` is just the `dotfiles.claude.settings` keys for the
  personal machine; agent hosts get the shared `~/.claude` content
  transitively, through `common/agent`'s import of this bundle.

- **`common/agent`** — the base for agent hosts: `bk`, the Claude
  managed-settings policy, and the MCP server list exported to
  `~/.config/agent/`. It `imports` `../claude`, so an environment adding
  `public.homeModules.agent` also gets the shared `~/.claude` content. Host-
  specific tooling belongs in the consuming environment.
- **`common/pairing`** — the laptop↔agent SSH wiring, one configurable bundle
  with `dotfiles.pairing.mode` (`off`/`client`/`server`) and
  `dotfiles.pairing.remotes`. `client` (set by `default`) installs the
  `remote-agent` launchd socket handler and a `RemoteForward` per paired
  remote; `server` (set by `agent-interactive` and `agent-autonomous`) installs
  the sshd drop-in and the `remote-agent/` shims. The remote list comes from
  `host.remoteAgents`, which `lib/nix` generates from `DOTFILES_REMOTE_AGENTS`.

These are the repo's only `options`/`mkOption` declarations — reserved for the
configurable-bundle case, where a profile genuinely needs to layer onto shared
content. Everything else stays unconditional `imports` plus platform `mkIf`.

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
  (`public.url = "github:ianwremmel/dotfiles?dir=core"`) and override
  scalars with `lib.mkForce`. A private env can carry its own `darwin.nix`, so
  sensitive system state has a declarative home. Note any private-side update in
  `README.md` when migrating something here.

## Pins

`flake.lock` pins nixpkgs (`nixos-26.05`), home-manager (`release-26.05`), and
nix-darwin (`nix-darwin-26.05`); `home.stateVersion` is `25.11` and
nix-darwin's `system.stateVersion` is `5`. Don't bump these casually — `./apply`
after a bump rebuilds everything.
