# Nix Commit-Signing Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate `plugins/commit_signing/` (GPG config files + `signingkey`/`commit.gpgsign` via `git config --global` + `pinentry-mac`-via-brew) into home-manager: `programs.gpg`, `services.gpg-agent` (per-OS pinentry), and `programs.git.settings.user.signingkey` + `programs.git.settings.commit.gpgsign` in the personal profile, with a one-time activation that retires the legacy `~/.gnupg/*.conf` files.

**Architecture:** `nix/profiles/all/default.nix` gains `programs.gpg` (settings: `auto-key-retrieve`, `no-emit-version`), `services.gpg-agent` (pinentry branches on `pkgs.stdenv.isDarwin`: `pinentry_mac` on macOS, `pinentry-tty` on Linux; cache TTLs 600/7200), and a `home.activation.migrateLegacyGnupgConfig` script that backs up any pre-existing real `~/.gnupg/gpg.conf` and `~/.gnupg/gpg-agent.conf` to `.legacy-backup` siblings exactly once (marker `~/.gnupg.hm-migrated` sibling to the dir). `nix/profiles/default/default.nix` adds `user.signingkey` + `commit.gpgsign = true` alongside the existing identity. Slice 1's always-on `touch ~/.gitconfig` clause is removed (its only consumer was `commit_signing`). `plugins/commit_signing/` (the bash plugin and its Brewfile) is deleted in the same commit so the repo never sits in a partially-migrated state. If `services.gpg-agent` on Darwin doesn't emit a usable `~/.gnupg/gpg-agent.conf`, an in-task fallback swaps to `home.file.".gnupg/gpg-agent.conf".text` (plus `home.packages` for the pinentry binary) before committing.

**Tech Stack:** Bash 5, Nix flakes, home-manager (`programs.gpg`, `services.gpg-agent`, `programs.git.settings`, `lib.hm.dag.entryAfter`), GPG/`gpg-agent`, `pinentry_mac` (macOS) / `pinentry-tty` (Linux).

---

## Notes for the executor

- **Reference spec:** `docs/superpowers/specs/2026-05-24-nix-commit-signing-design.md`. Re-read it if anything below seems ambiguous.
- **No automated test framework.** "Tests" are verification commands with expected output. Observe failing state → implement → observe passing state → commit.
- **Branch:** work is on `nix-commit-signing`. Branch stacks on `nix-git` (PR #64), which stacks on `nix-profiles` (PR #63) → `nix-cross-platform` (PR #62). **Do NOT merge anything** unless the user explicitly tells you to merge a specific PR. (User feedback after PR #61: "in the future, don't merge without my very explicit go ahead.")
- **Stacking machinery (assumed working from prior slices):** `homeModules.{base,all,default,agent}`, `lib.mkHome`, `homeConfigurations."<profile>@<system>"`, profile-module layering, the `--override-input public path:…` private-flake idiom, `home.activation.*` style migrations, `nix/host.nix` (untracked) with `{ username; profile; }`.
- **Sandbox disable required for:** `nix` (talks to the daemon), `gpg`-driven `git commit`, `mv`/`touch`/`cat` against `~/.gnupg/` and `~/.gitconfig*`, `./apply`. Use the Bash tool's `dangerouslyDisableSandbox: true`. If `nix` isn't on PATH inside a Bash call, first `source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh`.
- **Run commands from the repo root** (`/Users/ian/projects/dotfiles`) unless noted.
- **Existing local state assumed:** `nix/host.nix` = `{ username = "ian"; profile = "default"; }`, `~/.dotfilesrc` contains `DOTFILES_ENVIRONMENT=default`, `~/.gnupg/` exists with a real `gpg-agent.conf` (containing `pinentry-program /opt/homebrew/bin/pinentry-mac` + `default-cache-ttl 600` + `max-cache-ttl 7200`) and a real `gpg.conf` (containing `auto-key-retrieve` + `no-emit-version`).
- **No work-specific values** belong in any committed file — work signing key, work email, enterprise hosts, etc. live ONLY in the user's private `custom_environments/<env>/` repo. The README migration guide written here is pattern-based.
- **Conventional commits**, NO `Co-Authored-By: Claude` / `Generated with Claude Code` trailers — neither in commit messages nor in PR bodies.
- **Testing pattern from prior slices:** direct plugin invocation rather than full `./apply` — exercises the `nix` plugin + home-manager activation without rerunning unrelated framework plugins.
- **One personal GPG key id is public and OK to commit:** `C9DA1EE9CCF21B28`. GPG fingerprints appear in every signed commit; they are not secrets.

---

## Task 1: Atomic commit-signing migration (`programs.gpg` + `services.gpg-agent` + signing key + activation + plugin deletion)

This task makes every change in one commit. Splitting it would leave the repo in a state where home-manager wants to manage `~/.gnupg/*.conf` while the `commit_signing` plugin is still writing them, or in a "no commit signing anywhere" state if the deletion lands before the new home-manager owner does. The Darwin-fallback gate (steps 8–10) decides primary vs. fallback approach BEFORE the commit, so the committed code reflects whichever works.

**Files:**

- Modify (full file replacement): `nix/profiles/all/default.nix` — signature gains `pkgs`; adds `programs.gpg`, `services.gpg-agent`, `home.activation.migrateLegacyGnupgConfig`; removes Slice 1's always-on `touch ~/.gitconfig` clause.
- Modify: `nix/profiles/default/default.nix` — adds `signingkey` to the existing `user` block and `commit.gpgsign = true`.
- Delete: `plugins/commit_signing/commit_signing`, `plugins/commit_signing/Brewfile`, and the now-empty `plugins/commit_signing/` directory.

- [ ] **Step 1: Capture pre-flight state for later regression checks**

Run (sandbox disabled — reads `~/.gnupg/` and `~/.gitconfig`):
```bash
echo "=== ~/.gnupg/ pre-flight ==="
ls -la "$HOME/.gnupg/" | head -20
echo "--- ~/.gnupg/gpg.conf ---"
cat "$HOME/.gnupg/gpg.conf"
echo "--- ~/.gnupg/gpg-agent.conf ---"
cat "$HOME/.gnupg/gpg-agent.conf"
echo "--- types ---"
[ -L "$HOME/.gnupg/gpg.conf" ] && echo "gpg.conf: symlink" || echo "gpg.conf: real file"
[ -L "$HOME/.gnupg/gpg-agent.conf" ] && echo "gpg-agent.conf: symlink" || echo "gpg-agent.conf: real file"
echo "=== git signing config pre-flight ==="
git config --show-origin --get user.signingkey
git config --show-origin --get commit.gpgsign
echo "=== ~/.gitconfig type ==="
[ -e "$HOME/.gitconfig" ] && (ls -l "$HOME/.gitconfig"; [ -L "$HOME/.gitconfig" ] && echo "(symlink)" || echo "(real file)") || echo "(absent)"
echo "=== existing markers ==="
ls -la "$HOME/.gitconfig.hm-migrated" "$HOME/.gnupg.hm-migrated" 2>&1
```
Expected output to **save for later comparison**: both gpg conf files are real (not symlinks); `gpg.conf` shows `auto-key-retrieve` + `no-emit-version`; `gpg-agent.conf` shows the three lines (`pinentry-program /opt/homebrew/bin/pinentry-mac`, `default-cache-ttl 600`, `max-cache-ttl 7200`); `user.signingkey` resolves out of `~/.gitconfig` (or `~/.config/git/config` after Slice 1) to `C9DA1EE9CCF21B28`; `commit.gpgsign` resolves to `true`; the `~/.gitconfig.hm-migrated` marker exists from Slice 1; `~/.gnupg.hm-migrated` does NOT exist yet.

- [ ] **Step 2: Read the current `nix/profiles/all/default.nix` to confirm starting state**

Run: `cat nix/profiles/all/default.nix`
Expected: the file from Slice 1 — signature `{ lib, ... }:`, `programs.bat` + `programs.git` blocks, `home.activation.migrateLegacyGitConfig` containing BOTH the marker-gated legacy-backup clause AND the always-on `touch ~/.gitconfig` clause. The replacement in Step 3 drops the second clause and adds the GPG blocks.

- [ ] **Step 3: Replace `nix/profiles/all/default.nix` with exactly this content**

```nix
{ lib, pkgs, ... }: {
  # `all` is composed into every config by `lib.mkHome`, regardless of which
  # profile is active or whether a private flake overlays on top — anything
  # *every* machine should get goes here.
  programs.bat = {
    enable = true;          # installs bat (the package half of the slice)
    config.theme = "ansi";  # writes ~/.config/bat/config (the dotfile half)
  };

  programs.git = {
    enable = true;

    # Preserves `[include] path = .gitconfig.custom` from both source
    # .gitconfigs so user-managed local overrides keep working.
    includes = [ { path = "~/.gitconfig.custom"; } ];

    # `settings` replaces the older `aliases` + `extraConfig` options
    # (renamed in home-manager; the old names emit a deprecation warning).
    # `settings.alias` is the alias subsection; the other top-level attrs
    # map to git config sections of the same name.
    settings = {
      alias = {
        autosquash = "!GIT_SEQUENCE_EDITOR=true git rebase -i --autosquash";
        fixup      = "commit --fixup";
        pfl        = "push --force-with-lease";
      };

      branch = {
        sort = "-committerdate";
        main.rebase = true;
        master.rebase = true;
      };

      color = {
        ui = "auto";
        branch = { current = "yellow reverse"; local = "yellow"; remote = "green"; };
        diff   = { frag = "magenta bold"; meta = "yellow bold"; new = "green bold"; old = "red bold"; };
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
        algorithm       = "histogram";
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

  # ~/.gnupg/gpg.conf — preserves the two settings the old commit_signing
  # plugin and the user's manual config had.
  programs.gpg = {
    enable = true;  # also installs pkgs.gnupg into the profile.
    settings = {
      auto-key-retrieve = true;
      no-emit-version   = true;
    };
  };

  # ~/.gnupg/gpg-agent.conf — pinentry is per-OS; cache TTLs match the old
  # plugin's prior behavior (10-minute default, 2-hour max).
  services.gpg-agent = {
    enable = true;
    pinentry.package =
      if pkgs.stdenv.isDarwin then pkgs.pinentry_mac
      else                         pkgs.pinentry-tty;
    defaultCacheTtl = 600;
    maxCacheTtl     = 7200;
  };

  home.activation.migrateLegacyGitConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # One-time migration from Slice 1: move pre-migration ~/.gitconfig aside
    # so it stops shadowing the home-manager-managed ~/.config/git/config.
    # The marker file makes this idempotent — necessary because before this
    # slice, the commit_signing plugin ran *before* nix on macOS and would
    # recreate ~/.gitconfig with signing fields, which without the marker
    # would cause the guard to re-move the file every apply.
    if [ -f "$HOME/.gitconfig" ] \
         && [ ! -L "$HOME/.gitconfig" ] \
         && [ ! -e "$HOME/.gitconfig.hm-migrated" ]; then
      run mv "$HOME/.gitconfig" "$HOME/.gitconfig.legacy-backup"
      run touch "$HOME/.gitconfig.hm-migrated"
      # Use bare echo (not verboseEcho) so this one-time event is visible in
      # a normal ./apply run without requiring DOTFILES_DEBUG / $VERBOSE.
      echo "Moved legacy ~/.gitconfig → ~/.gitconfig.legacy-backup (one-time migration)"
    fi
    # NOTE: Slice 1's always-on `touch ~/.gitconfig` clause is intentionally
    # gone in this slice — commit_signing (its only consumer) is retired, so
    # nothing else writes to ~/.gitconfig anymore.
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
}
```

- [ ] **Step 4: Read the current `nix/profiles/default/default.nix` to confirm starting state**

Run: `cat nix/profiles/default/default.nix`
Expected: the file from Slice 1 — `home.packages = [ pkgs.ripgrep ]` and `programs.git.settings.user = { name; email; }`.

- [ ] **Step 5: Replace `nix/profiles/default/default.nix` with this content**

```nix
{ pkgs, ... }: {
  home.packages = [ pkgs.ripgrep ];

  # `settings.user.{name,email,signingkey}` is the current home-manager
  # option path (replaces the deprecated `programs.git.{userName,userEmail}`).
  # The signing key id is a public GPG fingerprint — fine to commit.
  programs.git.settings = {
    user = {
      name       = "ianwremmel";
      email      = "1182361+ianwremmel@users.noreply.github.com";
      signingkey = "C9DA1EE9CCF21B28";
    };
    commit.gpgsign = true;
  };
}
```

- [ ] **Step 6: Delete the `commit_signing` plugin (both files and the directory)**

```bash
git rm plugins/commit_signing/commit_signing plugins/commit_signing/Brewfile
rmdir plugins/commit_signing 2>/dev/null || true
ls -d plugins/commit_signing 2>&1 | head -1
```
Expected: `ls: cannot access 'plugins/commit_signing': No such file or directory` (or the equivalent macOS phrasing). `git status --porcelain plugins/commit_signing/` should show two `D` lines (one for each file) and nothing else.

- [ ] **Step 7: Verify the changed Nix files parse and the flake still evaluates**

Run (sandbox disabled):
```bash
nix-instantiate --parse nix/profiles/all/default.nix >/dev/null && echo "all parses"
nix-instantiate --parse nix/profiles/default/default.nix >/dev/null && echo "default parses"

nix --extra-experimental-features 'nix-command flakes' eval \
  "path:$PWD/nix#homeModules.all" --apply 'p: builtins.typeOf p' --raw; echo
nix --extra-experimental-features 'nix-command flakes' eval \
  "path:$PWD/nix#homeModules.default" --apply 'p: builtins.typeOf p' --raw; echo
```
Expected: `all parses`, `default parses`, `path`, `path`. If any line errors, fix the syntax in the file referenced by the error before proceeding.

- [ ] **Step 8: Run the plugin end-to-end (triggers the activation migrations)**

Run (sandbox disabled — full home-manager activation):
```bash
DOTFILES_ENVIRONMENT=default DOTFILES_ROOT_DIR="$PWD" bash -c '
  set -euo pipefail
  source framework/logging
  source plugins/nix/nix
  dotfiles_nix_apply
' 2>&1 | tail -20
```
Expected: log lines `Resolved profile: default`, `Building public profile 'default' for aarch64-darwin`, `Activating home-manager configuration`, and somewhere in the activation output the single line `Moved legacy ~/.gnupg/gpg-agent.conf → ~/.gnupg/gpg-agent.conf.legacy-backup (one-time migration)` followed by `Moved legacy ~/.gnupg/gpg.conf → ~/.gnupg/gpg.conf.legacy-backup (one-time migration)` (order may vary). Exit 0. (Note: the Slice-1 `migrateLegacyGitConfig` short-circuits silently because the marker is already in place.)

- [ ] **Step 9: Verify the legacy backups were created and home-manager now owns the conf files**

Run:
```bash
echo "=== backups ==="
ls -l "$HOME/.gnupg/gpg.conf.legacy-backup" "$HOME/.gnupg/gpg-agent.conf.legacy-backup"
echo "=== home-manager symlinks ==="
ls -l "$HOME/.gnupg/gpg.conf" "$HOME/.gnupg/gpg-agent.conf" 2>&1
echo "=== marker ==="
ls -l "$HOME/.gnupg.hm-migrated"
echo "=== backup byte-equality (against pre-flight state) ==="
diff <(cat "$HOME/.gnupg/gpg.conf.legacy-backup") <(printf 'auto-key-retrieve\nno-emit-version\n') && echo "gpg.conf backup matches pre-flight"
echo "(gpg-agent.conf backup compared visually:)"; cat "$HOME/.gnupg/gpg-agent.conf.legacy-backup"
```
Expected: both `.legacy-backup` files exist with the pre-flight content (Step 1 captured what to compare against — the `gpg.conf` byte-equality check should pass; `gpg-agent.conf` content shows the three original `pinentry-program …`, `default-cache-ttl 600`, `max-cache-ttl 7200` lines); both unsuffixed files are symlinks into `/nix/store/…-home-manager-files/.gnupg/…` (or are missing on Darwin if `services.gpg-agent` didn't emit `gpg-agent.conf` — that's the trigger for Step 10's fallback gate).

- [ ] **Step 10: Verify activated config content (the Darwin gate)**

Run:
```bash
echo "=== gpg.conf content ==="
cat "$HOME/.gnupg/gpg.conf"
echo "=== gpg-agent.conf content ==="
cat "$HOME/.gnupg/gpg-agent.conf" 2>&1
echo "=== pinentry binary in path under /nix/store ==="
grep -E '^pinentry-program' "$HOME/.gnupg/gpg-agent.conf" 2>&1
```
Expected (primary-approach success):
- `gpg.conf` contains `auto-key-retrieve` and `no-emit-version` (any order).
- `gpg-agent.conf` contains a `pinentry-program /nix/store/…-pinentry_mac-*/bin/pinentry-mac` line, plus `default-cache-ttl 600` and `max-cache-ttl 7200`.

**Decision gate:**
- If both files contain all expected lines: primary approach works — **skip Step 11** and proceed to Step 12.
- If `gpg-agent.conf` is missing (no such file/symlink), is empty, or lacks the `pinentry-program` line: `services.gpg-agent` did not emit a usable config on Darwin — **execute Step 11** (in-task fallback) before Step 12.

- [ ] **Step 11: (Conditional — only if Step 10's gate failed) Swap `services.gpg-agent` for the `home.file` fallback**

Re-open `nix/profiles/all/default.nix` and **replace the `services.gpg-agent = { … };` block** (and only that block) with the fallback below. Keep everything else (the `programs.bat`, `programs.git`, `programs.gpg`, and both `home.activation.*` blocks) exactly as-is.

```nix
  # Fallback for Darwin: services.gpg-agent didn't emit a usable
  # ~/.gnupg/gpg-agent.conf. Manage the file and the pinentry binary by hand.
  home.packages = [
    (if pkgs.stdenv.isDarwin then pkgs.pinentry_mac else pkgs.pinentry-tty)
  ];
  home.file.".gnupg/gpg-agent.conf".text = ''
    pinentry-program ${if pkgs.stdenv.isDarwin
                       then "${pkgs.pinentry_mac}/bin/pinentry-mac"
                       else "${pkgs.pinentry-tty}/bin/pinentry-tty"}
    default-cache-ttl 600
    max-cache-ttl 7200
  '';
```

Re-run the activation:
```bash
DOTFILES_ENVIRONMENT=default DOTFILES_ROOT_DIR="$PWD" bash -c '
  set -euo pipefail
  source framework/logging
  source plugins/nix/nix
  dotfiles_nix_apply
' 2>&1 | tail -10
```
Then re-run Step 10's verification block. The fallback MUST satisfy: `gpg-agent.conf` is a symlink into `/nix/store/…-home-manager-files/.gnupg/gpg-agent.conf` with `pinentry-program /nix/store/…-pinentry_mac-*/bin/pinentry-mac`, `default-cache-ttl 600`, `max-cache-ttl 7200`. If both Step 10 and the fallback fail, STOP — escalate (the spec's Darwin-fallback was the planned-for second option; a third option is out of scope for this slice).

- [ ] **Step 12: Verify Nix-installed `gnupg` is on PATH (no longer brew's)**

Run:
```bash
which gpg
readlink "$(which gpg)" || true
gpg --version | head -1
```
Expected: `which gpg` resolves to `~/.nix-profile/bin/gpg`. `readlink` shows it pointing into `/nix/store/…-gnupg-*/bin/gpg`. `gpg --version` reports the Nix-installed version. (If `which gpg` still resolves into `/opt/homebrew/bin/`, the user's PATH has brew before `~/.nix-profile` — note it but don't block; the system still works because `programs.gpg.enable = true` activates the Nix version into the profile.)

- [ ] **Step 13: Verify signing config now resolves from the home-manager-managed XDG file**

Run:
```bash
echo "=== signing key origin ==="
git config --show-origin --get user.signingkey
echo "=== commit.gpgsign origin ==="
git config --show-origin --get commit.gpgsign
echo "=== ~/.gitconfig should be absent (Slice 1 empty-seed touch is gone) ==="
[ -e "$HOME/.gitconfig" ] && (ls -l "$HOME/.gitconfig"; echo "WARNING: ~/.gitconfig still present") || echo "absent (as expected)"
```
Expected: `user.signingkey` origin is `file:/Users/ian/.config/git/config`, value `C9DA1EE9CCF21B28`. `commit.gpgsign` origin is `file:/Users/ian/.config/git/config`, value `true`. `~/.gitconfig` is absent — Slice 1's empty-seed `touch` clause is gone, `commit_signing` is gone, nothing creates it. (The Slice-1 `~/.gitconfig.legacy-backup` from the very first migration MAY still be on disk; that's fine and untouched.)

- [ ] **Step 14: Verify a GPG-signed commit still works end-to-end**

Run (sandbox disabled — `git commit` shells out to `gpg`):
```bash
WORKDIR="$(mktemp -d)"
( cd "$WORKDIR" && \
  git init -q && \
  git commit --allow-empty -m "test-sign" )
( cd "$WORKDIR" && git log -1 --format='%G? %GS' )
rm -rf "$WORKDIR"
```
Expected: the `git log` line begins with `G ` (good signature) or `U ` (good but untrusted — acceptable; happens if the key's not in the local trustdb). `N ` (no signature) is a FAILURE — `gpg-agent` did not pick up the new config or the wrong `gpg` was invoked; debug before proceeding (most likely cause: Step 12 showed brew's `gpg` shadowing Nix's, AND the brew `gpg`'s view of `~/.gnupg/` differs).

- [ ] **Step 15: Verify activation idempotency (second run is a no-op)**

Run:
```bash
DOTFILES_ENVIRONMENT=default DOTFILES_ROOT_DIR="$PWD" bash -c '
  set -euo pipefail
  source framework/logging
  source plugins/nix/nix
  dotfiles_nix_apply
' 2>&1 | grep -E "Moved legacy|migrateLegacyGnupgConfig" || echo "(no Moved-legacy lines — guard short-circuited, as expected)"
echo "=== backups still preserved (same mtimes) ==="
ls -l "$HOME/.gnupg/gpg.conf.legacy-backup" "$HOME/.gnupg/gpg-agent.conf.legacy-backup"
```
Expected: `(no Moved-legacy lines — guard short-circuited, as expected)` — the `~/.gnupg.hm-migrated` marker prevented a second pass. The two `.legacy-backup` files keep the mtimes they had after Step 9 (no re-move).

- [ ] **Step 16: Confirm host-state files untouched**

Run:
```bash
cat nix/host.nix
git status --porcelain nix/host.nix
grep -E '^DOTFILES_(GIT|COMMIT_SIGNING)_' "$HOME/.dotfilesrc" 2>/dev/null || echo "(no DOTFILES_GIT/COMMIT_SIGNING entries — clean)"
```
Expected: `nix/host.nix` still `{ username = "ian"; profile = "default"; }`, still untracked. Any orphaned `DOTFILES_GIT_CONFIG_*` entries from Slice 1 remain in `~/.dotfilesrc` (harmless; cleanup is the user's call — same non-goal as Slice 1).

- [ ] **Step 17: Commit the atomic migration**

Run:
```bash
git add nix/profiles/all/default.nix nix/profiles/default/default.nix
git status --porcelain
git -c gpg.program="$(which gpg)" commit -m "feat(nix): migrate commit_signing plugin to programs.gpg + services.gpg-agent + signing settings"
git log --oneline -1
```
Expected: `git status --porcelain` shows `M nix/profiles/all/default.nix`, `M nix/profiles/default/default.nix`, `D plugins/commit_signing/commit_signing`, `D plugins/commit_signing/Brewfile`. The commit succeeds and is GPG-signed (proving the end-to-end signing setup works — meta-validation). Conventional-commit message, no `Co-Authored-By` trailer.

---

## Task 2: README updates

Three changes to `nix/README.md` per the spec's "README updates" section: (1) extend the existing private-environment migration guide with a "commit-signing slice" block, (2) refresh the Background paragraph to include commit signing, (3) refresh the `all`-layer description in `### Public profiles and layers`.

**Files:**

- Modify: `nix/README.md`

- [ ] **Step 1: Locate the three insertion points**

Run:
```bash
grep -n '^For the git slice' nix/README.md      # end of slice-1 sub-block (insertion point for new sub-block)
grep -n '^## Background\|^## Install' nix/README.md
grep -n '^### Public profiles and layers' nix/README.md
grep -n 'currently `bat`' nix/README.md          # the line whose description gets extended
```
Expected: `For the git slice` appears around line 160; `## Background` and `## Install` are top-level sections; `### Public profiles and layers` is a subsection; the `currently \`bat\`` line is inside the `all` bullet under that subsection.

- [ ] **Step 2: Insert the "For the commit-signing slice" sub-block into the migration guide**

In `nix/README.md`, find the `3. **First \`./apply\` after this slice** runs the` paragraph (the third numbered item of the Slice-1 "For the git slice" block, ending with `…satisfied with the migration.`). Immediately AFTER that paragraph and BEFORE the line beginning `The same shape applies to future slices`, insert this new block:

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

(Note the trailing blank line above — it separates this sub-block from the `The same shape applies to future slices` paragraph that follows.)

- [ ] **Step 3: Refresh the Background paragraph**

Find the sentence in the `## Background` section that lists what's currently managed (starts with `So far this manages:`). Replace the entire sentence with:

```
So far this manages: `bat` (shared in the `all` layer); `ripgrep` (in the `default` profile); the full git config (aliases, body, identity, includes) via `programs.git` plus a one-time activation that retires the legacy rsync-managed `~/.gitconfig`; and commit signing — `programs.gpg` + `services.gpg-agent` with per-OS pinentry (`pinentry-mac` on macOS, `pinentry-tty` on Linux), `programs.git.settings.user.signingkey` + `commit.gpgsign` in the personal profile, and a one-time activation that retires the old plugin-written `~/.gnupg/*.conf`.
```

- [ ] **Step 4: Refresh the `all` layer description under `### Public profiles and layers`**

Find the bullet beginning `- \`all\` — always included via \`mkHome\`;`. Its parenthetical currently says `(currently \`bat\` and the shared git config — aliases, body, includes — via \`programs.git\`)`. Replace that parenthetical with:

```
(currently `bat`, the shared git config — aliases, body, includes — via `programs.git`, and GPG/agent setup with per-OS pinentry: `pinentry-mac` on macOS, `pinentry-tty` on Linux)
```

- [ ] **Step 5: Verify the three changes landed and the markdown is well-formed**

Run:
```bash
grep -n 'For the commit-signing slice' nix/README.md
grep -n 'commit signing — \`programs.gpg\`' nix/README.md
grep -n 'GPG/agent setup with per-OS pinentry' nix/README.md
echo "=== fence balance ==="
grep -c '^```\|^   ```' nix/README.md
```
Expected: each of the three `grep -n` lines returns exactly one match (so the insertions happened, in the right places). Fence count is an even number (open/close balanced).

- [ ] **Step 6: Commit**

```bash
git add nix/README.md
git -c gpg.program="$(which gpg)" commit -m "docs(nix): document commit-signing slice + private-env migration"
git log --oneline -2
```
Expected: commit succeeds (GPG-signed), the two most recent commits are this docs commit and Task 1's `feat(nix): migrate commit_signing plugin …`.

---

## Task 3: End-to-end verification (throwaway-private override + Linux container)

No file changes are committed by this task — throwaway-private files live under the gitignored `custom_environments/throwaway/` and are removed at end. Confirms (a) a private profile can override the signing key with `lib.mkForce`, (b) Linux activation produces the right `pinentry-tty` reference, and (c) the agent profile correctly does NOT enable signing.

**Files:** none committed.

- [ ] **Step 1: Throwaway private-profile signing-key override (macOS)**

Same scaffold as prior slices. Create a throwaway private flake that overrides the signing key, activate it, verify.

```bash
mkdir -p custom_environments/throwaway/nix
cat > custom_environments/throwaway/nix/flake.nix <<'EOF'
{
  description = "Throwaway test profile (signing-key override)";

  inputs = {
    public.url = "github:ianwremmel/dotfiles?dir=nix";
    nixpkgs.follows      = "public/nixpkgs";
    home-manager.follows = "public/home-manager";
  };

  outputs = { self, public, ... }:
    let
      host = import (public + "/host.nix");
      supportedSystems = [ "aarch64-darwin" "x86_64-linux" "aarch64-linux" ];
      mkConfig = system: public.lib.mkHome {
        inherit system;
        inherit (host) username;
        modules = [
          public.homeModules.default
          ./throwaway.nix
        ];
      };
    in {
      homeConfigurations = builtins.listToAttrs (map
        (system: { name = system; value = mkConfig system; })
        supportedSystems);
    };
}
EOF

cat > custom_environments/throwaway/nix/throwaway.nix <<'EOF'
{ lib, ... }: {
  # Override the personal signing key with a fake one. commit.gpgsign is
  # already inherited from public.homeModules.default — no need to re-set.
  programs.git.settings.user.signingkey = lib.mkForce "DEADBEEFDEADBEEF";
}
EOF

# Init nested git repo and commit so `path:` flake refs work.
( cd custom_environments/throwaway/nix \
    && git init -q \
    && git add . \
    && git -c user.email=t@e -c user.name=t -c commit.gpgsign=false commit -q -m init )

# Lock the private flake against the local public source.
( cd custom_environments/throwaway/nix \
    && nix --extra-experimental-features 'nix-command flakes' flake lock \
        --override-input public "path:$OLDPWD/nix" )

# Activate the throwaway profile.
DOTFILES_ENVIRONMENT=throwaway DOTFILES_ROOT_DIR="$PWD" bash -c '
  set -euo pipefail
  source framework/logging
  source plugins/nix/nix
  dotfiles_nix_apply
' 2>&1 | tail -10

echo "=== signing key should be the throwaway override ==="
git config --get user.signingkey
echo "=== commit.gpgsign still true (inherited from default) ==="
git config --get commit.gpgsign
echo "=== identity unchanged (also inherited from default) ==="
git config --get user.name
git config --get user.email
```
Expected: the plugin log shows `Resolved profile: throwaway` and the private-path build with `--override-input public→local`. `git config --get user.signingkey` returns `DEADBEEFDEADBEEF`; `commit.gpgsign` returns `true`; `user.name` returns `ianwremmel`; `user.email` returns the noreply email. (`programs.gpg` and `services.gpg-agent` from `all` still active — no change to `~/.gnupg/*.conf` symlinks.)

- [ ] **Step 2: Tear down throwaway and restore default profile**

```bash
rm -rf custom_environments/throwaway

DOTFILES_ENVIRONMENT=default DOTFILES_ROOT_DIR="$PWD" bash -c '
  set -euo pipefail
  source framework/logging
  source plugins/nix/nix
  dotfiles_nix_apply
' 2>&1 | tail -8

echo "=== signing key back to personal ==="
git config --get user.signingkey
echo "=== working tree clean? ==="
git status --porcelain
```
Expected: throwaway dir gone; `user.signingkey` returns `C9DA1EE9CCF21B28` again; `git status --porcelain` shows no changes (custom_environments was gitignored).

- [ ] **Step 3: Linux container verification (aarch64-linux, agent profile)**

Activate the `agent` profile in a clean ubuntu container and verify: GPG is set up (since `programs.gpg` + `services.gpg-agent` are in `all`), pinentry points at `pinentry-tty` (not `pinentry_mac`), but `commit.gpgsign` is NOT set (because `agent` doesn't inherit from `default`).

```bash
docker run --rm --platform linux/arm64 -v "$PWD":/src:ro ubuntu:24.04 bash -c '
  set -euo pipefail
  apt-get update -qq && apt-get install -y -qq curl xz-utils ca-certificates git gnupg >/dev/null
  cp -r /src /dotfiles
  cd /dotfiles
  install -m 0600 /dev/null "$HOME/.dotfilesrc"
  echo "DOTFILES_ENVIRONMENT=agent" > "$HOME/.dotfilesrc"
  ./apply
  echo "=== ~/.gnupg/ contents ==="
  ls -la "$HOME/.gnupg/" | head -10
  echo "=== gpg.conf content (from all) ==="
  cat "$HOME/.gnupg/gpg.conf"
  echo "=== gpg-agent.conf content (per-OS pinentry should be pinentry-tty) ==="
  cat "$HOME/.gnupg/gpg-agent.conf"
  echo "=== verify pinentry-tty reference, NOT pinentry_mac ==="
  grep -q "pinentry-tty" "$HOME/.gnupg/gpg-agent.conf" && echo "pinentry-tty: yes (correct)" || echo "pinentry-tty: NO (WRONG)"
  grep -q "pinentry-mac" "$HOME/.gnupg/gpg-agent.conf" && echo "pinentry-mac: YES (WRONG)" || echo "pinentry-mac: no (correct)"
  echo "=== agent profile: signing OFF ==="
  git config --get user.signingkey 2>&1 || echo "(no signingkey — correct: agent profile is lean)"
  git config --get commit.gpgsign 2>&1 || echo "(no commit.gpgsign — correct: agent profile does not sign)"
  echo "=== nix-installed gpg on PATH ==="
  readlink "$(which gpg)" 2>&1 | head -1 || which gpg
  echo "=== legacy-migration marker should exist; backups should NOT (clean container had no pre-existing ~/.gnupg/*.conf) ==="
  ls -la "$HOME/.gnupg.hm-migrated" 2>&1 | head -1
  ls "$HOME/.gnupg/"*.legacy-backup 2>&1 | head -1 || echo "(no legacy-backup files — correct, clean container)"
'
```
Expected: container builds, agent profile activates. `gpg.conf` shows `auto-key-retrieve` + `no-emit-version`. `gpg-agent.conf` contains `pinentry-program /nix/store/…-pinentry-tty-*/bin/pinentry-tty`, `default-cache-ttl 600`, `max-cache-ttl 7200`. The two `grep`s pass (`pinentry-tty: yes (correct)`, `pinentry-mac: no (correct)`). `user.signingkey` and `commit.gpgsign` both empty (agent profile doesn't sign — by design). `which gpg` resolves into `/nix/store/…-gnupg-*/bin/gpg`. Marker file exists; no `.legacy-backup` siblings (clean container).

- [ ] **Step 4: Final state check**

```bash
git log --oneline master..nix-commit-signing
git status --porcelain
echo "=== ~/.gnupg/*.legacy-backup still on user's mac ==="
ls -l "$HOME/.gnupg/"*.legacy-backup 2>&1
echo "=== current ~/.gnupg/*.conf are home-manager symlinks ==="
ls -l "$HOME/.gnupg/gpg.conf" "$HOME/.gnupg/gpg-agent.conf"
```
Expected: the branch contains the two commits from Tasks 1 and 2 (`feat(nix): migrate commit_signing…` and `docs(nix): document commit-signing slice…`), working tree clean, the two legacy backups still present on the user's mac (untouched since Step 9 of Task 1), the conf files are symlinks into `/nix/store/…`. The slice is verified end-to-end on both platforms.

---

## Self-review (completed by plan author)

- **Spec coverage:**
  - Decision 1 (scope: commit signing) — Task 1 atomic migration ✓
  - Decision 2 (Darwin fallback gate) — Task 1 Steps 10 (gate) + 11 (fallback) ✓
  - Decision 3 (per-OS pinentry) — Task 1 Step 3 (`pkgs.stdenv.isDarwin` branch); Task 3 Step 3 (Linux container verifies `pinentry-tty`) ✓
  - Decision 4 (signing key in `profiles/default`, public key id) — Task 1 Step 5 ✓
  - Decision 5 (`agent` profile lean / no signing) — Task 3 Step 3's two empty `user.signingkey`/`commit.gpgsign` checks ✓
  - Decision 6 (drop Slice-1 empty-seed `touch ~/.gitconfig`) — Task 1 Step 3 (no `touch` clause in new file) + Step 13 (`~/.gitconfig` absent) ✓
  - Decision 7 (one-time `~/.gnupg/*.conf` migration) — Task 1 Step 3 (`migrateLegacyGnupgConfig`) + Step 9 (verify backups) + Step 15 (idempotency) ✓
  - Decision 8 (don't touch keyring) — script's per-file `[ -f … ] && [ ! -L … ]` guard, and the loop is hard-coded to `gpg.conf` and `gpg-agent.conf` only ✓
  - Decision 9 (no work-specific values in public repo) — Task 2 Step 2's migration guide is pattern-based, no values ✓
  - Architecture deletions (`plugins/commit_signing/`) — Task 1 Step 6 ✓
  - `programs.gpg` + `services.gpg-agent` translation block — Task 1 Step 3 ✓
  - Identity + signing in `default` — Task 1 Step 5 ✓
  - Activation script (one-time + non-destructive + Linux-safe + idempotent + independent of git script) — Task 1 Steps 3, 9, 15; Task 3 Step 3 (Linux no-op) ✓
  - Darwin fallback block — Task 1 Step 11 ✓
  - Testing pre-flight / activation / config content / Nix `gnupg` on PATH / signing in effect / signed test commit / idempotency / Darwin fallback / throwaway / Linux — Task 1 Steps 1, 8–15 + Task 3 all steps ✓
  - README updates (migration sub-block + Background refresh + `all` description refresh) — Task 2 Steps 2–4 ✓
- **Placeholder scan:** no TBD / TODO / "appropriate error handling" / "similar to …". Every Nix block, command, and verification step is complete. The conditional Step 11 is gated explicitly on Step 10's output, not left to "fill in later."
- **Type/name consistency:**
  - `programs.gpg.settings.{auto-key-retrieve,no-emit-version}` — referenced consistently.
  - `services.gpg-agent.{enable,pinentry.package,defaultCacheTtl,maxCacheTtl}` — referenced consistently (the camelCase TTL names are the actual home-manager option names; the file emitted uses the kebab-case `default-cache-ttl` / `max-cache-ttl` lines that the verification steps grep for).
  - `programs.git.settings.user.signingkey` (one word, lowercase) and `programs.git.settings.commit.gpgsign` — referenced consistently across plan, spec, README guide, throwaway test.
  - `home.activation.migrateLegacyGnupgConfig` activation name — consistent.
  - `~/.gnupg.hm-migrated` marker location (sibling to `~/.gnupg/`, not inside it) — consistent with spec.
  - `homeModules.{base,all,default,agent}`, `lib.mkHome`, `--override-input public path:…`, `host.nix` shape — all referenced exactly as the stacked slices established them.
- **Atomicity:** Task 1 bundles the five file ops (modify `all`, modify `default`, delete two plugin files, plus the conditional Darwin-fallback re-edit if needed) into one commit. The decision gate (Step 10) and the fallback step (Step 11) both happen BEFORE the commit (Step 17), so whichever approach works is what gets committed — no partial-state window.
