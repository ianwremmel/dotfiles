# Nix Node.js Slice Design

**Date:** 2026-05-25
**Status:** Implemented
**Branch:** `nix-nodejs` (stacks on `nix-prompt` / PR #67 → `nix-shells` / PR #66 → `nix-commit-signing` / PR #65 → `nix-git` / PR #64 → `nix-profiles` / PR #63 → `nix-cross-platform` / PR #62)

## Goal

Retire `plugins/nvm/` and `plugins/node/` by switching Node.js version management from nvm (curl-installed bash script + dynamic GitHub-API version polling) to fnm (Rust-based, packaged in nixpkgs, declaratively managed via home-manager's `programs.fnm`). A marker-gated home-manager activation installs the LTS Node version on first apply so fresh-bootstrap machines have a working `node` without manual intervention. The two temporary `nvm.sh`-load blocks Slice 6 left in `nix/profiles/all/shells.nix` are removed.

This is **Slice 8** in the Nix migration and the final slice of the shell ecosystem.

## Post-implementation notes

The shipped implementation differs from this spec in one notable way:

- **`programs.fnm` doesn't exist in home-manager 26.05.** The spec assumed it did. The implementation correctly adapted by using `home.packages = [ pkgs.fnm ]` plus manual `eval "$(${pkgs.fnm}/bin/fnm env --use-on-cd --shell <shell>)"` injection into `programs.bash.bashrcExtra` and `programs.zsh.initContent`. Functionally equivalent to what a `programs.fnm.enable = true` would have produced. Private-flake overrides set fnm-specific env vars (`FNM_NODE_DIST_MIRROR`, etc.) via `programs.{bash,zsh}.{profileExtra,envExtra}` rather than via typed `programs.fnm.*` options. Together with Slices 6 (shells), 7 (prompt), and this slice, the entire interactive-shell stack lives in home-manager.

## Decisions (locked)

1. **Switch from nvm to fnm.** fnm is in nixpkgs (`pkgs.fnm`), is supported by home-manager (`programs.fnm`), is faster (Rust vs. bash), is cross-platform (works the same on macOS and Linux), and supports `.nvmrc` for project-version compat. nvm is curl-installed bash that requires sourcing `nvm.sh` at shell init.
2. **fnm-only architecture; no parallel `pkgs.nodejs_X` declarative pin.** All node management goes through fnm. Trade: "LTS" floats over time vs. fully-declarative-but-fixed-version semantics. The user explicitly chose fnm-only over a hybrid `pkgs.nodejs_24` + fnm setup.
3. **Auto-install LTS on first bootstrap via activation script.** A marker-gated `home.activation.installFnmDefaultNode` runs `fnm install --lts && fnm default lts-latest` on first apply. Marker (`~/.fnm-default-node.hm-migrated`) prevents re-install. Network failures leave the marker absent so the next apply retries. Fresh machines have a working `node` without manual `fnm install`.
4. **Activation uses absolute store path (`${pkgs.fnm}/bin/fnm`).** Home-manager activation scripts run with a stripped PATH (we discovered this in Slice 6's chsh script). Using the Nix store path avoids any PATH-prepend gymnastics.
5. **DAG ordering: `entryAfter [ "writeBoundary" ]`.** Different from the legacy-backup activations (which use `entryBefore [ "checkLinkTargets" ]` to move real files out of the way before HM creates symlinks). This activation has no link-collision concern; it just needs the profile (with `pkgs.fnm` in it) to exist on disk first.
6. **`~/.nvm/` left on disk.** Parallel to the prompt slice's "leave `~/powerlevel10k/` alone" decision. Once the two `nvm.sh`-load blocks are removed from `shells.nix`, nothing sources nvm — the nvm-managed node versions in `~/.nvm/versions/node/*/bin` are no longer on PATH. README documents `rm -rf ~/.nvm` as optional manual cleanup.
7. **`plugins/nvm/Brewfile` (just `brew 'jq'`) is deleted with the rest of the plugin.** `jq` was used only by the nvm plugin to parse the GitHub release API. With the plugin gone, `jq` is no longer needed. If the user wants `jq` for unrelated reasons, they install it explicitly (top-level Brewfile or `home.packages = [ pkgs.jq ];` in a future slice).
8. **No work-specific values in the public repo.** Private flakes can override `programs.fnm.*` options or skip the auto-LTS install by pre-creating the marker file.

## Architecture

```text
DELETIONS (committed in this slice):
  plugins/nvm/nvm
  plugins/nvm/Brewfile
  plugins/node/node

REMOVED FROM nix/profiles/all/shells.nix:
  programs.zsh.initContent's omz_nvm.sh block (5 lines: NVM_DIR setup + nvm.sh source)
  programs.bash.profileExtra's nvm-load block (4 lines: same idea for bash)

ADDITIONS in nix/profiles/all/shells.nix:
  programs.fnm.enable = true;
  home.activation.installFnmDefaultNode  # marker-gated, network-aware, retry-on-failure

UNTOUCHED IN THIS SLICE:
  ~/.nvm/                                          # left on disk; user runs rm -rf manually
  ~/.local/share/fnm-node/                         # fnm's data dir; created by fnm itself
  nix/profiles/{default,agent}/default.nix         # no per-profile node config
```

## `programs.fnm` block in `shells.nix`

Added alongside `programs.starship`, `programs.bash`, `programs.zsh`. Placement: after `programs.starship`, before the activation scripts.

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

## `installFnmDefaultNode` activation script

```nix
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

**Properties:**

- **One-time effective.** `~/.fnm-default-node.hm-migrated` marker short-circuits subsequent applies.
- **Retry-on-failure.** Marker is set only if BOTH `fnm install --lts` and `fnm default lts-latest` succeed. A network failure or partial install leaves the marker absent so the next `./apply` retries.
- **PATH-independent.** Uses `${pkgs.fnm}/bin/fnm` (Nix interpolation resolves to the store path at build time). No reliance on activation-time PATH.
- **Linux + macOS compatible.** fnm picks the right node tarball for the runtime architecture. The Linux-container test in Task 4 verifies this.
- **Manual LTS upgrades.** When Node 26 becomes LTS, `rm ~/.fnm-default-node.hm-migrated && ./apply` re-runs the activation (or `fnm install --lts && fnm default lts-latest` interactively). The marker name documents this implicit contract.
- **No tty check.** Unlike `chshAndEtcShells` (which needs a tty for sudo + password prompts), this activation only makes a network call — works equally well in container builds and interactive sessions.

## Removed content in `shells.nix`

Two blocks come out:

**From `programs.zsh.initContent`:**

```nix
# ---- from .zshrc.d/omz_nvm.sh (8 lines; retired in Slice 8) ----
# Set NVM_DIR if it isn't already defined
[[ -z "$NVM_DIR" ]] && export NVM_DIR="$HOME/.nvm"
# Load nvm if it exists
[[ -f "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
```

**From `programs.bash.profileExtra`:**

```nix
# Setup nvm and node so prompt can use it
if [ -d "$HOME/.nvm" ]; then
  source "$HOME/.nvm/nvm.sh"
fi
```

After removal, `~/.nvm/versions/node/*/bin` is no longer on PATH for either shell. `node` resolves via fnm's shell-init `eval "$(fnm env)"` injection (which sets up the shim PATH for fnm-managed versions).

## Cross-profile concerns

- **`programs.fnm.enable` + `installFnmDefaultNode` in `all`.** Every machine — agent boxes included — gets node automatically on bootstrap. Agent boxes that don't actually need node still pay the one-time `fnm install --lts` network cost, but it's idempotent and infrequent.
- **`default` and `agent` profile modules unchanged.**
- **Work private flake** can:
  - Override `programs.fnm.*` options (e.g., a specific `nodeDistMirror` for enterprise networks).
  - Skip the auto-LTS install by pre-creating the marker: in a setup step before first apply, `touch ~/.fnm-default-node.hm-migrated`.
  - Pin a different default version: post-apply, `fnm install <version> && fnm default <version>`. The marker prevents the activation from re-overriding.

## Post-merge user actions

Documented in the README sub-block. Optional cleanups:

```bash
# After the slice merges and ./apply runs successfully, optional cleanup:
rm -rf ~/.nvm                  # nvm's home dir (33-entry git repo + installed node versions)
brew uninstall jq              # if you don't otherwise need jq
```

To upgrade past the originally-installed LTS:

```bash
rm ~/.fnm-default-node.hm-migrated
./apply                        # activation re-runs and installs the current LTS
# OR interactively:
fnm install --lts
fnm default lts-latest
```

## Testing

- **Pre-flight (macOS):**
  - `nvm --version` (expected: 0.40.4 from current install)
  - `node --version` (expected: v24.13.0)
  - `which node` (expected: `~/.nvm/versions/node/v24.13.0/bin/node`)
  - `ls -d ~/.nvm/ ~/.local/share/fnm-node/ 2>&1` (expected: nvm present; fnm dir absent)
  - `command -v fnm 2>&1` (expected: not found — fnm not yet installed)
  - `ls -la ~/.fnm-default-node.hm-migrated 2>&1` (expected: absent)

- **Activation: fnm installed.** Run the plugin direct. Confirm:
  - Activation log includes `Installed default LTS node via fnm (one-time bootstrap)`.
  - `~/.fnm-default-node.hm-migrated` marker exists.
  - `which fnm` resolves into `~/.nix-profile/bin/fnm`.
  - `fnm --version` reports something.
  - `fnm list` shows an installed LTS version.

- **Generated `~/.zshrc` and `~/.bashrc` source fnm init, not nvm:**
  - `grep -n 'fnm env' ~/.zshrc ~/.bashrc` → one match each.
  - `grep -nE 'nvm\.sh|NVM_DIR' ~/.zshrc ~/.bashrc` → NO matches (the Slice 6 temp blocks are gone).

- **Verify node resolves via fnm:**
  - `which node` resolves into `~/.local/share/fnm-node/aliases/default/bin/node` (or similar fnm shim path).
  - `node --version` reports the LTS version (whatever was current at activation time).
  - In a fresh interactive shell (not the subagent's stripped environment): `bash -lic 'which node; node --version'` and `zsh -ic 'which node; node --version'` both return the fnm-managed version.

- **Activation idempotency:**
  - Re-run activation: no `Installed default LTS node …` message; marker preserved; `fnm list` output unchanged.
  - `rm ~/.fnm-default-node.hm-migrated; re-run activation`: message re-prints; `fnm list` may show the same version (idempotent on `fnm install`); marker re-touched.

- **Activation retry-on-failure** (manual sim): export `https_proxy=http://127.0.0.1:1` to break network, `rm ~/.fnm-default-node.hm-migrated`, re-run activation. Expected: `fnm bootstrap failed; will retry on next ./apply`; marker absent; subsequent apply with restored network completes the install.

- **Cross-slice intact:**
  - `git config alias.fixup` → `commit --fixup` (Slice 1)
  - `git config user.signingkey` → personal key (Slice 5)
  - `git --version` → 2.54.0 (Slice 5 nixpkgs bump)
  - `gpg --version` → resolves to nix store (Slice 5)
  - `bat --version` → works (Slice 1)
  - `which starship` → resolves to nix store (Slice 7)
  - Shell aliases (`psgrep`, `xo`) work in both shells (Slice 6)

- **Throwaway private-override.** Scratch flake adds `programs.fnm.nodeDistMirror = "https://nodejs.org/dist/";` (the default value, so the override is mostly a no-op — but exercises the `programs.fnm.*` option-override path). Activate; tear down. Confirm working tree clean.

- **Linux container (aarch64-linux, agent profile).** `./apply` runs:
  - fnm installed; `which fnm` resolves to nix store.
  - `installFnmDefaultNode` activation runs (no tty check — network is enough); installs the LTS for linux-arm64.
  - `~/.fnm-default-node.hm-migrated` marker present.
  - `bash -lic 'node --version'` and `zsh -ic 'node --version'` both return the LTS version.
  - `~/.nvm/` absent (clean container; nothing to backup).

- **Backout drill** (documented in README): `rm ~/.fnm-default-node.hm-migrated`, re-apply — activation re-runs and reinstalls; alternatively edit `programs.fnm` to disable.

## README updates

Three changes to `nix/README.md`:

1. **New "For the nodejs slice" sub-block** in the existing private-environment migration guide, parallel to the prior slices' sub-blocks:

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

2. **Refresh the Background paragraph** to add the nodejs entry. Append after the prompt entry:

   ```text
   ; and Node.js — fnm via `programs.fnm` (replacing the retired `nvm` and `node` plugins), with a one-time activation that installs the LTS version on first apply.
   ```

3. **Refresh the `all`-layer parenthetical** under `### Public profiles and layers` — append `, AND fnm for Node.js version management`.

## Scope / Non-goals

**In scope:**

- Retire `plugins/nvm/` (the bash plugin + Brewfile).
- Retire `plugins/node/` (the bash plugin).
- Delete two `nvm.sh`-load blocks from `shells.nix` (one in `initContent`, one in `profileExtra`).
- Add `programs.fnm.enable = true` to `shells.nix`.
- Add `installFnmDefaultNode` activation (marker-gated, retry-on-failure).
- README sub-block + Background refresh + `all`-layer refresh.

**Out of scope:**

- Migrating npm globals (yarn, pnpm, typescript, etc.). User reinstalls if they had any. None currently — verified during survey.
- Automated cleanup of `~/.nvm/`. (Manual `rm -rf ~/.nvm`; documented.)
- Automated cleanup of brew's `jq`. (Manual `brew uninstall jq`; documented.)
- Pinning the node version declaratively via `pkgs.nodejs_X`. (User explicitly chose fnm-only.)
- Supporting `.tool-versions` (asdf-style multi-language). fnm reads `.nvmrc` and `.node-version`.
- Migrating to nodenv, volta, asdf, or other version managers. fnm wins.
- Brewfile retirement (much later — would eventually let us drop all brew-based plugins).

## Future phases

This slice completes the shell ecosystem migration (Slices 6 + 7 + 8). Future slices target per-tool plugins (`vim`, `vscode`, `xcode`, `claude`) and eventually the homebrew retirement. With brew gone, `chshAndEtcShells` from Slice 6 can drop its brew-zsh fallback case.
