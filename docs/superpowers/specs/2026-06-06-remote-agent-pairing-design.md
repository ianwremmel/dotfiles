# Remote-agent pairing: one repo configures laptop and its agents, apply fans out

## Problem

The laptop and its remote coding agent (the homelab dev container) are configured
in two repos that have to be kept in lockstep by hand:

- The **client** half lives in `environments/default/`: `ssh.nix` (a hardcoded
  `RemoteForward` to the single host `dev-container-dev-container`) and
  `dev-container-agent.nix` (the macOS launchd "mac-agent" socket handler that
  opens URLs / bridges clipboard / plays sounds for the pod).
- The **server** half lives in `environments/agent/`: `sshd.nix` (the sshd drop-in)
  and `remote-agent.nix` + `remote-agent/` (the shims that talk back over the
  socket).
- The **dev-container specifics** live in a *third* flake in a *different repo*,
  `homelab/images/dev-container/` (`flake.nix` + `dev-container.nix`), which
  consumes the `agent` profile and adds cluster tooling. Its 27 KB `entrypoint.sh`
  does the runtime work (credential restore, repo cloning, Garage S3 → kube/talos
  config) and then calls `./apply`.

Three consequences:

1. **The client only ever pairs with one remote.** The host name is baked into
   `default/ssh.nix`; there is no way to declare a second agent.
2. **Applying is a per-machine chore.** After changing config on the laptop, each
   remote has to be SSH'd into and re-applied by hand, after manually pulling both
   the dotfiles repo and the private `custom_environments` repo.
3. **The dev container's config is split across two repos.** Changing what the
   agent installs means editing homelab, not dotfiles, and the homelab flake
   path-pins into `/root/projects/dotfiles`.

## Goals

- The laptop can be paired with **one or more** remote agents by name, in
  `~/.dotfilesrc`. The single hardcoded host stops being special.
- A successful local `./apply` **fans out**: SSH to each paired remote, pull the
  latest dotfiles and `custom_environments`, and re-apply there — no by-hand step.
- The client/server wiring lives in **one shared bundle** that both profiles
  import, so the two halves of the socket protocol can't drift. `default` marks
  itself client-mode, `agent` marks itself server-mode.
- The dev container's config moves **into this repo** as a public environment that
  inherits `agent`. The dev container's `entrypoint.sh` shrinks to "clone if
  absent, then `./apply`"; everything declarative (and the imperative runtime
  steps, as activation scripts) lives here.

## Non-goals

- **Parallel fan-out.** First cut is sequential with a per-host summary; parallel
  is a later optimization, not a requirement.
- **Per-host environment or path overrides.** Every remote is assumed to have the
  dotfiles repo at one default path and its own `DOTFILES_ENVIRONMENT` already set
  in its own `~/.dotfilesrc`. A global override is provided; per-host maps are out.
- **Provisioning a fresh remote.** Fan-out assumes the remote already has the repo
  cloned, Nix installed, and an environment selected (the dev container's
  Dockerfile/entrypoint still does first-boot clone). Fan-out re-applies an
  already-provisioned box; it does not stand one up.
- **Migrating `custom_environments` content**, and any **server→client** direction.
  Fan-out is one-way: laptop → its agents.

## Design

### The shared bundle: `core/common/pairing`

A new configurable bundle (the `core/common/claude` pattern), exposed from the core
`flake.nix` as `homeModules.pairing`. It declares two options:

```nix
options.dotfiles.pairing.mode = lib.mkOption {
  type = lib.types.enum [ "off" "client" "server" ];
  default = "off";
};
options.dotfiles.pairing.remotes = lib.mkOption {
  type = lib.types.listOf lib.types.str;
  default = [ ];
  description = "SSH host aliases of paired remotes; drives the client RemoteForward blocks.";
};
```

The client-mode wiring iterates `config.dotfiles.pairing.remotes`. The
bundle absorbs the four files that today live in the two environments, gated on
`mode` (the existing `pkgs.stdenv.isDarwin` / `isLinux` guards stay, as
belt-and-suspenders — client mode is macOS in practice, server mode is Linux):

- **client-mode** (`mode == "client"`): the launchd mac-agent socket handler
  (from `default/dev-container-agent.nix` + `mac-agent/agent.sh`), plus a generated
  SSH `Host` block **per entry in `config.dotfiles.pairing.remotes`**, each with
  `RemoteForward /run/remote-agent.sock <local socket>` and the `ControlMaster`
  settings. This replaces the single hardcoded `dev-container-dev-container` block
  in `default/ssh.nix`. One mac-agent serves all paired remotes; the local socket
  name generalizes from `~/.dev-container-agent.sock` to `~/.remote-agent.sock`.
- **server-mode** (`mode == "server"`): the sshd drop-in + its
  `installAgentSshdDropIn` activation (from `agent/sshd.nix`) and the
  `remote-agent/` shims + their packages (from `agent/remote-agent.nix`). The shim
  source tree moves to `core/common/pairing/remote-agent/`.

`default/home.nix` sets `dotfiles.pairing.mode = "client"` and adds
`public.homeModules.pairing` to its `modules` list; `default/ssh.nix` and
`default/dev-container-agent.nix` are deleted. `agent/home.nix` sets
`dotfiles.pairing.mode = "server"` and adds `public.homeModules.pairing`;
`agent/sshd.nix` and `agent/remote-agent.nix` are deleted. No installed behavior
changes in this step (same files land in the same places) — it is a refactor that
gives the two halves one source.

### `host.nix` carries the remote list

The generator in `lib/nix` grows from `{ username = "…"; }` to:

```nix
{ username = "ian"; remoteAgents = [ "host-a" "host-b" ]; }
```

The list is sourced from `DOTFILES_REMOTE_AGENTS` in `~/.dotfilesrc` (a
space-separated string, already exported into the environment by `config_load`
before `dotfiles_nix_apply` runs). When unset, the generator writes
`remoteAgents = [ ]`, so existing machines are unaffected. Each entry is an SSH host
alias — resolvable through the user's SSH config (Tailscale name, `Host` block,
whatever) — exactly the form `dev-container-dev-container` takes today.

Two consumers read it, both derived from the one `~/.dotfilesrc` value:

- The **client-mode bundle** reads `config.dotfiles.pairing.remotes` to generate
  the per-remote `RemoteForward` blocks. The client env flake (which already
  imports `host.nix` for `username`) sets that option from `host.remoteAgents` —
  e.g. an inline module `{ dotfiles.pairing = { mode = "client"; remotes =
  host.remoteAgents; }; }` in its `modules` list. Nix can't read env vars under
  pure eval, so the generated `host.nix` is how the list crosses from
  `~/.dotfilesrc` into the flake.
- **`apply`** reads `DOTFILES_REMOTE_AGENTS` directly (bash) to drive the fan-out.

Envs that don't use the bundle ignore `remoteAgents` entirely.

### Post-apply fan-out

After a successful local home-manager (and, on macOS, nix-darwin) activation,
`dotfiles_nix_apply` runs a fan-out step, guarded so it only fires from a laptop and
never recurses:

- Skip unless `dotfiles.pairing.mode` is client — in bash terms, skip unless the
  resolved profile is a client profile. A simple, explicit guard: skip when
  `DOTFILES_REMOTE_AGENTS` is empty (server boxes never set it) **and** skip when
  `DOTFILES_REMOTE_TRIGGER=1` is set in the environment (set by the wrapper below,
  so a remote apply can't fan out again — no loops).
- For each host in `DOTFILES_REMOTE_AGENTS`, sequentially:
  `ssh "$host" 'cd "$DOTFILES_REMOTE_PATH" && ./pull-and-apply'`, where
  `DOTFILES_REMOTE_PATH` defaults to `~/projects/dotfiles` and is overridable
  globally in `~/.dotfilesrc`.
- A host that is unreachable or whose remote apply fails is **logged and skipped**,
  not fatal — the local apply already succeeded. A one-line per-host result summary
  prints at the end (`ok` / `unreachable` / `apply failed`).

`pull-and-apply` is a new script at the repo root, beside `apply`:

1. `git pull --ff-only` in the dotfiles repo.
2. For each git work tree under `custom_environments/*`, `git pull --ff-only`
   (skip if the directory isn't a git repo — a remote may have none).
3. `exec env DOTFILES_REMOTE_TRIGGER=1 ./apply`.

`--ff-only` keeps it from creating merge commits on a dirty remote; a non-ff remote
surfaces as "apply failed" in the summary rather than silently diverging. Pulling
before `exec` (rather than mid-`apply`) means the freshly pulled `apply`/`lib`
is the one that runs.

### The `dev-container` environment

A new **public** environment `environments/dev-container/`, sibling to `agent`,
that inherits the generic `agent` server profile and layers the cluster specifics.
It is server-mode by inheritance.

- `environments/dev-container/flake.nix` — same shape as the other env flakes
  (consumes the `public` core). It composes the **agent home module** via the
  established cross-env path-import (`public + "/agent/home.nix"`, the mechanism the
  private `work` flake uses to layer on another env) plus its own
  `./dev-container.nix`. `agent` stays untouched and generic.
- `environments/dev-container/dev-container.nix` — the cluster layer moved out of
  homelab: the tooling packages (kubectl, helm, argocd, argo-workflows, talosctl,
  opentofu, yq, aws-sam-cli, flyctl, bats, mcp-grafana), the Grafana MCP server
  declaration, and the dev-container SSH identity pin (`github.com` →
  `id_ed25519`, `IdentityAgent none`, `IdentitiesOnly yes`).

The imperative parts of `entrypoint.sh` become **home-manager activation scripts**
in this module (`entryAfter ["writeBoundary"]`, idempotent like the existing
`seedClaudeSettings`/`installAgentSshdDropIn`). They read the same env vars at
activation time (so they stay runtime, never baked into the store, and re-run on
every apply — including a fan-out-triggered one, keeping credentials fresh):

- **Credential restore** — Claude (`$CLAUDE_CREDENTIALS`), Codex
  (`$CODEX_CREDENTIALS`), GitHub (`$GITHUB_TOKEN`), Buildkite
  (`$BUILDKITE_API_TOKEN`); same expiry-compare logic as today.
- **Repo clone/fetch** — the `repos.txt` list (public repo slugs; moves into this
  env), fetch-only when present.
- **Cluster credentials** — Garage S3 fetch of Terraform state → `talosconfig`,
  `kubeconfig`, default namespace. The Garage endpoint, today the literal
  `http://buttercup:3900`, is read from a new `$GARAGE_ENDPOINT` env var injected by
  the homelab pod spec, so no cluster hostname lands in the public repo. AWS creds
  come from the existing env vars.

After this, `homelab/images/dev-container/`:

- **Deletes** `flake.nix` and `dev-container.nix` (now in this repo).
- **Shrinks** `entrypoint.sh` to: clone the dotfiles repo if absent, then
  `cd "$DOTFILES_DIR" && DOTFILES_ENVIRONMENT=dev-container ./apply`. The
  `dotfiles-apply` convenience command stays (it's just `./apply`). The `Dockerfile`
  keeps the base image, apt prerequisites, and Nix install.
- Sets `$GARAGE_ENDPOINT` (and keeps the existing credential env vars) in the pod
  spec.

This is the homelab-side change. It is described here for completeness but lands in
the homelab repo, after the dotfiles side works.

### Build sequence (phases)

Each phase is independently testable and leaves the repo working.

1. **Extract the bundle.** Create `core/common/pairing/` from the four existing
   files; `default` opts in as `client`, `agent` as `server`. No installed-output
   change — verify `default` (macOS) and `agent` (Linux) build and activate
   identically to before.
2. **`host.nix` + per-remote client wiring.** Generator writes `remoteAgents`;
   client-mode iterates `host.remoteAgents` instead of the hardcoded host. Verify
   the generated `~/.ssh/config` contains a `RemoteForward` block per configured
   remote (and none when the list is empty).
3. **`dev-container` environment.** Add the env, move the cluster layer and the
   Garage-endpoint parameterization, migrate `entrypoint.sh`'s runtime steps to
   activation scripts. Verify it builds for `x86_64-linux`/`aarch64-linux` and
   activates inside a container with the secret env vars set.
4. **Fan-out.** Add `pull-and-apply` and the fan-out loop + guards to `lib/nix`.
   Verify a laptop `./apply` with `DOTFILES_REMOTE_AGENTS` set pulls and re-applies
   on a reachable remote, skips an unreachable one with a clear summary line, and
   that a remote apply does not itself fan out.
5. **Slim homelab.** Delete the moved files from homelab, shrink `entrypoint.sh`,
   set the pod env. Verify a fresh container boot reaches a working agent
   end-to-end. (Homelab repo.)

## Trade-offs

- **Fan-out failure is non-fatal and sequential.** A down remote is left stale
  (reported, not retried); a slow remote blocks the ones after it. Both are
  acceptable for a handful of personal agents and revisitable if the count grows.
- **`entrypoint.sh` logic becomes Nix activation.** Iterating on the runtime steps
  now means a rebuild rather than editing a shell script in place. The upside: the
  steps are declarative, run on every apply, and live beside the config they serve.
- **`--ff-only` is strict by design.** A remote with local commits/dirty tree fails
  its apply (surfaced in the summary) rather than silently merging. The fix is to
  clean the remote, which is the intended behavior for a throwaway agent box.
- **The dev-container env is public.** Tooling choices and `repos.txt` (public repo
  slugs) are visible; everything sensitive (cluster IPs, talosconfig, the Garage
  hostname, all tokens) stays runtime-only via env vars, never committed.
- **One bundle, two modes, vs. two bundles.** A single `pairing` bundle with a
  `mode` enum keeps the client and server halves of the socket protocol in one file
  so they can't drift; the cost is two unrelated config blocks behind one option,
  guarded by mode.

## Testing

No automated tests in this repo. Manual verification per phase, plus overall:

- `/bin/bash -n` parse-checks (stock 3.2 parser) on `apply`, `pull-and-apply`,
  `framework/*`, `lib/nix`.
- `nix build path:environments/default#homeConfigurations."<system>".activationPackage`
  and the same for `agent` and `dev-container`, on the relevant systems.
- Phase 1 regression: diff the realized activation package (or the materialized
  `~/.ssh/config`, `~/bin` shims, sshd drop-in) before and after the extraction —
  expect no change.
- Phase 2: set `DOTFILES_REMOTE_AGENTS="a b"`, apply, confirm two `RemoteForward`
  blocks in `~/.ssh/config`; unset it, apply, confirm none.
- Phase 4: a real laptop `./apply` against one reachable and one bogus remote;
  confirm the reachable one pulls + re-applies, the bogus one reports `unreachable`,
  and the local apply exit status is success regardless. Confirm the remote's apply
  ran with `DOTFILES_REMOTE_TRIGGER=1` (no second-level fan-out).
- Phase 3/5: fresh dev-container boot — `./apply` restores credentials, clones the
  repo list, writes `talosconfig`/`kubeconfig`, and the remote-agent shims work back
  to a connected client.
