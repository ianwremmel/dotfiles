# Nix Prompt Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Switch the interactive shell prompt from Powerlevel10k to Starship via `programs.starship.enable`, retire `plugins/powerlevel/`, delete the 1443-line `environments/all/home/.p10k.zsh` rsync source, remove three temporary p10k-related blocks Slice 6 left in `nix/profiles/all/shells.nix`'s `initContent`, and add a one-time activation that backs up any pre-existing `~/.p10k.zsh`.

**Architecture:** Single atomic commit edits `nix/profiles/all/shells.nix` (adds `programs.starship` block + `migrateLegacyP10kConfig` activation + removes three p10k blocks from `initContent` + drops the `zshrc-d-prompt.zsh` sibling `builtins.readFile` reference), deletes the bash plugin, deletes `.p10k.zsh`, and deletes the `zshrc-d-prompt.zsh` sibling file. A second commit updates `nix/README.md`. A third task is verification-only (throwaway override + Linux container).

**Tech Stack:** Bash 5, Nix flakes, home-manager (`programs.starship`, `lib.hm.dag.entryBefore`), Starship 1.x.

---

## Notes for the executor

- **Reference spec:** `docs/superpowers/specs/2026-05-25-nix-prompt-design.md`.
- **No automated test framework.** "Tests" are verification commands with expected output.
- **Branch:** work is on `nix-prompt`. Stacks on `nix-shells` (PR #66) → `nix-commit-signing` (PR #65) → `nix-git` (PR #64) → `nix-profiles` (PR #63) → `nix-cross-platform` (PR #62) → `master`. **Do NOT merge anything.**
- **Stacking machinery** (assumed working from prior slices): `homeModules.{base,all,default,agent}`, `lib.mkHome`, profile-module layering, `--override-input public path:…` private-flake idiom, `home.activation.*` style migrations, `nix/host.nix` (untracked).
- **Sandbox disable required for:** `nix`, `./apply`, `git commit` (gpg signing), modifying `~/.p10k.zsh*`. Use `dangerouslyDisableSandbox: true`. If `nix` isn't on PATH, prepend: `source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh`.
- **Run commands from repo root** (`/Users/ian/projects/dotfiles`).
- **Pre-existing local state:**
  - `nix/host.nix` = `{ username = "ian"; profile = "default"; }`, untracked.
  - `~/.dotfilesrc` contains `DOTFILES_ENVIRONMENT=default`.
  - `~/.p10k.zsh` exists as a real file (74,597 bytes, 1443 lines).
  - `~/powerlevel10k/` exists as a cloned git repo (228 entries).
  - `~/.p10k.hm-migrated` marker does NOT exist yet.
- **Conventional commits**, NO `Co-Authored-By: Claude` / `Generated with Claude Code` trailers.
- **No work-specific values** in any committed file.

---

## Task 1: Atomic prompt migration (`programs.starship` + remove p10k temp blocks + activation + plugin/source deletions)

Every change in one commit so the repo never sits in a state where the temp p10k blocks reference deleted siblings or where starship is installed but p10k blocks still try to source the deleted `~/.p10k.zsh`.

**Files:**

- Modify: `nix/profiles/all/shells.nix` — add `programs.starship`, add `migrateLegacyP10kConfig`, remove 3 p10k blocks from `initContent`, drop the `zshrc-d-prompt.zsh` sibling reference + its `# ---- from .zshrc.d/prompt.zsh ----` comment.
- Delete: `plugins/powerlevel/powerlevel` and the now-empty `plugins/powerlevel/` directory.
- Delete: `environments/all/home/.p10k.zsh`.
- Delete: `nix/profiles/all/zshrc-d-prompt.zsh` (the Slice 6 sibling file; no longer referenced).

- [ ] **Step 1: Capture pre-flight state**

Run (sandbox disabled):
```bash
echo "=== ~/.p10k.zsh ==="
ls -l "$HOME/.p10k.zsh" 2>&1
[ -L "$HOME/.p10k.zsh" ] && echo "(symlink)" || echo "(real file)"
wc -l "$HOME/.p10k.zsh" 2>&1
echo ""
echo "=== ~/powerlevel10k/ ==="
ls -d "$HOME/powerlevel10k" 2>&1
[ -d "$HOME/powerlevel10k" ] && echo "(present)" || echo "(absent)"
echo ""
echo "=== starship binary on PATH ==="
command -v starship 2>&1 || echo "absent"
starship --version 2>&1 || true
echo ""
echo "=== markers ==="
ls -la "$HOME/.p10k.hm-migrated" 2>&1 | head -1
echo ""
echo "=== current generated ~/.zshrc sources p10k? ==="
grep -nE 'powerlevel|p10k' "$HOME/.zshrc" 2>&1 | head -5
```
Expected: `.p10k.zsh` real file, 1443 lines. `~/powerlevel10k/` present (cloned long ago). `starship` absent (or maybe brew-installed). marker absent. `.zshrc` contains the three p10k blocks Slice 6 inlined.

- [ ] **Step 2: Read current `shells.nix` to confirm starting state**

Run: `wc -l nix/profiles/all/shells.nix; ls nix/profiles/all/zshrc-d-prompt.zsh`
Expected: shells.nix is ~400 lines; sibling file exists.

- [ ] **Step 3: Edit `shells.nix` — remove the top-of-initContent p10k instant-prompt block**

Find this block (around lines 266–276):

```nix
      # ---- Powerlevel10k instant prompt — MUST be at the very top of .zshrc.
      # The original .zshrc gates this on ~/powerlevel10k existing; preserved.
      # Slice 6 (prompt) will replace this when p10k moves to home-manager.
      if [ -d "$HOME/powerlevel10k" ]; then
        # Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
        # Initialization code that may require console input (password prompts, [y/n]
        # confirmations, etc.) must go above this block; everything else may go below.
        if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
          source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
        fi
      fi

      # ---- from .zshrc body ----
```

Replace with:

```nix
      # ---- from .zshrc body ----
```

(The whole instant-prompt block is removed; the `# ---- from .zshrc body ----` comment is what was already after it. The blank line before `# ---- from .zshrc body ----` should also be removed if it leaves a double-blank.)

- [ ] **Step 4: Edit `shells.nix` — remove the `zshrc-d-prompt.zsh` sibling reference**

Find this block (around lines 308–309):

```nix
      # ---- from .zshrc.d/prompt.zsh (replaced in Slice 6) ----
    '' + (builtins.readFile ./zshrc-d-prompt.zsh) + ''

      # ---- from .zshrc.d/rbenv.zsh ----
```

Replace with:

```nix
      # ---- from .zshrc.d/rbenv.zsh ----
```

(The two-line comment + `builtins.readFile` + blank line are all removed.)

- [ ] **Step 5: Edit `shells.nix` — remove the bottom-of-initContent p10k tail blocks**

Find this block (around lines 323–329):

```nix
      # ---- p10k tail of .zshrc (replaced in Slice 6) ----
      if [ -d "$HOME/powerlevel10k" ]; then
        source ~/powerlevel10k/powerlevel10k.zsh-theme
      fi

      # To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
      [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
    '';
```

Replace with:

```nix
    '';
```

(The whole p10k tail and the customization comment + .p10k.zsh source line are all removed; only the closing `'';` of `initContent` remains.)

- [ ] **Step 6: Edit `shells.nix` — add the `programs.starship` block**

Find the closing `};` of the `programs.zsh = { … };` block. Add IMMEDIATELY AFTER it (before the `# ---------- Activation: legacy-backup migration ----------` section):

```nix
  # ---------- Starship prompt ----------
  programs.starship = {
    enable = true;
    # No settings overrides — opt in to starship's defaults. The default
    # prompt shows directory + git status + character on one line; works
    # cleanly with both bash and zsh; ~10ms init overhead. Iterate post-
    # merge if a default module is undesirable (override via the typed
    # `settings` attrset, which serializes to ~/.config/starship.toml).
    settings = { };
  };

```

- [ ] **Step 7: Edit `shells.nix` — add `migrateLegacyP10kConfig` activation**

Find the closing `'';` of the `home.activation.chshAndEtcShells = …` block (the LAST activation in the file). Add IMMEDIATELY AFTER it (before the final `}`):

```nix

  # ---------- Activation: legacy .p10k.zsh backup (prompt slice) ----------
  home.activation.migrateLegacyP10kConfig = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    # One-time migration: starship replaces p10k. The old rsync'd ~/.p10k.zsh
    # is no longer sourced; move it aside as a backup. ~/powerlevel10k/ (the
    # cloned theme repo) is left in place — inert without sourcing; user can
    # `rm -rf` it manually.
    if [ ! -e "$HOME/.p10k.hm-migrated" ]; then
      if [ -f "$HOME/.p10k.zsh" ] && [ ! -L "$HOME/.p10k.zsh" ]; then
        run mv -n "$HOME/.p10k.zsh" "$HOME/.p10k.zsh.legacy-backup"
        echo "Moved legacy ~/.p10k.zsh → ~/.p10k.zsh.legacy-backup (one-time migration)"
      fi
      run touch "$HOME/.p10k.hm-migrated"
    fi
  '';
```

- [ ] **Step 8: Delete `plugins/powerlevel/`**

```bash
git rm plugins/powerlevel/powerlevel
rmdir plugins/powerlevel 2>/dev/null || true
ls -d plugins/powerlevel 2>&1 | head -1
```
Expected: `ls: cannot access 'plugins/powerlevel'`.

- [ ] **Step 9: Delete `environments/all/home/.p10k.zsh`**

```bash
git rm environments/all/home/.p10k.zsh
ls environments/all/home/.p10k.zsh 2>&1 | head -1
```
Expected: `ls: cannot access '…/.p10k.zsh'`.

- [ ] **Step 10: Delete the `zshrc-d-prompt.zsh` sibling file**

```bash
git rm nix/profiles/all/zshrc-d-prompt.zsh
ls nix/profiles/all/zshrc-d-prompt.zsh 2>&1 | head -1
```
Expected: `ls: cannot access 'nix/profiles/all/zshrc-d-prompt.zsh'`.

- [ ] **Step 11: Verify `shells.nix` parses + flake evaluates**

Run (sandbox disabled):
```bash
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
nix-instantiate --parse nix/profiles/all/shells.nix >/dev/null && echo "shells parses"
nix --extra-experimental-features 'nix-command flakes' eval \
  "path:$PWD/nix#homeModules.all" --apply 'p: builtins.typeOf p' --raw; echo
nix --extra-experimental-features 'nix-command flakes' eval \
  "path:$PWD/nix#homeConfigurations.\"default@$(nix --extra-experimental-features 'nix-command flakes' eval --impure --raw --expr builtins.currentSystem)\".activationPackage.outPath" --raw; echo
```
Expected: `shells parses`; `path`; `/nix/store/…-home-manager-generation` path.

- [ ] **Step 12: Run the plugin to activate**

Run (sandbox disabled):
```bash
DOTFILES_ENVIRONMENT=default DOTFILES_ROOT_DIR="$PWD" bash -c '
  set -euo pipefail
  source framework/logging
  source plugins/nix/nix
  dotfiles_nix_apply
' 2>&1 | tail -20
```
Expected: activation succeeds. Somewhere in the output: `Moved legacy ~/.p10k.zsh → ~/.p10k.zsh.legacy-backup (one-time migration)`. Activation reaches `Activating checkLinkTargets` and completes without errors.

- [ ] **Step 13: Verify the migration moved `.p10k.zsh` aside**

Run:
```bash
echo "=== markers ==="
ls -l "$HOME/.p10k.hm-migrated"
echo ""
echo "=== ~/.p10k.zsh state ==="
[ -e "$HOME/.p10k.zsh" ] && (ls -l "$HOME/.p10k.zsh"; echo "WARN: still present") || echo "absent (correct)"
echo ""
echo "=== backup ==="
ls -l "$HOME/.p10k.zsh.legacy-backup"
wc -l "$HOME/.p10k.zsh.legacy-backup"
echo ""
echo "=== ~/powerlevel10k/ left alone (correct) ==="
ls -d "$HOME/powerlevel10k" 2>&1 | head -1
```
Expected: marker exists; `~/.p10k.zsh` absent; `.legacy-backup` exists with 1443 lines; `~/powerlevel10k/` still on disk (we leave it alone).

- [ ] **Step 14: Verify starship is installed and on PATH**

Run:
```bash
which starship
readlink "$(which starship)" 2>&1 | head -1
starship --version
```
Expected: `which starship` resolves to `~/.nix-profile/bin/starship`. Readlink shows `/nix/store/…-starship-*/bin/starship`. Version reports 1.x.

- [ ] **Step 15: Verify generated `~/.zshrc` and `~/.bashrc` source starship init**

Run:
```bash
echo "=== zsh starship integration ==="
grep -n 'starship init' "$HOME/.zshrc"
echo ""
echo "=== bash starship integration ==="
grep -n 'starship init' "$HOME/.bashrc"
echo ""
echo "=== no powerlevel/p10k references remain ==="
grep -nE 'powerlevel|p10k' "$HOME/.zshrc" "$HOME/.bashrc" 2>&1 | head -5
[ -z "$(grep -lE 'powerlevel|p10k' "$HOME/.zshrc" "$HOME/.bashrc" 2>/dev/null)" ] && echo "(clean — no powerlevel/p10k references)" || echo "WARN: still references p10k"
```
Expected: `eval "$(starship init zsh)"` appears once in `.zshrc`; `eval "$(starship init bash)"` appears once in `.bashrc`. NO powerlevel/p10k references.

- [ ] **Step 16: Verify a fresh zsh shows the starship prompt**

Run:
```bash
# Simulate a fresh interactive shell; print the actual prompt
zsh -ic 'echo prompt-test' 2>&1 | grep -v gitstatus | head -10
```
Expected: a starship-style prompt appears in the output (or at least no errors about missing p10k files). The `echo prompt-test` line should print.

- [ ] **Step 17: Verify bash also shows the starship prompt**

Run:
```bash
bash -lic 'echo prompt-test' 2>&1 | head -10
```
Expected: starship prompt appears; `echo prompt-test` line prints.

- [ ] **Step 18: Cross-slice integrity check**

Run:
```bash
git config --get alias.fixup            # Slice 1
git config --get user.signingkey         # Slice 5
git config --get commit.gpgsign          # Slice 5
git --version | head -1                  # Slice 5 nixpkgs bump → 2.54.0
gpg --version | head -1                  # Slice 5
bat --version | head -1                  # Slice 1
zsh -ic 'alias psgrep' 2>&1 | grep -v gitstatus  # Slice 6
bash -lic 'alias psgrep' 2>&1            # Slice 6
```
Expected: all return their expected values; no regressions.

- [ ] **Step 19: Activation idempotency check**

Run (sandbox disabled):
```bash
DOTFILES_ENVIRONMENT=default DOTFILES_ROOT_DIR="$PWD" bash -c '
  source framework/logging
  source plugins/nix/nix
  dotfiles_nix_apply
' 2>&1 | grep -E 'Moved legacy|migrateLegacyP10kConfig' || echo "(no migration output — guard short-circuited, as expected)"
ls -l "$HOME/.p10k.zsh.legacy-backup"
```
Expected: `(no migration output — guard short-circuited, as expected)`. `.legacy-backup` mtime unchanged.

- [ ] **Step 20: Commit the atomic migration**

```bash
git add nix/profiles/all/shells.nix
git status --porcelain
git -c gpg.program="$(which gpg)" commit -m "feat(nix): switch prompt from powerlevel10k to starship"
git log --oneline -1
```
Expected: `git status --porcelain` shows `M nix/profiles/all/shells.nix`, `D plugins/powerlevel/powerlevel`, `D environments/all/home/.p10k.zsh`, `D nix/profiles/all/zshrc-d-prompt.zsh`. Commit succeeds, GPG-signed. No `Co-Authored-By` trailer.

---

## Task 2: README updates

Three changes to `nix/README.md`.

**Files:**

- Modify: `nix/README.md`

- [ ] **Step 1: Locate insertion points**

Run:
```bash
grep -n '^For the shells slice' nix/README.md
grep -n '^## Background\|^## Install' nix/README.md
grep -n '^### Public profiles and layers' nix/README.md
grep -n 'AND bash + zsh via' nix/README.md
```
Expected: `For the shells slice` is the most recent sub-block; the new "For the prompt slice" goes after its item 3 and before `The same shape applies to future slices`.

- [ ] **Step 2: Insert the "For the prompt slice" sub-block**

In `nix/README.md`, find the paragraph beginning `3. **First \`./apply\` after this slice** runs the` inside the shells block, where item 3 ends with `…satisfied with the migration.`. Immediately AFTER that paragraph and BEFORE the line beginning `The same shape applies to future slices`, insert this block:

```markdown
For the prompt slice (`powerlevel` plugin retired; `.p10k.zsh` dropped;
starship via `programs.starship.enable` takes over):

1. If your private flake had a `custom_environments/<env>/home/.p10k.zsh`
   override (none in the public template), `git rm` it from your private
   repo and commit. Starship reads no such file; the rsync source is
   orphaned.

2. To customize starship per-environment, add to your private flake:

       { lib, pkgs, ... }: {
         programs.starship.settings = lib.mkForce {
           # …your starship.toml content as a Nix attrset…
         };
       }

   Use `lib.mkForce` because the public profile sets `settings = { };` —
   the typed attrset would conflict without it. Alternatively, use
   `lib.recursiveUpdate` if you want to merge with potential future
   public defaults.

3. **First `./apply` after this slice** runs `migrateLegacyP10kConfig`,
   which moves any pre-existing `~/.p10k.zsh` aside to
   `~/.p10k.zsh.legacy-backup`. The cloned `~/powerlevel10k/` repo is
   left in place (228-entry inert directory); `rm -rf ~/powerlevel10k`
   when satisfied. You can also `rm ~/.p10k.zsh.legacy-backup` whenever
   you're done with the migration.

```

(Note the trailing blank line.)

- [ ] **Step 3: Refresh the Background paragraph**

Find the `So far this manages:` sentence in `## Background`. The current sentence ends with `…the rsync-managed shell dotfiles plus the \`shells\` plugin's chsh / /etc/shells logic.`. Append:

```
; and a prompt — starship via `programs.starship` (replacing the retired `powerlevel` plugin and its rsync'd `.p10k.zsh`).
```

(Insert before the final `See Profiles for the layering…` sentence if there is one, or before the period of the final clause.)

- [ ] **Step 4: Refresh the `all`-layer parenthetical under `### Public profiles and layers`**

Find the bullet beginning `- \`all\` — always included via \`mkHome\`;`. Its current parenthetical ends with `…plus \`.inputrc\` via \`home.file\`)`. Replace the closing `)` with `, AND starship as the prompt)`:

```
(currently `bat`, the shared git config — aliases, body, includes — via `programs.git`, GPG/agent setup with per-OS pinentry: `pinentry-mac` on macOS, `pinentry-tty` on Linux, bash + zsh via `programs.bash` + `programs.zsh` plus `.inputrc` via `home.file`, AND starship as the prompt)
```

- [ ] **Step 5: Verify the changes**

Run:
```bash
grep -n 'For the prompt slice' nix/README.md
grep -n 'starship via `programs.starship`' nix/README.md
grep -n 'AND starship as the prompt' nix/README.md
echo "=== fence balance (probably 0 since README uses indented blocks) ==="
grep -c '^```' nix/README.md
```
Expected: each grep returns exactly one match; fence count is 0 or even.

- [ ] **Step 6: Commit**

```bash
git add nix/README.md
git -c gpg.program="$(which gpg)" commit -m "docs(nix): document prompt slice (starship) + private-env migration"
git log --oneline -3
```
Expected: commit succeeds, GPG-signed. Top commits: this docs commit + the prompt-migration feat + earlier slice docs.

---

## Task 3: End-to-end verification (throwaway override + Linux container)

No commits.

**Files:** none committed.

- [ ] **Step 1: Throwaway private-profile starship override (macOS)**

```bash
mkdir -p custom_environments/throwaway/nix
cat > custom_environments/throwaway/nix/flake.nix <<'EOF'
{
  description = "Throwaway test profile (starship-settings override)";

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
  # Override the empty default with a concrete starship setting.
  programs.starship.settings = lib.mkForce {
    add_newline = false;
  };
}
EOF

( cd custom_environments/throwaway/nix \
    && git init -q \
    && git add . \
    && git -c user.email=t@e -c user.name=t -c commit.gpgsign=false commit -q -m init )

( cd custom_environments/throwaway/nix \
    && nix --extra-experimental-features 'nix-command flakes' flake lock \
        --override-input public "path:$OLDPWD/nix" )

DOTFILES_ENVIRONMENT=throwaway DOTFILES_ROOT_DIR="$PWD" bash -c '
  set -euo pipefail
  source framework/logging
  source plugins/nix/nix
  dotfiles_nix_apply
' 2>&1 | tail -10

echo "=== starship.toml contains the override ==="
cat "$HOME/.config/starship.toml" 2>&1 | head -10
grep -n 'add_newline = false' "$HOME/.config/starship.toml" 2>&1 | head -1 || echo "WARN: override not in starship.toml"
```
Expected: throwaway activation succeeds. `~/.config/starship.toml` exists with `add_newline = false` (and may include other settings home-manager auto-generates).

- [ ] **Step 2: Tear down**

```bash
rm -rf custom_environments/throwaway

DOTFILES_ENVIRONMENT=default DOTFILES_ROOT_DIR="$PWD" bash -c '
  set -euo pipefail
  source framework/logging
  source plugins/nix/nix
  dotfiles_nix_apply
' 2>&1 | tail -8

echo "=== starship.toml back to default (empty or absent) ==="
[ -f "$HOME/.config/starship.toml" ] && cat "$HOME/.config/starship.toml" || echo "(no starship.toml — defaults active)"
echo ""
echo "=== working tree clean? ==="
git status --porcelain
```
Expected: `add_newline = false` no longer present (file is either empty/minimal or absent depending on how HM handles `settings = { }`). `git status --porcelain` clean.

- [ ] **Step 3: Linux container verification (aarch64-linux, agent profile)**

```bash
docker run --rm --platform linux/arm64 -v "$PWD":/src:ro ubuntu:24.04 bash -c '
  set -euo pipefail
  apt-get update -qq && apt-get install -y -qq curl xz-utils ca-certificates git gnupg sudo locales >/dev/null
  locale-gen en_US.UTF-8 >/dev/null 2>&1
  cp -r /src /dotfiles
  cd /dotfiles
  install -m 0600 /dev/null "$HOME/.dotfilesrc"
  echo "DOTFILES_ENVIRONMENT=agent" > "$HOME/.dotfilesrc"
  ./apply 2>&1 | tail -15
  echo "=== starship installed and on PATH ==="
  command -v starship && starship --version
  echo ""
  echo "=== starship init in shells ==="
  grep -nE "starship init" "$HOME/.bashrc" "$HOME/.zshrc"
  echo ""
  echo "=== marker present, no .p10k.zsh / no backup (clean container) ==="
  ls -la "$HOME/.p10k.hm-migrated" 2>&1 | head -1
  ls "$HOME/.p10k.zsh"* 2>&1 | head -3 || echo "(no .p10k.zsh files — correct on clean container)"
  echo ""
  echo "=== fresh bash prompt ==="
  bash -lic "echo prompt-test" 2>&1 | head -5
'
```
Expected: container builds; agent activates; starship installed in nix profile; `starship init` line in both `.bashrc` and `.zshrc`; marker present; no `.p10k.zsh` files (clean container); bash prompt shows starship rendering.

- [ ] **Step 4: Final state check**

```bash
git log --oneline master..nix-prompt | head -5
git status --porcelain
echo "=== ~/.p10k.zsh.legacy-backup still on user's mac ==="
ls -l "$HOME/.p10k.zsh.legacy-backup"
echo "=== ~/powerlevel10k/ still on disk (left alone) ==="
ls -d "$HOME/powerlevel10k" 2>&1 | head -1
```
Expected: branch contains the slice's 2 commits (feat + docs) on top of prior stack. Working tree clean. Backup file preserved. `~/powerlevel10k/` still present.

---

## Self-review (completed by plan author)

- **Spec coverage:**
  - Decision 1 (switch to starship): Task 1 Step 6 ✓
  - Decision 2 (starship defaults, no overrides): Task 1 Step 6 (`settings = { };`) ✓
  - Decision 3 (retire `plugins/powerlevel/`): Task 1 Step 8 ✓
  - Decision 4 (move `~/.p10k.zsh` aside): Task 1 Step 7 (activation script); Task 1 Step 13 (verification) ✓
  - Decision 5 (leave `~/powerlevel10k/` alone): activation script doesn't touch it; README documents manual rm ✓
  - Decision 6 (all content in `shells.nix`): no new submodule created ✓
  - Decision 7 (entryBefore checkLinkTargets DAG): Task 1 Step 7 ✓
  - Decision 8 (no work-specific values): Tasks 2 and 3 use pattern-only content ✓
  - Removed content: 3 p10k blocks (Steps 3, 4, 5) ✓
  - Sibling file deletion (`zshrc-d-prompt.zsh`): Task 1 Step 10 ✓
  - README updates: Task 2 ✓
  - Throwaway + Linux container verification: Task 3 ✓
- **Placeholder scan:** all steps have concrete commands and verbatim Nix content. No TBDs.
- **Type/name consistency:**
  - `programs.starship.enable`, `programs.starship.settings` — referenced consistently.
  - `home.activation.migrateLegacyP10kConfig` — consistent.
  - `~/.p10k.hm-migrated` marker — consistent.
  - `lib.hm.dag.entryBefore [ "checkLinkTargets" ]` — consistent with prior slices.
  - `~/.p10k.zsh.legacy-backup` — consistent.
- **Atomicity:** Task 1 is one commit (5 file changes); Task 2 is one commit; Task 3 has no commits. 2 commits total on the slice (plus spec + plan docs from earlier).
