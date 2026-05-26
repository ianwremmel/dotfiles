# Nix Node.js Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Switch Node.js version management from nvm (curl-installed bash) to fnm (Rust-based, packaged in nixpkgs) via home-manager's `programs.fnm`, with a marker-gated activation that auto-installs the LTS node on first apply so fresh-bootstrap machines have a working `node` without manual intervention. Retire `plugins/nvm/` and `plugins/node/`. Remove the two temporary `nvm.sh`-load blocks Slice 6 left in `nix/profiles/all/shells.nix`.

**Architecture:** Single atomic feat commit edits `nix/profiles/all/shells.nix` (adds `programs.fnm.enable = true`, adds `installFnmDefaultNode` activation, removes 2 nvm-load blocks) and deletes both bash plugins. A second commit updates `nix/README.md`. A third task is verification-only (throwaway override + Linux container).

**Tech Stack:** Bash 5, Nix flakes, home-manager (`programs.fnm`, `lib.hm.dag.entryAfter`), fnm 1.x, Node.js LTS (whatever fnm resolves at activation time).

---

## Notes for the executor

- **Reference spec:** `docs/superpowers/specs/2026-05-25-nix-nodejs-design.md`.
- **No automated test framework.** "Tests" are verification commands with expected output.
- **Branch:** `nix-nodejs`. Stacks on `nix-prompt` (PR #67) → `nix-shells` (PR #66) → `nix-commit-signing` (PR #65) → `nix-git` (PR #64) → `nix-profiles` (PR #63) → `nix-cross-platform` (PR #62) → `master`. **Do NOT merge anything.**
- **Stacking machinery** (assumed working from prior slices): `homeModules.{base,all,default,agent}`, `lib.mkHome`, profile-module layering, `--override-input public path:…` private-flake idiom, `home.activation.*` style migrations, `nix/host.nix` (untracked).
- **Sandbox disable required for:** `nix`, `./apply`, `git commit` (gpg signing), `~/.nvm/` reads. Use `dangerouslyDisableSandbox: true`. If `nix` isn't on PATH, prepend `source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh`.
- **Run commands from repo root** (`/Users/ian/projects/dotfiles`).
- **Pre-existing local state:**
  - `nix/host.nix` = `{ username = "ian"; profile = "default"; }`, untracked.
  - `~/.dotfilesrc` contains `DOTFILES_ENVIRONMENT=default`.
  - `~/.nvm/` exists as a real cloned git repo with nvm 0.40.4.
  - `node --version` returns `v24.13.0` (nvm-managed; `~/.nvm/versions/node/v24.13.0/bin/node`).
  - `~/.fnm-default-node.hm-migrated` marker does NOT exist.
  - Brew has `jq` installed (declared by `plugins/nvm/Brewfile`).
- **Conventional commits**, NO `Co-Authored-By: Claude` / `Generated with Claude Code` trailers.
- **No work-specific values** in any committed file.

---

## Task 1: Atomic nodejs migration (`programs.fnm` + activation + remove nvm-load + plugin deletions)

Single atomic commit so the repo never sits in a state where the temp nvm blocks reference deleted plugins or where fnm is enabled but the old nvm blocks still try to source the (still-present-but-unsourced) `~/.nvm/`.

**Files:**

- Modify: `nix/profiles/all/shells.nix` — add `programs.fnm.enable`, add `installFnmDefaultNode` activation, remove 2 nvm-load blocks.
- Delete: `plugins/nvm/nvm`, `plugins/nvm/Brewfile`, and the now-empty `plugins/nvm/` directory.
- Delete: `plugins/node/node` and the now-empty `plugins/node/` directory.

- [ ] **Step 1: Capture pre-flight state**

Run (sandbox disabled):

```bash
echo "=== nvm state ==="
ls -d "$HOME/.nvm" 2>&1
[ -d "$HOME/.nvm" ] && (source "$HOME/.nvm/nvm.sh"; nvm --version) 2>&1
echo ""
echo "=== node state ==="
which node
node --version 2>&1
echo ""
echo "=== fnm state (expected: absent) ==="
command -v fnm 2>&1 || echo "absent"
echo ""
echo "=== markers ==="
ls -la "$HOME/.fnm-default-node.hm-migrated" 2>&1 | head -1
echo ""
echo "=== current generated shells source nvm? ==="
grep -nE 'nvm\.sh|NVM_DIR|fnm' "$HOME/.zshrc" "$HOME/.bashrc" 2>&1 | head -10
```

Expected: nvm 0.40.4 present; node v24.13.0 at `~/.nvm/versions/node/v24.13.0/bin/node`; fnm absent; marker absent; `.zshrc` and `.bashrc` contain the nvm.sh source lines from Slice 6.

- [ ] **Step 2: Read current shells.nix to confirm starting state**

Run: `wc -l nix/profiles/all/shells.nix; grep -n 'nvm\.sh\|NVM_DIR\|fnm' nix/profiles/all/shells.nix`

Expected: ~416 lines; the two nvm-load blocks are found (one in `programs.bash.profileExtra` around lines 178–181, one in `programs.zsh.initContent` around lines 289–293); no fnm references yet.

- [ ] **Step 3: Edit `shells.nix` — remove the nvm-load block in `programs.bash.profileExtra`**

Find this block (around lines 176–181, inside `programs.bash.profileExtra`):

```nix
      # ---- non-interactive tail of .bash_profile (interactive guard below) ----

      # Setup nvm and node so prompt can use it
      if [ -d "$HOME/.nvm" ]; then
        source "$HOME/.nvm/nvm.sh"
      fi

      # If not interactive, stop further processing
```

Replace with:

```nix
      # ---- non-interactive tail of .bash_profile (interactive guard below) ----

      # If not interactive, stop further processing
```

(The 4 lines from `# Setup nvm and node` through the closing `fi` plus the trailing blank are all removed; the `# ---- non-interactive tail …` comment and the `# If not interactive` comment that surround it stay.)

- [ ] **Step 4: Edit `shells.nix` — remove the nvm-load block in `programs.zsh.initContent`**

Find this block (around lines 286–294, inside `programs.zsh.initContent`):

```nix
      # ---- from .zshrc.d/omz_ls-colors.zsh ----
    '' + (builtins.readFile ./omz_ls-colors.zsh) + ''

      # ---- from .zshrc.d/omz_nvm.sh (8 lines; retired in Slice 8) ----
      # Set NVM_DIR if it isn't already defined
      [[ -z "$NVM_DIR" ]] && export NVM_DIR="$HOME/.nvm"
      # Load nvm if it exists
      [[ -f "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"

      # ---- from .zshrc.d/omz_termsupport.zsh ----
    '' + (builtins.readFile ./omz_termsupport.zsh) + ''
```

Replace with:

```nix
      # ---- from .zshrc.d/omz_ls-colors.zsh ----
    '' + (builtins.readFile ./omz_ls-colors.zsh) + ''

      # ---- from .zshrc.d/omz_termsupport.zsh ----
    '' + (builtins.readFile ./omz_termsupport.zsh) + ''
```

(The 6-line `omz_nvm.sh` block and its leading blank are gone; the surrounding `omz_ls-colors.zsh` and `omz_termsupport.zsh` blocks are unchanged.)

- [ ] **Step 5: Edit `shells.nix` — add the `programs.fnm` block**

Find the `# ---------- Starship prompt ----------` block (where `programs.starship = { … };` lives). Add IMMEDIATELY AFTER the closing `};` of the `programs.starship` block (and before the `# ---------- Activation: …` section):

```nix
  # ---------- fnm (Node.js version manager) ----------
  programs.fnm = {
    enable = true;
    # No settings overrides — opt in to fnm's defaults. enableBashIntegration
    # and enableZshIntegration default to true, so home-manager injects
    # `eval "$(fnm env --shell …)"` into the generated .bashrc and .zshrc.
    # fnm's data dir defaults to ~/.local/share/fnm-node; node versions
    # installed by `fnm install …` live there independently of nixpkgs and
    # persist across home-manager generations.
  };

```

- [ ] **Step 6: Edit `shells.nix` — add `installFnmDefaultNode` activation**

Find the closing `'';` of the LAST `home.activation.*` block in the file (likely `migrateLegacyP10kConfig` from Slice 7). Add IMMEDIATELY AFTER it (before the final `}` of the module):

```nix

  # ---------- Activation: bootstrap default LTS node via fnm ----------
  home.activation.installFnmDefaultNode = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # One-time bootstrap: install the LTS node version via fnm so a fresh
    # machine has node available without manual `fnm install`. Marker-gated.
    # Activation scripts run with a stripped PATH; use the absolute store
    # path for fnm to avoid PATH gymnastics. Network call; failures leave
    # the marker absent so a later apply can retry.
    if [ ! -e "$HOME/.fnm-default-node.hm-migrated" ]; then
      if ${pkgs.fnm}/bin/fnm install --lts && \
         ${pkgs.fnm}/bin/fnm default lts-latest; then
        run touch "$HOME/.fnm-default-node.hm-migrated"
        echo "Installed default LTS node via fnm (one-time bootstrap)"
      else
        echo "fnm bootstrap failed; will retry on next ./apply"
      fi
    fi
  '';
```

Note: the `${pkgs.fnm}` references are Nix-side interpolation (the leading `${` here is the Nix antiquotation operator, NOT shell expansion). Inside a `''…''` indented string, Nix antiquotation uses `${…}` directly; shell expansions like `${VAR}` would need `''${VAR}` to escape. Don't double-escape `${pkgs.fnm}`.

- [ ] **Step 7: Delete `plugins/nvm/`**

```bash
git rm plugins/nvm/nvm plugins/nvm/Brewfile
rmdir plugins/nvm 2>/dev/null || true
ls -d plugins/nvm 2>&1 | head -1
```

Expected: `ls: cannot access 'plugins/nvm'`.

- [ ] **Step 8: Delete `plugins/node/`**

```bash
git rm plugins/node/node
rmdir plugins/node 2>/dev/null || true
ls -d plugins/node 2>&1 | head -1
```

Expected: `ls: cannot access 'plugins/node'`.

- [ ] **Step 9: Verify `shells.nix` parses + flake evaluates**

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

- [ ] **Step 10: Run the plugin to activate**

Run (sandbox disabled — activation makes a network call to fetch the LTS node tarball, takes 30-60s):

```bash
DOTFILES_ENVIRONMENT=default DOTFILES_ROOT_DIR="$PWD" bash -c '
  set -euo pipefail
  source framework/logging
  source plugins/nix/nix
  dotfiles_nix_apply
' 2>&1 | tail -30
```

Expected: activation succeeds. Output includes `Activating installFnmDefaultNode` and `Installed default LTS node via fnm (one-time bootstrap)`. No errors. Total runtime depends on network speed.

If activation succeeds but the network call fails, the output will show `fnm bootstrap failed; will retry on next ./apply` — the marker is left absent and the next apply retries. That's an acceptable outcome for this step; proceed to Step 11 with awareness.

- [ ] **Step 11: Verify fnm and the LTS node are installed**

```bash
echo "=== marker ==="
ls -l "$HOME/.fnm-default-node.hm-migrated" 2>&1 | head -1
echo ""
echo "=== fnm on PATH ==="
which fnm
readlink "$(which fnm)" 2>&1 | head -1
fnm --version
echo ""
echo "=== fnm-installed node versions ==="
fnm list 2>&1
echo ""
echo "=== node via fnm shim ==="
which node
node --version
```

Expected: marker exists; fnm at `~/.nix-profile/bin/fnm` → `/nix/store/…-fnm-*/bin/fnm`; `fnm list` shows the LTS version (probably v22.x.y or v24.x.y — depends on what fnm calls "lts-latest" at activation time); `which node` resolves to `~/.local/share/fnm-node/aliases/default/bin/node` (or similar fnm-managed path); `node --version` reports the LTS version.

- [ ] **Step 12: Verify generated `~/.zshrc` and `~/.bashrc` source fnm init (not nvm)**

```bash
echo "=== zsh fnm integration ==="
grep -n 'fnm env\|fnm\.sh' "$HOME/.zshrc" | head -3
echo ""
echo "=== bash fnm integration ==="
grep -n 'fnm env\|fnm\.sh' "$HOME/.bashrc" | head -3
echo ""
echo "=== nvm refs gone ==="
grep -nE 'nvm\.sh|NVM_DIR' "$HOME/.zshrc" "$HOME/.bashrc" 2>&1 | head -5
[ -z "$(grep -lE 'nvm\.sh|NVM_DIR' "$HOME/.zshrc" "$HOME/.bashrc" 2>/dev/null)" ] && echo "(clean — no nvm references)" || echo "WARN: nvm references remain"
```

Expected: each shell rc has a `fnm env` line; no `nvm.sh` or `NVM_DIR` references remain.

- [ ] **Step 13: Verify fresh shells get node via fnm**

```bash
echo "=== fresh zsh ==="
zsh -ic 'which node; node --version' 2>&1 | grep -v gitstatus | head -5
echo ""
echo "=== fresh bash ==="
bash -lic 'which node; node --version' 2>&1 | head -5
```

Expected: both shells resolve `node` to a fnm-managed path (under `~/.local/share/fnm-node/`); version matches the LTS that activation installed.

- [ ] **Step 14: Cross-slice integrity check**

```bash
git config --get alias.fixup            # Slice 1
git config --get user.signingkey         # Slice 5
git config --get commit.gpgsign          # Slice 5
git --version | head -1                  # Slice 5 nixpkgs bump → 2.54.0
gpg --version | head -1                  # Slice 5
bat --version | head -1                  # Slice 1
which starship                           # Slice 7
zsh -ic 'alias psgrep' 2>&1 | grep -v gitstatus  # Slice 6
bash -lic 'alias psgrep' 2>&1 | head -5  # Slice 6
```

Expected: all return their expected values; no regressions.

- [ ] **Step 15: Activation idempotency check**

```bash
DOTFILES_ENVIRONMENT=default DOTFILES_ROOT_DIR="$PWD" bash -c '
  source framework/logging
  source plugins/nix/nix
  dotfiles_nix_apply
' 2>&1 | grep -E 'Installed default LTS|fnm bootstrap|installFnmDefaultNode' || echo "(no bootstrap output — guard short-circuited, as expected)"
ls -l "$HOME/.fnm-default-node.hm-migrated"
```

Expected: `(no bootstrap output — guard short-circuited, as expected)`. Marker mtime unchanged. fnm install is not re-run.

- [ ] **Step 16: Commit the atomic migration**

```bash
git add nix/profiles/all/shells.nix
git status --porcelain
git -c gpg.program="$(which gpg)" commit -m "feat(nix): switch node version management from nvm to fnm"
git log --oneline -1
```

Expected: `git status --porcelain` shows `M nix/profiles/all/shells.nix`, `D plugins/nvm/nvm`, `D plugins/nvm/Brewfile`, `D plugins/node/node` (four entries). Commit succeeds, GPG-signed. Conventional message, no `Co-Authored-By` trailer.

---

## Task 2: README updates

Three changes to `nix/README.md`.

**Files:**

- Modify: `nix/README.md`

- [ ] **Step 1: Locate insertion points**

```bash
grep -n '^For the prompt slice' nix/README.md
grep -n '^## Background\|^## Install' nix/README.md
grep -n '^### Public profiles and layers' nix/README.md
grep -n 'AND starship as the prompt' nix/README.md
```

Expected: `For the prompt slice` is the most recent sub-block (from Slice 7); the new "For the nodejs slice" goes after its item 3 and before `The same shape applies to future slices`.

- [ ] **Step 2: Insert the "For the nodejs slice" sub-block**

In `nix/README.md`, find the paragraph where the prompt slice's item 3 ends with `…when you're done with the migration.`. Immediately AFTER that paragraph and BEFORE the line beginning `The same shape applies to future slices`, insert this block:

```markdown
For the nodejs slice (`nvm` and `node` plugins retired; fnm via
`programs.fnm.enable` takes over; `home.activation.installFnmDefaultNode`
auto-installs the LTS node on first apply):

1. **No private flake changes needed** unless you have custom node
   configuration. To override fnm defaults (e.g., a specific
   `nodeDistMirror` for enterprise networks), add to your private flake:

       { lib, pkgs, ... }: {
         programs.fnm.nodeDistMirror = "https://your.mirror/dist/";
       }

2. **Optional cleanup after first apply:**

       rm -rf ~/.nvm           # the cloned nvm repo + installed node versions
       brew uninstall jq       # if you don't otherwise need jq

3. **To upgrade past the originally-installed LTS** (when Node 26
   becomes LTS, etc.):

       rm ~/.fnm-default-node.hm-migrated
       ./apply
       # OR interactively:
       fnm install --lts
       fnm default lts-latest

4. **To pin a different default version per environment**, post-apply:

       fnm install <version>
       fnm default <version>

   The marker file prevents the activation from re-overriding this.

```

(Note the trailing blank line — separates this sub-block from the next paragraph.)

- [ ] **Step 3: Refresh the Background paragraph**

Find the `So far this manages:` sentence in `## Background`. The sentence currently ends with `…replacing the retired \`powerlevel\` plugin and its rsync'd \`.p10k.zsh\`).` (from Slice 7). Append before the period:

```
; and Node.js — fnm via `programs.fnm` (replacing the retired `nvm` and `node` plugins), with a one-time activation that installs the LTS version on first apply
```

So the segment becomes: `…replacing the retired \`powerlevel\` plugin and its rsync'd \`.p10k.zsh\`); and Node.js — fnm via \`programs.fnm\` (replacing the retired \`nvm\` and \`node\` plugins), with a one-time activation that installs the LTS version on first apply.`

- [ ] **Step 4: Refresh the `all`-layer parenthetical under `### Public profiles and layers`**

Find the bullet beginning `- \`all\` — always included via \`mkHome\`;`. Its current parenthetical ends with `…AND starship as the prompt)` (Slice 7). Replace the closing `)` with `, AND fnm for Node.js version management)`:

```
(currently `bat`, the shared git config — aliases, body, includes — via `programs.git`, GPG/agent setup with per-OS pinentry: `pinentry-mac` on macOS, `pinentry-tty` on Linux, bash + zsh via `programs.bash` + `programs.zsh` plus `.inputrc` via `home.file`, AND starship as the prompt, AND fnm for Node.js version management)
```

- [ ] **Step 5: Verify the changes**

```bash
grep -n 'For the nodejs slice' nix/README.md
grep -n 'fnm via `programs.fnm`' nix/README.md
grep -n 'AND fnm for Node.js' nix/README.md
echo "=== fence balance (probably 0 since README uses indented blocks) ==="
grep -c '^```' nix/README.md
```

Expected: each grep returns at least one match; fence count is 0 or even.

- [ ] **Step 6: Commit**

```bash
git add nix/README.md
git -c gpg.program="$(which gpg)" commit -m "docs(nix): document nodejs slice (fnm) + private-env migration"
git log --oneline -3
```

Expected: commit succeeds, GPG-signed. Top commits: this docs commit + the feat commit + earlier spec/plan commits.

---

## Task 3: End-to-end verification (throwaway override + Linux container)

No commits.

**Files:** none committed.

- [ ] **Step 1: Throwaway private-profile fnm override (macOS)**

```bash
mkdir -p custom_environments/throwaway/nix
cat > custom_environments/throwaway/nix/flake.nix <<'EOF'
{
  description = "Throwaway test profile (fnm-settings override)";

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
  # Override fnm's nodeDistMirror as an exercise of the option-override path.
  # The default mirror is the same value; this is a no-op functionally but
  # verifies private-flake additivity works.
  programs.fnm.nodeDistMirror = "https://nodejs.org/dist/";
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

echo "=== fnm still works under throwaway profile ==="
fnm --version
fnm list 2>&1 | head -5
zsh -ic 'node --version' 2>&1 | grep -v gitstatus | head -3
```

Expected: throwaway activation succeeds. fnm still works; node version unchanged from Task 1's install (marker already set; activation short-circuits).

- [ ] **Step 2: Tear down**

```bash
rm -rf custom_environments/throwaway

DOTFILES_ENVIRONMENT=default DOTFILES_ROOT_DIR="$PWD" bash -c '
  set -euo pipefail
  source framework/logging
  source plugins/nix/nix
  dotfiles_nix_apply
' 2>&1 | tail -8

echo "=== working tree clean? ==="
git status --porcelain
echo ""
echo "=== fnm + node still work ==="
fnm --version
zsh -ic 'node --version' 2>&1 | grep -v gitstatus | head -3
```

Expected: `git status --porcelain` clean (custom_environments is gitignored); fnm + node still functional.

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
  echo "=== fnm installed and on nix profile ==="
  ls -l "$HOME/.nix-profile/bin/fnm" 2>&1 | head -1
  echo ""
  echo "=== installFnmDefaultNode ran ==="
  ls -la "$HOME/.fnm-default-node.hm-migrated" 2>&1 | head -1
  echo ""
  echo "=== node via fnm in fresh bash ==="
  bash -lic "node --version" 2>&1 | head -3
  echo ""
  echo "=== no .nvm/ (clean container) ==="
  ls -d "$HOME/.nvm" 2>&1 | head -1 || echo "(no .nvm — correct)"
'
```

Expected: container builds; agent profile activates; fnm installed in nix profile; activation ran and installed LTS node (or printed retry-on-failure message if network was slow); `bash -lic 'node --version'` returns the LTS version; no `~/.nvm/` on the clean container.

**Possible failure modes:**

- Docker not running. `docker info` first. Skip Step 3 if Docker unavailable.
- Network slow inside container; `fnm install --lts` may take longer than usual. Activation prints `Installed default LTS node via fnm` on success.
- Two attempts max for transient failures.

- [ ] **Step 4: Final state check**

```bash
git log --oneline master..nix-nodejs | head -5
git status --porcelain
echo "=== ~/.nvm/ still on disk (left alone) ==="
ls -d "$HOME/.nvm" 2>&1 | head -1
echo "=== fnm-managed node ==="
fnm list 2>&1
echo "=== marker ==="
ls -l "$HOME/.fnm-default-node.hm-migrated"
```

Expected: branch contains the slice's commits (spec + plan + feat + docs). Working tree clean. `~/.nvm/` still present (we don't touch it). fnm shows the installed LTS. Marker present.

---

## Self-review (completed by plan author)

- **Spec coverage:**
  - Decision 1 (switch nvm → fnm): Task 1 Step 5 ✓
  - Decision 2 (fnm-only; no parallel `pkgs.nodejs_X`): Task 1 Step 5 (only `programs.fnm.enable` added; no `home.packages` change) ✓
  - Decision 3 (auto-install LTS via activation, marker-gated, retry-on-failure): Task 1 Step 6 ✓
  - Decision 4 (absolute store path `${pkgs.fnm}/bin/fnm` for PATH-independence): Task 1 Step 6 ✓
  - Decision 5 (DAG `entryAfter [ "writeBoundary" ]`): Task 1 Step 6 ✓
  - Decision 6 (leave `~/.nvm/` alone): Task 1 doesn't touch it; README documents manual rm ✓
  - Decision 7 (delete `plugins/nvm/Brewfile`): Task 1 Step 7 ✓
  - Decision 8 (no work-specific values): Task 2 sub-block is pattern-only ✓
  - Removed content: 2 nvm-load blocks (Task 1 Steps 3, 4) ✓
  - README updates (sub-block + Background + all-layer): Task 2 ✓
  - Throwaway + Linux container verification: Task 3 ✓
- **Placeholder scan:** every step has concrete commands or code blocks. The `${pkgs.fnm}/bin/fnm` references are real Nix antiquotation (not placeholders). No TBDs.
- **Type/name consistency:**
  - `programs.fnm.enable` — consistent throughout.
  - `home.activation.installFnmDefaultNode` — consistent.
  - `~/.fnm-default-node.hm-migrated` marker — consistent.
  - `lib.hm.dag.entryAfter [ "writeBoundary" ]` — different DAG edge from prior slices' `entryBefore [ "checkLinkTargets" ]`, but rationale is documented in the spec and in the script's comment.
  - `${pkgs.fnm}/bin/fnm` — consistent.
- **Atomicity:** Task 1 is one commit (1 file modified + 3 files deleted). Task 2 is one commit. Task 3 has no commits. Total: 2 new feat/docs commits + the prior spec + plan commits = 4 commits on this slice.
