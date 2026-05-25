# Nix Git Slice (Identity + Config Body) Design

**Date:** 2026-05-24
**Status:** Draft — pending user approval
**Branch:** `nix-git` (stacks on `nix-profiles` / PR #63, which stacks on `nix-cross-platform` / PR #62)

## Goal

Replace the framework's `plugins/git` plugin and the rsync-managed
`environments/all/home/.gitconfig` with home-manager's `programs.git`,
layered through the public Nix profile system: shared body in
`nix/profiles/all`, per-profile identity in profile modules, work-specific
overrides in the user's private flake. Commit signing (the `commit_signing`
plugin, GPG agent, cross-platform pinentry) is deferred to a follow-up slice;
this slice leaves it untouched and verifies it still works alongside the new
home-manager-owned git config.

This builds on the prior slices: first slice established the `nix` plugin,
flake, and `host.nix`; cross-platform slice made the flake multi-system and
Linux-capable; profiles slice introduced `homeModules` +
`homeConfigurations."<profile>@<system>"` with the always-included `all`
layer and private-flake composition via `--override-input`.

## Decisions (locked)

1. **Scope: identity + config body. Commit signing deferred.** This slice
   migrates `plugins/git` (`user.name` / `user.email`) and the rsync'd
   `environments/all/home/.gitconfig` body. `plugins/commit_signing` keeps
   running and continues to write `signingkey` + `commit.gpgsign` via
   `git config --global`; those writes coexist with home-manager via the
   activation script described in Section 6.
2. **Layering.** Shared gitconfig body + aliases live in
   `nix/profiles/all/default.nix` (home-manager's `programs.git` block;
   always-included via `mkHome`). Identity (`userName`, `userEmail`) lives in
   the per-profile module (`nix/profiles/default/default.nix` for personal;
   the user's private flake for work). The work-specific extra settings (any
   per-env host config, enterprise overrides) move into the private flake's
   `extraConfig` and are never named in this public repo.
3. **Ownership of `~/.gitconfig`.** home-manager writes
   `~/.config/git/config` (XDG location, `programs.git`'s default). The
   pre-existing `~/.gitconfig` on disk would otherwise shadow home-manager's
   values (git reads it after the XDG file, last-wins), so a one-time
   activation script moves it to `~/.gitconfig.legacy-backup`. Idempotent and
   Linux-safe.
4. **No public-repo leakage of work-specific values.** Per-env host names,
   work email addresses, enterprise hub settings, etc. live only in the
   user's private `custom_environments/<env>/` repo. The public spec, plan,
   README, and code reference such overrides as abstract patterns.
5. **`~/.dotfilesrc`'s `DOTFILES_GIT_CONFIG_USER_*` entries become orphans.**
   No functional impact (the `git` plugin that read them is removed). Cleanup
   of `~/.dotfilesrc` is a separate concern (it's user-local state, not
   committed).

## Architecture

```text
DELETIONS (committed in this slice):
  plugins/git/git                         # responsibility moves to programs.git
  environments/all/home/.gitconfig        # body moves to nix/profiles/all

ADDITIONS / MODIFICATIONS:
  nix/profiles/all/default.nix            # gains programs.git block + activation script
  nix/profiles/default/default.nix        # gains programs.git.userName / userEmail
  nix/README.md                           # gains "Migration: private custom envs" section

UNTOUCHED IN THIS SLICE (deferred to follow-up):
  plugins/commit_signing/                 # still runs; writes signingkey via git config --global
  programs.gpg / services.gpg-agent       # follow-up slice

PRIVATE-REPO CLEANUP (documented, not committed here):
  custom_environments/<env>/home/.gitconfig   # user deletes from their private repo
  custom_environments/<env>/nix/…             # user adds programs.git overrides to private flake
```

## Layering — where each setting lives

Comparing `environments/all/home/.gitconfig` to `custom_environments/work/home/.gitconfig`,
the overlap is large; meaningful differences are limited to identity, signing
(deferred), and a small number of env-specific extras (e.g., a work host
setting that stays in the private flake).

| Setting | Personal source | Work source | Lands in |
| --- | --- | --- | --- |
| `[alias]` (autosquash, fixup, pfl) | yes | yes | `profiles/all` |
| `[branch]` sort, main.rebase, master.rebase | yes | yes | `profiles/all` |
| `[color]` ui / branch / diff / status | yes | yes | `profiles/all` |
| `[core]` excludesfile, attributesfile, whitespace, trustctime, precomposeunicode | yes | yes | `profiles/all` |
| `[diff]` indentHeuristic, renames | yes | yes | `profiles/all` |
| `[diff]` algorithm = histogram | yes | — | `profiles/all` (superset; harmless on work) |
| `[init]` defaultBranch | yes | yes | `profiles/all` |
| `[merge]` log, tool = opendiff | yes | yes | `profiles/all` |
| `[merge]` conflictstyle = zdiff3, keepbackup = false | yes | — | `profiles/all` (superset) |
| `[push]` default = upstream | yes | yes | `profiles/all` |
| `[rebase]` autoStash, updateRefs | yes | yes | `profiles/all` |
| `[rerere]` autoupdate, enabled | yes | yes | `profiles/all` |
| `[include] path = .gitconfig.custom` | yes | yes | `profiles/all` (via `programs.git.includes`) |
| `user.name` / `user.email` | personal | work | per-profile (`default`, private) |
| Any env-specific extras (enterprise host etc.) | — | work | private flake (`extraConfig`) |

## `programs.git` translation — `nix/profiles/all/default.nix`

The block added to the existing `all` module (alongside the current `bat`
config). All settings come straight from `environments/all/home/.gitconfig`;
the few "newer in personal that work doesn't have" superset items are kept
because they're harmless additions on a work machine.

```nix
{ lib, ... }: {
  # …existing programs.bat block stays…

  programs.git = {
    enable = true;

    aliases = {
      autosquash = "!GIT_SEQUENCE_EDITOR=true git rebase -i --autosquash";
      fixup      = "commit --fixup";
      pfl        = "push --force-with-lease";
    };

    # Preserves `[include] path = .gitconfig.custom` from both source
    # .gitconfigs so user-managed local overrides keep working.
    includes = [ { path = "~/.gitconfig.custom"; } ];

    extraConfig = {
      branch = {
        sort = "-committerdate";
        main.rebase = true;
        master.rebase = true;
      };

      color = {
        ui = "auto";
        branch = { current = "yellow reverse"; local = "yellow"; remote = "green"; };
        diff   = { algorithm = "histogram"; frag = "magenta bold"; meta = "yellow bold"; new = "green bold"; old = "red bold"; };
        status = { added = "yellow"; changed = "green"; untracked = "cyan"; };
      };

      core = {
        attributesfile    = "~/.gitattributes";
        excludesfile      = "~/.gitignore";
        precomposeunicode = false;
        trustctime        = false;
        whitespace        = "space-before-tab,indent-with-non-tab,trailing-space";
      };

      diff = {
        indentHeuristic = true;
        renames         = "copies";
      };

      init.defaultBranch = "main";

      merge = {
        conflictstyle = "zdiff3";
        keepbackup    = false;
        log           = true;
        tool          = "opendiff";
      };

      push.default = "upstream";

      rebase = {
        autoStash  = true;
        updateRefs = true;
      };

      rerere = {
        autoupdate = true;
        enabled    = 1;
      };
    };
  };
}
```

home-manager's generator handles the nested attrsets correctly: `branch.main`
becomes `[branch "main"]`, `color.diff` becomes `[color "diff"]`, etc. No
raw INI strings needed.

## Identity — `nix/profiles/default/default.nix`

```nix
{ pkgs, ... }: {
  home.packages = [ pkgs.ripgrep ];

  programs.git = {
    userName  = "ianwremmel";
    userEmail = "1182361+ianwremmel@users.noreply.github.com";
  };
}
```

The private work flake adds its own identity with `lib.mkForce` (see the
README migration guide). The `agent` public profile stays lean — no
identity, since agent boxes typically don't author commits.

## Legacy `~/.gitconfig` cleanup (activation script in `profiles/all`)

After this slice, home-manager owns `~/.config/git/config`. The pre-existing
`~/.gitconfig` on disk still has the rsync'd body plus the old `git`
plugin's `user.name`/`user.email`, and git reads it *after* the XDG file —
so it would shadow home-manager's values. Fix: one-time backup via a
home-manager activation script.

```nix
home.activation.migrateLegacyGitConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  # One-time migration: this slice moves all git config to home-manager
  # (~/.config/git/config + the XDG location). The pre-migration ~/.gitconfig
  # would shadow our values, so move it aside if it's a real file (not a
  # symlink home-manager already manages).
  if [ -f "$HOME/.gitconfig" ] && [ ! -L "$HOME/.gitconfig" ]; then
    $DRY_RUN_CMD mv "$HOME/.gitconfig" "$HOME/.gitconfig.legacy-backup"
    echo "Moved legacy ~/.gitconfig → ~/.gitconfig.legacy-backup (one-time migration)"
  fi
'';
```

Properties:

- **One-time effective.** After the first run, `~/.gitconfig` either doesn't
  exist (Linux, fresh installs) or is recreated solely by `commit_signing`'s
  `git config --global` writes (signing fields only, no overlap with
  home-manager's content). The `[ -f … ] && [ ! -L … ]` guard makes the
  script a no-op on every subsequent run.
- **Non-destructive.** The original content is preserved at
  `~/.gitconfig.legacy-backup`. The user can `diff` it against the new
  behavior anytime and `rm` it when satisfied.
- **Linux-safe.** Linux machines never had `~/.gitconfig` written (the
  rsync `homedir` plugin doesn't run there), so the guard makes it a no-op.
- **Idempotent under failed runs.** If activation fails halfway, the next
  run sees the legacy file already moved and the script no-ops.

## Coexistence with `plugins/commit_signing` (until the follow-up slice)

`commit_signing` keeps running on macOS as part of `./apply`. On each apply,
*after* this slice's activation script removes `~/.gitconfig`,
`commit_signing` then runs:

```bash
git config --global signingkey <fingerprint>
git config --global commit.gpgsign true
```

`git config --global` writes to `~/.gitconfig`, recreating it with **only
those two fields**. The result:

- `~/.gitconfig` contains *only* `signingkey` and `commit.gpgsign`.
- `~/.config/git/config` contains everything home-manager owns (identity,
  aliases, body).
- Git reads both; no overlap means no conflict; signing keeps working
  unchanged.

The follow-up slice will fold `signingkey` + `commit.gpgsign` into
`programs.git.signing` and bring up `programs.gpg` + `services.gpg-agent`
with cross-platform pinentry, retiring the `commit_signing` plugin entirely.

## README migration guide (for private custom environments)

Added to `nix/README.md` after the existing Profiles section. Pattern-based,
never naming a specific env's value:

```markdown
### Migrating a private custom environment after this slice

When a slice migrates a plugin or rsync-managed file into home-manager,
machines using a private `custom_environments/<env>/` repo need a one-time
update: the old rsync-managed file gets superseded by the home-manager-managed
XDG file, and any per-env overrides that used to live in the rsync'd file
move into the private flake.

For this slice (`git` plugin + the rsync'd `.gitconfig` body):

1. **Update your private flake** to add `programs.git`:

       { lib, pkgs, ... }: {
         programs.git.userName  = lib.mkForce "<your name for this env>";
         programs.git.userEmail = lib.mkForce "<your email for this env>";

         # Any env-specific git settings that used to live in your private
         # .gitconfig — enterprise hosts, additional aliases, etc. Use
         # `extraConfig` for raw settings and `lib.mkForce` only where
         # overriding a value the public layer set.
         programs.git.extraConfig = {
           # …your env's settings here…
         };
       }

2. **Delete the rsync'd .gitconfig source from your private repo:**
   `git rm custom_environments/<env>/home/.gitconfig` in the private repo
   and commit. home-manager will own `~/.config/git/config` on that machine
   after the next `./apply`, so the rsync source is no longer needed.

3. **First `./apply` after this slice** runs the
   `migrateLegacyGitConfig` activation script, which moves any pre-existing
   `~/.gitconfig` aside to `~/.gitconfig.legacy-backup` once. No action
   needed; mentioned so you know what the file is if you see it. You can
   `rm ~/.gitconfig.legacy-backup` whenever you're satisfied with the
   migration.

The same shape applies to future slices that migrate a plugin or rsync
source: add the new options to your private flake, delete the now-orphaned
rsync source from your private repo, and trust the activation cleanup.
```

## Testing

- **Pre-flight (record current state, macOS):** capture
  `git config --get user.name`, `user.email`, `commit.gpgsign`, `signingkey`,
  and `cat ~/.gitconfig | wc -l`. These become regression checks below.
- **Activation runs once, then no-ops.** Run the plugin (direct invocation,
  sandbox disabled, `DOTFILES_ENVIRONMENT=default`). Confirm: the activation
  output mentions the legacy-backup move; `~/.gitconfig.legacy-backup` exists
  and matches the pre-flight content. Re-run the plugin; confirm no second
  backup is made and the script's `[ -f … ]` guard short-circuits cleanly.
- **New git config is in effect.** `git config --show-origin user.email`
  resolves into `~/.config/git/config`; `git config --get alias.fixup`
  returns `commit --fixup`; `git config --get color.diff.algorithm` returns
  `histogram`; `git config --get init.defaultBranch` returns `main`;
  `git config --get include.path` returns `~/.gitconfig.custom`.
- **`commit_signing` still works.** Run `./apply -B` (full framework on
  macOS, brew bundle skipped for speed). After `commit_signing` runs, confirm
  `cat ~/.gitconfig` shows *only* signing fields; `git config --show-origin
  commit.gpgsign` resolves into `~/.gitconfig`; an actual GPG-signed test
  commit succeeds (`git -c commit.gpgsign=true commit --allow-empty -m
  test-sign`).
- **Throwaway private-profile override.** Same scaffold as the profiles
  slice: a throwaway private flake whose module sets
  `programs.git.userName = lib.mkForce "Throwaway User"`. Activate with
  `DOTFILES_ENVIRONMENT=throwaway` and confirm
  `git config --get user.name` returns `Throwaway User`. Tear down, return to
  `default`, confirm identity returns to the personal value.
- **Linux container.** Pre-seed `~/.dotfilesrc` with
  `DOTFILES_ENVIRONMENT=agent` in a fresh container. Run `./apply`. Confirm:
  no `~/.gitconfig` exists; `git config --get user.email` returns nothing
  (the `agent` profile doesn't set identity); `git config --get
  color.diff.algorithm` returns `histogram` (from `all`).
- **macOS regression.** The `homedir` plugin no longer rsyncs `.gitconfig`
  (the source file is gone). Other rsync'd dotfiles
  (`.zshrc`, `.vimrc`, etc.) continue to be plain files; `programs.git`
  ownership is confined to git config files.

## Scope / Non-goals

**In scope:** delete `plugins/git/` and `environments/all/home/.gitconfig`;
add `programs.git` block to `nix/profiles/all/default.nix` (full body +
aliases + includes + `migrateLegacyGitConfig` activation script); add
identity to `nix/profiles/default/default.nix`; add a "Migration: private
custom envs" section to `nix/README.md`; verified on macOS + a Linux
container; throwaway-private-override test.

**Out of scope:** `plugins/commit_signing/` migration (separate slice);
`programs.gpg` / `services.gpg-agent` setup; cross-platform pinentry; any
work-specific value (host, key, alias) committed to the public repo; cleanup
of `DOTFILES_GIT_CONFIG_USER_*` entries from `~/.dotfilesrc`; deleting any
file in the user's private `custom_environments/<env>/` repo (documented for
the user to do).

## Future phases (relation to this slice)

- **Next slice (immediate follow-up):** commit signing — `programs.git.signing`,
  `programs.gpg`, `services.gpg-agent`, cross-platform pinentry
  (pinentry_mac on macOS, pinentry-tty on Linux), delete
  `plugins/commit_signing/`. Cleans up the residual `~/.gitconfig` that
  `commit_signing` currently maintains.
- **Later:** other plugin migrations (`shells`, `vim`, `node`, etc.) follow
  the same pattern: shared body in `all`, per-profile bits in profile
  modules, private overrides documented for the user's private flake.
