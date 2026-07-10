# Claude config + agent flake cleanup

Date: 2026-07-09

Six independent cleanups, landed together. Four touch the Claude Code config
bundle; one changes a git default; one restructures the agent environment
flakes. A seventh, paired change lands in the `homelab` repo.

## Background

Two facts discovered while investigating why `/deliver` (from
`dispatch@agentic`) was missing in the homelab dev container:

1. `~/.claude/rules/*.md` and `<repo>/.claude/rules/*.md` are auto-discovered
   by Claude Code and loaded at session start; a rule needs no `@` import.
   Rules carrying `paths:` frontmatter load conditionally instead. Source:
   <https://code.claude.com/docs/en/memory.md>.
2. Nothing declares plugins for any environment except the agent
   managed-settings policy, which declares `codex@openai-codex` and nothing
   else. `dispatch@agentic` exists on the personal machine only as interactive
   state under `~/.claude/plugins/`, which no environment reproduces.

Separately, `environments/dev-container` consumes `environments/agent` through
a flake input, so anything added to `agent` is forced on `dev-container`.

## 1. Rules loading

`core/common/claude/CLAUDE_DOT_MD.md` contains `@rules/anti-ai-slop.md`. That
file is already auto-loaded, so the import loads it twice. Remove the `@` line.
The prose link to the rules file stays — it is a cross-reference, not an import.

`core/common/claude/files/rules/prefer-declarative-file-management.md` describes
a Nix/home-manager convention specific to this repo, but ships to
`~/.claude/rules/` on every machine. Move it to `.claude/rules/` at the root of
this repo, where it auto-loads for work in this repo and nowhere else. No wiring
changes: the file leaves the bundle's `files/` tree, so the bundle stops
managing it.

## 2. Anti-slop taxonomy has one home

`files/rules/anti-ai-slop.md` and `files/agents/anti-ai-slop-reviewer.md`
restate the same 13-item taxonomy. The rule file is canonical. The agent's
system prompt drops the taxonomy and keeps only what is agent-specific: what
input it receives, how it weighs severity, and its output format. It gains an
instruction to read `~/.claude/rules/anti-ai-slop.md`.

The agent has the `Read` tool, so it can load the taxonomy itself. Whether user
rules also land in a subagent's context automatically is not something this
change depends on.

## 3. Feature-branch push becomes config

`core/all/home/git.nix` sets `push.default = "upstream"`. With that value, a
branch whose upstream is `origin/master` pushes to `master` — the exact failure
`files/rules/feature-branch-push.md` warns about in prose. Prose has not
prevented it.

Replace with:

```nix
push = {
  default = "current";
  autoSetupRemote = true;
};
```

`current` resolves the push destination from the branch's own name and ignores
its upstream, so a branch cut from `master` cannot push to `master`.
`autoSetupRemote` creates the same-named remote branch on first push, so a bare
`git push` still works on a new branch.

Delete `files/rules/feature-branch-push.md`. The one thing config cannot
enforce — opening the PR against the default branch — is unremarkable and does
not need a global rule.

## 4. Concision rule

Add `core/common/claude/files/rules/concise-documentation.md`. It covers what
the anti-slop rule does not: document length and unrequested documents. Not
`@`-imported.

Content, in brief: prefer editing an existing doc to adding one; do not write a
document for a change a commit message already explains; a section earns its
place by answering a question a reader will have; when a doc grows past what
someone will read, cut rather than reorganize.

## 5. Plugins declared for every environment

New `core/common/claude/plugins.nix` — a plain attrset, not a module:

```nix
{
  extraKnownMarketplaces = {
    claude-plugins-official.source = { source = "github"; repo = "anthropics/claude-plugins-official"; };
    openai-codex.source           = { source = "github"; repo = "openai/codex-plugin-cc"; };
    agentic.source                = { source = "github"; repo = "ianwremmel/agentic"; };
  };
  enabledPlugins = {
    "code-review@claude-plugins-official"     = true;
    "code-simplifier@claude-plugins-official" = true;
    "typescript-lsp@claude-plugins-official"  = true;
    "codex@openai-codex"                      = true;
    "dispatch@agentic"                        = true;
  };
}
```

Two consumers:

- `common/claude/default.nix` merges it into `baseSettings`, so every
  environment that opts into the claude bundle gets these keys in
  `~/.claude/settings.json`. `baseSettings` exists for exactly this and is
  currently empty.
- `common/agent/claude.nix` imports the same file into `managedSettings`
  (`/etc/claude-code/managed-settings.json`), replacing its hardcoded
  codex-only block.

## 6. Agent flake split

Today `environments/agent` is both a selectable environment and the base that
`environments/dev-container` extends through a flake input. Those two roles
conflict.

New shape:

| Path | Role |
| --- | --- |
| `core/common/agent/` | Bundle. `cli-tools.nix`, `claude.nix`, and `imports = [ ../claude ]`. |
| `environments/agent-interactive/` | Cluster CLIs, `repos.txt` cloning, credential restore, tmux auto-attach. |
| `environments/agent-autonomous/` | Bundle + pairing server. Nothing else yet. |
| `environments/dev-container/` | Re-exports `agent-interactive`'s `homeConfigurations`. |
| `environments/agent/` | Re-exports `agent-autonomous`'s `homeConfigurations`. |

`core/common/agent` importing `../claude` fixes a live bug: the dev-container
flake passes `agent.homeModules.agent` to `mkHome` without
`public.homeModules.claude`, so the container has no `~/.claude/CLAUDE.md`,
`~/.claude/rules/`, or `~/.claude/agents/`. A bundle can carry its own imports;
a bare module path exported across a flake boundary cannot.

`environments/agent/shell-extras.nix` (tmux auto-attach, which `exec`s a shell
replacement) moves to `agent-interactive`. Both container images select
`dev-container`, so behavior is unchanged today.

`agent` and `dev-container` keep their names because `homelab`'s
`images/dev-base/lib/bootstrap.sh` hardcodes `DOTFILES_ENVIRONMENT=dev-container`.

### lib/nix input overrides

`lib/nix` hardcodes `--override-input agent path:.../environments/agent`,
gated on a grep for an `agent.url` / `agent.inputs` declaration. The trivial
shells need the same treatment for `agent-interactive` and `agent-autonomous`.

Generalize: iterate `environments/*/`, and for each directory name that the
selected flake declares as an input, add
`--override-input <name> path:.../environments/<name>`. This subsumes the
`agent` case and needs no further edits when an environment is added. The
`shared` case (a `custom_environments/shared` library) keeps its own gate.

The grep must stay anchored at line start modulo indentation, for the reason
the existing comment gives: a mention inside a comment or a `follows` string
would otherwise trigger a spurious override and a nix warning. Environment
names may contain `-`, which is safe inside the existing ERE.

## 7. Grafana MCP moves to the homelab repo (paired change)

`environments/dev-container/dev-container.nix` generates
`~/.config/agent/mcp-servers-homelab.json`, which `bootstrap.sh` merges into
the MCP server list for every session in the container. The Grafana server is
only useful when working on `homelab`.

Claude Code reads `.mcp.json` from a project root and expands `${VAR}`
references in it. So the server config moves into the homelab repo:

```json
{
  "mcpServers": {
    "grafana": {
      "command": "mcp-grafana",
      "args": ["-t", "stdio"],
      "env": {
        "GRAFANA_URL": "http://kube-prometheus-stack-grafana.observability.svc.cluster.local",
        "GRAFANA_SERVICE_ACCOUNT_TOKEN": "${GRAFANA_SERVICE_ACCOUNT_TOKEN}"
      }
    }
  }
}
```

In dotfiles: delete the `grafanaMcp` derivation and the
`home.file.".config/agent/mcp-servers-homelab.json"` entry. Keep `mcp-grafana`
in `agent-interactive`'s `home.packages` — the `.mcp.json` above invokes that
binary by name.

In homelab: add `.mcp.json`; drop the `mcp-servers-homelab.json` line from
`dev_bootstrap::register_mcp_servers` and the sentence in its comment that
describes it.

### Ordering

The homelab PR must merge before the dotfiles Grafana deletion reaches a
container, or Grafana is unavailable in the gap. The gap is a container
`dotfiles-apply` away from closing, and no automation depends on the Grafana
server, so the risk is a temporary missing tool, not breakage.

## Testing

No automated tests in this repo. Verification:

- `/bin/bash -n lib/nix` under the stock 3.2 parser.
- `nix build path:environments/<env>#homeConfigurations."<system>".activationPackage`
  with the same `--override-input` flags `lib/nix` passes, for each of the five
  environment flakes. The flakes' `github:` input URLs are placeholders that
  must never be fetched, so a bare `nix flake check` is not the right check.
- `./apply` on the personal machine; confirm `~/.claude/settings.json` gains
  `enabledPlugins`, `git config push.default` reads `current`, and
  `~/.claude/rules/` no longer contains `feature-branch-push.md` or
  `prefer-declarative-file-management.md`.
- In the dev container: `dotfiles-apply`, then confirm `/deliver` resolves and
  `~/.claude/CLAUDE.md` exists.

## Out of scope

- The `play-sound` Stop/Notification hooks stay in `core/common/agent`, so
  `agent-autonomous` inherits hooks nobody hears. Harmless (the shim is a no-op
  without a paired client) and worth revisiting when `agent-autonomous` gets
  real content.
- `images/ai-dev` continues to select `dev-container`. Pointing it at
  `agent-autonomous` is a homelab-side change for later.
