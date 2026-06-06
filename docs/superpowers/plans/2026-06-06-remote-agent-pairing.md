# Remote-agent pairing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pair the laptop with one or more remote agents — a shared `core/common/pairing` bundle drives the client/server SSH wiring, `host.nix` carries the remote list, a successful local `./apply` pulls + re-applies on each remote, and the homelab dev-container config moves into this repo as a public environment.

**Architecture:** A configurable home-manager bundle (`dotfiles.pairing.mode = "off"|"client"|"server"`) absorbs the four files split across `environments/default` and `environments/agent` today. `lib/nix` bakes `DOTFILES_REMOTE_AGENTS` from `~/.dotfilesrc` into the generated `core/host.nix` and, after a successful apply, fans out over SSH. The dev-container becomes `environments/dev-container/`, inheriting the `agent` profile and porting `entrypoint.sh`'s runtime steps into home-manager activation scripts.

**Tech Stack:** Nix flakes, home-manager, nix-darwin, Bash (stock 3.2 for `apply`/`framework`/`lib/nix`; Nix-provided Bash 5 for activation scripts).

**Testing note — this repo has no automated test framework.** Verification is `/bin/bash -n` parse-checks, `shellcheck`, `nix eval`/`nix build`, comparing realized store paths, and `./apply`. Each task's "verify" steps use those. Linux-only home configs can be *evaluated* on macOS (`nix eval …drvPath`) but only *built* on Linux (in the container) — the plan marks which is which.

**Conventions to honor (from `core/CLAUDE.md`, `framework/CLAUDE.md`, user global rules):**
- `apply`, `framework/*`, `lib/nix` must parse under stock Bash 3.2 (no `mapfile`, `local -n`, `${var^^}`, associative arrays). Activation-script bash runs under Nix Bash 5, where those are fine.
- Conventional-commit messages; no `Co-Authored-By`/"Generated with" trailers.
- `git commit` here needs gpg signing, which fails under the command sandbox — run commit steps with the sandbox disabled.
- Sentence-case headings; straight quotes.

**One pre-flight decision baked into this plan (validate early in Task 8):** `environments/dev-container/flake.nix` references the `agent` profile via a *relative path input* `agent.url = "path:../agent"` with `agent.inputs.public.follows = "public"`. This keeps the agent layer local (no GitHub fetch) and lets `lib/nix`'s `--override-input public path:.../core` reach it transitively. If `nix flake metadata` rejects the relative input on this Nix version, the fallback is to add `--override-input agent path:.../environments/agent` in `lib/nix` — but try the relative input first; it is the lower-footprint option.

---

## Phase 1 — Extract the `pairing` bundle (pure refactor, no installed-output change)

### Task 1: Create the `pairing` bundle directory by moving the existing files

**Files:**
- Move: `environments/default/mac-agent/` → `core/common/pairing/mac-agent/`
- Move: `environments/agent/remote-agent/` → `core/common/pairing/remote-agent/`
- Create: `core/common/pairing/default.nix`
- Delete (after move): `environments/default/ssh.nix`, `environments/default/dev-container-agent.nix`, `environments/agent/sshd.nix`, `environments/agent/remote-agent.nix`

- [ ] **Step 1: Move the two asset trees with git mv (preserves content hashes)**

```bash
cd /Users/ian/projects/dotfiles
mkdir -p core/common/pairing
git mv environments/default/mac-agent core/common/pairing/mac-agent
git mv environments/agent/remote-agent core/common/pairing/remote-agent
```

- [ ] **Step 2: Write the bundle module `core/common/pairing/default.nix`**

This is a verbatim consolidation of `default/dev-container-agent.nix` + `default/ssh.nix` (client) and `agent/remote-agent.nix` + `agent/sshd.nix` (server), gated by `mode`. Names and paths are unchanged from today so the realized output is identical; Task 5 generalizes them.

```nix
{ config, lib, pkgs, ... }:
# Shared-optional pairing bundle: the SSH wiring that makes a laptop and its
# remote agents feel like one machine. An environment opts in by adding
# `public.homeModules.pairing` to its `modules` list and setting
# `dotfiles.pairing.mode`. `client` is the laptop side (the launchd mac-agent
# socket handler + a RemoteForward per paired remote); `server` is the agent
# side (the sshd drop-in + the remote-agent shims). The two halves live in one
# file so the socket protocol can't drift between them.
let
  cfg = config.dotfiles.pairing;

  # --- client (macOS) ---
  devContainerHost = "dev-container-dev-container";
  localSock = "${config.home.homeDirectory}/.dev-container-agent.sock";
  agentBin = "${config.home.homeDirectory}/.local/bin/dev-container-agent";

  # --- server (Linux) ---
  shimSrc = ./remote-agent;
  shimPrefix = toString shimSrc + "/";
  discovered = lib.listToAttrs (map
    (p:
      let name = lib.removePrefix shimPrefix (toString p); in
      lib.nameValuePair "bin/${name}" {
        source = p;
        executable = name != "_remote-agent.sh";
      })
    (builtins.filter
      (p: !(lib.hasInfix "/test/" (toString p)))
      (lib.filesystem.listFilesRecursive shimSrc)));
  aliases = lib.listToAttrs (map
    (n: lib.nameValuePair "bin/${n}" { source = shimSrc + "/open-link"; executable = true; })
    [ "xdg-open" "www-browser" ]);
  sshdDropIn = ''
    # Managed by the dotfiles `pairing` bundle (server mode). Copied into
    # /etc/ssh/sshd_config.d/ by hosts that opt in.

    # The login user is root; allow key-based root login, never a password.
    PermitRootLogin prohibit-password
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    PubkeyAuthentication yes

    # tmux -CC iTerm2 detection needs LC_TERMINAL forwarded from the client.
    # Only that one — locale (LANG/LC_*) comes from the agent profile's session
    # vars, so there's no need to widen the accepted-env surface.
    AcceptEnv LC_TERMINAL

    Banner /etc/issue
    StreamLocalBindUnlink yes
    PrintMotd no
    X11Forwarding no
  '';
in
{
  options.dotfiles.pairing = {
    mode = lib.mkOption {
      type = lib.types.enum [ "off" "client" "server" ];
      default = "off";
      description = "Pairing role: client (laptop), server (agent host), or off.";
    };
    remotes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "SSH host aliases of paired remotes; drives the client RemoteForward blocks.";
    };
  };

  config = lib.mkMerge [
    # CLIENT — macOS launchd socket handler + ssh RemoteForward to the agent.
    (lib.mkIf (cfg.mode == "client" && pkgs.stdenv.isDarwin) {
      home.file.".local/bin/dev-container-agent" = {
        source = ./mac-agent/agent.sh;
        executable = true;
      };
      launchd.agents.dev-container-agent = {
        enable = true;
        config = {
          ProgramArguments = [ agentBin ];
          inetdCompatibility.Wait = false;
          Sockets.Listener.SockPathName = localSock;
        };
      };
      programs.ssh.settings.${devContainerHost} = {
        ControlMaster = "auto";
        ControlPath = "~/.ssh/cm-%C";
        RemoteForward = "/run/remote-agent.sock ${localSock}";
      };
    })

    # SERVER — sshd drop-in + remote-agent shims (Linux).
    (lib.mkIf (cfg.mode == "server") {
      home.file = lib.mkIf pkgs.stdenv.isLinux (discovered // aliases // {
        ".config/agent/sshd.conf".text = sshdDropIn;
      });
      home.packages = lib.mkIf pkgs.stdenv.isLinux [
        pkgs.netcat-openbsd
        pkgs.iproute2
        pkgs.util-linux
      ];
      home.sessionVariables = lib.mkIf pkgs.stdenv.isLinux { BROWSER = "open-link"; };
      home.activation.installAgentSshdDropIn =
        lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          if [ "$(id -u)" = 0 ] && [ -f "$HOME/.config/agent/sshd.conf" ]; then
            run mkdir -p /etc/ssh/sshd_config.d
            run install -m 0644 "$HOME/.config/agent/sshd.conf" \
              /etc/ssh/sshd_config.d/agent.conf
          fi
        '';
    })
  ];
}
```

- [ ] **Step 3: Delete the four now-superseded env files**

```bash
cd /Users/ian/projects/dotfiles
git rm environments/default/ssh.nix \
       environments/default/dev-container-agent.nix \
       environments/agent/sshd.nix \
       environments/agent/remote-agent.nix
```

- [ ] **Step 4: Verify the bundle file parses as Nix**

Run: `nix eval --impure --expr 'let f = import ./core/common/pairing/default.nix; in builtins.isFunction f'`
Expected: `true`

(Do not commit yet — the env flakes don't reference the bundle until Task 2, and `default`/`agent` still import the deleted files until then. Tasks 1 and 2 commit together.)

### Task 2: Wire the bundle into `core`, `default`, and `agent`

**Files:**
- Modify: `core/flake.nix:19-24` (add `pairing` to `homeModules`)
- Modify: `environments/default/flake.nix:25` (modules list)
- Modify: `environments/default/home.nix:5-11` (drop deleted imports)
- Modify: `environments/agent/flake.nix:29` and `:43` (modules list)
- Modify: `environments/agent/home.nix:8-14` (drop deleted imports)

- [ ] **Step 1: Export the bundle from `core/flake.nix`**

Change the `homeModules` block:

```nix
      homeModules = {
        base = ./home.nix;
        all  = ./all/home/default.nix;

        claude  = ./common/claude;
        pairing = ./common/pairing;
      };
```

- [ ] **Step 2: `environments/default/home.nix` — remove the two deleted imports**

```nix
{ ... }: {
  # The `default` environment is the personal-machine one (vs. `agent`, which
  # stays lean). cli-tools.nix carries personal-machine CLI installs that
  # don't belong on agent boxes.
  imports = [
    ./claude.nix
    ./cli-tools.nix
    ./terminal-fonts.nix
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

- [ ] **Step 3: `environments/default/flake.nix` — opt into the bundle as client**

Change the `modules` line (currently `modules = [ ./home.nix public.homeModules.claude ];`) to:

```nix
            modules = [
              ./home.nix
              public.homeModules.claude
              public.homeModules.pairing
              { dotfiles.pairing.mode = "client"; }
            ];
```

- [ ] **Step 4: `environments/agent/home.nix` — remove the two deleted imports**

```nix
{ ... }: {
  # The `agent` environment is the reusable base for autonomous-agent hosts:
  # the tooling and machinery needed to run Claude (and other agents)
  # unattended over SSH. The homelab dev container consumes it through its own
  # flake and layers cluster-specific tooling on top. Anything host-specific
  # (a particular cluster's CLIs, that cluster's Grafana MCP) belongs in the
  # consuming environment, not here. The SSH-server / remote-agent wiring now
  # lives in the shared `pairing` bundle (server mode), opted into by the flake.
  imports = [
    ./cli-tools.nix
    ./claude.nix
    ./shell-extras.nix
  ];
}
```

- [ ] **Step 5: `environments/agent/flake.nix` — opt into the bundle as server**

Change the home `modules` line (`modules = [ ./home.nix public.homeModules.claude ];`) to:

```nix
            modules = [
              ./home.nix
              public.homeModules.claude
              public.homeModules.pairing
              { dotfiles.pairing.mode = "server"; }
            ];
```

Leave the `darwinConfigurations` block and `homeModules.agent = ./home.nix` unchanged.

- [ ] **Step 6: Capture the BEFORE store paths (run on `master`, before this branch's changes are built)**

Because Task 1+2 must produce byte-identical output, compare the realized activation package before vs. after. Capture the baseline from a clean checkout of `master`:

```bash
sys=$(nix eval --impure --raw --expr 'builtins.currentSystem')
echo "system: $sys"
# From a worktree/checkout at origin/master HEAD (no pairing changes):
git stash list  # ensure you know your state
nix build --no-link --print-out-paths \
  "path:/Users/ian/projects/dotfiles/environments/default#homeConfigurations.\"$sys\".activationPackage" \
  > /tmp/pairing-before-default.txt
cat /tmp/pairing-before-default.txt
```

If capturing from `master` is impractical mid-branch, instead record the path now from your working tree *before* applying Task 1+2 edits. The check that matters is before-vs-after the refactor.

- [ ] **Step 7: Verify AFTER store path is identical (the no-change proof)**

```bash
sys=$(nix eval --impure --raw --expr 'builtins.currentSystem')
nix build --no-link --print-out-paths \
  "path:/Users/ian/projects/dotfiles/environments/default#homeConfigurations.\"$sys\".activationPackage" \
  --override-input public "path:/Users/ian/projects/dotfiles/core" \
  > /tmp/pairing-after-default.txt
diff /tmp/pairing-before-default.txt /tmp/pairing-after-default.txt && echo "IDENTICAL"
```

Expected: `IDENTICAL` (same store path → byte-identical activation package). On macOS this proves the client path. If the path differs, inspect with `nix build … --out-link /tmp/r-after` then `diff -r` against a before build — the only legitimate differences are none; investigate any.

- [ ] **Step 8: Verify the `agent` (server) config evaluates for Linux**

`agent`'s server content is Linux-only and can't be *built* on macOS, but it must *evaluate*:

```bash
nix eval --raw \
  "path:/Users/ian/projects/dotfiles/environments/agent#homeConfigurations.\"x86_64-linux\".activationPackage.drvPath" \
  --override-input public "path:/Users/ian/projects/dotfiles/core"
```
Expected: a `/nix/store/….drv` path printed, no eval error. Confirm the sshd drop-in is present:
```bash
nix eval \
  "path:/Users/ian/projects/dotfiles/environments/agent#homeConfigurations.\"x86_64-linux\".config.home.file.\".config/agent/sshd.conf\".text" \
  --override-input public "path:/Users/ian/projects/dotfiles/core" 2>&1 | grep -q PermitRootLogin && echo "sshd drop-in present"
```
Expected: `sshd drop-in present`

- [ ] **Step 9: Commit (sandbox disabled — gpg signing)**

```bash
cd /Users/ian/projects/dotfiles
git add -A
git commit -m "refactor(pairing): extract client/server SSH wiring into core/common/pairing bundle"
```

---

## Phase 2 — `host.nix` carries the remote list; client wiring iterates it

### Task 3: Generate `remoteAgents` into `core/host.nix`

**Files:**
- Modify: `lib/nix:133-137` (the `host.nix` generator)

- [ ] **Step 1: Replace the `host.nix` generation block**

Current (lines 133-137):
```bash
  # The username (from whoami) lives in an untracked, generated
  # core/host.nix so it stays out of git. The selected $profile picks
  # the env's flake dir below but is not written into host.nix.
  printf '# Generated by lib/nix — host-specific, not tracked in git.\n{ username = "%s"; }\n' \
    "$(whoami)" > "$DOTFILES_ROOT_DIR/core/host.nix"
```

Replace with:
```bash
  # The username (from whoami) and the paired remote-agent list live in an
  # untracked, generated core/host.nix so they stay out of git. The selected
  # $profile picks the env's flake dir below but is not written into host.nix.
  # remoteAgents comes from DOTFILES_REMOTE_AGENTS in ~/.dotfilesrc (a
  # space-separated string, exported by config_load); empty/unset → []. Nix
  # can't read env vars under pure eval, so this generated file is how the
  # list crosses from ~/.dotfilesrc into the client flake.
  local _remotes_nix _r
  _remotes_nix=''
  for _r in ${DOTFILES_REMOTE_AGENTS:-}; do
    _remotes_nix="$_remotes_nix \"$_r\""
  done
  printf '# Generated by lib/nix — host-specific, not tracked in git.\n{ username = "%s"; remoteAgents = [%s ]; }\n' \
    "$(whoami)" "$_remotes_nix" > "$DOTFILES_ROOT_DIR/core/host.nix"
```

Note: the `for _r in ${DOTFILES_REMOTE_AGENTS:-}` is intentionally unquoted for word-splitting; `${…:-}` keeps it safe under `set -u`.

- [ ] **Step 2: Parse-check under stock Bash 3.2**

Run: `/bin/bash -n /Users/ian/projects/dotfiles/lib/nix && echo OK`
Expected: `OK`

- [ ] **Step 3: shellcheck**

Run: `shellcheck -s bash /Users/ian/projects/dotfiles/lib/nix`
Expected: no new errors for the edited block (`SC2086` word-splitting on `$_remotes_nix`/`$DOTFILES_REMOTE_AGENTS` is intentional — add `# shellcheck disable=SC2086` on the `for` line if shellcheck flags it).

- [ ] **Step 4: Functionally verify the generated file (isolated, no full apply)**

```bash
cd /Users/ian/projects/dotfiles
# Exercise the generator logic in isolation:
DOTFILES_REMOTE_AGENTS="host-a host-b" bash -c '
  _remotes_nix=""
  for _r in ${DOTFILES_REMOTE_AGENTS:-}; do _remotes_nix="$_remotes_nix \"$_r\""; done
  printf "{ username = \"%s\"; remoteAgents = [%s ]; }\n" "$(whoami)" "$_remotes_nix"
'
```
Expected: `{ username = "ian"; remoteAgents = [ "host-a" "host-b" ]; }`

Then the empty case:
```bash
DOTFILES_REMOTE_AGENTS="" bash -c '
  _remotes_nix=""
  for _r in ${DOTFILES_REMOTE_AGENTS:-}; do _remotes_nix="$_remotes_nix \"$_r\""; done
  printf "{ username = \"%s\"; remoteAgents = [%s ]; }\n" "$(whoami)" "$_remotes_nix"
'
```
Expected: `{ username = "ian"; remoteAgents = [ ]; }`

- [ ] **Step 5: Commit**

```bash
cd /Users/ian/projects/dotfiles
git add lib/nix
git commit -m "feat(pairing): bake DOTFILES_REMOTE_AGENTS into generated host.nix"
```

### Task 4: Thread `remoteAgents` into the client bundle

**Files:**
- Modify: `environments/default/flake.nix` (pass `remotes = host.remoteAgents`)

- [ ] **Step 1: Set `remotes` from `host.remoteAgents` in the default flake**

Change the inline pairing module added in Task 2:
```nix
            modules = [
              ./home.nix
              public.homeModules.claude
              public.homeModules.pairing
              { dotfiles.pairing = { mode = "client"; remotes = host.remoteAgents; }; }
            ];
```

`host` is already bound at the top of the flake (`host = import (public + "/host.nix")`). `host.remoteAgents` now exists because Task 3's generator always writes it.

- [ ] **Step 2: Verify the flake still evaluates with a remotes-bearing host.nix**

```bash
cd /Users/ian/projects/dotfiles
printf '{ username = "ian"; remoteAgents = [ "host-a" ]; }\n' > core/host.nix
sys=$(nix eval --impure --raw --expr 'builtins.currentSystem')
nix eval --raw \
  "path:/Users/ian/projects/dotfiles/environments/default#homeConfigurations.\"$sys\".activationPackage.drvPath" \
  --override-input public "path:/Users/ian/projects/dotfiles/core" >/dev/null && echo "evaluates"
```
Expected: `evaluates` (no error about a missing `remoteAgents` attribute).

- [ ] **Step 3: Commit**

```bash
cd /Users/ian/projects/dotfiles
git add environments/default/flake.nix
git commit -m "feat(pairing): pass host.remoteAgents into the client pairing bundle"
```

### Task 5: Generalize the client bundle — one RemoteForward per remote, renamed agent

**Files:**
- Modify: `core/common/pairing/default.nix` (client branch)
- Modify: `core/common/pairing/mac-agent/agent.sh` (SSH_HOST from launchd env; drop the conf-file fallback)

- [ ] **Step 1: Rewrite the client `let` bindings and branch in `core/common/pairing/default.nix`**

Replace the client `let` bindings:
```nix
  # --- client (macOS) ---
  devContainerHost = "dev-container-dev-container";
  localSock = "${config.home.homeDirectory}/.dev-container-agent.sock";
  agentBin = "${config.home.homeDirectory}/.local/bin/dev-container-agent";
```
with:
```nix
  # --- client (macOS) ---
  sock = "${config.home.homeDirectory}/.remote-agent.sock";
  agentBin = "${config.home.homeDirectory}/.local/bin/remote-agent";
  # OAuth callback port-forwarding (the FORWARD verb) targets a single host;
  # use the first paired remote. Multi-remote callback forwarding is out of
  # scope — the socket-based open-link/clipboard/sound verbs work for all
  # remotes since they don't need to know which remote a request came from.
  primaryRemote = if cfg.remotes == [ ] then "" else builtins.head cfg.remotes;
  # One ssh Host block per paired remote: forward the agent's
  # /run/remote-agent.sock back to this machine's local socket.
  remoteSshBlocks = lib.listToAttrs (map
    (h: lib.nameValuePair h {
      ControlMaster = "auto";
      ControlPath = "~/.ssh/cm-%C";
      RemoteForward = "/run/remote-agent.sock ${sock}";
    })
    cfg.remotes);
```

Replace the client `config` branch:
```nix
    (lib.mkIf (cfg.mode == "client" && pkgs.stdenv.isDarwin) {
      home.file.".local/bin/remote-agent" = {
        source = ./mac-agent/agent.sh;
        executable = true;
      };
      launchd.agents.remote-agent = {
        enable = true;
        config = {
          ProgramArguments = [ agentBin ];
          # The handler reads SSH_HOST for the FORWARD verb; point it at the
          # primary paired remote (empty when none are configured).
          EnvironmentVariables.SSH_HOST = primaryRemote;
          # Per-connection socket activation: launchd wires the accepted
          # connection to the handler's stdin/stdout (Wait=false).
          inetdCompatibility.Wait = false;
          Sockets.Listener.SockPathName = sock;
        };
      };
      programs.ssh.settings = remoteSshBlocks;
    })
```

- [ ] **Step 2: Simplify `core/common/pairing/mac-agent/agent.sh` SSH_HOST resolution**

Replace lines 12-21 (the `SSH_HOST`/`AGENT_CONF` block):
```bash
# Which ssh Host (ControlMaster) to inject port forwards into. Read from a
# config file install.sh writes, unless already set in the environment.
SSH_HOST="${SSH_HOST:-}"
if [ -z "$SSH_HOST" ]; then
    AGENT_CONF="${AGENT_CONF:-$HOME/.dev-container-agent.conf}"
    # `if` (not `&&`): a bare `[ -f x ] && .` would exit non-zero when the
    # conf is absent and abort the whole agent under `set -euo pipefail`.
    if [ -f "$AGENT_CONF" ]; then . "$AGENT_CONF"; fi
fi
SSH_HOST="${SSH_HOST:-dev-container-dev-container}"
```
with:
```bash
# Which ssh Host (ControlMaster) to inject OAuth callback port forwards into.
# Set by the launchd job (EnvironmentVariables.SSH_HOST = the primary paired
# remote). Empty when no remotes are configured; FORWARD/UNFORWARD then no-op.
SSH_HOST="${SSH_HOST:-}"
```

Then guard the two `ssh -O` calls so an empty `SSH_HOST` is a no-op. Change the `FORWARD` body:
```bash
        ssh -O forward -L "$arg:127.0.0.1:$arg" -- "$SSH_HOST" >/dev/null 2>&1 || true
```
to:
```bash
        if [ -n "$SSH_HOST" ]; then
            ssh -O forward -L "$arg:127.0.0.1:$arg" -- "$SSH_HOST" >/dev/null 2>&1 || true
        fi
```
and the `UNFORWARD` body:
```bash
        ssh -O cancel -L "$arg:127.0.0.1:$arg" -- "$SSH_HOST" >/dev/null 2>&1 || true
```
to:
```bash
        if [ -n "$SSH_HOST" ]; then
            ssh -O cancel -L "$arg:127.0.0.1:$arg" -- "$SSH_HOST" >/dev/null 2>&1 || true
        fi
```

- [ ] **Step 3: Parse-check the handler script**

Run: `bash -n /Users/ian/projects/dotfiles/core/common/pairing/mac-agent/agent.sh && echo OK`
Expected: `OK`

- [ ] **Step 4: Verify per-remote ssh blocks are generated (macOS)**

```bash
cd /Users/ian/projects/dotfiles
printf '{ username = "ian"; remoteAgents = [ "host-a" "host-b" ]; }\n' > core/host.nix
sys=$(nix eval --impure --raw --expr 'builtins.currentSystem')
nix eval --json \
  "path:/Users/ian/projects/dotfiles/environments/default#homeConfigurations.\"$sys\".config.programs.ssh.settings" \
  --override-input public "path:/Users/ian/projects/dotfiles/core" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print([k for k in d if k in ("host-a","host-b")])'
```
Expected: `['host-a', 'host-b']`

Then confirm the empty case yields no pairing blocks:
```bash
printf '{ username = "ian"; remoteAgents = [ ]; }\n' > core/host.nix
nix eval --json \
  "path:/Users/ian/projects/dotfiles/environments/default#homeConfigurations.\"$sys\".config.programs.ssh.settings" \
  --override-input public "path:/Users/ian/projects/dotfiles/core" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print(sorted(d.keys()))'
```
Expected: a list with the shared `core/all/home/ssh.nix` hosts (`github.com`, `no-auto-trust`, `*`) and **no** `host-a`/`host-b`.

- [ ] **Step 5: Verify the launchd plist carries the renamed label + SSH_HOST**

```bash
printf '{ username = "ian"; remoteAgents = [ "host-a" ]; }\n' > core/host.nix
sys=$(nix eval --impure --raw --expr 'builtins.currentSystem')
nix build --no-link --print-out-paths \
  "path:/Users/ian/projects/dotfiles/environments/default#homeConfigurations.\"$sys\".activationPackage" \
  --override-input public "path:/Users/ian/projects/dotfiles/core" --out-link /tmp/r-client
grep -rl 'remote-agent' /tmp/r-client/home-files/Library/LaunchAgents/ 2>/dev/null && \
  grep -q 'host-a' /tmp/r-client/home-files/Library/LaunchAgents/*remote-agent* && echo "SSH_HOST wired"
```
Expected: a plist filename printed and `SSH_HOST wired`. (The plist label is `…remote-agent`; it includes `SSH_HOST` = `host-a`.)

- [ ] **Step 6: Run the real apply on the laptop (the actual client check)**

Run: `cd /Users/ian/projects/dotfiles && DOTFILES_ENVIRONMENT=default ./apply`
Expected: completes; `~/.remote-agent.sock` is served by the new `remote-agent` launchd job (`launchctl list | grep remote-agent`), and `~/.ssh/config` has a `Host` block per entry in `DOTFILES_REMOTE_AGENTS`.

- [ ] **Step 7: Commit**

```bash
cd /Users/ian/projects/dotfiles
git checkout core/host.nix 2>/dev/null || true   # discard the test-generated file if tracked; it's gitignored
git add core/common/pairing/default.nix core/common/pairing/mac-agent/agent.sh
git commit -m "feat(pairing): generate one RemoteForward per remote; rename mac-agent to remote-agent"
```

---

## Phase 3 — The `dev-container` environment

### Task 6: Scaffold `environments/dev-container/` (flake + repos list)

**Files:**
- Create: `environments/dev-container/flake.nix`
- Create: `environments/dev-container/repos.txt`

- [ ] **Step 1: Write `environments/dev-container/flake.nix`**

```nix
{
  description = "ianwremmel dotfiles — dev-container environment (agent profile + homelab cluster tooling)";

  # Linux-only (the homelab dev container). Inherits the generic `agent`
  # profile via a relative path input so the agent layer comes from this local
  # checkout (no GitHub fetch); `agent.inputs.public.follows = "public"` makes
  # the agent layer build against the same core that lib/nix overrides to local.
  inputs = {
    public.url = "github:ianwremmel/dotfiles?dir=core";
    agent.url = "path:../agent";
    agent.inputs.public.follows = "public";
    nixpkgs.follows      = "public/nixpkgs";
    home-manager.follows = "public/home-manager";
    nix-darwin.follows   = "public/nix-darwin";
  };

  outputs = { self, public, agent, ... }:
    let
      host = import (public + "/host.nix");
      systems = [ "x86_64-linux" "aarch64-linux" ];
    in {
      # Agent profile + this container's cluster tooling, opting into the
      # pairing bundle as a server (the agent home module can't carry bundles
      # across the flake boundary, so add them here explicitly).
      homeConfigurations = builtins.listToAttrs (map
        (system: {
          name = system;
          value = public.lib.mkHome {
            inherit system;
            inherit (host) username;
            modules = [
              agent.homeModules.agent
              ./dev-container.nix
              public.homeModules.pairing
              { dotfiles.pairing.mode = "server"; }
            ];
          };
        })
        systems);
    };
}
```

- [ ] **Step 2: Write `environments/dev-container/repos.txt`**

```
ianwremmel/apps
ianwremmel/homelab
ianwremmel/llc-infrastructure
ianwremmel/dotfiles
```

- [ ] **Step 3: Validate the relative `agent` path input resolves (the pre-flight decision)**

```bash
cd /Users/ian/projects/dotfiles
nix flake metadata "path:/Users/ian/projects/dotfiles/environments/dev-container" \
  --override-input public "path:/Users/ian/projects/dotfiles/core" 2>&1 | head -30
```
Expected: metadata prints with `agent` resolved to the local `environments/agent` path and `public` to local `core`, no fetch error. **If it errors on the relative path input**, apply the fallback from the plan header: keep `agent.url = "github:ianwremmel/dotfiles?dir=environments/agent"` and add `--override-input agent "path:$DOTFILES_ROOT_DIR/environments/agent"` to the `nix build` in `lib/nix` (note this in Task 9). Re-run until metadata resolves locally.

- [ ] **Step 4: Commit (the env doesn't build yet — `dev-container.nix` is Task 7; commit the scaffold)**

Skip the commit until Task 7 so the env is buildable in one commit. Proceed to Task 7.

### Task 7: Write `environments/dev-container/dev-container.nix` (tooling + activation scripts)

**Files:**
- Create: `environments/dev-container/dev-container.nix`

This combines the tooling/MCP/ssh-pin from the old homelab `dev-container.nix` with the three runtime blocks ported from `entrypoint.sh` as idempotent activation scripts. Tools are referenced by store path (`${pkgs.X}/bin/X`) because activation runs before the new packages are on `PATH`; `bk` (Buildkite CLI, not in nixpkgs here) stays a `command -v` probe. The Garage endpoint is read from `$GARAGE_ENDPOINT` (no hostname committed). Each script is wrapped so a failure warns but does not abort `./apply`, and is skipped under `home-manager switch -n` (`$DRY_RUN_CMD` set).

- [ ] **Step 1: Write the module**

```nix
{ pkgs, lib, ... }:
let
  jsonFormat = pkgs.formats.json { };

  # Grafana MCP server — homelab-specific (points at this cluster's Grafana), so
  # it lives here rather than in the shared agent profile. The agent profile's
  # claude.nix exports the base MCP list to ~/.config/agent/mcp-servers.json;
  # this file sits alongside it for the host to merge at boot.
  grafanaMcp = jsonFormat.generate "mcp-servers-homelab.json" {
    servers = [
      {
        name = "grafana";
        transport = "stdio";
        command = "mcp-grafana";
        args = [ "-t" "stdio" ];
        env = {
          GRAFANA_URL = "http://kube-prometheus-stack-grafana.monitoring.svc.cluster.local";
          GRAFANA_SERVICE_ACCOUNT_TOKEN = "$GRAFANA_SERVICE_ACCOUNT_TOKEN";
        };
      }
    ];
  };

  jq = "${pkgs.jq}/bin/jq";
  git = "${pkgs.git}/bin/git";
  gh = "${pkgs.gh}/bin/gh";
  aws = "${pkgs.awscli2}/bin/aws";
  talosctl = "${pkgs.talosctl}/bin/talosctl";
  kubectl = "${pkgs.kubectl}/bin/kubectl";
in
{
  # Cluster / infra tooling that used to be hand-downloaded in the Dockerfile.
  # Versions track nixpkgs; if a tool needs to match the cluster exactly
  # (talosctl / kubectl skew), pin it here via an overlay.
  home.packages = with pkgs; [
    kubectl
    kubernetes-helm
    argocd
    argo-workflows # the `argo` CLI
    talosctl
    opentofu
    yq-go
    aws-sam-cli
    flyctl
    bats
    mcp-grafana
    awscli2 # also used by the cluster-credential activation script
  ];

  home.file.".config/agent/mcp-servers-homelab.json".source = grafanaMcp;

  # Force the mounted Claude Bot key for github.com so `git push` attributes to
  # the bot, not whatever the operator forwards over `ssh -A`. Merges with the
  # shared programs.ssh github.com block (User/HostName/PreferredAuthentications).
  programs.ssh.settings."github.com" = {
    IdentityFile = "~/.ssh/id_ed25519";
    IdentitiesOnly = "yes";
    IdentityAgent = "none";
  };

  # --- Runtime bootstrap, ported from the homelab entrypoint.sh. Each runs on
  # every apply (idempotent), reads secrets from env vars at activation time
  # (never baked into the store), and soft-fails so a missing secret or down
  # endpoint warns rather than aborting the apply. ---

  # Credentials: restore Claude/Codex tokens (newer-wins by expiry), configure
  # the bk CLI org, and set the git identity from the GitHub token.
  home.activation.restoreAgentCredentials =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      # Wrap (don't `exit`) the dry-run guard: activation entries are sourced
      # into one script, so a top-level `exit` would kill the whole activation.
      if [ -z "$DRY_RUN_CMD" ]; then
      (
        set +e
        if [ -n "''${CLAUDE_CREDENTIALS:-}" ] && echo "$CLAUDE_CREDENTIALS" | ${jq} empty 2>/dev/null; then
          mkdir -p "$HOME/.claude"
          if [ ! -f "$HOME/.claude/.credentials.json" ]; then
            echo "$CLAUDE_CREDENTIALS" > "$HOME/.claude/.credentials.json"
            chmod 600 "$HOME/.claude/.credentials.json"
          else
            disk=$(${jq} -r '.claudeAiOauth.expiresAt // 0' "$HOME/.claude/.credentials.json" 2>/dev/null || echo 0)
            env=$(echo "$CLAUDE_CREDENTIALS" | ${jq} -r '.claudeAiOauth.expiresAt // 0')
            if [ "$env" -gt "$disk" ] 2>/dev/null; then
              echo "$CLAUDE_CREDENTIALS" > "$HOME/.claude/.credentials.json"
              chmod 600 "$HOME/.claude/.credentials.json"
            fi
          fi
        fi
        if [ -n "''${CODEX_CREDENTIALS:-}" ] && echo "$CODEX_CREDENTIALS" | ${jq} empty 2>/dev/null; then
          mkdir -p "$HOME/.codex"
          if [ ! -f "$HOME/.codex/auth.json" ]; then
            echo "$CODEX_CREDENTIALS" > "$HOME/.codex/auth.json"
            chmod 600 "$HOME/.codex/auth.json"
          else
            disk=$(${jq} -r '.expires_at // 0' "$HOME/.codex/auth.json" 2>/dev/null || echo 0)
            env=$(echo "$CODEX_CREDENTIALS" | ${jq} -r '.expires_at // 0')
            if [ "$env" -gt "$disk" ] 2>/dev/null; then
              echo "$CODEX_CREDENTIALS" > "$HOME/.codex/auth.json"
              chmod 600 "$HOME/.codex/auth.json"
            fi
          fi
        fi
        if [ -n "''${BUILDKITE_API_TOKEN:-}" ] && command -v bk >/dev/null 2>&1 \
            && ! grep -q 'selected_org' "$HOME/.config/bk.yaml" 2>/dev/null; then
          mkdir -p "$HOME/.config"
          bk config set selected_org ianremmelllc 2>/dev/null || true
        fi
        if [ -n "''${GITHUB_TOKEN:-}" ]; then
          if gh_json=$(${gh} api user 2>/dev/null); then
            login=$(echo "$gh_json" | ${jq} -r '.login // empty')
            name=$(echo  "$gh_json" | ${jq} -r '.name  // empty')
            email=$(echo "$gh_json" | ${jq} -r '.email // empty')
            if [ -n "$login" ]; then
              [ -z "$name" ]  && name="$login"
              [ -z "$email" ] && email="$login@users.noreply.github.com"
              ${git} config --global user.name  "$name"
              ${git} config --global user.email "$email"
            fi
          fi
        fi
      ) || echo "[pairing] WARNING: credential restore aborted unexpectedly" >&2
      fi
    '';

  # Project repos: clone (or fetch) the slugs in repos.txt into ~/projects.
  home.activation.cloneAgentProjects =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ -z "$DRY_RUN_CMD" ]; then
      (
        set +e
        repos_file=${./repos.txt}
        projects="$HOME/projects"
        mkdir -p "$projects"
        while IFS= read -r slug; do
          slug="''${slug%%#*}"
          slug="$(echo "$slug" | tr -d '[:space:]')"
          [ -z "$slug" ] && continue
          case "$slug" in
            *[!A-Za-z0-9._/-]* | *..* | /* | */ | */*/*)
              echo "[pairing] skipping malformed repo slug '$slug'" >&2; continue ;;
          esac
          case "$slug" in */*) ;; *) echo "[pairing] skipping repo slug without owner '$slug'" >&2; continue ;; esac
          name="''${slug##*/}"
          dest="$projects/$name"
          if [ -d "$dest/.git" ]; then
            ${git} -C "$dest" fetch --all --prune --quiet || echo "[pairing] fetch failed: $slug" >&2
          else
            [ -e "$dest" ] && rm -rf "$dest"
            ${git} clone --quiet "git@github.com:$slug.git" "$dest" || echo "[pairing] clone failed: $slug" >&2
          fi
        done < "$repos_file"
      ) || echo "[pairing] WARNING: project clone aborted unexpectedly" >&2
      fi
    '';

  # Cluster credentials: fetch Terraform state from Garage S3 and derive
  # talosconfig/kubeconfig. Endpoint comes from $GARAGE_ENDPOINT (no hostname
  # committed); skipped when it or the AWS creds are unset.
  home.activation.bootstrapClusterCreds =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ -z "$DRY_RUN_CMD" ]; then
      (
        set +e
        if [ -z "''${GARAGE_ENDPOINT:-}" ] || [ -z "''${AWS_ACCESS_KEY_ID:-}" ] || [ -z "''${AWS_SECRET_ACCESS_KEY:-}" ]; then
          echo "[pairing] cluster creds: GARAGE_ENDPOINT or AWS creds unset; skipping" >&2
          exit 0
        fi
        state_tmp=$(mktemp "''${TMPDIR:-/tmp}/tofu-state.XXXXXX.json")
        trap 'rm -f "$state_tmp"' EXIT
        if ! ${aws} --endpoint-url "$GARAGE_ENDPOINT" --region us-east-1 \
             s3 cp "s3://terraform-state/homelab/terraform.tfstate" "$state_tmp" --no-progress >/dev/null 2>&1; then
          echo "[pairing] cluster creds: state fetch from Garage failed" >&2; exit 0
        fi
        mkdir -p "$HOME/.talos" "$HOME/.kube"
        if ! ${jq} -er '.outputs.talosconfig.value' "$state_tmp" > "$HOME/.talos/config" 2>/dev/null; then
          echo "[pairing] cluster creds: state missing talosconfig output" >&2; exit 0
        fi
        chmod 600 "$HOME/.talos/config"
        ips_json=$(${jq} -ce '.outputs.controlplane_ips.value | select(type == "array" and length > 0)' "$state_tmp" 2>/dev/null) || {
          echo "[pairing] cluster creds: state missing/empty controlplane_ips" >&2; exit 0; }
        mapfile -t ips < <(echo "$ips_json" | ${jq} -r '.[]')
        first_ip="''${ips[0]}"
        ${talosctl} config endpoint "''${ips[@]}"
        ${talosctl} config node "$first_ip"
        if ! ${talosctl} kubeconfig --force "$HOME/.kube/config" >/dev/null 2>&1; then
          echo "[pairing] cluster creds: talosctl kubeconfig failed" >&2; exit 0
        fi
        chmod 600 "$HOME/.kube/config"
        ${kubectl} config set-cluster homelab-cluster --server="https://$first_ip:6443" >/dev/null
        ${kubectl} config set-context --current --namespace=argocd >/dev/null
        echo "[pairing] cluster creds configured (endpoints: ''${ips[*]})" >&2
      ) || echo "[pairing] WARNING: cluster cred bootstrap aborted unexpectedly" >&2
      fi
    '';
}
```

- [ ] **Step 2: Evaluate the dev-container env for Linux (can't build on macOS)**

```bash
cd /Users/ian/projects/dotfiles
printf '{ username = "ian"; remoteAgents = [ ]; }\n' > core/host.nix
nix eval --raw \
  "path:/Users/ian/projects/dotfiles/environments/dev-container#homeConfigurations.\"x86_64-linux\".activationPackage.drvPath" \
  --override-input public "path:/Users/ian/projects/dotfiles/core"
```
Expected: a `.drv` path, no eval error (confirms the agent layer, pairing server mode, tooling, and the three activation scripts all evaluate together).

- [ ] **Step 3: Confirm server-mode pairing reached the env**

```bash
nix eval \
  "path:/Users/ian/projects/dotfiles/environments/dev-container#homeConfigurations.\"x86_64-linux\".config.dotfiles.pairing.mode" \
  --override-input public "path:/Users/ian/projects/dotfiles/core"
```
Expected: `"server"`

- [ ] **Step 4: Build on Linux (in the container, or any aarch64/x86_64-linux Nix host)**

Run on a Linux host (e.g. the dev container after Task 11, or a Linux builder):
```bash
sys=$(nix eval --impure --raw --expr 'builtins.currentSystem')   # e.g. x86_64-linux
nix build \
  "path:/root/projects/dotfiles/environments/dev-container#homeConfigurations.\"$sys\".activationPackage" \
  --override-input public "path:/root/projects/dotfiles/core"
```
Expected: builds. (Defer to the Task 11 end-to-end if no Linux Nix host is available now.)

- [ ] **Step 5: Commit the scaffold + module together**

```bash
cd /Users/ian/projects/dotfiles
git checkout core/host.nix 2>/dev/null || true
git add environments/dev-container/
git commit -m "feat(dev-container): public environment inheriting agent + cluster tooling and runtime bootstrap"
```

---

## Phase 4 — Post-apply fan-out

### Task 8: `pull-and-apply` wrapper

**Files:**
- Create: `pull-and-apply` (repo root, executable)

- [ ] **Step 1: Write `pull-and-apply`**

```bash
#!/usr/bin/env bash
# Pull the latest dotfiles (and any custom_environments repos), then apply.
# Invoked over SSH by a paired client's post-apply fan-out (see lib/nix's
# _dotfiles_nix_fanout). DOTFILES_REMOTE_TRIGGER=1 marks the downstream apply
# so it does not fan out again — no loops.
set -euo pipefail

cd "$(dirname "$0")"

# --ff-only: never create a merge commit on a remote with local commits; a
# diverged remote fails here and surfaces as "apply failed" in the client's
# fan-out summary rather than silently merging.
git pull --ff-only

if [ -d custom_environments ]; then
  for d in custom_environments/*/; do
    if [ -d "$d.git" ]; then
      ( cd "$d" && git pull --ff-only ) || echo "warning: git pull --ff-only failed in $d" >&2
    fi
  done
fi

exec env DOTFILES_REMOTE_TRIGGER=1 ./apply
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x /Users/ian/projects/dotfiles/pull-and-apply
```

- [ ] **Step 3: Parse-check and shellcheck**

```bash
/bin/bash -n /Users/ian/projects/dotfiles/pull-and-apply && echo OK
shellcheck /Users/ian/projects/dotfiles/pull-and-apply
```
Expected: `OK`, no shellcheck errors.

- [ ] **Step 4: Commit**

```bash
cd /Users/ian/projects/dotfiles
git add pull-and-apply
git commit -m "feat(pairing): add pull-and-apply wrapper for remote fan-out"
```

### Task 9: Fan-out in `lib/nix`

**Files:**
- Modify: `lib/nix` (add `_dotfiles_nix_fanout`; call it at the end of `dotfiles_nix_apply`)

- [ ] **Step 1: Add the `_dotfiles_nix_fanout` helper**

Insert this function definition above `dotfiles_nix_apply` (e.g. just before line 111, `dotfiles_nix_apply () {`):

```bash
# After a successful local apply, re-apply on each paired remote agent (pulling
# latest first). Sequential; an unreachable or failing remote is logged and
# skipped (the local apply already succeeded). Guarded by the caller so it only
# runs from a client and never recurses.
_dotfiles_nix_fanout () {
  local _remote_path _host _rc _summary
  # Literal $HOME so the REMOTE shell expands it; override with an absolute
  # DOTFILES_REMOTE_PATH in ~/.dotfilesrc when a remote keeps dotfiles elsewhere.
  _remote_path="${DOTFILES_REMOTE_PATH:-\$HOME/projects/dotfiles}"
  _summary=''
  # shellcheck disable=SC2086
  for _host in ${DOTFILES_REMOTE_AGENTS}; do
    log "Fanning out to remote agent: $_host"
    if ssh "$_host" "cd \"$_remote_path\" && ./pull-and-apply"; then
      _summary="$_summary
  $_host: ok"
    else
      _rc=$?
      if [ "$_rc" -eq 255 ]; then
        _summary="$_summary
  $_host: unreachable"
      else
        _summary="$_summary
  $_host: apply failed (exit $_rc)"
      fi
    fi
  done
  printf '%s\n' "Remote agent fan-out summary:$_summary"
}
```

- [ ] **Step 2: Call it at the end of `dotfiles_nix_apply`**

Immediately before the closing `}` of `dotfiles_nix_apply` (after the macOS nix-darwin `if` block, line ~260), add:

```bash
  # Post-apply fan-out. Skip when this apply was itself triggered by a remote
  # fan-out (no loops) and when no remotes are configured (server boxes never
  # set DOTFILES_REMOTE_AGENTS).
  if [ "${DOTFILES_REMOTE_TRIGGER:-0}" != 1 ] && [ -n "${DOTFILES_REMOTE_AGENTS:-}" ]; then
    _dotfiles_nix_fanout
  fi
```

- [ ] **Step 3: Parse-check and shellcheck**

```bash
/bin/bash -n /Users/ian/projects/dotfiles/lib/nix && echo OK
shellcheck -s bash /Users/ian/projects/dotfiles/lib/nix
```
Expected: `OK`; no new shellcheck errors (the `SC2086` on the `for` is disabled inline).

- [ ] **Step 4: Verify the guard logic in isolation**

```bash
# Source just the helper and confirm the guard short-circuits.
DOTFILES_REMOTE_TRIGGER=1 DOTFILES_REMOTE_AGENTS="bogus.invalid" bash -c '
  if [ "${DOTFILES_REMOTE_TRIGGER:-0}" != 1 ] && [ -n "${DOTFILES_REMOTE_AGENTS:-}" ]; then
    echo "would fan out"; else echo "skipped (trigger guard)"; fi'
```
Expected: `skipped (trigger guard)`

```bash
DOTFILES_REMOTE_AGENTS="" bash -c '
  if [ "${DOTFILES_REMOTE_TRIGGER:-0}" != 1 ] && [ -n "${DOTFILES_REMOTE_AGENTS:-}" ]; then
    echo "would fan out"; else echo "skipped (no remotes)"; fi'
```
Expected: `skipped (no remotes)`

- [ ] **Step 5: Verify unreachable-host handling does not abort and reports correctly**

Extract the helper and run it against a bogus host (source `framework/logging` for `log`):
```bash
cd /Users/ian/projects/dotfiles
DOTFILES_REMOTE_AGENTS="bogus.invalid.example" bash -c '
  . framework/logging
  '"$(sed -n "/^_dotfiles_nix_fanout () {/,/^}/p" lib/nix)"'
  _dotfiles_nix_fanout; echo "rc=$?"'
```
Expected: a summary line containing `bogus.invalid.example: unreachable` and `rc=0` (ssh exits 255 on connection failure; the function does not propagate it).

- [ ] **Step 6: Real end-to-end with one reachable remote (laptop)**

Set `DOTFILES_REMOTE_AGENTS` to one real reachable agent host alias in `~/.dotfilesrc`, then:
```bash
cd /Users/ian/projects/dotfiles && DOTFILES_ENVIRONMENT=default ./apply
```
Expected: local apply finishes, then the fan-out SSHes to the remote, which prints its own `git pull --ff-only` + apply output, and the run ends with a summary showing `<host>: ok`. Confirm on the remote that the apply ran with the trigger set (its log shows no second-level fan-out).

- [ ] **Step 7: Commit**

```bash
cd /Users/ian/projects/dotfiles
git add lib/nix
git commit -m "feat(pairing): fan out apply to paired remotes after a successful local apply"
```

### Task 10: Document the new config + bundle in the repo guides

**Files:**
- Modify: `core/CLAUDE.md` (common bundles section — add `pairing`)
- Modify: `framework/CLAUDE.md` (env vars — add the new `DOTFILES_*` vars)

- [ ] **Step 1: Add `pairing` to the bundles list in `core/CLAUDE.md`**

Under "## Common bundles (`common/`)", after the `common/claude` description, add:

```markdown
- **`common/pairing`** — the laptop↔agent SSH wiring, one configurable bundle
  with `dotfiles.pairing.mode` (`off`/`client`/`server`) and
  `dotfiles.pairing.remotes`. `client` (set by `default`) installs the
  `remote-agent` launchd socket handler and a `RemoteForward` per paired
  remote; `server` (set by `agent`, re-set by `dev-container`) installs the
  sshd drop-in and the `remote-agent/` shims. The remote list comes from
  `host.remoteAgents`, which `lib/nix` generates from `DOTFILES_REMOTE_AGENTS`.
```

- [ ] **Step 2: Add the new env vars to `framework/CLAUDE.md`**

In the "## Env vars" section, append:

```markdown
`DOTFILES_REMOTE_AGENTS` (space-separated SSH host aliases of paired remote
agents; baked into `host.nix` and used by the post-apply fan-out),
`DOTFILES_REMOTE_PATH` (path to the dotfiles repo on a remote; default
`$HOME/projects/dotfiles`), `DOTFILES_REMOTE_TRIGGER=1` (set by `pull-and-apply`
so a remote apply does not fan out again).
```

- [ ] **Step 3: Commit**

```bash
cd /Users/ian/projects/dotfiles
git add core/CLAUDE.md framework/CLAUDE.md
git commit -m "docs(pairing): document the pairing bundle and remote-agent env vars"
```

---

## Phase 5 — Slim the homelab dev-container (homelab repo)

> **Cross-repo:** these edits land in `/Users/ian/projects/homelab`, not dotfiles. Do them only after the dotfiles branch above is merged (or available to the container clone), because the container now resolves `DOTFILES_ENVIRONMENT=dev-container` to the **public** `environments/dev-container/` in dotfiles. Commit in the homelab repo.

### Task 11: Remove the moved flake and migrated runtime; shrink the entrypoint

**Files:**
- Delete: `homelab/images/dev-container/flake.nix`, `homelab/images/dev-container/dev-container.nix`
- Delete: `homelab/images/dev-container/projects/repos.txt` (now `environments/dev-container/repos.txt` in dotfiles)
- Modify: `homelab/images/dev-container/entrypoint.sh`
- Modify: the dev-container Kubernetes manifest that sets the pod env (add `GARAGE_ENDPOINT`)
- Modify: `homelab/images/dev-container/Dockerfile` (drop the `repos.txt` COPY if present)

- [ ] **Step 1: Delete the files now owned by dotfiles**

```bash
cd /Users/ian/projects/homelab
git rm images/dev-container/flake.nix images/dev-container/dev-container.nix
git rm images/dev-container/projects/repos.txt
```

- [ ] **Step 2: Remove the migrated runtime blocks from `entrypoint.sh`**

Delete these sections (now home-manager activation scripts in the dotfiles env):
- The credential-restore blocks (Claude lines ~242-263, Codex ~265-285, Buildkite ~287-292, GitHub identity ~294-322).
- The repo clone/fetch loop reading `repos.txt` (the `PROJECTS_DIR`/`REPOS_FILE` block, ~436-454) — keep the `clone_or_fetch`/`clone_or_pull` helpers only if still used by the dotfiles/homelab clone below; otherwise remove the now-unused one.
- The Garage S3 cluster-cred block (~485-554, including the `ARGOCD_OPTS` append).

Keep: the SSH host-key restore + `~/.ssh/config` seed (lines 1-56), the dotfiles clone, the bootstrap `./apply`, and the Nix/HM profile loads.

- [ ] **Step 3: Point the bootstrap at the public env and drop the custom_environments copy**

Replace the custom-environment wiring (the `mkdir -p "$DOTFILES_DIR/custom_environments"; rm -rf "$CUSTOM_ENV_DIR"; cp -r "$DEVCONTAINER_ENV" "$CUSTOM_ENV_DIR"` block and the `$DEVCONTAINER_ENV` guard) so the entrypoint just clones dotfiles and applies the public env:

```bash
load_nix_profile
if [ -d "$DOTFILES_DIR/.git" ]; then
    if ! nix --version >/dev/null 2>&1 || [ ! -e "$AGENT_CONF_DIR/sshd.conf" ]; then
        echo "[setup] bootstrapping via ./apply (one-time per PVC; installs Nix + builds the env)..." >&2
        if ( cd "$DOTFILES_DIR" && DOTFILES_ENVIRONMENT=dev-container ./apply ); then
            echo "[setup] dev-container env applied" >&2
        else
            echo "[setup] WARNING: ./apply failed; agent tooling is unavailable" >&2
            echo "[!] ./apply failed — fix connectivity and run dotfiles-apply" >> /etc/issue
        fi
    fi
else
    echo "[setup] WARNING: dotfiles clone missing; skipping bootstrap" >&2
    echo "[!] repo clone missing — fix connectivity and run dotfiles-apply" >> /etc/issue
fi
```

The homelab clone (`clone_or_pull ianwremmel/homelab "$HOMELAB_DIR"`) is no longer needed for the env build; keep it only if other tooling expects the checkout, otherwise remove it and the `HOMELAB_DIR`/`DEVCONTAINER_ENV`/`CUSTOM_ENV_DIR` vars.

- [ ] **Step 4: Add `GARAGE_ENDPOINT` to the pod env**

Find the manifest that already injects `CLAUDE_CREDENTIALS`/`AWS_ACCESS_KEY_ID` into the dev-container pod:
```bash
cd /Users/ian/projects/homelab
grep -rl 'CLAUDE_CREDENTIALS\|AWS_ACCESS_KEY_ID' --include='*.yaml' --include='*.yml' .
```
In that manifest, add an env entry `GARAGE_ENDPOINT` with value `http://buttercup:3900` (the value the dotfiles activation script now reads instead of hardcoding).

- [ ] **Step 5: Drop the `repos.txt` COPY from the Dockerfile if present**

```bash
cd /Users/ian/projects/homelab
grep -n 'repos.txt\|share/dev-container/projects' images/dev-container/Dockerfile
```
Remove any `COPY … repos.txt …` / `projects/` line that referenced the deleted file.

- [ ] **Step 6: Parse-check the entrypoint**

Run: `bash -n /Users/ian/projects/homelab/images/dev-container/entrypoint.sh && echo OK`
Expected: `OK`

- [ ] **Step 7: End-to-end — fresh container boot**

Rebuild the image and start a fresh dev-container pod (recreate the `/root` and `/nix` PVCs to exercise first boot). Confirm:
- `./apply` runs and finishes.
- `~/.claude/.credentials.json` and `~/.codex/auth.json` are present (credential-restore activation script).
- `~/projects/{apps,homelab,llc-infrastructure,dotfiles}` exist (clone activation script).
- `~/.kube/config` and `~/.talos/config` exist and `kubectl config current-context` shows the `argocd` namespace (cluster-cred activation script).
- From a connected client, `open-link https://example.com` opens on the client and `play-sound` is audible (remote-agent shims via the pairing server mode).

- [ ] **Step 8: Commit (homelab repo)**

```bash
cd /Users/ian/projects/homelab
git add -A
git commit -m "refactor(dev-container): move flake + runtime bootstrap into dotfiles; entrypoint just applies"
```

---

## Self-review notes (addressed)

- **Spec coverage:** bundle + modes (Tasks 1-2, 5), `host.nix` remotes (Task 3-4), per-remote client wiring (Task 5), `dev-container` env + migrated runtime (Tasks 6-7), fan-out + `pull-and-apply` (Tasks 8-9), homelab slim (Task 11), docs (Task 10). All five spec phases map to tasks.
- **No-behavior-change proof** for the Phase 1 refactor is the before/after store-path diff (Task 2, Steps 6-7).
- **Naming consistency:** the launchd job/socket/binary rename (`dev-container-agent` → `remote-agent`, `~/.dev-container-agent.sock` → `~/.remote-agent.sock`) happens only in Task 5; Phase 1 keeps the old names so its diff is clean.
- **Linux-only builds** (`agent` server content, `dev-container`) are *evaluated* on macOS and *built* on Linux — every such step says which.
- **Known limitation, stated in code:** OAuth callback port-forwarding (`FORWARD`) targets the first paired remote only; the socket verbs (open/clipboard/sound) work for all remotes.
