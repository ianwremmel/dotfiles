# Nix Homedir Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Migrate `environments/all/home/` rsync content into home-manager. Native modules where they fit (`programs.git.ignores`, `programs.screen`); a single claude-style auto-discovery helper over a `home-files/home/` tree for the dotfiles + `bin/git-*` scripts; `home.file.text` (from a regular source file + darwin-gated `UseKeychain`) for `~/.ssh/config`. Delete the migrated sources; **keep the `homedir` bash plugin** (still serves `custom_environments/work/home/`).

**Architecture:** Single atomic `feat` commit: create `nix/profiles/all/home-files.nix` + `home-files/{home/<tree>,screenrc,ssh-config}` (the `home/` files moved via `git mv` from `environments/all/home/` where possible to preserve history), modify `nix/profiles/all/git.nix` (`+ignores`, `-core.excludesfile`), modify `nix/profiles/all/default.nix` (import), delete the remaining `environments/all/home/` files. A `docs` commit for `nix/README.md`. A verification task.

**Tech Stack:** Nix flakes, home-manager (`release-26.05`), `programs.git`, `programs.screen`, `home.file`, `lib.filesystem.listFilesRecursive`, `lib.hm.dag`, `pkgs.stdenv.isDarwin`.

---

## Notes for the executor

- **Reference spec:** `docs/superpowers/specs/2026-05-27-nix-homedir-design.md`. The decisions + full `home-files.nix` content + the `ssh-config` source are authoritative.
- **No automated tests.** Verification commands with expected output (Task 3).
- **Branch:** `nix-homedir`. Stacks on `nix-vscode` (#74) → … → master. **Do NOT merge.**
- **Sandbox disable** for `nix`, `git commit` (gpg), anything writing under `$HOME`. `nix eval` form: `nix eval "path:./nix#…"`.
- **`./apply` needs interactive sudo (TTY).** At the apply step, run eval gates first, then report NEEDS_CONTEXT and ask the user to run `./apply`. Resume after.
- **Flakes only see git-tracked files** — every new source file (the `home/` tree, `screenrc`, `ssh-config`) must be `git add`ed before `nix eval`, or eval won't see them.
- **Conventional commits**, no Claude attribution. **No push** without user approval.

### Pre-existing local state (assume)

- `~/.gemrc`, `~/.wgetrc`, `~/.screenrc`, `~/.hushlogin`, `~/.gitignore`, `~/.ssh/config` exist as regular files (rsynced).
- `~/bin/git-*` (8 scripts) exist, executable; `~/bin/steam` is a non-repo symlink (must NOT be shadowed).
- `~/.ssh/` has `id_rsa`, `id_rsa.pub`, `known_hosts`, `agent/` (live; untouched).
- `git config --get core.excludesfile` → `~/.gitignore`.
- `nix/profiles/all/git.nix:35` has `excludesfile = "~/.gitignore";` under `programs.git.settings.core`.
- `custom_environments/work/home/` has content (served by homedir; out of scope).

### Open-question gates (from spec)

1. **`discovered` attr names + executability (HARD GATE, pre-apply).** `nix eval` the produced `home.file` attr names; MUST be exactly the 11 — `.gemrc`, `.wgetrc`, `.hushlogin`, `bin/git-{cpr,delete-branch,last-commit-message,superprune,superrebase,touch,update-author,upush}` — plus `.ssh/config`, with NO `/nix/store/` leakage. The 8 `bin/*` must have `executable = true`, the dotfiles `false`. Do not apply until clean.
2. **`programs.git.ignores` / `excludesfile` (pre-apply).** `nix eval` `core.excludesFile` resolves to the HM-generated `~/.config/git/ignore` path, with no duplicate/conflict from a leftover `excludesfile` line.
3. **`programs.screen` package=null (pre-apply).** `nix eval` `home.packages` contains no `screen`.
4. **ssh perms (at-apply).** After apply, `ssh -G github.com` resolves correctly and ssh doesn't reject the `/nix/store` symlink config.

---

## Task 1: Atomic homedir migration

**Files:**
- Create: `nix/profiles/all/home-files.nix`
- Create (via `git mv` from `environments/all/home/`): `home-files/home/{.gemrc,.wgetrc,.hushlogin}`, `home-files/home/bin/git-*` (8), `home-files/screenrc` (from `.screenrc`), `home-files/ssh-config` (from `.ssh/config`, minus the `UseKeychain` line)
- Modify: `nix/profiles/all/git.nix`
- Modify: `nix/profiles/all/default.nix`
- Delete: remaining `environments/all/home/` (the `.gitignore`, and whatever `git mv` didn't move)

### Step-by-step

- [ ] **Step 1: Pre-flight capture**

```bash
{
  echo "=== target files (current, rsynced regular files) ==="
  ls -la ~/.gemrc ~/.wgetrc ~/.screenrc ~/.hushlogin ~/.gitignore ~/.ssh/config 2>&1
  echo "=== ~/bin (note steam symlink + 8 git-*) ==="
  ls -la ~/bin 2>&1
  echo "=== git excludesfile ==="
  git config --get core.excludesfile 2>&1
  echo "=== a sample bin script runs ==="
  ~/bin/git-superrebase --help 2>&1 | head -2 || echo "(no --help; existence ok)"
  echo "=== ssh resolves github ==="
  ssh -G github.com 2>&1 | grep -iE '^(user|hostname|preferredauthentications|usekeychain) '
} > "$TMPDIR/homedir-preflight.txt" 2>&1
cat "$TMPDIR/homedir-preflight.txt"
```

- [ ] **Step 2: Confirm starting file state**

```bash
ls environments/all/home/.gitignore environments/all/home/.gemrc environments/all/home/.wgetrc environments/all/home/.screenrc environments/all/home/.hushlogin environments/all/home/.ssh/config
ls environments/all/home/bin/
grep -n "excludesfile" nix/profiles/all/git.nix
grep -n "ignores" nix/profiles/all/git.nix || echo "(no ignores yet)"
```

Expected: all sources present; `excludesfile = "~/.gitignore";` at git.nix:35; no `ignores` yet.

- [ ] **Step 3: Move sources into the nix tree (preserve git history)**

```bash
mkdir -p nix/profiles/all/home-files/home/bin

# dotfiles → home/ tree
git mv environments/all/home/.gemrc     nix/profiles/all/home-files/home/.gemrc
git mv environments/all/home/.wgetrc    nix/profiles/all/home-files/home/.wgetrc
git mv environments/all/home/.hushlogin nix/profiles/all/home-files/home/.hushlogin

# bin scripts → home/bin/
for s in git-cpr git-delete-branch git-last-commit-message git-superprune git-superrebase git-touch git-update-author git-upush; do
  git mv "environments/all/home/bin/$s" "nix/profiles/all/home-files/home/bin/$s"
done

# screenrc → standalone (programs.screen source)
git mv environments/all/home/.screenrc nix/profiles/all/home-files/screenrc

# ssh config → standalone source; will need the UseKeychain line removed in Step 4
git mv environments/all/home/.ssh/config nix/profiles/all/home-files/ssh-config
```

Verify: `git status` shows the renames; `ls nix/profiles/all/home-files/home/ nix/profiles/all/home-files/home/bin/`.

- [ ] **Step 4: Strip the `UseKeychain` line from `home-files/ssh-config`**

The module appends `UseKeychain` conditionally (darwin-only), so remove it from the source file. Edit `nix/profiles/all/home-files/ssh-config`: delete the `UseKeychain yes` line and its preceding comment (`# Maintain macOS keychain/key-autoloading behavior` and the apple.stackexchange URL comment). The file's `host *` block should end with `IdentityFile ~/.ssh/id_rsa`.

After editing, the file should match the spec's `home-files/ssh-config` block (the `host *` block ends at `IdentityFile`). Verify:

```bash
grep -i usekeychain nix/profiles/all/home-files/ssh-config && echo "FAIL: still present" || echo "OK: UseKeychain removed"
tail -5 nix/profiles/all/home-files/ssh-config
```

Expected: `OK: UseKeychain removed`; the file ends with the `host *` block's `IdentityFile` line.

- [ ] **Step 5: Create `nix/profiles/all/home-files.nix`**

Use the exact module content from the spec ("`nix/profiles/all/home-files.nix` (full content)"):

```nix
{ pkgs, lib, ... }:
let
  homeTree = ./home-files/home;
  prefix = toString homeTree + "/";
  discovered = lib.listToAttrs (map
    (p:
      let rel = lib.removePrefix prefix (toString p);
      in lib.nameValuePair rel {
        source = p;
        executable = lib.hasPrefix "bin/" rel;
      })
    (lib.filesystem.listFilesRecursive homeTree));

  clearPaths = (builtins.attrNames discovered) ++ [ ".screenrc" ".ssh/config" ".gitignore" ];
in
{
  programs.screen = {
    enable = true;
    package = null;
    screenrc = ./home-files/screenrc;
  };

  home.file = discovered // {
    ".ssh/config".text =
      builtins.readFile ./home-files/ssh-config
      + lib.optionalString pkgs.stdenv.isDarwin "  UseKeychain              yes\n";
  };

  home.activation.clearLegacyHomedirFiles =
    lib.hm.dag.entryBefore [ "checkLinkTargets" ] (
      lib.concatMapStringsSep "\n"
        (rel: ''if [ -f "$HOME/${rel}" ] && [ ! -L "$HOME/${rel}" ]; then /bin/rm "$HOME/${rel}"; fi'')
        clearPaths
    );
}
```

- [ ] **Step 6: Modify `nix/profiles/all/git.nix`**

Two edits:
1. Remove the line `        excludesfile      = "~/.gitignore";` from the `programs.git.settings.core` block. Leave `attributesfile`, `precomposeunicode`, `trustctime`, `whitespace` intact.
2. Add `ignores` as a top-level `programs.git` option (after `includes`, before `settings`):

```nix
    ignores = [
      # Editor temp files
      "*.orig" "*.swp" "*~" ".*.swo" "*.pyc"
      # Archives
      "*.dmg" "*.gz" "*.iso" "*.rar" "*.tar" "*.zip"
      # Logs and databases
      "*.log" "*.sql" "*.sqlite"
      # OS generated files
      ".DS_Store" ".DS_Store?" ".Spotlight-V100" ".Trashes" "._*" "Icon?" "Thumbs.db" "Desktop.ini"
      # Eclipse/Aptana
      ".settings" ".project"
    ];
```

- [ ] **Step 7: Import `./home-files.nix` in `nix/profiles/all/default.nix`**

Add `./home-files.nix` to the imports (alphabetical, after `./gpg.nix`, before `./shells.nix`):

```nix
  imports = [
    ./cli-tools.nix
    ./dotfilesrc-cleanup.nix
    ./git.nix
    ./gpg.nix
    ./home-files.nix
    ./shells.nix
    ./vim.nix
  ];
```

- [ ] **Step 8: Stage new files + delete remaining sources**

```bash
git add nix/profiles/all/home-files.nix nix/profiles/all/home-files/
git rm environments/all/home/.gitignore
# remove the now-empty environments/all/home/ tree (git mv emptied the rest)
git status
ls -la environments/all/home/ 2>&1
```

Expected: `.gitignore` deleted; `environments/all/home/` empty (the `.ssh/` and `bin/` subdirs emptied by `git mv`). If empty dirs linger in the working tree, that's fine — git doesn't track them.

- [ ] **Step 9: HARD GATE — eval the discovered attr names + executability + git/screen**

```bash
SYSTEM="$(nix eval --raw --impure --expr builtins.currentSystem)"

echo "=== home.file attr names (claude/ssh/bin/dotfiles) ==="
nix eval --json "path:./nix#homeConfigurations.default@${SYSTEM}.config.home.file" --apply 'builtins.attrNames' 2>&1 | tr ',' '\n' | grep -E '\.gemrc|\.wgetrc|\.hushlogin|\.ssh/config|bin/git-'

echo "=== executable bits ==="
nix eval --json "path:./nix#homeConfigurations.default@${SYSTEM}.config.home.file" \
  --apply 'fs: builtins.listToAttrs (map (n: { name = n; value = fs.${n}.executable or null; }) (builtins.filter (n: builtins.match "(bin/git-.*|\\.gemrc|\\.wgetrc|\\.hushlogin)" n != null) (builtins.attrNames fs)))' 2>&1 | tail -20

echo "=== core.excludesFile (should be HM-generated path, not ~/.gitignore) ==="
nix eval --raw "path:./nix#homeConfigurations.default@${SYSTEM}.config.programs.git.settings.core.excludesFile" 2>&1 | tail -2 || \
  nix eval "path:./nix#homeConfigurations.default@${SYSTEM}.config.home.file.\".config/git/ignore\".source" 2>&1 | tail -2

echo "=== screen NOT in home.packages ==="
nix eval --json "path:./nix#homeConfigurations.default@${SYSTEM}.config.home.packages" --apply 'ps: builtins.any (p: builtins.match ".*screen.*" (p.name or "") != null) ps' 2>&1 | tail -1
```

Expected:
- The 11 names appear: `.gemrc`, `.wgetrc`, `.hushlogin`, `.ssh/config`, and `bin/git-*` (×8). No `/nix/store/` in any name.
- `bin/git-*` entries → `executable = true`; `.gemrc`/`.wgetrc`/`.hushlogin` → `false`.
- `core.excludesFile` resolves to a `~/.config/git/ignore` (or `/nix/store/...git/ignore`) path — NOT `~/.gitignore`.
- screen-in-packages check → `false`.

If any fails, fix per the spec's open-question fallbacks and re-eval. Do NOT proceed to apply until green.

- [ ] **Step 10: Full flake eval**

```bash
SYSTEM="$(nix eval --raw --impure --expr builtins.currentSystem)"
nix flake check --no-build path:./nix 2>&1 | tail -20
nix eval "path:./nix#homeConfigurations.default@${SYSTEM}.config.home.activationPackage.drvPath" 2>&1 | tail -3
# Also eval the agent (Linux) profile to confirm UseKeychain is omitted there:
nix eval "path:./nix#homeConfigurations.agent@x86_64-linux.config.home.activationPackage.drvPath" 2>&1 | tail -3
```

Expected: all succeed. (The agent eval confirms the darwin-conditional ssh config builds on Linux too.)

Optional — confirm the darwin gate works by reading the generated ssh config text for each platform:

```bash
nix eval --raw "path:./nix#homeConfigurations.default@aarch64-darwin.config.home.file.\".ssh/config\".text" 2>&1 | grep -i usekeychain && echo "darwin: has UseKeychain (correct)"
nix eval --raw "path:./nix#homeConfigurations.agent@x86_64-linux.config.home.file.\".ssh/config\".text" 2>&1 | grep -i usekeychain && echo "linux: UNEXPECTED UseKeychain" || echo "linux: no UseKeychain (correct)"
```

- [ ] **Step 11: Run `./apply`**

Needs interactive sudo. Report NEEDS_CONTEXT, ask the user to run `./apply`, resume from Step 12.

- [ ] **Step 12: Verify managed files are symlinks; legacy cleared**

```bash
for f in .gemrc .wgetrc .hushlogin .screenrc .ssh/config; do
  echo -n "~/$f: "; [ -L "$HOME/$f" ] && echo "symlink OK" || echo "NOT a symlink (FAIL)"
done
for s in git-cpr git-delete-branch git-last-commit-message git-superprune git-superrebase git-touch git-update-author git-upush; do
  echo -n "~/bin/$s: "; { [ -L "$HOME/bin/$s" ] && [ -x "$HOME/bin/$s" ]; } && echo "symlink+exec OK" || echo "FAIL"
done
echo -n "~/.gitignore (should be GONE): "; [ -e "$HOME/.gitignore" ] && echo "STILL PRESENT (check)" || echo "gone OK"
```

Expected: all dotfiles + ssh config + bin scripts are symlinks; bin scripts executable; `~/.gitignore` gone.

- [ ] **Step 13: Verify invariants — steam symlink + ssh keys untouched; git ignore works**

```bash
echo -n "~/bin/steam (must be untouched non-repo symlink): "; ls -la "$HOME/bin/steam" 2>&1
echo -n "~/.ssh/id_rsa untouched: "; ls -la "$HOME/.ssh/id_rsa" 2>&1 | head -1
echo "=== git global ignore active ==="
git config --get core.excludesFile
git check-ignore -v /tmp/foo.swp 2>&1 || (cd /tmp && touch foo.swp && git -C "$HOME" check-ignore -v "$HOME/foo.swp" 2>&1; rm -f /tmp/foo.swp)
echo "=== ssh resolves github (User=git) + UseKeychain on macOS ==="
ssh -G github.com 2>&1 | grep -iE '^(user|preferredauthentications|usekeychain) '
echo "=== screen rc present, screen still runs ==="
ls -la "$HOME/.screenrc"; command -v screen && screen --version 2>&1 | head -1
```

Expected: `steam` symlink unchanged; `id_rsa` unchanged; `core.excludesFile` → HM path; `*.swp` is ignored; `ssh -G github.com` shows `user git` and (on macOS) `usekeychain yes`; `~/.screenrc` is a symlink; system `screen` runs.

- [ ] **Step 14: Verify framework state**

```bash
ls -la environments/all/home/ 2>&1 || echo "(gone)"
grep -n DOTFILES_HOMEDIR_DEPS plugins/homedir/homedir   # unchanged: ()
echo "homedir plugin still present:"; ls plugins/homedir/homedir
```

Expected: `environments/all/home/` empty/gone; homedir plugin unchanged and present (still serves custom_environments).

- [ ] **Step 15: Stage and commit**

```bash
git add nix/profiles/all/home-files.nix nix/profiles/all/home-files/ nix/profiles/all/git.nix nix/profiles/all/default.nix
git add -u
git status
git commit -m "$(cat <<'EOF'
feat(nix): migrate environments/all/home rsync content to home-manager

Move the universal rsync dotfiles into home-manager: global gitignore →
programs.git.ignores (dropping core.excludesfile), .screenrc → programs.screen
(package=null), and .gemrc/.wgetrc/.hushlogin + the ~/bin/git-* scripts via a
single auto-discovery helper over a home-files/home/ tree mirroring $HOME
(executable bit derived from the bin/ prefix; per-file so ~/bin/steam isn't
shadowed). ~/.ssh/config is read from a source file with the macOS-only
UseKeychain line appended via pkgs.stdenv.isDarwin.

A derived activation clears the legacy rsynced regular files (no backup — exact
tracked copies) so home-manager can link the managed versions.

The homedir bash plugin stays: it still rsyncs custom_environments/<env>/home/,
which migrates in a later slice.
EOF
)"
```

Sandbox disable for gpg. No Claude attribution.

- [ ] **Step 16: Verify commit + compare pre-flight**

```bash
git log --oneline -1
git show --stat HEAD | head -40
diff "$TMPDIR/homedir-preflight.txt" <(
  ls -la ~/.gemrc ~/.wgetrc ~/.screenrc ~/.hushlogin ~/.ssh/config 2>&1
  ls -la ~/bin/steam 2>&1
  git config --get core.excludesFile 2>&1
) 2>&1 | head -30 || true
```

Expected: commit shows renames (`environments/all/home/*` → `nix/profiles/all/home-files/...`), git.nix/default.nix modified, `.gitignore` deleted. Pre-flight diff: the 5 dotfiles/ssh flipped to symlinks; `steam` unchanged; excludesfile → HM path.

---

## Task 2: Update `nix/README.md`

**Files:** Modify `nix/README.md`.

- [ ] **Step 1: Locate** the "For the nix-vscode slice" block (`grep -n "For the nix-vscode slice" nix/README.md`); insert after it (before the closing "The same shape applies to future slices" paragraph).

- [ ] **Step 2: Insert** the spec's "For the nix-homedir slice" block verbatim (paragraph-heading style, no `###`).

- [ ] **Step 3: Verify** `grep -nE "^For the nix-homedir slice" nix/README.md` → one paragraph-form match.

- [ ] **Step 4: Commit** `git add nix/README.md && git commit -m "docs(nix): document nix-homedir slice migration"` (sandbox disable for gpg).

- [ ] **Step 5: Verify** `git log --oneline -3`.

---

## Task 3: Cross-slice verification

- [ ] **Step 1:** Clean reapply (user-run if needed): `./apply 2>&1 | tee /tmp/homedir-slice-apply.log`; inspect for warnings.
- [ ] **Step 2:** Re-confirm invariants from Task 1 Steps 12-14 (symlinks, steam untouched, ssh keys untouched, git ignore active, screen runs, homedir plugin present).
- [ ] **Step 3:** Confirm `environments/all/home/` is gone and `custom_environments/work/home/` still rsyncs on apply (homedir plugin functional): `DOTFILES_DEBUG=1 ./apply 2>&1 | grep -i "Rsyncing.*work/home" || echo "(check homedir still serves work env)"`.
- [ ] **Step 4:** Confirm commit shape: `git log --oneline nix-vscode..HEAD` → spec + feat + docs.
- [ ] **Step 5:** Update `docs/superpowers/nix-migration-status.md` (LOCAL ONLY): slice 15 nix-homedir added; note homedir plugin remains (serves custom_environments); `environments/all/home/` emptied.
- [ ] **Step 6:** Open PR (gated on explicit user approval — memory `ask-before-merging`). `git push -u origin nix-homedir`; `gh pr create --base nix-vscode --title "feat(nix): migrate all/home rsync content to home-manager" --body "..."`.

---

## Self-review against the spec

- Decision 1 (native where fits): git.ignores + screen native (Steps 5-6); rest home.file.
- Decision 2 (gitignore → programs.git.ignores, drop excludesfile): Step 6.
- Decision 3 (screen, package=null): Step 5.
- Decision 4 (ssh as readFile + darwin gate): Step 5 + Step 4 (strip UseKeychain from source).
- Decision 5 (auto-discovery for dotfiles+bin): Step 5 `discovered`.
- Decision 6 (screenrc/ssh-config standalone specials): Steps 3-5.
- Decision 7 (derived clear list, no backup): Step 5 `clearPaths` + `clearLegacyHomedirFiles`.
- Decision 8 (all profile): home-files.nix in profiles/all, imported by all/default.nix.
- Decision 9 (keep homedir plugin): not touched (Step 14 confirms).
- Decision 10 (delete migrated sources): Steps 3, 8.
- Decision 11 (no work-specific values): none.

Placeholder scan: exact commands/code throughout. Type consistency: `discovered`, `clearPaths`, `clearLegacyHomedirFiles`, `homeTree` consistent.

## Cross-references

- Design spec: `docs/superpowers/specs/2026-05-27-nix-homedir-design.md`
- Prior slice plan: `docs/superpowers/plans/2026-05-27-nix-claude.md`
