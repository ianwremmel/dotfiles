# Nix Commit-Signing Slice Design

**Date:** 2026-05-24
**Status:** Implemented
**Branch:** `nix-commit-signing` (stacks on `nix-git` / PR #64 → `nix-profiles` / PR #63 → `nix-cross-platform` / PR #62)

## Goal

Migrate the framework's `plugins/commit_signing` (GPG setup +
`signingkey` / `commit.gpgsign` via `git config --global` +
`pinentry-mac`-via-brew) into home-manager: `programs.gpg`,
`services.gpg-agent` with per-OS pinentry, plus
`programs.git.settings.user.signingkey` and
`programs.git.settings.commit.gpgsign` in the personal profile. Cross-platform
(`pinentry_mac` on macOS, `pinentry-tty` on Linux), with a one-time activation
that moves the old plugin-written `~/.gnupg/gpg.conf` and
`~/.gnupg/gpg-agent.conf` aside so home-manager can take them over.

This is Slice 2 of the git-ecosystem migration started in Slice 1
(`docs/superpowers/specs/2026-05-24-nix-git-design.md`). Together with Slice 1
it retires the `git` and `commit_signing` plugins entirely; home-manager owns
the full git + GPG-agent config end-to-end.

## Decisions (locked)

1. **Scope: commit signing.** Migrate `plugins/commit_signing` (GPG config
   files + git signing settings + per-OS pinentry). Slice 1 already migrated
   identity and the `.gitconfig` body.
2. **Agent-config strategy: `services.gpg-agent` with Darwin fallback.** Use
   home-manager's typed `services.gpg-agent` module. If macOS doesn't emit a
   usable `~/.gnupg/gpg-agent.conf` (Darwin support is patchy in the module),
   fall back to a plain `home.file.".gnupg/gpg-agent.conf".text` block in the
   same slice. Decided empirically during implementation.
3. **Per-OS pinentry.** `pkgs.pinentry_mac` on macOS, `pkgs.pinentry-tty` on
   Linux (per Slice 1's brainstorm decision). Branch on
   `pkgs.stdenv.isDarwin`.
4. **Signing-key placement: per-profile.** The personal key id lives in
   `nix/profiles/default/default.nix` (alongside identity). The `agent`
   profile stays lean — no signing. Private work flake overrides with
   `lib.mkForce "<work key id>"`; no work-specific value lands in the public
   repo.
5. **`agent` profile doesn't sign.** Agent boxes typically lack a GPG
   keyring; enabling `commit.gpgsign` without a usable key would just cause
   commit failures. `programs.gpg` + `services.gpg-agent` *are* enabled in
   `all` (the agent is available for ad-hoc use) — but `commit.gpgsign`
   stays off in `agent` because `default` is what turns it on.
6. **Drop Slice 1's empty-seed `~/.gitconfig` touch.** It existed only so
   `commit_signing`'s `git config --global` writes had a writable target.
   With `commit_signing` gone, nothing writes to `~/.gitconfig` and the
   empty seed has no consumer. Keep Slice 1's marker-gated legacy backup —
   still useful for fresh-machine first-apply scenarios.
7. **One-time `~/.gnupg/*.conf` migration.** Pre-existing real
   `~/.gnupg/gpg.conf` and `~/.gnupg/gpg-agent.conf` (written by the old
   plugin) would block home-manager's symlink activation. A new
   `migrateLegacyGnupgConfig` activation script moves them aside once to
   `.legacy-backup` siblings, gated by a single `~/.gnupg.hm-migrated`
   marker (sibling to `~/.gnupg/`, not inside the GPG-owned 0700 dir).
8. **Don't touch the user's keyring.** `~/.gnupg/pubring.kbx`,
   `private-keys-v1.d/`, `trustdb.gpg`, etc. are user data and stay exactly
   as they are. Nix only manages the two config files.
9. **No public-repo leakage of work-specific values.** Work signing key,
   work email, enterprise host, etc. live only in the user's private repo.
   Spec, plan, README, code all reference patterns abstractly.

## Architecture

```text
DELETIONS (committed in this slice):
  plugins/commit_signing/                  # whole dir (bash plugin + Brewfile)

REMOVED FROM SLICE 1's ACTIVATION SCRIPT:
  the always-on `touch "$HOME/.gitconfig"` clause                      # no remaining consumer

ADDITIONS / MODIFICATIONS in nix/profiles/all/default.nix:
  programs.gpg.enable + .settings (auto-key-retrieve, no-emit-version)
  services.gpg-agent.enable + .pinentry.package (per-OS) + cache TTLs
  home.activation.migrateLegacyGnupgConfig (one-time, marker-gated)

ADDITIONS in nix/profiles/default/default.nix:
  programs.git.settings.user.signingkey = "<personal key id>"
  programs.git.settings.commit.gpgsign  = true

UNTOUCHED IN THIS SLICE:
  nix/profiles/agent/default.nix  # stays lean; agent doesn't sign

UNTOUCHED BY DESIGN (never managed by Nix):
  ~/.gnupg/pubring.kbx, private-keys-v1.d/, trustdb.gpg, etc.  # user keyring

PRIVATE-REPO CLEANUP (documented in README, not committed here):
  work private flake gains `programs.git.settings.user.signingkey = lib.mkForce "<work key id>"`
```

## `programs.gpg` + `services.gpg-agent` in `profiles/all`

Added to `nix/profiles/all/default.nix` alongside the existing `programs.bat`
and `programs.git` blocks. The module signature gains `pkgs` (was
`{ lib, ... }`) for the pinentry branch.

```nix
{ lib, pkgs, ... }: {
  # …existing programs.bat and programs.git blocks stay as-is…

  # ~/.gnupg/gpg.conf — preserves the two settings the old commit_signing
  # plugin and the user's existing manual config had.
  programs.gpg = {
    enable = true;  # also installs pkgs.gnupg into the profile.
    settings = {
      auto-key-retrieve = true;
      no-emit-version   = true;
    };
  };

  # ~/.gnupg/gpg-agent.conf — pinentry program is per-OS; cache TTLs match
  # the old plugin's previous behavior (10-minute default, 2-hour max).
  services.gpg-agent = {
    enable = true;
    pinentry.package =
      if pkgs.stdenv.isDarwin then pkgs.pinentry_mac
      else                         pkgs.pinentry-tty;
    defaultCacheTtl = 600;
    maxCacheTtl     = 7200;
  };
}
```

**Darwin validation risk.** `services.gpg-agent` is well-tested on Linux
(systemd user service + config file). On macOS the module writes the config
file but doesn't (and can't) manage launchd; some attributes may be gated on
non-Darwin platforms. Implementation verifies that the activated
`~/.gnupg/gpg-agent.conf` contains the expected `pinentry-program`,
`default-cache-ttl`, and `max-cache-ttl` lines. If it doesn't, the fallback
inside the same slice is:

```nix
# Fallback (only if services.gpg-agent doesn't work on Darwin):
home.packages = [
  (if pkgs.stdenv.isDarwin then pkgs.pinentry_mac else pkgs.pinentry-tty)
];
home.file.".gnupg/gpg-agent.conf".text = ''
  pinentry-program ${if pkgs.stdenv.isDarwin then "${pkgs.pinentry_mac}/bin/pinentry-mac" else "${pkgs.pinentry-tty}/bin/pinentry-tty"}
  default-cache-ttl 600
  max-cache-ttl 7200
'';
```

## Identity + signing in `profiles/default`

Slot the signing key alongside the existing identity block from Slice 1:

```nix
# nix/profiles/default/default.nix
{ pkgs, ... }: {
  home.packages = [ pkgs.ripgrep ];

  # `settings.user.{name,email,signingkey}` is the current home-manager
  # option path (replaces the deprecated `programs.git.{userName,userEmail}`).
  programs.git.settings = {
    user = {
      name       = "ianwremmel";
      email      = "1182361+ianwremmel@users.noreply.github.com";
      signingkey = "C9DA1EE9CCF21B28";  # personal GPG key — public fingerprint
    };
    commit.gpgsign = true;
  };
}
```

**Layering implications:**

- `agent` profile stays the empty `{ ... }: { }` it is today — no identity,
  no signing.
- Private work flake adds its own `programs.git.settings.user.signingkey =
  lib.mkForce "<work key id>"`; if the private flake imports
  `public.homeModules.default`, `commit.gpgsign = true` is already inherited
  from `default`; otherwise the private flake sets it explicitly.
- The public `default` profile is the only place `commit.gpgsign = true`
  lives in the public flake — `agent` doesn't inherit from `default`, so it
  stays off there.

**Key id is public.** GPG fingerprints are not secrets; they appear in
every signed commit and in any public-key export. Committing
`C9DA1EE9CCF21B28` to the public repo is fine.

## Activation script: drop slice-1 empty-seed, add `~/.gnupg/*.conf` migration

Slice 1's `migrateLegacyGitConfig` had two clauses; this slice removes the
second (always-on `touch ~/.gitconfig`) and adds a new
`migrateLegacyGnupgConfig` script for the two GPG config files:

```nix
home.activation.migrateLegacyGitConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  # One-time migration from Slice 1: move pre-migration ~/.gitconfig aside
  # so it stops shadowing the home-manager-managed ~/.config/git/config.
  if [ -f "$HOME/.gitconfig" ] \
       && [ ! -L "$HOME/.gitconfig" ] \
       && [ ! -e "$HOME/.gitconfig.hm-migrated" ]; then
    run mv "$HOME/.gitconfig" "$HOME/.gitconfig.legacy-backup"
    run touch "$HOME/.gitconfig.hm-migrated"
    echo "Moved legacy ~/.gitconfig → ~/.gitconfig.legacy-backup (one-time migration)"
  fi
  # NOTE: Slice 1's always-on `touch ~/.gitconfig` clause is REMOVED in this
  # slice — commit_signing (its only consumer) is gone, so nothing writes
  # to ~/.gitconfig anymore.
'';

home.activation.migrateLegacyGnupgConfig = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
  # One-time migration: home-manager wants to symlink ~/.gnupg/gpg.conf and
  # ~/.gnupg/gpg-agent.conf, but it refuses to overwrite real files. The
  # old commit_signing plugin wrote those as real files; move them aside
  # once so home-manager can take over. Marker lives outside ~/.gnupg/
  # because that dir is GPG-owned mode 0700 and littering it with home-
  # manager bookkeeping feels off.
  if [ ! -e "$HOME/.gnupg.hm-migrated" ]; then
    for f in gpg.conf gpg-agent.conf; do
      if [ -f "$HOME/.gnupg/$f" ] && [ ! -L "$HOME/.gnupg/$f" ]; then
        run mv -n "$HOME/.gnupg/$f" "$HOME/.gnupg/$f.legacy-backup"
        echo "Moved legacy ~/.gnupg/$f → ~/.gnupg/$f.legacy-backup (one-time migration)"
      fi
    done
    run touch "$HOME/.gnupg.hm-migrated"
  fi
'';
```

**Properties:**

- **One-time effective.** `~/.gnupg.hm-migrated` marker short-circuits the
  GPG migration after the first run.
- **Non-destructive.** Both files preserved as `.legacy-backup` siblings
  inside `~/.gnupg/`. User can `diff` and `rm` whenever. `mv -n` prevents
  silent backup-overwrite if a prior activation crashed between the move
  and the marker touch.
- **Linux-safe.** The old plugin was macOS-only (`pinentry-mac`-via-brew);
  Linux machines never had real `~/.gnupg/*.conf` from it. Inner per-file
  `[ -f … ] && [ ! -L … ]` guards make the migration a no-op there. The
  marker still gets touched, so the script becomes a fast no-op on
  subsequent Linux runs as well.
- **Idempotent under failed runs.** Marker is touched *after* the move
  loop, so a half-failed run re-tries cleanly next time.
- **Independent of the Git migration.** Separate activation block with its
  own marker — failures in one don't affect the other.
- **DAG edge differs from Slice 1's migration.** `migrateLegacyGitConfig`
  uses `entryAfter [ "writeBoundary" ]`; this one uses
  `entryBefore [ "checkLinkTargets" ]`. home-manager's `checkLinkTargets`
  phase runs before `writeBoundary` and aborts if a real file occupies a
  target path. `programs.gpg` and `services.gpg-agent` place managed
  symlinks at `~/.gnupg/{gpg.conf,gpg-agent.conf}`, so the real files
  must move aside before `checkLinkTargets`. Slice 1 didn't face this
  because home-manager symlinks at `~/.config/git/config`, not at
  `~/.gitconfig`.

## Testing

- **Pre-flight (record current state, macOS):** capture
  `git config --get commit.gpgsign`, `git config --get user.signingkey`,
  `cat ~/.gnupg/gpg-agent.conf`, `cat ~/.gnupg/gpg.conf`, and the timestamps
  / sizes of those two files. These become regression checks below.
- **Activation migration.** Run the plugin direct (sandbox disabled,
  `DOTFILES_ENVIRONMENT=default`). Confirm:
  - `migrateLegacyGnupgConfig` prints both "Moved legacy …" lines once.
  - `~/.gnupg/gpg.conf.legacy-backup` and `~/.gnupg/gpg-agent.conf.legacy-backup`
    exist with the pre-flight content (byte-equal).
  - `~/.gnupg/gpg.conf` and `~/.gnupg/gpg-agent.conf` are now symlinks into
    `/nix/store/…-home-manager-files/.gnupg/…`.
  - `~/.gnupg.hm-migrated` marker exists.
- **Verify config content.** `cat ~/.gnupg/gpg.conf` shows
  `auto-key-retrieve` + `no-emit-version`. `cat ~/.gnupg/gpg-agent.conf`
  shows `pinentry-program /nix/store/…-pinentry_mac-*/bin/pinentry-mac`,
  `default-cache-ttl 600`, `max-cache-ttl 7200`.
- **Nix-installed `gnupg` on PATH.** `readlink "$(which gpg)"` resolves
  into the Nix store (the `programs.gpg`-installed `gnupg`, not brew's).
- **Signing config in effect.** `git config --show-origin user.signingkey`
  resolves into `~/.config/git/config`, value `C9DA1EE9CCF21B28`.
  `git config --show-origin commit.gpgsign` likewise → `true`.
  `~/.gitconfig` does not exist anymore (Slice 1's empty-seed touch is
  gone; `commit_signing` is gone; nothing creates it).
- **GPG-signed test commit.** `git init` in a scratch dir, `git commit
  --allow-empty -m test-sign`, `git log -1 --format='%G? %GS'`. `G` or `U`
  signature status acceptable; `N` (no signature) is a failure.
- **Activation idempotency.** Re-run the plugin. `migrateLegacyGnupgConfig`
  short-circuits via the marker — no second "Moved legacy …" lines, no
  changes to the `.legacy-backup` files' mtimes.
- **Darwin fallback verification.** Inspect the `~/.gnupg/gpg-agent.conf`
  symlink's target. If `services.gpg-agent` on Darwin produced a usable
  file, the slice is done as-designed. If the file is missing the
  `pinentry-program` line or contains nothing usable, swap to the
  `home.file`-based fallback (see Section 2) in the same slice; re-test
  all of the above.
- **Throwaway private override.** Same scaffold as prior slices. Throwaway
  module sets `programs.git.settings.user.signingkey = lib.mkForce
  "<fake-key-id>"` and `programs.git.settings.commit.gpgsign = lib.mkForce
  true`. Activate; confirm `git config --get user.signingkey` returns the
  throwaway value. Tear down; confirm reversion to the personal key.
- **Linux container.** Pre-seed `~/.dotfilesrc` with
  `DOTFILES_ENVIRONMENT=agent` in an `aarch64-linux` container. `./apply`.
  Confirm: `~/.gnupg/gpg.conf` and `~/.gnupg/gpg-agent.conf` exist as
  home-manager symlinks; `gpg-agent.conf` references
  `pkgs.pinentry-tty` (not `pinentry_mac`); `git config --get
  commit.gpgsign` returns nothing (agent doesn't sign — by design);
  `gpg --version` resolves to the Nix-installed `gnupg`.
- **macOS regression: brew packages can stay or be cleaned up.** The
  deleted `plugins/commit_signing/Brewfile` no longer aggregates `gnupg` +
  `pinentry-mac` into the master Brewfile. Existing brew installs of those
  become orphans (still on disk, just unused — Nix's versions take PATH
  precedence). Optional cleanup (`brew uninstall gnupg pinentry-mac`)
  documented in the README but not required.

## README updates

Three additions/changes to `nix/README.md`:

1. **Extend the existing "Migrating a private custom environment after this
   slice" section** with a "For the commit-signing slice" block alongside
   the Slice 1 "For the git slice" block. Pattern-based, no work values:

   ```markdown
   For the commit-signing slice (`commit_signing` plugin retired;
   `programs.gpg`, `services.gpg-agent`, and
   `programs.git.settings.{user.signingkey,commit.gpgsign}` take over):

   1. **Update your private flake** to override the signing key
      (and explicitly set `commit.gpgsign` if your private flake
      doesn't import `public.homeModules.default`):

          { lib, pkgs, ... }: {
            programs.git.settings = {
              user.signingkey = lib.mkForce "<your env's key id>";
              # commit.gpgsign already inherited from `default` if your
              # private flake imports `public.homeModules.default`;
              # otherwise:
              # commit.gpgsign = lib.mkForce true;
            };
          }

   2. **Nothing to delete from your private repo this time.** The old
      `commit_signing` plugin lived only in the public repo (no rsync
      source under `custom_environments/<env>/home/`).

   3. **First `./apply` after this slice** runs the
      `migrateLegacyGnupgConfig` activation script, which moves any
      pre-existing real `~/.gnupg/gpg.conf` and `~/.gnupg/gpg-agent.conf`
      aside to `.legacy-backup` siblings once. No action needed; `rm`
      them when satisfied. Your actual keyring (`pubring.kbx`,
      `private-keys-v1.d/`, `trustdb.gpg`, etc.) is never touched.
   ```

2. **Refresh the Background paragraph** so the "So far this manages …" list
   includes commit signing (`programs.git.settings.user.signingkey` +
   `commit.gpgsign` + GPG agent with per-OS
   pinentry).

3. **Refresh the `all`-layer description** in `### Public profiles and
   layers` — extend "(currently `bat` and the shared git config …)" to
   "(currently `bat`, the shared git config, and GPG/agent setup with
   per-OS pinentry — `pinentry-mac` on macOS, `pinentry-tty` on Linux)".

## Scope / Non-goals

**In scope:** delete `plugins/commit_signing/`; add `programs.gpg`,
`services.gpg-agent` (with Darwin fallback), and signing settings in
`profiles/default`; remove Slice 1's empty-seed `~/.gitconfig` touch; add
`migrateLegacyGnupgConfig` activation script; verified on macOS + an
aarch64-linux container; throwaway-private signing-key override;
README updates.

**Out of scope:** managing the user's actual GPG keyring; per-machine
selection of the pinentry program beyond the macOS/Linux split (e.g., GUI
pinentry on Linux desktops); `nix-darwin`'s system-level GPG agent
integration; brew-orphan cleanup of pre-Nix `gnupg`/`pinentry-mac` (left to
the user); cleanup of `DOTFILES_GIT_CONFIG_*` orphans in `~/.dotfilesrc`
(Slice 1 non-goal carried forward).

## Future phases

This slice completes the git-ecosystem migration. Future slices migrate
other plugins (`shells`, `vim`, `node`, etc.) using the same patterns
established here: shared config in `all`, per-profile differences in
profile modules, private overrides via `lib.mkForce` in the user's private
flake, one-time activation scripts for any rsync-managed-file/`git config
--global`-style state that home-manager needs to take over.
