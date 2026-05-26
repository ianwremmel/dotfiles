# Nix Brew-Formulas Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate every brew formula from the three public Brewfiles (`environments/all/Brewfile`, `environments/default/Brewfile`, `plugins/homebrew/Brewfile.erb`) into `home.packages` via two new `nix/profiles/{all,default}/cli-tools.nix` files. Brewfiles slim to cask + mas + tap entries. Remove the `bat`/`ripgrep` demo packages from earlier slices.

**Architecture:** Single atomic feat commit creates `nix/profiles/all/cli-tools.nix` and `nix/profiles/default/cli-tools.nix`, updates both `default.nix` files' imports lists, strips the migrated `brew '...'` lines from the three Brewfiles, deletes `nix/profiles/all/bat.nix`, removes the `home.packages = [ pkgs.ripgrep ];` line from `default/default.nix`, and (for `terraform` specifically) enables `nixpkgs.config.allowUnfree`. A second commit updates `nix/README.md`. A third task is verification-only.

**Tech Stack:** Bash 5, Nix flakes, home-manager (`home.packages`, `nixpkgs.config.allowUnfree`), nixpkgs 26.05, brew (still installed for casks/mas).

---

## Notes for the executor

- **Reference spec:** `docs/superpowers/specs/2026-05-25-nix-brew-formulas-design.md`.
- **No automated test framework.** "Tests" are verification commands with expected output.
- **Branch:** `nix-homebrew`. Stacks on `nix-nodejs` (PR #68) → `nix-prompt` (PR #67) → `nix-shells` (PR #66) → … → master. **Do NOT merge anything.**
- **Stacking machinery** (assumed from prior slices): `homeModules.{all,default,agent}`, `lib.mkHome`, profile imports, `--override-input public path:…` private-flake idiom, `nix/host.nix` (untracked) with `{ username; profile; }`.
- **Sandbox disable required for:** `nix`, `./apply`, `git commit` (gpg signing), `brew`, anything touching `/opt/homebrew/`, `~/.nix-profile/`. Use `dangerouslyDisableSandbox: true`. If `nix` isn't on PATH, prepend `source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh`.
- **Run commands from repo root** (`/Users/ian/projects/dotfiles`).
- **Pre-existing local state:**
  - `nix/host.nix` = `{ username = "ian"; profile = "default"; }`, untracked.
  - `~/.dotfilesrc` contains `DOTFILES_ENVIRONMENT=default`.
  - All formulas in the three public Brewfiles are currently brew-installed.
  - `bat` is currently installed via nix `programs.bat.enable = true` (Slice 1 demo content).
  - `ripgrep` is currently installed via nix `home.packages = [ pkgs.ripgrep ]` (Slice 1 demo content).
- **Conventional commits**, NO `Co-Authored-By: Claude` / `Generated with Claude Code` trailers.
- **No work-specific values.** Work-only formulas (custom taps) live only in `custom_environments/work/Brewfile`; this slice doesn't touch them.

---

## Task 1: Atomic brew-formulas migration

Single commit:

- Create `nix/profiles/all/cli-tools.nix` with all-profile formulas.
- Create `nix/profiles/default/cli-tools.nix` with default-profile formulas.
- Update `nix/profiles/all/default.nix` imports.
- Update `nix/profiles/default/default.nix` to gain an imports list + drop the ripgrep line.
- Delete `nix/profiles/all/bat.nix`.
- Update `nix/home.nix` to enable `nixpkgs.config.allowUnfree = true` (for terraform).
- Strip migrated `brew '...'` lines from `environments/all/Brewfile`, `environments/default/Brewfile`, `plugins/homebrew/Brewfile.erb`.
- Activate; verify each migrated tool resolves via nix; commit.

**Files:**

- Create: `nix/profiles/all/cli-tools.nix`
- Create: `nix/profiles/default/cli-tools.nix`
- Modify: `nix/profiles/all/default.nix` (imports `cli-tools.nix`; drops `bat.nix`)
- Modify: `nix/profiles/default/default.nix` (gains imports list; drops ripgrep line)
- Modify: `nix/home.nix` (enables `nixpkgs.config.allowUnfree`)
- Delete: `nix/profiles/all/bat.nix`
- Modify: `environments/all/Brewfile` (strip `brew '...'` lines)
- Modify: `environments/default/Brewfile` (strip `brew '...'` lines)
- Modify: `plugins/homebrew/Brewfile.erb` (strip aggregator `brew '...'` lines except `bash`, `bash-completion@2`, `mas`)

- [ ] **Step 1: Capture pre-flight state**

Run (sandbox disabled):

```bash
echo "=== brew formulas (top-level, not transitive deps) ==="
brew leaves 2>&1 | head -30
echo "(total $(brew leaves | wc -l) top-level formulas)"
echo ""
echo "=== brew list --formula (incl. transitive) ==="
brew list --formula 2>&1 | wc -l
echo ""
echo "=== representative tool resolutions ==="
for t in git vim gh ansible terraform awscli kubectl python3 jq; do
  printf '%-12s ' "$t"
  command -v "$t" 2>&1 || echo "(not found)"
done
echo ""
echo "=== nix profile demo packages ==="
ls -l "$HOME/.nix-profile/bin/bat" 2>&1 | head -1
ls -l "$HOME/.nix-profile/bin/rg" 2>&1 | head -1
echo ""
echo "=== nixpkgs allowUnfree currently? ==="
grep -nE 'allowUnfree' nix/home.nix nix/flake.nix nix/profiles/all/*.nix nix/profiles/default/*.nix 2>&1 | head -5 || echo "(not set)"
```

Save the output. Step 14's verification compares against it.

Expected: most tools resolve to `/opt/homebrew/bin/*`; bat and rg resolve to `~/.nix-profile/bin/*`; allowUnfree not currently set.

- [ ] **Step 2: Read the three Brewfiles to confirm starting state**

```bash
echo "=== environments/all/Brewfile ==="
grep -nE '^brew ' environments/all/Brewfile
echo "(total $(grep -cE '^brew ' environments/all/Brewfile))"
echo ""
echo "=== environments/default/Brewfile ==="
grep -nE '^brew ' environments/default/Brewfile
echo "(total $(grep -cE '^brew ' environments/default/Brewfile))"
echo ""
echo "=== plugins/homebrew/Brewfile.erb ==="
grep -nE '^brew ' plugins/homebrew/Brewfile.erb
echo "(total $(grep -cE '^brew ' plugins/homebrew/Brewfile.erb))"
```

Expected: roughly 24 / 15 / 5 brew lines respectively.

- [ ] **Step 3: Create `nix/profiles/all/cli-tools.nix`**

Write this content. The formula list maps the union of `environments/all/Brewfile`'s `brew ...` entries + the non-bash aggregator entries from `plugins/homebrew/Brewfile.erb` (coreutils, gh — but NOT bash, bash-completion@2, or mas — those stay in the Brewfile per Decisions 4 and 5).

```nix
{ pkgs, ... }: {
  # CLI tools that every machine gets. Migrated from
  # `environments/all/Brewfile` plus the non-bash aggregator entries in
  # `plugins/homebrew/Brewfile.erb` (coreutils, gh). The corresponding
  # `brew '<name>'` lines are removed from the Brewfiles by this same
  # slice; brew bundle cleanup uninstalls them on next apply and these
  # nix-installed versions take over via PATH precedence.
  home.packages = with pkgs; [
    # GNU coreutils + replacements for outdated macOS variants
    coreutils
    findutils
    gnused
    gnugrep
    gnumake
    wget

    # Dev essentials
    git
    git-lfs
    gh
    vim
    shellcheck
    tree
    watch
    watchman
    screen

    # AWS tooling
    awscli2
    chamber

    # Web / API
    httpie

    # Infrastructure
    terraform  # unfree; requires nixpkgs.config.allowUnfree = true
    tflint

    # Language runtimes
    openjdk
    python3

    # Shell extras (the zsh binary itself is provided by programs.zsh.enable)
    bash             # also stays in Brewfile per Decision 4 (bash-5 bootstrap)
    bash-completion  # also stays in Brewfile per Decision 4
    zsh-completions
  ];
}
```

**Implementer notes for Step 3:**

- The brew formula `gnu-sed` becomes `gnused`; `bash-completion@2` becomes `bash-completion` (nixpkgs has one version).
- `awscli` → `awscli2` (nixpkgs uses `awscli2` for the v2 series).
- `java` → `openjdk` (`pkgs.openjdk` is JDK; pin like `pkgs.openjdk21` if you want a specific major version — leave generic for now).
- `python` → `python3` (`pkgs.python3` is the meta-attribute pointing to the current stable).
- The brew `grep` is GNU grep; nix's `gnugrep` is the equivalent (it shadows macOS's built-in `grep` via PATH).
- The brew `make` is GNU make; nix's `gnumake` is the equivalent.
- `chamber` should exist as `pkgs.chamber` in nixpkgs 26.05; if not, leave the corresponding `brew 'chamber'` line in `environments/all/Brewfile` and remove `chamber` from the list above. Note this in your commit message.
- `terraform` is unfree (BSL license); Step 6 enables `allowUnfree` to permit it.

- [ ] **Step 4: Create `nix/profiles/default/cli-tools.nix`**

Write this content. Maps `environments/default/Brewfile`'s `brew ...` entries.

```nix
{ pkgs, ... }: {
  # CLI tools that only the `default` (personal) profile gets. Migrated from
  # `environments/default/Brewfile`. Agent profiles do NOT get these.
  home.packages = with pkgs; [
    # Configuration management / scripting
    ansible
    bats
    uv

    # AWS / cloud
    aws-sam-cli
    flyctl

    # YAML processing
    yq-go

    # Terraform-like IaC (the OpenTofu fork; we kept terraform in the
    # `all` profile and add opentofu here as the default-profile companion
    # — both available because some workflows still expect each).
    opentofu

    # Kubernetes / homelab tooling
    argo
    argocd
    cilium-cli
    kubernetes-helm
    k9s
    kubectl
    talosctl
  ];
}
```

**Implementer notes for Step 4:**

- `helm` → `kubernetes-helm` (renamed in nixpkgs).
- `yq` → `yq-go` (brew's `yq` is the Go implementation; nixpkgs distinguishes the Python and Go variants).
- `argo` — verify the binary in nixpkgs is what you expect (argo workflows CLI vs. argocd CLI vs. something else). brew's `argo` is the Argo Workflows CLI; nixpkgs has both `argo` and `argocd`.
- `argocd` should be `pkgs.argocd`.
- `cilium-cli`, `talosctl`, `k9s`, `kubectl` map 1:1.
- If any of `argo`, `cilium-cli`, `talosctl`, or any other formula isn't found in nixpkgs 26.05, leave the corresponding `brew '<name>'` line in `environments/default/Brewfile` and remove from the list above. Note this in your commit message.

- [ ] **Step 5: Modify `nix/profiles/all/default.nix` imports**

Read current content:

```bash
cat nix/profiles/all/default.nix
```

Expected: 4-entry imports list (`./bat.nix`, `./git.nix`, `./gpg.nix`, `./shells.nix`).

Replace the file with:

```nix
{ ... }: {
  # `all` is composed into every config by `lib.mkHome`, regardless of which
  # profile is active or whether a private flake overlays on top — anything
  # *every* machine should get goes here. Split into per-feature submodules
  # so each feature stays focused and reviewable.
  imports = [
    ./cli-tools.nix
    ./git.nix
    ./gpg.nix
    ./shells.nix
  ];
}
```

(Alphabetical order: `cli-tools` replaces `bat` at the top of the list.)

- [ ] **Step 6: Modify `nix/profiles/default/default.nix`**

Read current content:

```bash
cat nix/profiles/default/default.nix
```

Expected:

```nix
{ pkgs, ... }: {
  home.packages = [ pkgs.ripgrep ];

  # `settings.user.{name,email,signingkey}` is the current home-manager
  # option path. (`name` and `email` replace the deprecated
  # `userName`/`userEmail`; `signingkey` is just a new key under the same
  # `user` subsection.) The signing key id is a public GPG fingerprint —
  # fine to commit.
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

Replace with:

```nix
{ ... }: {
  imports = [
    ./cli-tools.nix
  ];

  # `settings.user.{name,email,signingkey}` is the current home-manager
  # option path. (`name` and `email` replace the deprecated
  # `userName`/`userEmail`; `signingkey` is just a new key under the same
  # `user` subsection.) The signing key id is a public GPG fingerprint —
  # fine to commit.
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

(The `home.packages = [ pkgs.ripgrep ];` line is gone. The module signature drops `pkgs` since `pkgs` is no longer referenced in the body — `programs.git.settings` is a typed option and doesn't need it. If the implementer prefers to leave the signature as `{ pkgs, ... }:` for defensive symmetry, that's acceptable.)

- [ ] **Step 7: Enable `nixpkgs.config.allowUnfree` in `nix/home.nix`**

Read current content:

```bash
cat nix/home.nix
```

Expected: 16-line file with `home.username`, `home.homeDirectory`, `home.stateVersion`, `programs.home-manager.enable`, and a comment.

Replace with:

```nix
{ pkgs, username, ... }:
{
  home.username = username;
  # Home directory differs by OS; Linux root is a special case (/root, not /home/root).
  home.homeDirectory =
    if pkgs.stdenv.isDarwin then "/Users/${username}"
    else if username == "root" then "/root"
    else "/home/${username}";
  home.stateVersion = "25.11"; # pins home-manager behavior; never bump casually
  programs.home-manager.enable = true; # home-manager manages itself

  # Allow installing unfree packages (terraform's BSL license, etc.).
  # Required for the `terraform` entry in `profiles/all/cli-tools.nix`.
  nixpkgs.config.allowUnfree = true;

  # Infrastructure only — shared content (universally-installed packages and
  # programs) lives in `profiles/all/default.nix`, which `lib.mkHome` always
  # composes alongside this base. Profile-specific additions live under
  # `profiles/<name>/default.nix`.
}
```

- [ ] **Step 8: Delete the demo `bat.nix`**

```bash
git rm nix/profiles/all/bat.nix
ls nix/profiles/all/bat.nix 2>&1 | head -1
```

Expected: `ls: cannot access 'nix/profiles/all/bat.nix'`.

- [ ] **Step 9: Strip migrated `brew '...'` lines from `environments/all/Brewfile`**

Read the current file:

```bash
cat environments/all/Brewfile
```

Edit it to remove EVERY `brew '<name>'` line. Also remove the `tap 'wata727/tflint'` line (the tap existed only for `tflint`; nix has `pkgs.tflint` without needing the tap). Keep all `cask`, `mas`, and comment lines.

Final content should be (with comments preserved where they still make sense):

```ruby
##
## Strongly Recommended
##
## Not necessarily required for functionality, but unclear if things will work
## without these upgrades
##

# CLI formulas migrated to nix (see nix/profiles/all/cli-tools.nix).
# Casks, mas, and taps remain here until the nix-darwin slice migrates them.

##
## AWS Tools
##

cask 'aws-vault'

##
## User
##
## Put your packages here
##

cask '1password'
cask '1password-cli'
cask 'docker'
cask 'elgato-control-center'
cask 'elgato-stream-deck'
cask 'fork'
cask 'firefox'
cask 'gitup'
cask 'gpg-suite'
cask 'grandperspective'
cask 'ngrok'
cask 'obsidian'
cask 'visual-studio-code'
cask 'vlc'
cask 'xquartz'

# Install App Store packages
# for some reason, Keynote, Numbers, and Pages insist on being reinstalled on
# every run, so, for the time being, they've been disabled.
# mas 'Keynote', id: 409_183_694
# mas 'Numbers', id: 409_203_825
# mas 'Pages', id: 409_201_541
mas 'Magnet', id: 441_258_766
mas 'Slack', id: 803_453_959
```

(The `Recommended` and other thematic comments are dropped along with their associated brew lines; the AWS/User sections shrink to the remaining cask/mas content. Keep the file readable.)

- [ ] **Step 10: Strip migrated `brew '...'` lines from `environments/default/Brewfile`**

Read the current file:

```bash
cat environments/default/Brewfile
```

Edit to remove every `brew '<name>'` line. Also remove the `tap 'siderolabs/tap'` line (existed only for `talosctl`; nix has `pkgs.talosctl` without the tap). Keep all `cask`, `mas`, and comment lines.

Final content:

```ruby
# CLI formulas migrated to nix (see nix/profiles/default/cli-tools.nix).
# Casks, mas, and taps remain here until the nix-darwin slice migrates them.

cask 'adobe-creative-cloud'
cask 'discord'
cask 'proton-mail'
cask 'quicken'
cask 'steam'
cask 'synology-drive'
cask 'webstorm'
# Not including in `all` because many companies may install it through MDM and
# I don't want to clobber that
cask 'zoom'

mas 'Byword', id: 420_212_497
mas 'Tailscale', id: 1_475_387_142

cask 'proton-mail-bridge'

# Homelab — CLI formulas migrated to nix; the cask/mas list above stays.
```

- [ ] **Step 11: Strip aggregator-level `brew '...'` lines from `plugins/homebrew/Brewfile.erb`**

Read the current file:

```bash
cat plugins/homebrew/Brewfile.erb
```

Edit to remove `brew 'coreutils'` and `brew 'gh'` (now in nix). KEEP `brew 'bash'`, `brew 'bash-completion@2'`, and `brew 'mas'`. Final content:

```erb
<%#
  Techincally, bash, bash-completion etc belong in a root level brewfile and not
  a plugin, but that's rather inconvenient just to service pedantry.
%>

cask_args appdir: '/Applications'

# bash + bash-completion@2 stay here AND in nix (see Decision 4 in the
# nix-brew-formulas spec): the framework's bash-5 bootstrap (framework/compat)
# needs brew's bash before nix is installed on a fresh machine. Nix's bash
# coexists for interactive use via ~/.nix-profile/bin/bash.
brew 'bash'
brew 'bash-completion@2'

# Enable Mac App Store (`mas`) entries in Brewfile.
# Stays here (not in nix) because mas is only useful while brew owns
# cask/mas installs; once nix-darwin's homebrew.masApps takes over, this
# line goes away too.
brew 'mas'

<%# DOTFILES_HOMEBREW_CONFIG_BREWFILES must contain full paths %>
<% ENV.fetch('DOTFILES_HOMEBREW_CONFIG_BREWFILES').split(' ').each do |filename| %>
# begin <%= filename %>
<%= File.read(filename) %>
# end <%= filename %>
<% end %>
```

- [ ] **Step 12: Verify all Nix files parse + the flake evaluates**

Run (sandbox disabled):

```bash
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
nix-instantiate --parse nix/profiles/all/default.nix >/dev/null && echo "all/default parses"
nix-instantiate --parse nix/profiles/all/cli-tools.nix >/dev/null && echo "all/cli-tools parses"
nix-instantiate --parse nix/profiles/default/default.nix >/dev/null && echo "default/default parses"
nix-instantiate --parse nix/profiles/default/cli-tools.nix >/dev/null && echo "default/cli-tools parses"
nix-instantiate --parse nix/home.nix >/dev/null && echo "home.nix parses"

nix --extra-experimental-features 'nix-command flakes' eval \
  "path:$PWD/nix#homeModules.all" --apply 'p: builtins.typeOf p' --raw; echo
nix --extra-experimental-features 'nix-command flakes' eval \
  "path:$PWD/nix#homeConfigurations.\"default@$(nix --extra-experimental-features 'nix-command flakes' eval --impure --raw --expr builtins.currentSystem)\".activationPackage.outPath" --raw; echo
```

Expected: all 5 parses succeed; `path` returned for the module; `/nix/store/…-home-manager-generation` path returned for the activation package.

If `terraform` causes an "unfree" error during evaluation, the `allowUnfree = true` in `nix/home.nix` from Step 7 isn't being picked up. Double-check the home.nix edit and that `pkgs` in the cli-tools.nix is the SAME pkgs instance (it is, since lib.mkHome passes one `pkgs` to all modules including home.nix).

If a package doesn't exist in nixpkgs 26.05 (e.g., `chamber`, `argo`), the eval will fail with "attribute 'X' missing". Fix by either:

- Removing the package from `cli-tools.nix` AND re-adding the corresponding `brew '<name>'` line back to the originating Brewfile.
- Finding the correct nixpkgs attribute name (e.g., maybe `argo` is `argo-workflows-cli`?) and updating the list.

Note the deviation in the commit message.

- [ ] **Step 13: Run home-manager activation**

Run (sandbox disabled — nix may need to download new packages; first run takes 2-5 min):

```bash
DOTFILES_ENVIRONMENT=default DOTFILES_ROOT_DIR="$PWD" bash -c '
  set -euo pipefail
  source framework/logging
  source plugins/nix/nix
  dotfiles_nix_apply
' 2>&1 | tail -30
```

Expected: activation succeeds. Many new package symlinks created in `~/.nix-profile/bin/`. No errors.

- [ ] **Step 14: Verify migrated tools resolve via nix**

```bash
echo "=== representative tools resolve to nix-profile ==="
for t in git vim gh ansible terraform awscli kubectl python3 helm bats yq tflint; do
  printf '%-12s ' "$t"
  which "$t" 2>&1 || echo "(not found)"
done
echo ""
echo "=== nix-profile contains all the new tools ==="
ls "$HOME/.nix-profile/bin/" | grep -E '^(git|vim|gh|ansible|terraform|aws|kubectl|python3|helm|bats|yq|tflint|argo|argocd|talosctl|cilium|wget|tree|watch|httpie|shellcheck|chamber|opentofu)' | head -25
echo ""
echo "=== zsh-completions in nix-profile ==="
ls "$HOME/.nix-profile/share/zsh/site-functions/" 2>&1 | head -5
echo ""
echo "=== representative tool versions ==="
git --version
terraform --version 2>&1 | head -1
kubectl version --client 2>&1 | head -2
python3 --version
gh --version 2>&1 | head -1
```

Expected: every tool resolves to `~/.nix-profile/bin/<tool>` (which symlinks into `/nix/store/`). PATH precedence (nix-profile before homebrew) means the nix versions win.

- [ ] **Step 15: Verify `bat` and `ripgrep` are gone from the nix profile**

```bash
echo "=== bat: should be absent from nix profile ==="
ls -l "$HOME/.nix-profile/bin/bat" 2>&1 | head -1
echo ""
echo "=== ripgrep (rg): should be absent from nix profile ==="
ls -l "$HOME/.nix-profile/bin/rg" 2>&1 | head -1
```

Expected: both report `No such file or directory`. They're no longer in `home.packages`.

(If you still have `bat` or `rg` shadowed via brew, they may still be on PATH via `/opt/homebrew/bin/` — that's brew's installation if it ever was one. Not our concern.)

- [ ] **Step 16: Cross-slice integrity check**

```bash
git config --get alias.fixup            # Slice 1
git config --get user.signingkey         # Slice 5
git config --get commit.gpgsign          # Slice 5
git --version                            # Slice 5 nixpkgs bump → 2.54.0
gpg --version | head -1                  # Slice 5
which starship                           # Slice 7
which fnm                                # Slice 8
node --version                           # Slice 8
zsh -ic 'alias psgrep' 2>&1 | grep -v gitstatus  # Slice 6
bash -lic 'alias psgrep' 2>&1 | head -3  # Slice 6
```

Expected: all return their expected values. No regressions.

- [ ] **Step 17: Idempotency check**

```bash
DOTFILES_ENVIRONMENT=default DOTFILES_ROOT_DIR="$PWD" bash -c '
  source framework/logging
  source plugins/nix/nix
  dotfiles_nix_apply
' 2>&1 | tail -8
```

Expected: activation runs cleanly; no errors. The generation may be a no-op (same hash as the first activation).

- [ ] **Step 18: Commit**

```bash
git add nix/profiles/all/cli-tools.nix nix/profiles/all/default.nix \
        nix/profiles/default/cli-tools.nix nix/profiles/default/default.nix \
        nix/home.nix \
        environments/all/Brewfile environments/default/Brewfile \
        plugins/homebrew/Brewfile.erb
git status --porcelain
git -c gpg.program="$(which gpg)" commit -m "feat(nix): migrate brew formulas to home.packages; remove bat/ripgrep demo"
git log --oneline -1
```

Expected porcelain entries:

- `M nix/profiles/all/default.nix` (imports list change)
- `A nix/profiles/all/cli-tools.nix`
- `D nix/profiles/all/bat.nix`
- `M nix/profiles/default/default.nix` (ripgrep removed; imports list added)
- `A nix/profiles/default/cli-tools.nix`
- `M nix/home.nix` (allowUnfree)
- `M environments/all/Brewfile`
- `M environments/default/Brewfile`
- `M plugins/homebrew/Brewfile.erb`

Commit succeeds, GPG-signed, no trailer.

---

## Task 2: README updates

Three changes to `nix/README.md` (same pattern as prior slices).

**Files:**

- Modify: `nix/README.md`

- [ ] **Step 1: Locate insertion points**

```bash
grep -n '^For the nodejs slice' nix/README.md
grep -n '^## Background' nix/README.md
grep -n '^### Public profiles and layers' nix/README.md
grep -n 'AND fnm for Node.js' nix/README.md
```

Expected: `For the nodejs slice` is the most recent sub-block; the new "For the brew-formulas slice" goes after its item 4 and before `The same shape applies to future slices`.

- [ ] **Step 2: Insert the "For the brew-formulas slice" sub-block**

Find the paragraph where the nodejs slice's item 4 ends with `…re-overriding this.`. Immediately AFTER that paragraph and BEFORE the line beginning `The same shape applies to future slices`, insert this block:

```markdown
For the brew-formulas slice (most CLI formulas migrated from Brewfiles to
`home.packages` via `nix/profiles/{all,default}/cli-tools.nix`; casks,
mas, and taps stay in Brewfiles until a later nix-darwin slice):

1. **Update your private flake** to add any of YOUR brew formulas that
   have nix equivalents to `home.packages` in a private module:

       { pkgs, ... }: {
         home.packages = with pkgs; [
           # …your private CLI tools…
         ];
       }

2. **Delete the corresponding `brew '<name>'` lines** from your private
   Brewfile. Keep cask, mas, and tap entries (those move in a later slice).

3. **First `./apply` after this slice** runs the brew step against your
   slimmed Brewfile; `brew bundle cleanup --force` uninstalls the formulas
   that no longer appear there, and the nix-installed versions take over
   via PATH precedence.

4. **Formulas without a nix equivalent** (e.g., custom-tap formulas from
   work-specific taps) STAY in your private Brewfile. The `homebrew.brews`
   option in a future nix-darwin slice will give you a declarative way to
   manage these.

5. **`bat` and `ripgrep` were proof-of-concept demo packages** added in
   the first nix slices to prove the migration was working. They're
   removed in this slice. If you actually want either, add them to
   `nix/profiles/<profile>/cli-tools.nix` (or your private flake) as
   ordinary `home.packages` entries.

```

(Note the trailing blank line.)

- [ ] **Step 3: Refresh the Background paragraph**

Find the `So far this manages:` sentence in `## Background`. Append before the period of the final clause:

```
; and CLI tools — most brew formulas migrated to `home.packages` (casks, mas, and taps still managed by the legacy `plugins/homebrew` until a later nix-darwin slice)
```

So the segment becomes: `…installs the LTS version on first apply; and CLI tools — most brew formulas migrated to \`home.packages\` (casks, mas, and taps still managed by the legacy \`plugins/homebrew\` until a later nix-darwin slice). See Profiles for the layering…`

- [ ] **Step 4: Refresh the `all`-layer parenthetical**

Find the bullet beginning `- \`all\` — always included via \`mkHome\`;`. Its parenthetical currently lists managed content ending with `AND fnm for Node.js version management`. Update to:

1. Remove `\`bat\`` from the parenthetical (we deleted it in Task 1).
2. Append `, AND a curated set of CLI tools via \`home.packages\`` before the closing paren.

So the parenthetical becomes:

```
(currently the shared git config — aliases, body, includes — via `programs.git`, GPG/agent setup with per-OS pinentry: `pinentry-mac` on macOS, `pinentry-tty` on Linux, bash + zsh via `programs.bash` + `programs.zsh` plus `.inputrc` via `home.file`, AND starship as the prompt, AND fnm for Node.js version management, AND a curated set of CLI tools via `home.packages`)
```

- [ ] **Step 5: Verify the changes**

```bash
grep -n 'For the brew-formulas slice' nix/README.md
grep -n 'CLI tools — most brew formulas migrated' nix/README.md
grep -n 'curated set of CLI tools via' nix/README.md
echo "=== verify bat removed from all-layer ==="
grep -nE '^- `all`.*bat' nix/README.md | head -2 || echo "(no bat reference in all-layer — correct)"
echo "=== fence balance ==="
grep -c '^```' nix/README.md
```

Expected: each grep returns at least one match (or "no bat reference" message); fence count is 0 or even.

- [ ] **Step 6: Commit**

```bash
git add nix/README.md
git -c gpg.program="$(which gpg)" commit -m "docs(nix): document brew-formulas slice + private-env migration"
git log --oneline -3
```

Expected: commit succeeds, GPG-signed. Top commits: this docs commit + the feat commit + earlier slice docs.

---

## Task 3: End-to-end verification (throwaway override + Linux container)

No commits.

**Files:** none committed.

- [ ] **Step 1: Throwaway private-profile additive home.packages override (macOS)**

```bash
mkdir -p custom_environments/throwaway/nix
cat > custom_environments/throwaway/nix/flake.nix <<'EOF'
{
  description = "Throwaway test profile (home.packages additive override)";

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
{ pkgs, ... }: {
  # Verify list-typed home.packages concatenates across layers.
  home.packages = with pkgs; [ cowsay ];
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
' 2>&1 | tail -8

echo "=== throwaway-added package is present ==="
ls -l "$HOME/.nix-profile/bin/cowsay" 2>&1 | head -1
cowsay --version 2>&1 | head -1 || echo "(cowsay not in PATH — check)"
echo ""
echo "=== public-layer packages still present ==="
which git
which terraform
```

Expected: throwaway activation succeeds; cowsay lands in nix-profile; the public-layer packages (git, terraform) still resolve. Concatenation works.

- [ ] **Step 2: Tear down**

```bash
rm -rf custom_environments/throwaway

DOTFILES_ENVIRONMENT=default DOTFILES_ROOT_DIR="$PWD" bash -c '
  set -euo pipefail
  source framework/logging
  source plugins/nix/nix
  dotfiles_nix_apply
' 2>&1 | tail -8

echo "=== cowsay removed ==="
ls "$HOME/.nix-profile/bin/cowsay" 2>&1 | head -1
echo ""
echo "=== git/terraform still work ==="
which git
which terraform
echo ""
echo "=== git status clean ==="
git status --porcelain
```

Expected: cowsay gone; git/terraform still resolve via nix; working tree clean.

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

  echo "=== all-profile tools installed ==="
  for t in git vim gh shellcheck tree wget; do
    printf "%-12s " "$t"
    which "$t" 2>&1 | head -1
  done

  echo ""
  echo "=== default-profile tools NOT installed (agent profile is lean) ==="
  for t in ansible terraform kubectl helm; do
    printf "%-12s " "$t"
    which "$t" 2>&1 | head -1 || echo "(not installed — correct on agent)"
  done

  echo ""
  echo "=== brew not invoked on Linux ==="
  command -v brew 2>&1 || echo "(brew absent — correct; Linux skips homebrew plugins)"
'
```

Expected:

- Container builds; agent profile activates.
- `all`-layer formulas (git, vim, gh, shellcheck, tree, wget) all resolve via nix.
- `default`-layer formulas (ansible, terraform, kubectl, helm) do NOT resolve (agent profile didn't import them).
- brew never enters the picture on Linux.

**Possible failure modes:** Docker not running; skip Step 3 if so. Network slow; activation downloads packages; up to 5 min on first run.

- [ ] **Step 4: Final state check**

```bash
git log --oneline master..nix-homebrew | head -5
git status --porcelain
echo "=== Brewfiles slimmed ==="
echo "  environments/all/Brewfile: $(grep -cE '^brew ' environments/all/Brewfile) brew lines (was ~24)"
echo "  environments/default/Brewfile: $(grep -cE '^brew ' environments/default/Brewfile) brew lines (was ~15)"
echo "  plugins/homebrew/Brewfile.erb: $(grep -cE '^brew ' plugins/homebrew/Brewfile.erb) brew lines (was 5; should be 3: bash, bash-completion@2, mas)"
echo ""
echo "=== brew bundle cleanup would now uninstall the migrated formulas on next ./apply ==="
echo "(test manually: ./apply; verify brew uninstalls the migrated formulas)"
```

Expected:

- Branch has 3 commits (spec + plan + feat + docs) on top of the prior 7-PR stack.
- Working tree clean.
- Brewfiles show 0/0/3 brew lines.

---

## Self-review (completed by plan author)

- **Spec coverage:**
  - Decision 1 (migrate ALL formulas in one slice) — Task 1 atomic commit ✓
  - Decision 2 (split between `all` and `default` mirroring Brewfile dispersal) — Task 1 Steps 3 + 4 ✓
  - Decision 3 (defer casks/mas/taps to nix-darwin slice) — Brewfile changes preserve cask/mas/tap lines ✓
  - Decision 4 (`bash` and `bash-completion@2` stay in Brewfile AND in nix) — Step 11 keeps both in Brewfile; Step 3 adds both to cli-tools.nix ✓
  - Decision 5 (untouched items: xcode Brewfile, work Brewfile, homebrew plugins, framework/compat, customize, shells.nix brewPathSetup) — plan doesn't modify any of these ✓
  - Decision 6 (no activation script; brew bundle cleanup handles it) — no migrate-script tasks ✓
  - Decision 7 (per-formula mapping is implementation work) — Step 3/4 list packages but acknowledge name-mapping is implementer-validated ✓
  - Decision 8 (no work-specific values) — Step 9/10 strip Brewfile content but the README sub-block in Task 2 is pattern-only ✓
  - Demo-package cleanup (`bat.nix` delete, ripgrep removal) — Steps 5, 6, 8 ✓
  - README updates (sub-block + Background + all-layer + bat-from-all-layer removal) — Task 2 ✓
  - Throwaway + Linux container verification — Task 3 ✓
- **Placeholder scan:** every step has concrete commands and code. Package lists in Steps 3/4 are concrete (with notes for the implementer to verify each in nixpkgs 26.05). No TBDs.
- **Type/name consistency:**
  - `nix/profiles/all/cli-tools.nix` and `nix/profiles/default/cli-tools.nix` — consistent paths throughout.
  - `nixpkgs.config.allowUnfree = true;` — referenced in Step 7 (creation) and Step 12 (verification).
  - `home.packages = with pkgs; [ … ];` syntax — consistent.
  - Brewfile paths — consistent.
- **Atomicity:** Task 1 is one commit (9 files changed: 2 created, 5 modified, 1 deleted, plus the home.nix tweak). Task 2 is one commit (1 file). Task 3 has no commits. Total: 2 new feat/docs commits on top of the spec + plan commits.
