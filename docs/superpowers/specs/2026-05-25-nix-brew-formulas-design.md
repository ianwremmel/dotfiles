# Nix Brew-Formulas Slice Design

**Date:** 2026-05-25
**Status:** Draft — pending user approval
**Branch:** `nix-homebrew` (stacks on `nix-nodejs` / PR #68 → `nix-prompt` / PR #67 → `nix-shells` / PR #66 → `nix-commit-signing` / PR #65 → `nix-git` / PR #64 → `nix-profiles` / PR #63 → `nix-cross-platform` / PR #62)

## Goal

Migrate every brew formula in the public Brewfiles (`environments/all/Brewfile`, `environments/default/Brewfile`, and the aggregator-level entries in `plugins/homebrew/Brewfile.erb`) to `home.packages` in nix. Brewfiles slim down to cask + mas + tap entries only. The bash `plugins/homebrew` and `plugins/homebrew_core` plugins stay (still needed to install casks + App Store apps); brew itself stays installed. No nix-darwin involvement yet — this is the easiest declarative win, deferring the architectural shift.

This is the first slice in the broader homebrew-retirement effort. Future slices migrate casks + mas via nix-darwin, then retire the brew plugins entirely.

## Decisions (locked)

1. **Migrate ALL formula entries** in the three public Brewfiles in one slice. Approximately 45 unique formulas across `environments/all`, `environments/default`, and the aggregator. One PR, one apply, brew bundle cleanup handles the state transition.
2. **Split between `all` and `default` profiles mirroring the existing Brewfile dispersal.** Per the user's direction: "packages should be spread across all and default profiles, just like they're spread across environments now."
   - `nix/profiles/all/cli-tools.nix` — formulas from `environments/all/Brewfile` + aggregator-level entries (bash, bash-completion@2, coreutils, gh).
   - `nix/profiles/default/cli-tools.nix` — formulas from `environments/default/Brewfile`.
3. **Defer the casks/mas/taps to a later slice (nix-darwin path).** Brewfiles retain those entries. The user's chosen overall strategy is `home.packages` for nix-friendly tools + `homebrew.casks` / `homebrew.brews` via nix-darwin for the rest.
4. **`bash` stays in Brewfiles AND lands in `home.packages`.** The framework's Bash-5 bootstrap (`framework/compat`'s `compat_ensure_modern_bash`) needs brew's bash before nix is installed. Nix's `bash` coexists for interactive use. The chicken-and-egg cleanup is deferred to a future "invert boot order" slice. See memory `nix-bootstrap-bash-deferred`.
5. **Untouched in this slice:**
   - `plugins/xcode/Brewfile` and `XcodeBrewfile` (mas-only; handled by the nix-darwin slice).
   - `custom_environments/work/Brewfile` (private; user migrates their own formulas using this slice as the template).
   - `plugins/homebrew` and `plugins/homebrew_core` (still run for casks/mas).
   - `framework/compat`'s brew bootstrap.
   - `framework/customize`'s `brew install gh/jq` fallbacks (now dead code, but cleanup deferred to alongside boot-order work).
   - `shells.nix`'s `brewPathSetup` let-binding (brew still on system).
   - `chshAndEtcShells` brew-zsh fallback (defensive; still valid).
6. **No activation script needed.** Brew bundle cleanup (driven by `plugins/homebrew` which still runs) detects the absent-from-Brewfile formulas and uninstalls them on the next apply. Nix's versions take over via PATH precedence (and remain after brew's cleanup). No marker file, no `mv`-aside dance.
7. **Per-formula brew→nix mapping is implementation work.** Most are 1:1 (`brew 'git'` → `pkgs.git`). The known renames are documented in the plan. If a formula has no clean nix equivalent, it stays in the Brewfile (none expected in the public Brewfiles per the survey).
8. **No work-specific values in the public repo.** Private/work taps and their formulas stay in `custom_environments/<env>/Brewfile`. The README sub-block points work-side users at the migration pattern but specifies no values.

## Architecture

```text
NEW FILES:
  nix/profiles/all/cli-tools.nix       # home.packages for all-profile formulas (~30 entries)
  nix/profiles/default/cli-tools.nix   # home.packages for default-profile formulas (~15 entries)

MODIFIED FILES:
  nix/profiles/all/default.nix         # imports += ./cli-tools.nix; imports -= ./bat.nix
  nix/profiles/default/default.nix     # imports += ./cli-tools.nix (gains imports list); ripgrep line removed
  environments/all/Brewfile            # strip `brew '...'` lines; keep cask/mas/tap
  environments/default/Brewfile        # strip `brew '...'` lines; keep cask/mas/tap
  plugins/homebrew/Brewfile.erb        # strip aggregator-level `brew '...'` lines; keep mas

DELETED FILES:
  nix/profiles/all/bat.nix             # demo content from Slice 1; see "Demo-package cleanup"

UNTOUCHED:
  plugins/xcode/Brewfile               # mas-only; nix-darwin slice handles it
  plugins/xcode/XcodeBrewfile          # same
  custom_environments/work/Brewfile    # private; user migrates separately
  plugins/homebrew                     # still runs brew bundle for casks/mas
  plugins/homebrew_core                # still bootstraps brew
  framework/compat                     # brew bootstrap stays
  framework/customize                  # brew install gh/jq fallbacks stay (dead code; cleanup deferred)
  nix/profiles/all/shells.nix          # brewPathSetup + chshAndEtcShells brew-zsh fallback stay
```

## `nix/profiles/all/cli-tools.nix` content

Module signature `{ pkgs, ... }:`. Body:

```nix
{ pkgs, ... }: {
  # CLI tools that every machine gets. Migrated from
  # `environments/all/Brewfile` + the aggregator-level brews in
  # `plugins/homebrew/Brewfile.erb`. The corresponding `brew '<name>'` lines
  # are removed from the Brewfiles by this same slice; brew bundle cleanup
  # uninstalls them on next apply and the nix-installed versions take over
  # via PATH precedence.
  home.packages = with pkgs; [
    # …list of ~30 packages, one per migrated formula…
  ];
}
```

The exact list is implementation work (the implementer reads each Brewfile, maps brew names to nix names per the rename table below, and writes the list).

## `nix/profiles/default/cli-tools.nix` content

Same shape; smaller list (~15 entries from `environments/default/Brewfile`).

```nix
{ pkgs, ... }: {
  # CLI tools that only the `default` (personal) profile gets. Migrated
  # from `environments/default/Brewfile`. Agent profiles do NOT get these.
  home.packages = with pkgs; [
    # …list of ~15 packages…
  ];
}
```

## Brew → nix name mapping (known cases)

Most brew formulas map 1:1 to `pkgs.<name>`. These are the known renames:

| brew name           | nix name               | notes |
| ------------------- | ---------------------- | ----- |
| `gnu-sed`           | `pkgs.gnused`          | |
| `gnu-tar`           | `pkgs.gnutar`          | |
| `kubernetes-cli`    | `pkgs.kubectl`         | brew formula is named `kubernetes-cli` but binary is `kubectl` |
| `helm`              | `pkgs.kubernetes-helm` | renamed in nixpkgs |
| `bash-completion@2` | `pkgs.bash-completion` | nixpkgs has one version |
| `python`            | `pkgs.python3`         | or pin like `pkgs.python314` for a specific version |
| `awscli`            | `pkgs.awscli2`         | nixpkgs has the v2 variant under a different attribute name |
| `yq`                | `pkgs.yq-go`           | the brew `yq` is the Go implementation |
| `openjdk`           | `pkgs.openjdk`         | works; may need a version (`pkgs.openjdk21`) if specific |
| `terraform`         | `pkgs.terraform`       | Unfree license (BSL) — requires `nixpkgs.config.allowUnfree = true` somewhere upstream; verify before adding |
| `bash` | `pkgs.bash` | (also stays in Brewfile per Decision 4) |

All other formulas should map 1:1. If a formula has no clean nix equivalent, the implementer leaves it in the Brewfile and notes it in the commit.

## Modifications to existing `default.nix` files

**`nix/profiles/all/default.nix`** — currently:

```nix
{ ... }: {
  imports = [
    ./bat.nix
    ./git.nix
    ./gpg.nix
    ./shells.nix
  ];
}
```

Becomes:

```nix
{ ... }: {
  imports = [
    ./bat.nix
    ./cli-tools.nix
    ./git.nix
    ./gpg.nix
    ./shells.nix
  ];
}
```

(Alphabetical insertion of `./cli-tools.nix` between `bat` and `git`.)

**`nix/profiles/default/default.nix`** — currently a single module with `home.packages = [ pkgs.ripgrep ];` + `programs.git.settings` content. Gains an `imports` list at the top:

```nix
{ pkgs, ... }: {
  imports = [
    ./cli-tools.nix
  ];

  home.packages = [ pkgs.ripgrep ];

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

(The `ripgrep` line could also move into `cli-tools.nix` — implementer's call; both equally valid. Probably keep it where it is since it's not a brew migration; it lands as part of a future cleanup if anyone wants symmetry.)

## Brewfile changes

**`environments/all/Brewfile`** — strip every `brew '<name>'` line; keep `cask`, `mas`, `tap` entries verbatim. Leave a single comment marking the migration:

```ruby
# CLI formulas migrated to nix (see nix/profiles/all/cli-tools.nix).
# Casks, mas, and taps remain here until the nix-darwin slice migrates them.
```

Same treatment for `environments/default/Brewfile` and `plugins/homebrew/Brewfile.erb` (in the latter, the aggregator's `brew 'bash'`, `brew 'bash-completion@2'`, `brew 'coreutils'`, `brew 'gh'` lines come out; `brew 'mas'` STAYS since the xcode plugin still depends on it).

**`bash` exception:** despite migrating to nix, the `brew 'bash'` and `brew 'bash-completion@2'` entries in `plugins/homebrew/Brewfile.erb` STAY (Decision 4). The Brewfile comment should call out why.

## Transition mechanic

On the first `./apply` after this slice merges:

1. **`nix` plugin** runs (early in the bash framework's plugin order; no homebrew deps).
   `home.packages` includes all the migrated formulas → nix builds the home-manager generation with `~/.nix-profile/bin/<tool>` symlinks for each.
2. **Activation** symlinks land in the user's profile.
3. **`homebrew` plugin** runs later (after `homebrew_core` + `xcode`).
   `brew bundle --file=<aggregated>` against the slimmed Brewfiles → notices the migrated formulas are no longer requested.
   `brew bundle cleanup --force` uninstalls those formulas from `/opt/homebrew/Cellar`.
4. **Result:** only the nix-installed versions remain on disk for the migrated tools. PATH order (nix-profile before homebrew on the user's interactive shell) means `which git` resolves to the nix version both before and after the cleanup; the cleanup just frees disk.

`bash` is the exception: still in the Brewfile, so brew bundle keeps `/opt/homebrew/bin/bash` installed; nix also installs `~/.nix-profile/bin/bash`. Both coexist.

No marker file. No `mv`-aside. The brew bundle cleanup is the state transition.

## Cross-profile concerns

- **`all` profile** gets the universal formulas (~30 entries: GNU utils, dev essentials, shell completion, etc.).
- **`default` profile** gets additional personal-machine formulas (~15 entries: cloud tools, scripting languages, dev runtimes).
- **`agent` profile** stays lean. Agent boxes get only what's in `all`. They don't get the personal-machine extras (per the existing `environments/default/` vs. `environments/all/` split — this slice preserves that).
- **Work private flake** can extend `home.packages` directly. The migration guide in the README points to the pattern.

Per-shell PATH: `~/.nix-profile/bin` is already on PATH (from prior slices). New packages slot in automatically.

## Testing

- **Pre-flight:**
  - `brew list --formula | wc -l` (count formulas pre-migration)
  - `which git vim gh ansible terraform awscli`
  - Capture the output of `git --version`, `terraform --version`, etc. for ~5 representative tools

- **Activation:**
  - `nix-instantiate --parse nix/profiles/all/cli-tools.nix` parses
  - `nix-instantiate --parse nix/profiles/default/cli-tools.nix` parses
  - `nix --extra-experimental-features 'nix-command flakes' eval ".#homeModules.all"` returns `path`
  - Run home-manager activation (direct nix-plugin invocation pattern)
  - Verify `ls ~/.nix-profile/bin/{git,vim,gh,ansible,terraform,...}` shows symlinks into `/nix/store/`

- **PATH precedence:**
  - `which git` resolves to `~/.nix-profile/bin/git`
  - `git --version` works
  - Repeat for ~5 representative tools

- **Brew bundle cleanup:**
  - Run `./apply -B` to skip brew step (or wait until next full apply)
  - When the brew step does run, verify migrated formulas are uninstalled from `/opt/homebrew/Cellar` afterward
  - `bash` remains (Decision 4)

- **Cross-slice intact:**
  - `git config alias.fixup` returns `commit --fixup` (Slice 1)
  - `git config commit.gpgsign` returns `true` (Slice 5)
  - `git --version` returns `2.54.0` (Slice 5 nixpkgs bump)
  - `gpg --version` resolves to nix store (Slice 5)
  - `bat --version` works (Slice 1)
  - `which starship` resolves to nix store (Slice 7)
  - `which fnm; node --version` (Slice 8)
  - Shell aliases (`psgrep`, `xo`) work in both shells (Slice 6)

- **Idempotency:**
  - Second activation: no changes; `which git` still resolves to nix; no errors

- **Throwaway private override:**
  - Scratch flake adds `home.packages = [ pkgs.cowsay ];` (a harmless extra package)
  - Activate; `which cowsay` resolves; tear down restores

- **Linux container (aarch64-linux, agent profile):**
  - `./apply` runs only the nix step (Linux skips brew per the cross-platform slice)
  - Verify the `all`-layer subset of formulas installed in the nix profile
  - `default`-only formulas are NOT installed (agent profile doesn't get them)
  - `bash`, `coreutils`, `gh`, etc. (the always-on ones) ARE installed

- **Backout drill:**
  - Revert the feat commit
  - `./apply` — brew bundle re-installs the formulas (still in original Brewfile lines as long as the user also reverts the Brewfile changes); recovery works

## README updates

Three changes to `nix/README.md` (same pattern as prior slices):

1. **New "For the brew-formulas slice" sub-block** in the private-environment migration guide:

   ```markdown
   For the brew-formulas slice (CLI formulas migrated to `home.packages`; casks, mas,
   and taps still managed by `plugins/homebrew` until a later nix-darwin slice):

   1. **Update your private flake** to add any of YOUR brew formulas that have
      nix equivalents to `home.packages` in a private module:

          { pkgs, ... }: {
            home.packages = with pkgs; [
              # …your private CLI tools…
            ];
          }

   2. **Delete the corresponding `brew '<name>'` lines** from your private Brewfile.
      Keep cask, mas, and tap entries (those move in a later slice).

   3. **First `./apply` after this slice** runs the brew step against your slimmed
      Brewfile; `brew bundle cleanup --force` uninstalls the formulas that no
      longer appear there, and the nix-installed versions take over via PATH
      precedence.

   4. **Formulas without a nix equivalent** (e.g., custom-tap formulas
      from work-specific taps) STAY in your private Brewfile. The
      `homebrew.brews` option in a future nix-darwin slice will give you a
      declarative way to manage these.
   ```

2. **Refresh Background paragraph** to add the brew-formulas entry:

   ```text
   ; and CLI tools — most brew formulas migrated to `home.packages` (casks, mas, and taps still managed by the legacy `plugins/homebrew` until a later nix-darwin slice).
   ```

3. **Refresh `all`-layer parenthetical** under `### Public profiles and layers`:

   ```text
   (…AND fnm for Node.js version management, AND a curated set of CLI tools via `home.packages`)
   ```

   The references to `bat` are dropped here too (the demo `programs.bat` module is removed in this slice; see "Demo-package cleanup" below).

## Demo-package cleanup

Slices 1-2 introduced `bat` (`nix/profiles/all/bat.nix` with `programs.bat.enable = true`) and `ripgrep` (`home.packages = [ pkgs.ripgrep ]` in `nix/profiles/default/default.nix`) as proof-of-concept content. With this slice establishing a real `cli-tools.nix` pattern, the demo packages are removed:

- **Delete `nix/profiles/all/bat.nix`** entirely.
- **Remove `./bat.nix`** from `nix/profiles/all/default.nix`'s imports list.
- **Remove `home.packages = [ pkgs.ripgrep ];`** line from `nix/profiles/default/default.nix`. (The `programs.git.settings` content stays; the file gains `imports = [ ./cli-tools.nix ];` from this slice's main work.)

If either `bat` or `ripgrep` is genuinely wanted, they should be added to the appropriate `cli-tools.nix` as ordinary `home.packages` entries (and `programs.bat`'s typed config would just become a `pkgs.bat` entry — losing the typed `config.theme` option, which the implementer is free to re-add via `programs.bat` if the user actually uses that theme).

## Scope / Non-goals

**In scope:**

- Migrate all `brew '<name>'` lines from `environments/all/Brewfile`, `environments/default/Brewfile`, and the aggregator portion of `plugins/homebrew/Brewfile.erb` to two new `cli-tools.nix` files.
- Strip those `brew '<name>'` lines from the Brewfiles (keeping cask/mas/tap).
- Keep `brew 'bash'`, `brew 'bash-completion@2'` in `plugins/homebrew/Brewfile.erb` per Decision 4.
- Keep `brew 'mas'` in the aggregator (used by xcode plugin).
- Remove the `bat`/`ripgrep` demo packages (see "Demo-package cleanup" above).
- README sub-block + Background + `all`-layer refresh.

**Out of scope:**

- Casks (handled by future nix-darwin slice).
- Mas / App Store apps (handled by future nix-darwin slice).
- Taps (work-specific; user manages).
- Retiring `plugins/homebrew` + `plugins/homebrew_core` (handled by future nix-darwin slice).
- Removing brew from `framework/compat` or `framework/customize` (deferred; framework still needs brew for bash-5 bootstrap).
- Cleaning up `shells.nix`'s `brewPathSetup` (brew still on the system).
- The bash chicken-and-egg between framework boot and nix-installed bash (memory: `nix-bootstrap-bash-deferred`).
- Migrating the `custom_environments/work/Brewfile` formulas (private; user does this in their own repo using this slice as the template).
- Removing the framework's `customize` fallbacks (`brew install gh/jq`) — they become dead code but stay for now.

## Future phases

After this slice, the remaining homebrew-retirement work is:

- **Slice 10: Bring in nix-darwin.** Add `nix-darwin` as a flake input. Set up minimal config. `apply` learns to invoke `darwin-rebuild switch`.
- **Slice 11: Migrate casks to `homebrew.casks`.** All ~27 cask entries from Brewfiles move into nix-darwin declarations.
- **Slice 12: Migrate mas entries to `homebrew.masApps`.** Including Xcode (replacing the `plugins/xcode/{Brewfile,XcodeBrewfile}` swap dance).
- **Slice 13: Retire `plugins/homebrew` + `plugins/homebrew_core`.** nix-darwin owns brew bundle now.
- **Slice 14: Clean up `framework/compat` brew bootstrap + `framework/customize` fallbacks + `shells.nix`'s `brewPathSetup`.** Touches the bash bootstrap chicken-and-egg; see memory `nix-bootstrap-bash-deferred`.
- **Slice 15 (optional): Move `chshAndEtcShells` from home-manager activation to nix-darwin's `system.activationScripts`.** Cleaner layering.
