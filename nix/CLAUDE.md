# Nix configuration (`nix/`)

This flake *is* the configuration. `./apply` only bootstraps it (see
`../framework/CLAUDE.md`). User-level state is home-manager; macOS system-level
state is nix-darwin. New configuration goes here — not in shell scripts.

For the human-facing tour (install, manual build, private-flake template,
backout) see `README.md` in this directory. This file is the map for *editing*
the config.

## Layering

`flake.nix` composes modules in order; each layer can extend or override the
ones below it.

- **`home.nix`** — base infrastructure: username, homeDirectory,
  stateVersion, `allowUnfree`. Rarely edited.
- **`profiles/all/`** — composed into *every* config by `lib.mkHome`,
  regardless of profile or private overlay. Anything every machine should get.
  Split per-feature: `cli-tools` `git` `gpg` `shells` `vim` `home-files`
  `dotfilesrc-cleanup`.
- **`profiles/<profile>/`** — selectable. `default` = personal machine (Claude
  config, personal CLI tools, terminal fonts, git identity + signing);
  `agent` = headless, intentionally empty.
- **`darwin/`** (macOS system layer) — `base.nix` (universal: homebrew base,
  login shell, system PATH, Xcode license, macOS `defaults` via
  `defaults.nix`) + `default/homebrew.nix` (personal casks/mas/brews). Only
  `default` has a darwin module — there is no `agent` system layer. (`agent`
  still has a home-manager config on every system, including macOS.)

The active profile comes from `DOTFILES_ENVIRONMENT` via the untracked
`host.nix` (`{ username; profile; }`). Home outputs are
`homeConfigurations."<profile>@<system>"` (one per profile × system). Only
`default` has a darwin module, so the sole darwin output is
`darwinConfigurations."default@<system>"` — and `lib/nix` always activates that
one regardless of the active profile.

## Where things go

- **A CLI tool** → `home.packages` in `profiles/all/cli-tools.nix` (every
  machine) or `profiles/default/cli-tools.nix` (personal only).
- **A program with home-manager support** → `programs.<name>` in the matching
  `profiles/all/*.nix`.
- **A dotfile** → drop it under `profiles/all/home-files/home/` — every file
  there is auto-symlinked to `$HOME` 1:1 (files under `bin/` become
  executable). No module edit needed.
- **A macOS preference** → `system.defaults.*` in `darwin/defaults.nix`; if the
  key has no typed option, use `system.defaults.CustomUserPreferences`.
- **A macOS app** → `homebrew.{casks,masApps,brews}` in `darwin/base.nix`
  (universal) or `darwin/default/homebrew.nix` (personal). There is no private
  darwin path yet, so sensitive apps have no declarative home — add them to a
  public module or install them imperatively (the cleanup policy removes any
  undeclared brew package on the next apply).
- **Claude Code config** → `profiles/default/claude/` — files under
  `agents/ skills/ commands/ rules/ guides/` auto-map to `~/.claude/`;
  `settings.json` is generated from the attrset in `claude.nix`.

## Conventions

- **Escape hatch for nix-unfriendly packages** → `homebrew.brews` (e.g.
  `watchman`, `argo`). Comment why.
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
- **`nix.enable = false`** in `darwin/base.nix` — Determinate's installer owns
  the daemon; nix-darwin must not fight it.
- **Private flakes** (`custom_environments/<env>/nix/`) consume this flake as
  the `public` input and override scalars with `lib.mkForce`. Note any
  private-side update in `README.md` when migrating something here.

## Pins

`flake.lock` pins nixpkgs / home-manager / nix-darwin to the `26.05` line;
`home.stateVersion` is `25.11` and nix-darwin's `system.stateVersion` is `5`.
Don't bump these casually — `./apply` after a bump rebuilds everything.
