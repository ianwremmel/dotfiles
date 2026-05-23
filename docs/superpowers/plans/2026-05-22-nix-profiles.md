# Nix Profiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-machine profile support to the Nix slice via `DOTFILES_ENVIRONMENT`, with the public flake serving as a module library that private flakes in `custom_environments/<env>/nix/` consume as an input.

**Architecture:** Public flake exposes `homeModules.{base, default, agent}` + a `lib.mkHome` helper + ready-made `homeConfigurations."<profile>@<system>"`. Private flakes declare `inputs.public` pointing to the published public repo (github:) by default; the `nix` plugin passes `--override-input public path:$DOTFILES_ROOT_DIR/nix` at build time so each apply runs against the current local public source (including its untracked `host.nix`). `./apply`'s Linux branch is extended to source `framework/environment` and run `environment_get_current` + `config_load`, matching the macOS framework's selection flow so the first-run `select` prompt fires identically on both platforms.

**Tech Stack:** Bash 5, Nix (flakes, `nix-command`), home-manager, the existing `framework/{logging,config,environment}` modules.

---

## Notes for the executor

- **Reference spec:** `docs/superpowers/specs/2026-05-22-nix-profiles-design.md`.
- **No automated test framework.** "Tests" are verification commands with expected output: observe failing state → implement → observe passing state → commit.
- **Branch:** work is on `nix-profiles`, off `nix-cross-platform`. Do **not** merge anything (PR #62 is still open and merging this slice is the user's call).
- **Stacking:** this slice depends on the cross-platform changes already on the parent branch. Where verifications reference the existing plugin behavior (e.g. `--extra-experimental-features` flag, `_dotfiles_nix_install` helper), that comes from the parent branch.
- **Sandbox:** `nix`, `docker`, and any `~/.gnupg` access need it disabled. Use the Bash tool's `dangerouslyDisableSandbox: true` for those. If `git commit` fails with `gpg: ... Operation not permitted`, retry the same commit with the sandbox disabled.
- **Run commands from the repo root** unless noted.
- **`nix/host.nix` already exists locally** as `{ username = "ian"; }` (gitignored). Tasks 3 will extend it to `{ username = "ian"; profile = "default"; }` via the plugin.
- **`~/.dotfilesrc` already exists locally** with `DOTFILES_ENVIRONMENT=default`, so the framework's `environment_get_current` will skip the prompt on this Mac.
- **Conventional commits**, no `Co-Authored-By` / `Generated with` trailers.
- **Network needed** for Task 4 (`nix flake lock` resolves the github: default of the throwaway private flake), even though the actual build uses `--override-input` to local.
- **You will not run `./apply`** in this plan — testing uses direct plugin invocation, which the cross-platform slice already established as the per-Task verification idiom and avoids triggering all the unrelated macOS plugins.

---

## Task 1: Update `apply`'s Linux branch

The cross-platform slice's Linux branch sources only `framework/logging` and the plugin. Extend it to also source `framework/config` and `framework/environment`, and to run the same two framework calls macOS's `framework_init` makes (`environment_get_current` + `config_load`). The macOS branch is unchanged.

**Files:**
- Modify: `apply` (the `if [ "$(uname -s)" = Linux ]` block)

- [ ] **Step 1: Read the current Linux branch**

Run: `sed -n '36,52p' apply`
Expected: shows the existing `if [ "$(uname -s)" = Linux ]; then … else … fi` block with the comment block above and the `set -euo pipefail` + sourcing inside.

- [ ] **Step 2: Replace the Linux branch**

Find this exact block in `apply`:
```bash
if [ "$(uname -s)" = Linux ]; then
  /usr/bin/env bash -c '
    set -euo pipefail
    export DOTFILES_ROOT_DIR; DOTFILES_ROOT_DIR="$(pwd)"
    source ./framework/logging
    source ./plugins/nix/nix
    dotfiles_nix_apply
  '
else
  /usr/bin/env bash -c 'source ./framework/framework && framework_apply'
fi
```
Replace with:
```bash
if [ "$(uname -s)" = Linux ]; then
  /usr/bin/env bash -c '
    set -euo pipefail
    export DOTFILES_ROOT_DIR; DOTFILES_ROOT_DIR="$(pwd)"
    source ./framework/logging
    source ./framework/config
    source ./framework/environment
    # The framework expects ~/.dotfilesrc to exist (config_read/_write).
    # Mode 0600 matches the framework first-run permissions.
    [ -f "$HOME/.dotfilesrc" ] || install -m 0600 /dev/null "$HOME/.dotfilesrc"
    environment_get_current   # may prompt + persist; same call framework_init makes
    config_load               # exports DOTFILES_ENVIRONMENT etc. from ~/.dotfilesrc
    source ./plugins/nix/nix
    dotfiles_nix_apply
  '
else
  /usr/bin/env bash -c 'source ./framework/framework && framework_apply'
fi
```

- [ ] **Step 3: Verify `apply` parses**

Run: `bash -n apply && echo "syntax OK"`
Expected: `syntax OK`.

- [ ] **Step 4: Verify the macOS branch is unchanged**

Run: `grep -A1 '^else$' apply | head -3`
Expected: shows `else` followed by `/usr/bin/env bash -c 'source ./framework/framework && framework_apply'` exactly — confirming the macOS path is preserved.

- [ ] **Step 5: Commit**

```bash
git add apply
git commit -m "feat(nix): match macOS env-selection UX on Linux apply branch"
```

---

## Task 2: Create the two public profile modules

Each is a directory with a `default.nix` entry — the convention every profile in the new design follows. No flake change yet (Task 3 wires them in).

**Files:**
- Create: `nix/profiles/default/default.nix`
- Create: `nix/profiles/agent/default.nix`

- [ ] **Step 1: Confirm the profile dirs don't yet exist (failing state)**

Run:
```bash
ls nix/profiles 2>/dev/null || echo "no profiles dir"
```
Expected: `no profiles dir`.

- [ ] **Step 2: Create `nix/profiles/default/default.nix`** with exactly:

```nix
{ pkgs, ... }: {
  home.sessionVariables.DOTFILES_PROFILE = "default";
  home.packages = [ pkgs.ripgrep ];
}
```

- [ ] **Step 3: Create `nix/profiles/agent/default.nix`** with exactly:

```nix
{ pkgs, ... }: {
  home.sessionVariables.DOTFILES_PROFILE = "agent";
  # Intentionally lean: no extra packages beyond the shared base.
}
```

- [ ] **Step 4: Verify both files parse as Nix**

Run (sandbox disabled — `nix-instantiate` talks to the daemon for path resolution; if `nix` isn't on PATH, first `source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh`):
```bash
nix-instantiate --parse nix/profiles/default/default.nix >/dev/null && echo "default profile parses OK"
nix-instantiate --parse nix/profiles/agent/default.nix   >/dev/null && echo "agent   profile parses OK"
```
Expected: both `parses OK` lines.

- [ ] **Step 5: Commit**

```bash
git add nix/profiles/default/default.nix nix/profiles/agent/default.nix
git commit -m "feat(nix): add public profile modules (default, agent)"
```

---

## Task 3: Rewrite `nix/flake.nix` and update the `nix` plugin (atomic)

The flake gains `homeModules`, `lib.mkHome`, and `homeConfigurations."<profile>@<system>"` (replacing the cross-platform slice's `<user>@<system>` naming). The plugin gains `_dotfiles_nix_resolve_profile`, writes `profile` into `host.nix`, branches the build by whether `custom_environments/<profile>/nix/flake.nix` exists, and passes `--override-input public path:$DOTFILES_ROOT_DIR/nix` on the private path. **These two file changes commit together** — the flake needs `host.profile` (only the new plugin writes it) and the plugin builds `<profile>@<system>` (only the new flake exposes it), so the repo would not evaluate between them.

**Files:**
- Modify: `nix/flake.nix` (full replacement)
- Modify: `plugins/nix/nix` (add helper; replace the host-write-and-build block)

- [ ] **Step 1: Read both files**

Run:
```bash
cat nix/flake.nix
sed -n '/^dotfiles_nix_apply/,/^}/p' plugins/nix/nix
```
Expected: the cross-platform versions described in this plan's preamble.

- [ ] **Step 2: Replace `nix/flake.nix` with exactly:**

```nix
{
  description = "ianwremmel dotfiles — public nix slice";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager, ... }:
    let
      supportedSystems = [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ];
      publicProfiles   = [ "default" "agent" ];
      inherit (nixpkgs) lib;

      host =
        if builtins.pathExists ./host.nix then import ./host.nix
        else throw "nix/host.nix not found — run ./apply (generates it) or create it: { username = \"<you>\"; profile = \"default\"; }";
    in {
      # Module library for downstream (private) flakes to consume.
      homeModules = {
        base    = ./home.nix;
        default = ./profiles/default/default.nix;
        agent   = ./profiles/agent/default.nix;
      };

      # Helper: build a homeConfiguration with the shared base + caller's extras.
      lib.mkHome = { system, username, modules ? [] }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          extraSpecialArgs = { inherit username; };
          modules = [ self.homeModules.base ] ++ modules;
        };

      # Ready-made configs for the no-private-overlay case, one per public profile × system.
      homeConfigurations = builtins.listToAttrs (lib.concatMap (system:
        map (profile: {
          name  = "${profile}@${system}";
          value = self.lib.mkHome {
            inherit system;
            inherit (host) username;
            modules = [ self.homeModules.${profile} ];
          };
        }) publicProfiles
      ) supportedSystems);
    };
}
```

- [ ] **Step 3: Update `plugins/nix/nix`** — add the resolver helper near the existing helpers (just above `dotfiles_nix_apply`):

Add this function between `_dotfiles_nix_install` and `dotfiles_nix_apply`:

```bash
_dotfiles_nix_resolve_profile () {
  # Both macOS and Linux populate DOTFILES_ENVIRONMENT via the framework's
  # config_load before this runs (see ./apply), so no per-platform fallback
  # is needed.
  echo "${DOTFILES_ENVIRONMENT:-default}"
}
```

- [ ] **Step 4: Replace the host-write-and-build block in `plugins/nix/nix`**

Find this exact block inside `dotfiles_nix_apply`:
```bash
  # Host-specific values (currently just the username) live in an untracked,
  # plugin-generated nix/host.nix so they stay out of git.
  printf '# Generated by the nix plugin — host-specific, not tracked in git.\n{ username = "%s"; }\n' \
    "$(whoami)" > "$DOTFILES_ROOT_DIR/nix/host.nix"

  # The flake exposes one homeConfigurations."<user>@<system>" per supported
  # system; build the one matching this machine.
  local system target
  system="$(nix "${nixflags[@]}" eval --impure --raw --expr 'builtins.currentSystem')"
  target="$(whoami)@$system"

  local tmpdir
  tmpdir="$(mktemp -d)"

  log "Building home-manager configuration ($target)"
  nix "${nixflags[@]}" build \
    "path:$DOTFILES_ROOT_DIR/nix#homeConfigurations.\"$target\".activationPackage" \
    --out-link "$tmpdir/result"

  log 'Activating home-manager configuration'
  "$tmpdir/result/activate"

  # Clean up on the success path. A failed build/activate aborts under `set -e`
  # before this and leaks one small temp dir, which is an acceptable rare case.
  rm -rf "$tmpdir"
```

Replace with:
```bash
  local profile
  profile="$(_dotfiles_nix_resolve_profile)"
  log "Resolved profile: $profile"

  # Host-specific values (username from whoami; profile from $DOTFILES_ENVIRONMENT)
  # live in an untracked, plugin-generated nix/host.nix so they stay out of git.
  printf '# Generated by the nix plugin — host-specific, not tracked in git.\n{ username = "%s"; profile = "%s"; }\n' \
    "$(whoami)" "$profile" > "$DOTFILES_ROOT_DIR/nix/host.nix"

  local system
  system="$(nix "${nixflags[@]}" eval --impure --raw --expr 'builtins.currentSystem')"

  # Choose flake + target based on whether a private flake exists for this profile.
  # Private path: build the env's flake; redirect its `public` input to current
  # local public source via --override-input (so untracked host.nix is visible
  # without invalidating the private's lock).
  local flake_ref target
  local priv_flake="$DOTFILES_ROOT_DIR/custom_environments/$profile/nix"
  local -a extra_args=()
  if [ -f "$priv_flake/flake.nix" ]; then
    flake_ref="path:$priv_flake"
    target="homeConfigurations.\"$system\".activationPackage"
    extra_args=(--override-input public "path:$DOTFILES_ROOT_DIR/nix")
    log "Building private profile '$profile' for $system (overriding public→local)"
  else
    flake_ref="path:$DOTFILES_ROOT_DIR/nix"
    target="homeConfigurations.\"$profile@$system\".activationPackage"
    log "Building public profile '$profile' for $system"
  fi

  local tmpdir
  tmpdir="$(mktemp -d)"
  nix "${nixflags[@]}" build "$flake_ref#$target" "${extra_args[@]}" --out-link "$tmpdir/result"

  log 'Activating home-manager configuration'
  "$tmpdir/result/activate"

  # Clean up on the success path. A failed build/activate aborts under `set -e`
  # before this and leaks one small temp dir, which is an acceptable rare case.
  rm -rf "$tmpdir"
```

- [ ] **Step 5: Verify both files parse**

Run:
```bash
bash -n plugins/nix/nix && echo "plugin syntax OK"
nix-instantiate --parse nix/flake.nix >/dev/null && echo "flake parses"
```
Expected: `plugin syntax OK` and `flake parses`.

- [ ] **Step 6: Verify the no-host-needed flake outputs evaluate**

Run (sandbox disabled — needs the daemon socket):
```bash
nix --extra-experimental-features 'nix-command flakes' eval \
  "path:$PWD/nix#lib.mkHome" --apply 'f: builtins.typeOf f' --raw
echo
nix --extra-experimental-features 'nix-command flakes' eval \
  "path:$PWD/nix#homeModules.default" --apply 'p: builtins.typeOf p' --raw
echo
```
Expected: `lambda` and `path` (lib.mkHome is a function; homeModules.default is a path).

- [ ] **Step 7: Run the plugin end-to-end on this Mac**

Run (sandbox disabled — full Nix build):
```bash
DOTFILES_ENVIRONMENT=default DOTFILES_ROOT_DIR="$PWD" bash -c '
  set -euo pipefail
  source framework/logging
  source plugins/nix/nix
  dotfiles_nix_apply
' 2>&1 | tail -8
```
Expected: log line `Resolved profile: default`, then `Building public profile 'default' for aarch64-darwin`, then `Activating home-manager configuration`, then the home-manager activation output. Exit code 0.

- [ ] **Step 8: Verify host.nix carries the profile field and the activated config includes ripgrep**

Run:
```bash
cat nix/host.nix
echo "---"
ls -l "$HOME/.nix-profile/bin/bat" "$HOME/.nix-profile/bin/rg"
"$HOME/.nix-profile/bin/rg" --version | head -1
```
Expected: `{ username = "ian"; profile = "default"; }` in `host.nix`; both `bat` and `rg` symlinked into `/nix/store/…`; an `ripgrep <version>` line.

- [ ] **Step 9: Confirm host.nix stayed untracked**

Run: `git status --porcelain nix/host.nix`
Expected: no output.

- [ ] **Step 10: Commit**

```bash
git add nix/flake.nix plugins/nix/nix
git commit -m "feat(nix): per-profile public flake + plugin resolver and build target"
```

---

## Task 4: Validate the throwaway-private flake path

End-to-end exercise of the private-flake composition (including `--override-input`, multi-file private modules, and the github: default in the template). This task creates files under `custom_environments/throwaway/` (gitignored), exercises them, then cleans up — **no commit**.

**Files:** none committed.

- [ ] **Step 1: Confirm starting state**

Run:
```bash
ls custom_environments/throwaway 2>/dev/null || echo "no throwaway yet"
cat nix/host.nix
```
Expected: `no throwaway yet` and `host.nix` showing `{ username = "ian"; profile = "default"; }` from Task 3.

- [ ] **Step 2: Create the throwaway private flake**

```bash
mkdir -p custom_environments/throwaway/nix
cat > custom_environments/throwaway/nix/flake.nix <<'EOF'
{
  description = "Private throwaway test profile";

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
  imports = [ ./helpers.nix ];
  home.sessionVariables.DOTFILES_PROFILE = "throwaway";
}
EOF

cat > custom_environments/throwaway/nix/helpers.nix <<'EOF'
{ pkgs, ... }: {
  # A distinct package not in the default profile, to prove the
  # multi-file private module reaches the activated config.
  home.packages = [ pkgs.jq ];
}
EOF
```

- [ ] **Step 3: Lock the throwaway flake against the current local public**

The github: default in the template can't yet point at this branch's new public flake (it hasn't merged to master), so lock the input against the local source instead. This produces a `flake.lock` in the throwaway dir.

Run (sandbox disabled):
```bash
cd custom_environments/throwaway/nix
nix --extra-experimental-features 'nix-command flakes' flake lock \
  --override-input public "path:$OLDPWD/nix"
ls -l flake.lock
cd "$OLDPWD"
```
Expected: a `flake.lock` exists with `public` pinned to a `path:`-style entry. (Verifying the github: default is reachable for standalone `nix flake check` is **deferred until this branch merges to master** — only then will the github: URL resolve to a public flake that exposes `homeModules.default`.)

- [ ] **Step 4: Drive the plugin to take the private path**

Run (sandbox disabled — full Nix build):
```bash
DOTFILES_ENVIRONMENT=throwaway DOTFILES_ROOT_DIR="$PWD" bash -c '
  set -euo pipefail
  source framework/logging
  source plugins/nix/nix
  dotfiles_nix_apply
' 2>&1 | tail -10
```
Expected: log lines `Resolved profile: throwaway` and `Building private profile 'throwaway' for aarch64-darwin (overriding public→local)`, then the build/activate output, exit 0.

- [ ] **Step 5: Verify both layers (`default` base + throwaway/helpers) landed**

Run:
```bash
cat nix/host.nix
echo "---"
ls -l "$HOME/.nix-profile/bin/bat" "$HOME/.nix-profile/bin/rg" "$HOME/.nix-profile/bin/jq"
"$HOME/.nix-profile/bin/jq" --version
```
Expected: `host.nix` shows `profile = "throwaway"`; all three of `bat` (from base), `rg` (from `public.homeModules.default`), and `jq` (from the throwaway helpers) are symlinked into `/nix/store/…`; `jq` prints a version. This proves base + public-default + private+helpers composed correctly.

- [ ] **Step 6: Tear down and restore the machine to the default profile**

Run:
```bash
rm -rf custom_environments/throwaway
DOTFILES_ENVIRONMENT=default DOTFILES_ROOT_DIR="$PWD" bash -c '
  set -euo pipefail
  source framework/logging
  source plugins/nix/nix
  dotfiles_nix_apply
' 2>&1 | tail -6
```
Expected: throwaway dir gone, plugin re-activates `default@aarch64-darwin`, `host.nix` is back to `{ username = "ian"; profile = "default"; }`.

- [ ] **Step 7: Confirm jq is gone and bat/rg remain**

Run:
```bash
ls -l "$HOME/.nix-profile/bin/jq" 2>&1 | head -1
ls -l "$HOME/.nix-profile/bin/bat" "$HOME/.nix-profile/bin/rg"
git status --porcelain
```
Expected: `jq` no longer present (`No such file or directory`); `bat` and `rg` still present; clean working tree (custom_environments was gitignored, throwaway is gone).

---

## Task 5: Document profiles in `nix/README.md`

Add a "Profiles" section after the existing "Install" / "Usage" sections, describing selection, the public/private split, and the private-flake template.

**Files:**
- Modify: `nix/README.md`

- [ ] **Step 1: Read the current README to find the insertion point**

Run: `cat nix/README.md`
Expected: shows the README ending with a "License" (or similar) section; sections include Install / Usage / Backout from the prior slices.

- [ ] **Step 2: Insert a Profiles section** before the Backout section. Add this block (preserve whatever section precedes Backout):

```markdown
## Profiles

Per-machine profiles select which extra modules layer on top of the shared
base. Selection reuses the framework's `DOTFILES_ENVIRONMENT` value — no new
variable — and is loaded the same way on both platforms (`./apply` runs
`environment_get_current` + `config_load` from the framework). The
plugin-generated `nix/host.nix` carries both `username` and `profile`.

### Public profiles

Public profiles live in this repo at `nix/profiles/<name>/default.nix`. This
slice ships two:

- `default` — the baseline (matches `DOTFILES_ENVIRONMENT=default`, which is
  the framework's default value).
- `agent` — lean, intended for headless / agent boxes.

The public flake exposes them as both a module library
(`homeModules.{base,default,agent}` + a `lib.mkHome` helper) and as
ready-made `homeConfigurations."<profile>@<system>"` outputs. When no private
flake matches the active profile, the plugin builds the matching public
config directly.

### Private profiles

Private/sensitive profiles live in your separate `custom_environments/` repo
as **flakes** at `custom_environments/<env>/nix/flake.nix`. The private flake
consumes the public flake as an input, composes on top of it, and exposes
`homeConfigurations."<system>"` (one per supported system; no profile prefix
because the env is implicit in the flake's location).

Template:

    {
      description = "Private profile for <env>";

      inputs = {
        # Default points at the published public repo so `nix flake check`
        # works in this private repo standalone. The dotfiles `nix` plugin
        # overrides this to a local `path:` at apply time, so day-to-day
        # builds use whatever local public source is current — including
        # its untracked host.nix.
        public.url = "github:ianwremmel/dotfiles?dir=nix";
        nixpkgs.follows      = "public/nixpkgs";
        home-manager.follows = "public/home-manager";
      };

      outputs = { self, public, ... }:
        let
          host = import (public + "/host.nix");
          supportedSystems = [ "aarch64-darwin" "x86_64-linux" ];
          mkConfig = system: public.lib.mkHome {
            inherit system;
            inherit (host) username;
            modules = [
              public.homeModules.default
              ./work.nix
            ];
          };
        in {
          homeConfigurations = builtins.listToAttrs (map
            (system: { name = system; value = mkConfig system; })
            supportedSystems);
        };
    }

`./work.nix` (or any name) is a normal home-manager module living alongside
`flake.nix` and may import siblings. The private flake gets its own
`flake.lock` (committed to your private repo) for standalone reproducibility.
```

- [ ] **Step 3: Verify fences balanced**

Run: `grep -c '```' nix/README.md`
Expected: an even number (or zero if the README uses indented code blocks throughout — confirm no orphaned ` ``` ` markers).

- [ ] **Step 4: Commit**

```bash
git add nix/README.md
git commit -m "docs(nix): document profiles selection and the private-flake template"
```

---

## Self-review (completed by plan author)

- **Spec coverage:**
  - Decision 1 (selector loaded uniformly via `framework/environment` + `config_load`): Task 1 ✓
  - Decision 2 (profile = `DOTFILES_ENVIRONMENT` verbatim): Task 3 (plugin resolver) ✓
  - Decision 3 (`host.nix` carries `profile`): Task 3 (plugin host-write) ✓
  - Decision 4 (private consumes public as input + `--override-input`): Task 3 (plugin build branch) + Task 4 (validation) ✓
  - Decision 5 (one directory-with-`default.nix` convention): Task 2 ✓
  - Decision 6 (per-profile packages + `DOTFILES_PROFILE` sentinel): Task 2 ✓
  - Decision 7 (output naming `<profile>@<system>` public, `<system>` private): Task 3 ✓
  - Docs: Task 5 ✓
  - Validation risks (untracked-file inclusion via `--override-input`; standalone `nix flake check`): Task 4 covers the first end-to-end; the second is explicitly deferred to post-merge per Task 4 Step 3.
- **Placeholder scan:** no TBD/TODO; all code/command blocks are complete. The "standalone `nix flake check`" caveat is an explicit deferral with stated reasoning (the github: default can't reach this branch's flake until merge), not a placeholder.
- **Type/name consistency:** `_dotfiles_nix_resolve_profile`, `homeConfigurations."<profile>@<system>"`, `homeConfigurations."<system>"`, `--override-input public path:…`, `host.nix` shape `{ username; profile; }`, and the throwaway flake module names (`./throwaway.nix`, `./helpers.nix`) are referenced consistently across tasks.
- **Atomicity:** flake rewrite + plugin update bundled in Task 3 to avoid an intermediate non-evaluable state (the flake reads `host.profile` only after the plugin writes it).
