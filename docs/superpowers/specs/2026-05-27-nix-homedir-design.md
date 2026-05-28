# Nix Homedir Slice Design

**Date:** 2026-05-27
**Status:** Draft — pending user approval
**Branch:** `nix-homedir` (stacks on `nix-vscode` / PR #74 → `nix-claude` / PR #73 → … → master)

## Goal

Migrate the `environments/all/home/` rsync content — the universal dotfiles, the global gitignore, the `~/bin/git-*` helper scripts, and `~/.ssh/config` — into home-manager. Use native home-manager modules where they genuinely fit (`programs.git.ignores`, `programs.screen`) and `home.file` for the rest. Delete the migrated source files from `environments/all/home/`. **Keep the `homedir` bash plugin in place** — it still rsyncs `custom_environments/work/home/`, whose migration is deferred to the finale.

## Why the homedir plugin stays

The `homedir` plugin rsyncs every environment's `home/` dir in the resolution chain (`environment_map_func`). After this slice, `environments/all/home/` is empty, but `custom_environments/work/home/` still has content (`.zshrc`, `.bash_profile`, `.gitconfig`, `bin/{jk,jk-1,gwr,git-air,git-airpr}`). Per the user's directive, `custom_environments` migration is the last step (with an automated process). So the plugin must remain functional to serve the work environment until then. This slice empties the public `all/home/` rsync source but does not touch the plugin.

## What's being migrated (the `environments/all/home/` inventory)

| Source file | Destination | Mechanism |
| ----------- | ----------- | --------- |
| `.gitignore` | `~/.config/git/ignore` (git reads natively) | `programs.git.ignores` (native) — fold into existing `git.nix` |
| `.screenrc` | `~/.screenrc` | `programs.screen` (native), `package = null`, standalone source |
| `.gemrc` | `~/.gemrc` | `home.file` via auto-discovery (`home/` tree) |
| `.wgetrc` | `~/.wgetrc` | `home.file` via auto-discovery (`home/` tree) |
| `.hushlogin` | `~/.hushlogin` | `home.file` via auto-discovery (`home/` tree) |
| `.ssh/config` | `~/.ssh/config` | `home.file.text` = `readFile(ssh-config)` + darwin-gated `UseKeychain` (native `programs.ssh` exists but rejected — see decision 4) |
| `bin/git-*` (8 scripts) | `~/bin/git-*` | `home.file` via auto-discovery (`home/bin/` → `executable = true` from `bin/` prefix) |

## Decisions (locked)

1. **Native modules where they fit; `home.file` otherwise.** Confirmed against the pinned home-manager (`b179bde`): native modules exist for `programs.git` (ignores), `programs.screen`, and `programs.ssh`. No modules for wget, gem, hushlogin, or arbitrary scripts.

2. **`.gitignore` → `programs.git.ignores`** in `nix/profiles/all/git.nix`. The patterns become an inline Nix list. **Drop the existing `core.excludesfile = "~/.gitignore"` line** (git.nix:35) — home-manager writes `~/.config/git/ignore` and sets `core.excludesFile` to it automatically. The old `~/.gitignore` becomes vestigial and is cleared by the activation (decision 7).

3. **`.screenrc` → `programs.screen`** with `enable = true`, `package = null` (don't install nix's screen; preserve current behavior where `screen` comes from the system), `screenrc = ./home-files/screenrc` (the module writes `~/.screenrc` from the source path verbatim — handles the backtick `escape` and `%`-heavy hardstatus string with no escaping risk).

4. **`.ssh/config` → `home.file.".ssh/config".text` assembled from a regular source file**, NOT `programs.ssh`. Native support exists but is deliberately not used because:
   - **Order-sensitivity:** the config's documented precedence (most-specific-host first: `github.com` before `host *`) would require `lib.hm.dag.entryBefore`/`entryAfter` annotations on every block; a naive attrset sorts `*` ahead of `github.com` and silently breaks first-match-wins.
   - **API churn:** `programs.ssh.matchBlocks` is deprecated in this version (warns "Use `programs.ssh.settings`").
   - **`enableDefaultConfig`** injects an opinionated default `Host *` block that could collide with the explicit `host *`.

   The config content lives in a **regular source file** `home-files/ssh-config` (editable, syntax-highlighted — same treatment as every other file). The module reads it with `builtins.readFile` and appends only the one macOS-specific line conditionally:
   ```nix
   ".ssh/config".text =
     builtins.readFile ./home-files/ssh-config
     + lib.optionalString pkgs.stdenv.isDarwin "  UseKeychain              yes\n";
   ```
   The source file ends with the `host *` block, so the appended `UseKeychain` lands inside it (option order within a single block is irrelevant). The `default@darwin` build emits `UseKeychain`, the `agent@linux` build omits it — "platform-appropriate bits in each" with a single source of truth, and the config is NOT inlined in the `.nix` module.

5. **`.gemrc`, `.wgetrc`, `.hushlogin`, and the `bin/git-*` scripts → one auto-discovery helper** (claude-slice style) over a `nix/profiles/all/home-files/home/` tree that mirrors `$HOME`. The helper maps every file at `home-files/home/<rel>` → `home.file.<rel>` (i.e. `~/<rel>`), so the source tree's layout *is* the home layout. The executable bit is derived from the path: `executable = lib.hasPrefix "bin/" rel` (bin scripts get +x; dotfiles don't). **Per-file** (not whole-dir symlink) so the non-repo `~/bin/steam` symlink is never shadowed. Adding a future dotfile or script = drop it in `home-files/home/` at the right relative path and `./apply` — no per-file callout in the module.

6. **`.screenrc` and `.ssh/config` are the two special cases** handled outside the auto-discovery tree (they need module-specific or conditional handling — see decisions 3 and 4). They live as standalone source files (`home-files/screenrc`, `home-files/ssh-config`), NOT under `home-files/home/`, so the helper doesn't double-manage them.

7. **Clear the vestigial rsynced files directly (no backup), with the list derived — not hardcoded.** One activation `clearLegacyHomedirFiles` (`entryBefore [ "checkLinkTargets" ]`) `rm`s each target path, guarded `[ -f "$f" ] && [ ! -L "$f" ]`. The path list is computed in Nix as `builtins.attrNames discovered ++ [ ".screenrc" ".ssh/config" ".gitignore" ]` — so the auto-discovered files contribute their own cleanup automatically, and only the three specials are named explicitly. No `.legacy-backup` (per user: these are exact tracked copies — rsync `-av` already clobbered local edits on every apply, so nothing recoverable is lost; git has the content). `.gitignore` is included as vestigial after the `programs.git.ignores` switch; `.screenrc` and `.ssh/config` because their managed versions (via `programs.screen` / the `.text` assembly) also can't overwrite a pre-existing regular file.

8. **Profile: `all` (universal)** for everything. The ssh `UseKeychain` darwin-gate handles the only platform-specific bit; no per-profile file splitting needed (which would duplicate the common ssh blocks).

9. **Keep `plugins/homedir/homedir`.** Still serves `custom_environments/work/home/`. `DOTFILES_HOMEDIR_DEPS` stays `()`. No plugin changes.

10. **Delete the migrated files from `environments/all/home/`** (`.gitignore`, `.gemrc`, `.wgetrc`, `.screenrc`, `.hushlogin`, `.ssh/config`, `bin/git-*`). This empties `environments/all/home/` (and its `.ssh/` and `bin/` subdirs) — the dir effectively disappears. The homedir plugin's `[ -d "$candidate" ]` guard skips the now-absent `all/home/`.

11. **No work-specific values.** All migrated content is from the public `all/` layer.

## Architecture

```text
NEW FILES:
  nix/profiles/all/home-files.nix                       # the module: auto-discovery helper + screen + ssh + derived clear activation
  nix/profiles/all/home-files/home/.gemrc               # → ~/.gemrc       (auto-discovered)
  nix/profiles/all/home-files/home/.wgetrc              # → ~/.wgetrc      (auto-discovered)
  nix/profiles/all/home-files/home/.hushlogin           # → ~/.hushlogin   (auto-discovered)
  nix/profiles/all/home-files/home/bin/git-cpr          # → ~/bin/git-cpr  (auto-discovered, +x via bin/ prefix)
  nix/profiles/all/home-files/home/bin/git-delete-branch        # (and the other 7 git-* scripts)
  nix/profiles/all/home-files/home/bin/git-last-commit-message
  nix/profiles/all/home-files/home/bin/git-superprune
  nix/profiles/all/home-files/home/bin/git-superrebase
  nix/profiles/all/home-files/home/bin/git-touch
  nix/profiles/all/home-files/home/bin/git-update-author
  nix/profiles/all/home-files/home/bin/git-upush
  nix/profiles/all/home-files/screenrc                  # standalone → programs.screen.screenrc
  nix/profiles/all/home-files/ssh-config                # standalone → readFile + darwin-gated UseKeychain

MODIFIED FILES:
  nix/profiles/all/git.nix                              # +programs.git.ignores; -core.excludesfile line
  nix/profiles/all/default.nix                          # imports ./home-files.nix
  nix/README.md                                         # +migration guide sub-block

DELETED (from environments/all/home/):
  .gitignore .gemrc .wgetrc .screenrc .hushlogin
  .ssh/config  (and the now-empty .ssh/)
  bin/git-{cpr,delete-branch,last-commit-message,superprune,superrebase,touch,update-author,upush}
  (the now-empty bin/ and the now-empty environments/all/home/ itself)

UNTOUCHED:
  plugins/homedir/homedir                               # still serves custom_environments/work/home/
  custom_environments/work/home/                        # finale slice
  ~/bin/steam                                           # non-repo symlink, never shadowed (per-file mgmt)
  ~/.ssh/{id_rsa,id_rsa.pub,known_hosts,agent/}         # live secrets/state, untouched
```

## `nix/profiles/all/home-files.nix` (full content)

```nix
{ pkgs, lib, ... }:
let
  # Auto-discover every file under ./home-files/home/ and map it to the same
  # relative path under $HOME. The source tree's layout IS the home layout.
  # Per-file (not a whole-dir symlink) so non-repo entries (e.g. ~/bin/steam)
  # are never shadowed. Scripts under bin/ are installed executable. Add a new
  # dotfile or script by dropping it in ./home-files/home/<rel> and ./apply.
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

  # Legacy rsynced regular files to clear so home-manager can link. Derived
  # from the discovered set plus the three specially-handled files (.screenrc
  # via programs.screen, .ssh/config via the .text assembly below, and the
  # now-vestigial .gitignore whose patterns moved to programs.git.ignores).
  clearPaths = (builtins.attrNames discovered) ++ [ ".screenrc" ".ssh/config" ".gitignore" ];
in
{
  programs.screen = {
    enable = true;
    package = null;                       # don't install nix's screen; system screen + our rc
    screenrc = ./home-files/screenrc;
  };

  home.file = discovered // {
    # ~/.ssh/config from a regular source file (programs.ssh would
    # reorder/deprecate/inject — see design decision 4). Only the macOS-only
    # UseKeychain line is appended conditionally; it lands inside the trailing
    # `host *` block (option order within a block is irrelevant).
    ".ssh/config".text =
      builtins.readFile ./home-files/ssh-config
      + lib.optionalString pkgs.stdenv.isDarwin "  UseKeychain              yes\n";
  };

  # Clear the legacy rsynced regular files so home-manager can take over.
  # Direct rm (no backup) — exact tracked copies; rsync -av already clobbered
  # local edits on every apply, and git has the content. Guarded so it only
  # touches a real file that isn't already our symlink. List is derived, not
  # hardcoded — new home-files entries contribute their own cleanup.
  home.activation.clearLegacyHomedirFiles =
    lib.hm.dag.entryBefore [ "checkLinkTargets" ] (
      lib.concatMapStringsSep "\n"
        (rel: ''if [ -f "$HOME/${rel}" ] && [ ! -L "$HOME/${rel}" ]; then /bin/rm "$HOME/${rel}"; fi'')
        clearPaths
    );
}
```

`home-files/ssh-config` (regular source file — the verbatim config minus the macOS `UseKeychain` line, which the module appends):

```text
# Precedence: most-specific host blocks first, general defaults last
# (ssh uses the first obtained value for each parameter).

host github.com
  User                     git
  Hostname                 github.com
  PreferredAuthentications publickey

# Don't auto-trust these hosts
host *.amazonaws.com github.com monkey.org *.heroku.com
  strictHostKeyChecking    yes

host *
  ForwardAgent             yes
  AddKeysToAgent           yes
  IdentityFile             ~/.ssh/id_rsa
```

Notes:
- The legacy file had `UseKeychain` mid-`host *`-block; appending it at the end of the same block is semantically identical (distinct ssh parameters; order within a block is irrelevant).
- `~/.ssh/config` perms: ssh requires the config not be group/world-writable. A home-manager symlink targets a `/nix/store` file (mode 444, root-owned); ssh accepts root-owned, non-writable config. Verified-at-apply in the test plan.
- `executable = lib.hasPrefix "bin/" rel` forces +x on `bin/*` and non-exec on dotfiles, rather than relying on source-mode preservation through the Nix store.
- All source files (the `home/` tree, `screenrc`, `ssh-config`) must be `git add`ed — flakes only see git-tracked files.

## `nix/profiles/all/git.nix` change

Confirmed structure: `programs.git.settings.core.excludesfile = "~/.gitignore";` (line 35), and `ignores` is a top-level `programs.git` option (sibling to `enable`, `includes`, `settings`).

Two edits:

1. **Remove** the single line `excludesfile = "~/.gitignore";` from the `programs.git.settings.core` block. Leave the sibling `core` keys (`attributesfile = "~/.gitattributes"`, `precomposeunicode`, `trustctime`, `whitespace`) untouched — they are NOT part of this slice.
2. **Add** `programs.git.ignores` as a top-level `programs.git` option (e.g. right after `includes`):

```nix
  programs.git = {
    enable = true;
    includes = [ { path = "~/.gitconfig.custom"; } ];

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

    settings = {
      # ... existing, with core.excludesfile removed ...
    };
  };
```

home-manager's `programs.git.ignores` writes `~/.config/git/ignore` and sets `core.excludesFile` to it. **Note:** `core.attributesfile = "~/.gitattributes"` stays — that's a separate file (not in `environments/all/home/`, out of this slice's scope); do not touch it.

## `nix/profiles/all/default.nix` change

Add `./home-files.nix` to the imports list (alphabetical placement):

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

## Migration guide block in `nix/README.md`

Append after the "For the nix-vscode slice" sub-block, paragraph-heading style:

```markdown
For the nix-homedir slice (`environments/all/home/` rsync content → home-manager; the homedir plugin stays for custom_environments):

This slice migrates the universal rsync dotfiles into home-manager: the global
gitignore (`programs.git.ignores`), `.screenrc` (`programs.screen`), `.gemrc` /
`.wgetrc` / `.hushlogin` (`home.file`), the `~/bin/git-*` helper scripts
(`home.file`, executable, per-file so `~/bin` stays writable), and `~/.ssh/config`
(`home.file` with the macOS-only `UseKeychain` gated by platform).

The `homedir` bash plugin is NOT retired — it still rsyncs
`custom_environments/<env>/home/`. It retires in a later slice once
custom_environments is migrated.

**One-time apply notes:**

- On first apply, an activation deletes the now-vestigial rsynced copies of
  these files from `$HOME` (`.gemrc`, `.wgetrc`, `.screenrc`, `.hushlogin`,
  `.gitignore`, `.ssh/config`, and the `~/bin/git-*` scripts) so home-manager
  can link the managed versions. No backup is kept — they were exact copies of
  tracked repo content. Your non-managed `~/bin` entries, `~/.ssh` keys, and
  `known_hosts` are untouched.

- The global gitignore moved from `~/.gitignore` to `~/.config/git/ignore`
  (git reads it natively via `core.excludesFile`, which home-manager now sets).

**Private flake update (only if you have one):**

If your private flake adds `home.file` entries or `programs.git.ignores`, Nix
module merging handles additive entries; conflicting keys need `lib.mkForce`.
```

## Open questions resolved during plan / implementation

1. **`excludesfile` line location in `git.nix`.** Determine whether it's under `programs.git.settings.core.excludesfile` or `programs.git.extraConfig.core.excludesfile` and remove from the right place. Confirm `nix eval` shows `core.excludesFile` pointing at the home-manager-generated `~/.config/git/ignore` after the change (not a duplicate/conflict).
2. **`programs.screen` with `package = null`.** Confirm the module accepts `package = null` (it's `mkPackageOption ... { nullable = true; }`, so yes) and writes `~/.screenrc` without adding screen to `home.packages`. Verify via `nix eval` that `home.packages` gains no `screen`.
3. **ssh config symlink + perms.** After apply, verify `ssh -G github.com` resolves correctly (User=git, the right options) and ssh doesn't complain about config ownership/permissions on the `/nix/store` symlink target.
4. **Auto-discovery (`discovered`) attr names + executability.** Verify via `nix eval` that the helper produces exactly 11 clean relative names — `.gemrc`, `.wgetrc`, `.hushlogin`, and `bin/git-*` (×8) — with no `/nix/store/` leakage, that the 8 `bin/*` entries have `executable = true` and the 3 dotfiles `executable = false`, and that `clearPaths` resolves to those 11 + `.screenrc` + `.ssh/config` + `.gitignore` (14 total). Same gate style as the claude slice's `mapClaudeTree`. Also confirm `lib.filesystem.listFilesRecursive` includes the dot-prefixed files (`.gemrc` etc.).

## Testing

Per project convention (no automated tests), manual verification in the plan:

1. **Pre-flight:** capture `ls -la ~/bin ~/.ssh/config ~/.gitignore ~/.gemrc ~/.wgetrc ~/.screenrc ~/.hushlogin`; `git config --get core.excludesfile`; `command -v git-cpr` (or `git cpr -h`); note `~/bin/steam` symlink present.
2. **Eval gates (pre-apply):** `mapBinScripts` produces 8 clean `bin/git-*` entries; `home.packages` has no `screen`; `core.excludesFile` resolves to the HM-generated ignore path; flake check + activationPackage drv eval clean.
3. **After `./apply`:**
   - `~/.gemrc`, `~/.wgetrc`, `~/.screenrc`, `~/.hushlogin`, `~/.ssh/config`, `~/bin/git-*` are symlinks into `/nix/store`.
   - `~/.gitignore` is GONE (cleared; content now at `~/.config/git/ignore`). `git config --get core.excludesFile` → the HM path. `git check-ignore -v foo.swp` → matches a pattern.
   - `~/bin/steam` symlink UNCHANGED (not shadowed). `~/.ssh/{id_rsa,known_hosts}` unchanged.
   - `git cpr` / `git-superrebase` etc. are runnable (executable bit set). `ssh -G github.com | grep -i 'user\|preferredauthentications'` shows the github block applied; `ssh -G github.com | grep -i usekeychain` shows `usekeychain yes` on macOS.
   - `screen -v` still runs (system screen); `~/.screenrc` is the managed symlink.
4. **Framework:** `environments/all/home/` is empty/gone; `plugins/homedir/homedir` unchanged; the homedir plugin still rsyncs custom_environments on apply (no error).
5. **Idempotence:** second `./apply` — the clear activation no-ops (targets are now symlinks), no duplicate state.

## Risk and rollback

**Risk profile:** Medium-low. The genuine risks: (a) ssh config symlink perms rejected by ssh — mitigated by verify-at-apply, fallback to `home.file.<>.text` materialized differently or `programs.ssh` if needed; (b) `programs.git.ignores`/`excludesfile` conflict producing a broken gitconfig — caught at `nix eval`; (c) a bin script losing its executable bit — caught by the apply test running one.

**Rollback:** `git revert` the slice; re-`./apply`. The homedir plugin's rsync re-deploys `environments/all/home/` content on the reverted tree — but since this slice deletes those source files, a revert restores them, and rsync re-creates `~/.gitignore`, `~/bin/git-*`, etc. The cleared files are all recoverable from git history.

## Out of scope

- **`custom_environments/work/home/` migration** — the finale (automated process).
- **Retiring the `homedir` plugin** — blocked on custom_environments.
- **Converting `.ssh/config` to `programs.ssh`** — deliberately rejected (decision 4).
- **Installing nix's `screen`/`wget`/`gem` packages** — config-only migration; package management is separate.
- **Splitting ssh config across default/agent profile files** — the darwin conditional in `all` achieves platform-appropriateness without duplication.

## Cross-references

- Master design: `docs/superpowers/specs/2026-05-22-nix-migration-design.md`
- Prior slice (nix-vscode): `docs/superpowers/specs/2026-05-27-nix-vscode-design.md`
- Git slice (holds `programs.git`): `docs/superpowers/specs/2026-05-24-nix-git-design.md`
- Status doc (local, uncommitted): `docs/superpowers/nix-migration-status.md`
