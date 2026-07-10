# Claude config + agent flake cleanup implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deduplicate the Claude Code rule content, declare the five plugins every environment needs, replace the feature-branch-push rule with git config that enforces it, and split the agent environment into a `core/common/agent` bundle plus `agent-interactive` / `agent-autonomous` environments.

**Architecture:** Shared Claude content stays in the `core/common/claude` bundle; a new `core/common/agent` bundle carries the agent base and imports `../claude`, which fixes the dev container's missing `~/.claude` tree. Environment flakes under `environments/` become thin: `agent-interactive` holds the real content, and `agent` / `dev-container` re-export a sibling's `homeConfigurations`. `lib/nix` learns to override any flake input named after a local environment directory.

**Tech Stack:** Nix flakes, home-manager, nix-darwin. `lib/nix` and `framework/*` run on stock macOS Bash 3.2.57.

**Spec:** `docs/superpowers/specs/2026-07-09-claude-config-and-agent-flake-cleanup-design.md`

## Global constraints

- `apply`, `lib/nix`, and `framework/*` must parse and run under Bash 3.2.57. No `local -n`, no `${var^^}`, no `+=` on arrays — grow arrays with `arr=("${arr[@]}" new)`.
- No automated test suite exists. Verification is `/bin/bash -n` parse checks, `nix eval` of each environment's `activationPackage.drvPath`, and `grep` assertions against generated output.
- Environment flakes declare `github:` input URLs as placeholders. `lib/nix` overrides them to the local checkout at build time. Never run a bare `nix flake check` or `nix build` on these flakes without the `--override-input` flags — it will fetch from GitHub and build a stale tree.
- Conventional commit messages. No `Co-Authored-By: Claude` or `Generated with Claude Code` trailers.
- The environment names `agent` and `dev-container` must keep working: `homelab`'s `images/dev-base/lib/bootstrap.sh` hardcodes `DOTFILES_ENVIRONMENT=dev-container`.
- No tombstone comments. Comments describe the code as it exists, never what it replaced.

## File structure

**Created:**
- `.claude/rules/prefer-declarative-file-management.md` — repo-scoped rule (moved).
- `core/common/claude/plugins.nix` — plain attrset of `extraKnownMarketplaces` + `enabledPlugins`. Not a module. Imported by two consumers.
- `core/common/claude/files/rules/concise-documentation.md` — new global rule.
- `core/common/agent/default.nix` — bundle entry point; imports `../claude`, `./cli-tools.nix`, `./claude.nix`.
- `core/common/agent/cli-tools.nix` — moved from `environments/agent/cli-tools.nix`.
- `core/common/agent/claude.nix` — moved from `environments/agent/claude.nix`; `managedSettings` now imports `plugins.nix`.
- `environments/agent-interactive/{flake.nix,home.nix,shell-extras.nix,repos.txt}` — real content.
- `environments/agent-autonomous/flake.nix` — bundle + pairing server, nothing else.

**Modified:**
- `core/common/claude/CLAUDE_DOT_MD.md` — drop the `@rules/anti-ai-slop.md` import.
- `core/common/claude/default.nix` — `baseSettings = import ./plugins.nix`.
- `core/common/claude/files/agents/anti-ai-slop-reviewer.md` — drop the duplicated taxonomy.
- `core/all/home/git.nix:73` — `push.default = "upstream"` → `push = { default = "current"; autoSetupRemote = true; }`.
- `core/flake.nix` — export `homeModules.agent`.
- `core/CLAUDE.md` — document the new bundle.
- `CLAUDE.md` — document `.claude/rules/` and the new environments.
- `lib/nix:273-294` — generalize the input override.
- `environments/agent/flake.nix` — re-export `agent-autonomous`.
- `environments/dev-container/flake.nix` — re-export `agent-interactive`.
- `~/projects/homelab/.mcp.json` (create), `~/projects/homelab/images/dev-base/lib/bootstrap.sh` (modify).

**Deleted:**
- `core/common/claude/files/rules/feature-branch-push.md`
- `core/common/claude/files/rules/prefer-declarative-file-management.md` (moved)
- `environments/agent/{home.nix,cli-tools.nix,claude.nix,shell-extras.nix}`
- `environments/dev-container/{dev-container.nix,repos.txt}`

---

### Task 1: Enforce feature-branch push with git config

**Files:**
- Modify: `core/all/home/git.nix:73`
- Delete: `core/common/claude/files/rules/feature-branch-push.md`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Confirm the current behavior is the broken one**

```bash
cd ~/projects/dotfiles
git config --get push.default
```

Expected: `upstream`. This is the value that makes a branch whose upstream is `origin/master` push to `master`.

- [ ] **Step 2: Replace the setting**

In `core/all/home/git.nix`, replace line 73:

```nix
      push.default = "upstream";
```

with:

```nix
      # `current` resolves the push destination from the branch's own name and
      # ignores its upstream, so a branch cut from `master` cannot push to
      # `master`. `autoSetupRemote` creates the same-named remote branch on
      # first push, so a bare `git push` still works on a new branch.
      push = {
        default         = "current";
        autoSetupRemote = true;
      };
```

- [ ] **Step 3: Delete the rule the config now enforces**

```bash
cd ~/projects/dotfiles
git rm core/common/claude/files/rules/feature-branch-push.md
```

- [ ] **Step 4: Verify the nix evaluates**

```bash
cd ~/projects/dotfiles
nix eval --raw "path:$PWD/environments/default#homeConfigurations.\"$(nix eval --raw --impure --expr builtins.currentSystem)\".activationPackage.drvPath" \
  --override-input public "path:$PWD/core"
```

Expected: a `/nix/store/....drv` path on stdout, no error.

- [ ] **Step 5: Commit**

```bash
cd ~/projects/dotfiles
git add core/all/home/git.nix
git commit -m "fix(git): push.default=current so branches never push to master

A branch whose upstream is origin/master pushed to master under
push.default=upstream. The feature-branch-push rule described this in prose and
did not prevent it; the config now does. autoSetupRemote keeps a bare 'git push'
working on a fresh branch.

Removes files/rules/feature-branch-push.md, which the config supersedes."
```

Note: `git rm` already staged the deletion, so this one commit carries both.

---

### Task 2: Fix rule loading

`~/.claude/rules/*.md` and `<repo>/.claude/rules/*.md` are auto-discovered by Claude Code and loaded at session start. An `@` import of a rule loads it a second time.

**Files:**
- Modify: `core/common/claude/CLAUDE_DOT_MD.md`
- Create: `.claude/rules/prefer-declarative-file-management.md`
- Delete: `core/common/claude/files/rules/prefer-declarative-file-management.md`

**Interfaces:**
- Consumes: nothing.
- Produces: `.claude/rules/` as the repo's rule directory; Task 7 documents it.

**Note:** `core/common/claude/CLAUDE_DOT_MD.md` already has an uncommitted edit
in the working tree — the user's change extending the Node.js section with a
preference for `.mts` extensions. It is unrelated to this task but lives in the
same file, so this task's commit carries it. Leave it exactly as written.

- [ ] **Step 1: Remove the double-loading import**

In `core/common/claude/CLAUDE_DOT_MD.md`, the Writing Style section reads:

```markdown
## Writing Style

Follow the [anti-AI-slop rules](./rules/anti-ai-slop.md) for all prose you write
for a human to read — chat answers, commit messages, PR descriptions, docs, code
comments. Plain, direct, information-dense; no puffery, filler, or AI tics.

@rules/anti-ai-slop.md
```

Delete the `@rules/anti-ai-slop.md` line and the blank line above it. Keep the
prose link — it is a cross-reference for a human reader, not an import.

- [ ] **Step 2: Move the Nix rule into this repo**

```bash
cd ~/projects/dotfiles
mkdir -p .claude/rules
git mv core/common/claude/files/rules/prefer-declarative-file-management.md \
       .claude/rules/prefer-declarative-file-management.md
```

The file's contents do not change. It gets no `paths:` frontmatter — it should
load for all work in this repo, not only when a `.nix` file is read.

- [ ] **Step 3: Verify the bundle no longer ships it**

```bash
cd ~/projects/dotfiles
ls core/common/claude/files/rules/
```

Expected: `anti-ai-slop.md` and `no-tombstone-comments.md` only. (Task 1 removed
`feature-branch-push.md`; `concise-documentation.md` arrives in Task 4.)

- [ ] **Step 4: Confirm `.claude/rules/` is not gitignored**

```bash
cd ~/projects/dotfiles
git check-ignore -v .claude/rules/prefer-declarative-file-management.md; echo "exit=$?"
```

Expected: `exit=1` with no output, meaning the file is not ignored. If it prints
a matching ignore rule, add a `!.claude/rules/` negation to `.gitignore` before
continuing.

- [ ] **Step 5: Commit**

```bash
cd ~/projects/dotfiles
git add -A .claude/rules core/common/claude/CLAUDE_DOT_MD.md
git commit -m "fix(claude): stop double-loading anti-ai-slop, scope the nix rule to this repo

Claude Code auto-discovers ~/.claude/rules/*.md and <repo>/.claude/rules/*.md at
session start, so the @rules/anti-ai-slop.md import loaded that file twice.

prefer-declarative-file-management describes a convention specific to this
repo's nix tree, so it moves to .claude/rules/ instead of shipping to every
machine's ~/.claude/rules/."
```

---

### Task 3: Give the anti-slop taxonomy one home

**Files:**
- Modify: `core/common/claude/files/agents/anti-ai-slop-reviewer.md`

**Interfaces:**
- Consumes: `~/.claude/rules/anti-ai-slop.md`, unchanged by this plan.
- Produces: nothing.

- [ ] **Step 1: Confirm the duplication**

```bash
cd ~/projects/dotfiles
grep -c 'plethora' core/common/claude/files/rules/anti-ai-slop.md \
                   core/common/claude/files/agents/anti-ai-slop-reviewer.md
```

Expected: a nonzero count in both files — the vocabulary list is restated.

- [ ] **Step 2: Replace the agent's taxonomy with a pointer**

In `core/common/claude/files/agents/anti-ai-slop-reviewer.md`, leave the YAML
frontmatter exactly as it is. Replace everything from the `## What you flag`
heading through the end of numbered item 13 (`**Formatting bloat** — … straight
quotes belong (they break code blocks and configs).`) with:

```markdown
## What you flag

The taxonomy is `~/.claude/rules/anti-ai-slop.md`. Read it before you review;
it is canonical and this prompt deliberately does not restate it. Work through
its numbered sections and find every instance in the text you were given. For
each, the fix is almost always **cut it or replace it with a plain, specific
statement**.

Two items need more than the rule file gives you:

- **Fabrication** — when a text names a file, symbol, flag, config key, or URL,
  verify it with Read/Grep/Glob. Flag anything that does not exist. Report that
  a reference *looks* invented; do not adjudicate whether the underlying fact is
  true.
- **Formatting** — check headings against the surrounding document's existing
  case convention rather than against a fixed rule.
```

Leave `## How to decide severity` and `## Output format` untouched. Leave the
`## What you receive` section untouched.

- [ ] **Step 3: Verify the agent file no longer restates the vocabulary**

```bash
cd ~/projects/dotfiles
grep -c 'plethora' core/common/claude/files/agents/anti-ai-slop-reviewer.md; echo "exit=$?"
```

Expected: `0` and `exit=1` (grep found nothing).

- [ ] **Step 4: Verify frontmatter still parses**

```bash
cd ~/projects/dotfiles
head -1 core/common/claude/files/agents/anti-ai-slop-reviewer.md
grep -n '^---$' core/common/claude/files/agents/anti-ai-slop-reviewer.md | head -2
```

Expected: first line is `---`, and exactly two `---` lines appear near the top
(opening and closing the frontmatter).

- [ ] **Step 5: Commit**

```bash
cd ~/projects/dotfiles
git add core/common/claude/files/agents/anti-ai-slop-reviewer.md
git commit -m "refactor(claude): anti-ai-slop-reviewer reads the rule instead of restating it

The agent prompt restated all 13 taxonomy items from
files/rules/anti-ai-slop.md. The rule file is now the single source; the agent
keeps only what is agent-specific (input handling, severity weighting, output
format) and reads the taxonomy with the Read tool it already has."
```

---

### Task 4: Add the concision rule

**Files:**
- Create: `core/common/claude/files/rules/concise-documentation.md`

**Interfaces:**
- Consumes: nothing.
- Produces: a file the `mapTree` walker in `core/common/claude/default.nix` picks up automatically. No module edit needed.

- [ ] **Step 1: Write the rule**

Create `core/common/claude/files/rules/concise-documentation.md`:

```markdown
# Write less documentation, and write it shorter

The anti-AI-slop rules govern how a sentence reads. This one governs whether the
sentence should exist.

## Don't write documents nobody asked for

- Default to editing an existing document rather than adding one. A new file
  fragments the place a reader looks.
- A change that a commit message explains does not also need a design note, a
  summary file, or a `NOTES.md`. Write the commit message.
- Do not leave behind the scaffolding of your own work — status files, migration
  checklists, "what I did" summaries. If it was useful to you and not to the
  next reader, delete it.
- When asked to "document" something, ask what question the reader will arrive
  with. Answer that question. Stop.

## Keep what you do write short

- A section earns its place by answering a question a reader will actually have.
  Delete sections that exist for symmetry, for completeness, or to look
  thorough.
- Prefer one accurate sentence to three hedged ones. Prefer a code block to a
  paragraph describing the code block.
- When a document grows past what someone will read, cut it. Do not reorganize
  it, add a table of contents, or split it into a directory of smaller documents
  that collectively nobody reads.
- Comments follow the same rule: explain a constraint the code cannot show.
  Never narrate what the next line does.

## The test

Read what you wrote and ask, of each paragraph: if I deleted this, what would
the reader fail to do? If the answer is "nothing", delete it.
```

- [ ] **Step 2: Verify the rules directory holds exactly what it should**

`core/common/claude/default.nix` maps every regular file under `files/` to
`~/.claude/<relpath>` with `lib.filesystem.listFilesRecursive`, so a new file
needs no module edit. Confirm the directory contents:

```bash
cd ~/projects/dotfiles
ls core/common/claude/files/rules/
```

Expected exactly: `anti-ai-slop.md`, `concise-documentation.md`,
`no-tombstone-comments.md`. Task 9 Step 2 confirms the mapping reaches
`~/.claude/rules/`.

- [ ] **Step 3: Commit**

```bash
cd ~/projects/dotfiles
git add core/common/claude/files/rules/concise-documentation.md
git commit -m "feat(claude): add concise-documentation rule

The anti-ai-slop rule covers how prose reads; nothing covered whether a document
should exist or how long it should be. Generated docs keep growing."
```

---

### Task 5: Declare the plugins every environment needs

**Files:**
- Create: `core/common/claude/plugins.nix`
- Modify: `core/common/claude/default.nix` (the `baseSettings` binding)
- Modify: `environments/agent/claude.nix` (the `managedSettings` binding)

**Interfaces:**
- Produces: `core/common/claude/plugins.nix` evaluates to
  `{ extraKnownMarketplaces = { <name>.source = { source = "github"; repo = "<owner>/<repo>"; }; ... }; enabledPlugins = { "<plugin>@<marketplace>" = true; ... }; }`.
  It is a plain attrset, **not** a module — `import` it, do not add it to `imports`.
  Task 6 moves the `environments/agent/claude.nix` consumer to `core/common/agent/claude.nix`.

- [ ] **Step 1: Confirm the container is missing the plugins today**

```bash
cd ~/projects/dotfiles
grep -n 'enabledPlugins' -r core environments
```

Expected: exactly one hit, in `environments/agent/claude.nix`, enabling only
`codex@openai-codex`. Nothing declares `dispatch@agentic`.

- [ ] **Step 2: Create the shared attrset**

Create `core/common/claude/plugins.nix`:

```nix
# Claude Code plugins every environment gets, as a plain attrset (not a module)
# so it can be spliced into two different shapes of settings JSON:
#
#   - core/common/claude/default.nix folds it into `baseSettings`, which lands
#     in the user's ~/.claude/settings.json.
#   - core/common/agent/claude.nix folds it into the managed-settings policy the
#     agent host installs at /etc/claude-code/managed-settings.json.
#
# A marketplace must be declared before a plugin from it can be enabled; a fresh
# container knows about none of them, so all three are listed explicitly even
# though an interactive machine may already have added them via `/plugin`.
{
  extraKnownMarketplaces = {
    claude-plugins-official.source = {
      source = "github";
      repo = "anthropics/claude-plugins-official";
    };
    openai-codex.source = {
      source = "github";
      repo = "openai/codex-plugin-cc";
    };
    agentic.source = {
      source = "github";
      repo = "ianwremmel/agentic";
    };
  };

  enabledPlugins = {
    "code-review@claude-plugins-official" = true;
    "code-simplifier@claude-plugins-official" = true;
    "typescript-lsp@claude-plugins-official" = true;
    "codex@openai-codex" = true;
    "dispatch@agentic" = true;
  };
}
```

- [ ] **Step 3: Feed it into the user settings**

In `core/common/claude/default.nix`, the `baseSettings` binding currently reads:

```nix
  # Keys every profile should have; per-profile keys come from cfg.settings and
  # win on conflict. Empty today — kept so universal defaults have a home.
  baseSettings = { };
```

Replace with:

```nix
  # Keys every profile should have; per-profile keys come from cfg.settings and
  # win on conflict.
  baseSettings = import ./plugins.nix;
```

- [ ] **Step 4: Feed it into the managed-settings policy**

In `environments/agent/claude.nix`, the `managedSettings` binding currently reads:

```nix
  managedSettings = jsonFormat.generate "claude-managed-settings.json" {
    extraKnownMarketplaces.openai-codex.source = {
      source = "github";
      repo = "openai/codex-plugin-cc";
    };
    enabledPlugins."codex@openai-codex" = true;
    hooks = {
      Stop = [{ hooks = [{ type = "command"; command = "play-sound Morse 0.4"; }]; }];
      Notification = [{ hooks = [{ type = "command"; command = "play-sound Ping 0.35"; }]; }];
    };
  };
```

Replace with:

```nix
  managedSettings = jsonFormat.generate "claude-managed-settings.json" (
    (import ../../core/common/claude/plugins.nix) // {
      hooks = {
        Stop = [{ hooks = [{ type = "command"; command = "play-sound Morse 0.4"; }]; }];
        Notification = [{ hooks = [{ type = "command"; command = "play-sound Ping 0.35"; }]; }];
      };
    }
  );
```

Also update the comment above it: it says "It pre-approves the codex plugin
marketplace + plugin". Change that clause to "It pre-approves the shared plugin
set (see `core/common/claude/plugins.nix`)".

The `../../core/...` relative path works because `environments/agent/` is a
sibling of `core/` in the source tree, and `lib/nix` builds this flake with
`path:` (whole-tree) semantics. Task 6 removes this path when the consumer moves
into `core/common/agent/`, where it becomes `../claude/plugins.nix`.

- [ ] **Step 5: Verify the attrset shape**

`settings.json` is not a `home.file` entry — the bundle seeds it from a store
path via the `seedClaudeSettings` activation script, so it cannot be read out of
the evaluated config. Check the attrset directly, and leave the end-to-end
assertion to Task 9 Step 2:

```bash
cd ~/projects/dotfiles
nix eval --impure --expr '(import ./core/common/claude/plugins.nix).enabledPlugins'
nix eval --impure --expr 'builtins.attrNames (import ./core/common/claude/plugins.nix).extraKnownMarketplaces'
```

Expected: an attrset with all five plugin keys set to `true`, then
`[ "agentic" "claude-plugins-official" "openai-codex" ]`.

- [ ] **Step 6: Verify the agent environment still evaluates**

```bash
cd ~/projects/dotfiles
nix eval --raw "path:$PWD/environments/agent#homeConfigurations.\"x86_64-linux\".activationPackage.drvPath" \
  --override-input public "path:$PWD/core"
```

Expected: a `/nix/store/....drv` path. Evaluation works cross-platform, so this
succeeds on macOS even though the output is a Linux derivation.

- [ ] **Step 7: Commit**

```bash
cd ~/projects/dotfiles
git add core/common/claude/plugins.nix core/common/claude/default.nix environments/agent/claude.nix
git commit -m "feat(claude): declare the plugin set for every environment

Only the agent managed-settings policy declared a plugin, and only codex. Every
other plugin existed as interactive ~/.claude/plugins state that no environment
reproduced, so a fresh dev container had no /deliver, no /code-review, and no
typescript LSP.

plugins.nix is the one declaration, spliced into both the user settings.json
seed and the managed-settings policy."
```

---

### Task 6: Split the agent environment

This is the largest task. It creates the `core/common/agent` bundle, two real
environments, two re-exporting shells, and generalizes the `lib/nix` input
override. It is one task because no intermediate state evaluates: `lib/nix`
cannot override `agent-interactive` until that directory exists, and
`dev-container` cannot re-export it until `lib/nix` can.

**Files:**
- Create: `core/common/agent/default.nix`, `core/common/agent/cli-tools.nix`, `core/common/agent/claude.nix`
- Create: `environments/agent-interactive/flake.nix`, `environments/agent-interactive/home.nix`, `environments/agent-interactive/shell-extras.nix`, `environments/agent-interactive/repos.txt`
- Create: `environments/agent-autonomous/flake.nix`
- Modify: `core/flake.nix` (add `homeModules.agent`)
- Modify: `lib/nix:273-294`
- Rewrite: `environments/agent/flake.nix`, `environments/dev-container/flake.nix`
- Delete: `environments/agent/{home.nix,cli-tools.nix,claude.nix,shell-extras.nix}`, `environments/dev-container/{dev-container.nix,repos.txt}`

**Interfaces:**
- Consumes: `core/common/claude/plugins.nix` from Task 5, at its new relative path `../claude/plugins.nix`.
- Produces: `public.homeModules.agent` — a bundle that already imports `public.homeModules.claude`. An environment adds it to `mkHome`'s `modules` list. It does **not** set `dotfiles.pairing.mode`; each environment sets that itself.

- [ ] **Step 1: Move the agent modules into a core bundle**

```bash
cd ~/projects/dotfiles
mkdir -p core/common/agent environments/agent-interactive environments/agent-autonomous
git mv environments/agent/cli-tools.nix    core/common/agent/cli-tools.nix
git mv environments/agent/claude.nix       core/common/agent/claude.nix
git mv environments/agent/shell-extras.nix environments/agent-interactive/shell-extras.nix
git rm environments/agent/home.nix
```

`shell-extras.nix` lands in `agent-interactive`, not the bundle: it `exec`s into
a tmux session, which only makes sense with a human on the far end of the SSH
connection.

- [ ] **Step 2: Write the bundle entry point**

Create `core/common/agent/default.nix`:

```nix
{ ... }: {
  # Shared-optional bundle: the tooling and machinery needed to run Claude (and
  # other agents) unattended over SSH. An environment opts in by adding
  # `public.homeModules.agent` to the `modules` list it passes to `mkHome`.
  #
  # The bundle imports `../claude` so a consuming environment gets the shared
  # ~/.claude content (rules, agents, base CLAUDE.md, the settings.json
  # seed/merge) without listing that bundle separately. The module system
  # dedupes, so an environment may still list `public.homeModules.claude`.
  #
  # Anything specific to one agent host — a cluster's CLIs, its MCP servers,
  # which repos to clone — belongs in the consuming environment, not here.
  imports = [
    ../claude
    ./cli-tools.nix
    ./claude.nix
  ];
}
```

- [ ] **Step 3: Repoint the moved `claude.nix`**

`core/common/agent/claude.nix` came from `environments/agent/claude.nix`. Two edits:

1. Its `plugins.nix` import path changes from `../../core/common/claude/plugins.nix` to `../claude/plugins.nix`.
2. Its header comment describes the old flake-boundary caveat. Replace the whole
   leading comment on the `home.file` attribute with:

```nix
  # Exported under ~/.config/agent/ as content the host wires in: the managed
  # settings is a system policy file, and the MCP list is registered at boot with
  # token substitution. Linux only — the sound hooks call the play-sound shim,
  # which (like the sshd config) only ships on Linux agent hosts.
  home.file = lib.mkIf pkgs.stdenv.isLinux {
```

Everything else in the file (the `mcpServers` derivation, the
`installAgentManagedSettings` activation script) is unchanged.

- [ ] **Step 4: Export the bundle from core**

In `core/flake.nix`, the `homeModules` attrset reads:

```nix
      homeModules = {
        base = ./home.nix;
        all  = ./all/home/default.nix;

        claude  = ./common/claude;
        pairing = ./common/pairing;
      };
```

Change to:

```nix
      homeModules = {
        base = ./home.nix;
        all  = ./all/home/default.nix;

        agent   = ./common/agent;
        claude  = ./common/claude;
        pairing = ./common/pairing;
      };
```

- [ ] **Step 5: Build `agent-interactive`**

```bash
cd ~/projects/dotfiles
git mv environments/dev-container/repos.txt        environments/agent-interactive/repos.txt
git mv environments/dev-container/dev-container.nix environments/agent-interactive/home.nix
```

`environments/agent-interactive/home.nix` keeps its contents verbatim for now —
the Grafana removal is Task 8. Update only its leading comment, which says
"homelab dev container", to say "interactive agent host". Its `repos_file`
reference (`${./repos.txt}`) resolves against the new directory unchanged.

Create `environments/agent-interactive/flake.nix`:

```nix
{
  description = "ianwremmel dotfiles — agent-interactive environment (agent bundle + homelab cluster tooling)";

  # Linux-only: an interactive agent host is a container you SSH into. Layers
  # the shared agent bundle (which carries the claude bundle) with this host's
  # cluster tooling, repo clones, and tmux auto-attach.
  inputs = {
    public.url = "github:ianwremmel/dotfiles?dir=core";
    nixpkgs.follows      = "public/nixpkgs";
    home-manager.follows = "public/home-manager";
    nix-darwin.follows   = "public/nix-darwin";
  };

  outputs = { self, public, ... }:
    let
      host = import (public + "/host.nix");
      systems = [ "x86_64-linux" "aarch64-linux" ];
    in {
      homeConfigurations = builtins.listToAttrs (map
        (system: {
          name = system;
          value = public.lib.mkHome {
            inherit system;
            inherit (host) username;
            modules = [
              public.homeModules.agent
              ./home.nix
              ./shell-extras.nix
              public.homeModules.pairing
              { dotfiles.pairing.mode = "server"; }
            ];
          };
        })
        systems);
    };
}
```

- [ ] **Step 6: Build `agent-autonomous`**

Create `environments/agent-autonomous/flake.nix`:

```nix
{
  description = "ianwremmel dotfiles — agent-autonomous environment (agent bundle, unattended)";

  # An unattended agent host: the shared agent bundle and nothing else. Distinct
  # from agent-interactive, which adds a cluster toolchain, repo clones, and a
  # tmux session for a human on the other end of an SSH pipe.
  inputs = {
    public.url = "github:ianwremmel/dotfiles?dir=core";
    nixpkgs.follows      = "public/nixpkgs";
    home-manager.follows = "public/home-manager";
    nix-darwin.follows   = "public/nix-darwin";
  };

  outputs = { self, public, ... }:
    let
      host = import (public + "/host.nix");
      supportedSystems = [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ];
      darwinSystems    = [ "aarch64-darwin" "x86_64-darwin" ];
    in {
      homeConfigurations = builtins.listToAttrs (map
        (system: {
          name = system;
          value = public.lib.mkHome {
            inherit system;
            inherit (host) username;
            modules = [
              public.homeModules.agent
              public.homeModules.pairing
              { dotfiles.pairing.mode = "server"; }
            ];
          };
        })
        supportedSystems);

      # This environment contributes no darwin module; on macOS it gets the
      # universal base + all system layer only.
      darwinConfigurations = builtins.listToAttrs (map
        (system: {
          name = system;
          value = public.lib.mkDarwin {
            inherit system;
            inherit (host) username;
            modules = [ ];
          };
        })
        darwinSystems);
    };
}
```

- [ ] **Step 7: Turn `agent` and `dev-container` into re-exporting shells**

Replace `environments/agent/flake.nix` entirely with:

```nix
{
  description = "ianwremmel dotfiles — agent environment (alias for agent-autonomous)";

  # Kept as a selectable name. `agent-autonomous` holds the content; this flake
  # re-exports its configurations unchanged. `agent-autonomous.inputs.public
  # .follows = "public"` makes both halves build against the same core, which
  # lib/nix overrides to the local checkout.
  inputs = {
    public.url = "github:ianwremmel/dotfiles?dir=core";
    agent-autonomous.url = "github:ianwremmel/dotfiles?dir=environments/agent-autonomous";
    agent-autonomous.inputs.public.follows = "public";
    nixpkgs.follows      = "public/nixpkgs";
    home-manager.follows = "public/home-manager";
    nix-darwin.follows   = "public/nix-darwin";
  };

  outputs = { self, agent-autonomous, ... }: {
    inherit (agent-autonomous) homeConfigurations darwinConfigurations;
  };
}
```

Replace `environments/dev-container/flake.nix` entirely with:

```nix
{
  description = "ianwremmel dotfiles — dev-container environment (alias for agent-interactive)";

  # Kept as a selectable name because homelab's images/dev-base/lib/bootstrap.sh
  # hardcodes DOTFILES_ENVIRONMENT=dev-container. `agent-interactive` holds the
  # content; this flake re-exports its configurations unchanged.
  inputs = {
    public.url = "github:ianwremmel/dotfiles?dir=core";
    agent-interactive.url = "github:ianwremmel/dotfiles?dir=environments/agent-interactive";
    agent-interactive.inputs.public.follows = "public";
    nixpkgs.follows      = "public/nixpkgs";
    home-manager.follows = "public/home-manager";
    nix-darwin.follows   = "public/nix-darwin";
  };

  outputs = { self, agent-interactive, ... }: {
    inherit (agent-interactive) homeConfigurations;
  };
}
```

Nix identifiers admit `-`, so `agent-interactive` is a legal name in both the
input attrset and the `outputs` function pattern — the same way `home-manager`
already appears in `core/flake.nix`.

- [ ] **Step 8: Generalize the `lib/nix` input override**

In `lib/nix`, replace the comment block and code at lines 273-294 (from
`# \`agent\` is overridden only for envs` through the closing `fi` of the agent
gate) with:

```bash
  # An env flake may declare another *environment* as an input — the trivial
  # `agent` / `dev-container` shells re-export a sibling's configurations. For
  # every directory under environments/ whose name the selected flake declares
  # as an input, override that input to the local checkout, exactly as `public`
  # is overridden. Without this, nix would fetch the sibling from github and
  # build a stale tree.
  #
  # `shared` is the custom_environments library consumed by private envs that
  # declare it; override it to the local tree only when the selected env does.
  #
  # Every override is gated on a declaration test because passing
  # `--override-input` for an input the env doesn't declare makes nix warn
  # ("does not match any input"). The greps are cheap text tests (no `nix
  # eval`); they match an input DECLARATION — `<name>.url` / `<name>.inputs` as
  # the first non-whitespace token on a line, the form these flakes use.
  # Anchoring at line start (modulo indentation) avoids matching the name inside
  # a comment or mid-line (e.g. a `# … agent.inputs …` note, or a
  # `something.follows = "agent/nixpkgs"`), which would re-introduce the very
  # warning this gate exists to prevent. The trailing `\.` in the pattern also
  # keeps `agent` from matching a declaration of `agent-autonomous`. `overrides`
  # always carries `public`, so plain `"${overrides[@]}"` expansion is never
  # empty.
  local -a overrides
  overrides=(--override-input public "path:$DOTFILES_ROOT_DIR/core")
  local env_dir env_name
  for env_dir in "$DOTFILES_ROOT_DIR"/environments/*/; do
    [ -f "$env_dir/flake.nix" ] || continue
    env_name="$(basename "$env_dir")"
    if grep -Eq "^[[:space:]]*${env_name}\.(url|inputs)" "$flake_dir/flake.nix" 2>/dev/null; then
      overrides=("${overrides[@]}" --override-input "$env_name" "path:$DOTFILES_ROOT_DIR/environments/$env_name")
    fi
  done
  local shared_dir="$DOTFILES_ROOT_DIR/custom_environments/shared"
  if [ -d "$shared_dir" ] \
     && grep -Eq '^[[:space:]]*shared\.(url|inputs)' "$flake_dir/flake.nix" 2>/dev/null; then
    overrides=("${overrides[@]}" --override-input shared "path:$shared_dir")
  fi
```

Note the array grows with `overrides=("${overrides[@]}" …)`, never `+=`, for
Bash 3.2.

- [ ] **Step 9: Parse-check under the stock 3.2 parser**

```bash
cd ~/projects/dotfiles
/bin/bash --version | head -1
/bin/bash -n lib/nix && echo "lib/nix OK"
/bin/bash -n apply && echo "apply OK"
for f in framework/*; do [ -f "$f" ] && /bin/bash -n "$f" && echo "$f OK"; done
```

Expected: `GNU bash, version 3.2.57` on the first line, then `OK` for each file.

- [ ] **Step 10: Verify the override loop selects the right inputs**

```bash
cd ~/projects/dotfiles
for env in agent agent-autonomous agent-interactive default dev-container; do
  printf '%-20s' "$env"
  for d in environments/*/; do
    n="$(basename "$d")"
    grep -Eq "^[[:space:]]*${n}\.(url|inputs)" "environments/$env/flake.nix" 2>/dev/null && printf ' %s' "$n"
  done
  echo
done
```

Expected exactly:

```
agent                agent-autonomous
agent-autonomous
agent-interactive
default
dev-container        agent-interactive
```

In particular `agent` must not appear on the `agent` row (a flake declaring
`agent-autonomous.url` must not match the `agent` pattern) and must not appear
on the `dev-container` row.

- [ ] **Step 11: Evaluate every environment**

```bash
cd ~/projects/dotfiles
root="$PWD"
sys_darwin="$(nix eval --raw --impure --expr builtins.currentSystem)"

nix eval --raw "path:$root/environments/default#homeConfigurations.\"$sys_darwin\".activationPackage.drvPath" \
  --override-input public "path:$root/core" >/dev/null && echo "default OK"

nix eval --raw "path:$root/environments/agent-interactive#homeConfigurations.\"x86_64-linux\".activationPackage.drvPath" \
  --override-input public "path:$root/core" >/dev/null && echo "agent-interactive OK"

nix eval --raw "path:$root/environments/agent-autonomous#homeConfigurations.\"x86_64-linux\".activationPackage.drvPath" \
  --override-input public "path:$root/core" >/dev/null && echo "agent-autonomous OK"

nix eval --raw "path:$root/environments/dev-container#homeConfigurations.\"x86_64-linux\".activationPackage.drvPath" \
  --override-input public "path:$root/core" \
  --override-input agent-interactive "path:$root/environments/agent-interactive" >/dev/null && echo "dev-container OK"

nix eval --raw "path:$root/environments/agent#homeConfigurations.\"x86_64-linux\".activationPackage.drvPath" \
  --override-input public "path:$root/core" \
  --override-input agent-autonomous "path:$root/environments/agent-autonomous" >/dev/null && echo "agent OK"
```

Expected: five `OK` lines, no `warning: input 'X' does not match any input`.

If a flake input is not yet in `flake.lock`, nix will try to fetch the
placeholder `github:` URL. Pass `--no-write-lock-file` and confirm the
`--override-input` supplies it; if nix still fetches, the input name in the
flake does not match the name passed to `--override-input`.

- [ ] **Step 12: Verify the dev container now gets the claude bundle**

This is the bug that started the work. `~/.claude/CLAUDE.md` must appear in the
dev-container config's `home.file`:

```bash
cd ~/projects/dotfiles
root="$PWD"
nix eval "path:$root/environments/dev-container#homeConfigurations.\"x86_64-linux\".config.home.file.\".claude/CLAUDE.md\".source" \
  --override-input public "path:$root/core" \
  --override-input agent-interactive "path:$root/environments/agent-interactive"
```

Expected: a `/nix/store/...` path. Before this task it would have thrown
`attribute '".claude/CLAUDE.md"' missing`.

- [ ] **Step 13: Commit**

```bash
cd ~/projects/dotfiles
git add -A core/common/agent core/flake.nix lib/nix environments
git commit -m "refactor(nix): split agent into a core bundle + interactive/autonomous envs

environments/agent was both a selectable environment and the base that
dev-container extended through a flake input, so anything added for one was
forced on the other.

The base becomes core/common/agent, a bundle. It imports ../claude, which fixes
a live bug: dev-container passed agent.homeModules.agent to mkHome without
public.homeModules.claude, so the container had no ~/.claude/CLAUDE.md, rules,
or agents. A bundle carries its own imports; a bare module path exported across
a flake boundary cannot.

agent-interactive holds the cluster tooling, repo clones, credential restore,
and tmux auto-attach. agent-autonomous holds nothing yet. agent and
dev-container re-export a sibling's homeConfigurations so both names keep
working; homelab's bootstrap.sh hardcodes dev-container.

lib/nix now overrides any input named after a local environment directory
rather than hardcoding 'agent'."
```

---

### Task 7: Update the repo's own documentation

**Files:**
- Modify: `CLAUDE.md`
- Modify: `core/CLAUDE.md`

**Interfaces:**
- Consumes: the structure created in Tasks 2, 5, and 6.
- Produces: nothing.

- [ ] **Step 1: Update the root `CLAUDE.md` structure list**

The `## Structure` section lists `environments/` as "One flake per selectable
environment (`default`, `agent`)". Replace that bullet with:

```markdown
- `environments/` - One flake per selectable environment, each consuming
  `core/`. `default` (personal machine) and `agent-interactive` (SSH-in agent
  host) carry content; `agent-autonomous` is the unattended host, empty beyond
  the shared bundle. `agent` and `dev-container` are thin aliases that
  re-export `agent-autonomous` and `agent-interactive` respectively — homelab's
  `bootstrap.sh` hardcodes `DOTFILES_ENVIRONMENT=dev-container`.
```

Add a bullet after it:

```markdown
- `.claude/rules/` - Rules that apply only to work in this repo. Claude Code
  auto-discovers them; no `@` import needed.
```

- [ ] **Step 2: Update `core/CLAUDE.md`**

In the `## Layering` section, the `homeModules.<bundle>` bullet says
"`homeModules.claude` is the first one." Change that clause to
"`homeModules.{agent,claude,pairing}` are the shipped bundles."

In the `## Common bundles (common/)` section, add a bullet before the
`common/pairing` one:

```markdown
- **`common/agent`** — the base for agent hosts: `bk`, the Claude
  managed-settings policy, and the MCP server list exported to
  `~/.config/agent/`. It `imports` `../claude`, so an environment adding
  `public.homeModules.agent` also gets the shared `~/.claude` content. Host-
  specific tooling belongs in the consuming environment.
```

In the same section, the `common/pairing` bullet says `server` is "set by
`agent`, re-set by `dev-container`". Change to "set by `agent-interactive` and
`agent-autonomous`".

In `## Where things go`, add after the Claude Code bullet:

```markdown
- **A Claude Code plugin every machine should have** → `enabledPlugins` in
  `core/common/claude/plugins.nix`, with its marketplace in the
  `extraKnownMarketplaces` attrset beside it. The file is spliced into both the
  user `settings.json` seed and the agent managed-settings policy.
```

In the `## Layering` section, the two shipped environments are described as
`default` and `agent`. Replace the `agent` bullet with:

```markdown
- **`agent-interactive`** — an SSH-in agent host. Home half only, Linux only:
  the `agent` bundle plus cluster CLIs, `repos.txt` clones, credential restore,
  and tmux auto-attach.
- **`agent-autonomous`** — an unattended agent host. The `agent` bundle and
  nothing else. Both halves, since it still yields the universal darwin layer
  on macOS.
```

- [ ] **Step 3: Verify no stale references remain**

```bash
cd ~/projects/dotfiles
grep -rn 'homeModules\.agent\b' --include=*.md --include=*.nix . | grep -v '^\./docs/'
grep -rn 'dev-container\.nix' --include=*.md --include=*.nix . | grep -v '^\./docs/'
```

Expected from the first: hits in `core/flake.nix`, `core/CLAUDE.md`, and the two
agent environment flakes — all referring to the new bundle. Expected from the
second: no hits.

- [ ] **Step 4: Commit**

```bash
cd ~/projects/dotfiles
git add CLAUDE.md core/CLAUDE.md
git commit -m "docs: describe the agent bundle, the new environments, and plugins.nix"
```

---

### Task 8: Move the Grafana MCP server into the homelab repo

Two repos. The homelab change must merge first, or the dev container loses
Grafana between the dotfiles merge and the homelab merge.

**Files:**
- Create: `~/projects/homelab/.mcp.json`
- Modify: `~/projects/homelab/images/dev-base/lib/bootstrap.sh` (the `dev_bootstrap::register_mcp_servers` function, around line 225-236)
- Modify: `~/projects/dotfiles/environments/agent-interactive/home.nix`

**Interfaces:**
- Consumes: `environments/agent-interactive/home.nix` from Task 6.
- Produces: nothing.

- [ ] **Step 1: Add `.mcp.json` to the homelab repo, on a branch**

```bash
cd ~/projects/homelab
git switch -c feat/grafana-mcp-project-scoped
```

Create `~/projects/homelab/.mcp.json`:

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

Claude Code reads `.mcp.json` from a project root and expands `${VAR}` from the
environment, so the token is never written to disk.

- [ ] **Step 2: Stop merging the nix-generated homelab MCP file**

In `~/projects/homelab/images/dev-base/lib/bootstrap.sh`, the function reads:

```bash
dev_bootstrap::register_mcp_servers() {
    # ---- Register MCP servers from declarative config ----
    # The server list is assembled from the agent profile (Linear, Buildkite) plus
    # any host-specific servers the dev-container flake adds (Grafana). Both are
    # nix-managed files under ~/.config/agent/; merge their `servers` arrays.
    MCP_MERGED=""
    mcp_files=()
    [ -f "$AGENT_CONF_DIR/mcp-servers.json" ] && mcp_files+=("$AGENT_CONF_DIR/mcp-servers.json")
    [ -f "$AGENT_CONF_DIR/mcp-servers-homelab.json" ] && mcp_files+=("$AGENT_CONF_DIR/mcp-servers-homelab.json")
```

Replace those lines with:

```bash
dev_bootstrap::register_mcp_servers() {
    # ---- Register MCP servers from declarative config ----
    # The globally-registered servers (Linear, Buildkite) come from the agent
    # profile as a nix-managed file under ~/.config/agent/. A server useful only
    # inside one project belongs in that project's own `.mcp.json` instead.
    MCP_MERGED=""
    mcp_files=()
    [ -f "$AGENT_CONF_DIR/mcp-servers.json" ] && mcp_files+=("$AGENT_CONF_DIR/mcp-servers.json")
```

Leave the `AI_DEV_MCP_EXTRA` lines and everything below unchanged. This file is
not under the Bash 3.2 constraint — it runs in the container — so its `+=` array
append stays.

- [ ] **Step 3: Verify the homelab JSON parses**

```bash
cd ~/projects/homelab
jq . .mcp.json
bash -n images/dev-base/lib/bootstrap.sh && echo "bootstrap.sh OK"
grep -c 'mcp-servers-homelab' images/dev-base/lib/bootstrap.sh; echo "exit=$?"
```

Expected: the JSON pretty-prints, `bootstrap.sh OK`, and the final grep prints
`0` with `exit=1`.

- [ ] **Step 4: Commit and open the homelab PR**

```bash
cd ~/projects/homelab
git add .mcp.json images/dev-base/lib/bootstrap.sh
git commit -m "feat: scope the grafana MCP server to this project

The grafana server was registered for every session in the dev container via a
nix-generated ~/.config/agent/mcp-servers-homelab.json. It is only useful when
working on this repo, so it moves to a project-root .mcp.json, where Claude Code
expands \${GRAFANA_SERVICE_ACCOUNT_TOKEN} from the environment.

Pairs with a dotfiles change that drops the generated file."
git push -u origin HEAD
gh pr create --base main --head feat/grafana-mcp-project-scoped \
  --title "feat: scope the grafana MCP server to this project" \
  --body "The grafana MCP server was registered globally in every dev-container session. It only matters when working on homelab, so it moves to a project-root \`.mcp.json\`.

Pairs with ianwremmel/dotfiles, which drops the nix-generated \`~/.config/agent/mcp-servers-homelab.json\`. **Merge this first** — otherwise the container loses grafana between the two merges.

\`mcp-grafana\` stays on PATH: it is still installed by the dotfiles \`agent-interactive\` environment."
```

Check the push output says `feat/grafana-mcp-project-scoped -> feat/grafana-mcp-project-scoped`. Do not merge without asking.

- [ ] **Step 5: Drop the generated file from dotfiles**

In `environments/agent-interactive/home.nix`, delete the `grafanaMcp` binding
from the `let` block:

```nix
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
          GRAFANA_URL = "http://kube-prometheus-stack-grafana.observability.svc.cluster.local";
          GRAFANA_SERVICE_ACCOUNT_TOKEN = "$GRAFANA_SERVICE_ACCOUNT_TOKEN";
        };
      }
    ];
  };
```

and delete this line from the module body:

```nix
  home.file.".config/agent/mcp-servers-homelab.json".source = grafanaMcp;
```

`jsonFormat` is then unused — delete `jsonFormat = pkgs.formats.json { };` from
the `let` block too, and drop `pkgs` from the module arguments if nothing else
uses it. **Check first**: `home.packages = with pkgs; [...]` uses `pkgs`, so keep it.

Keep `mcp-grafana` in `home.packages`. The project `.mcp.json` invokes that
binary by name and needs it on `PATH`.

- [ ] **Step 6: Verify**

```bash
cd ~/projects/dotfiles
root="$PWD"
grep -c 'grafana' environments/agent-interactive/home.nix
nix eval --raw "path:$root/environments/agent-interactive#homeConfigurations.\"x86_64-linux\".activationPackage.drvPath" \
  --override-input public "path:$root/core" >/dev/null && echo "agent-interactive OK"
```

Expected: the grep prints `1` (the surviving `mcp-grafana` package), then
`agent-interactive OK`.

- [ ] **Step 7: Commit**

```bash
cd ~/projects/dotfiles
git add environments/agent-interactive/home.nix
git commit -m "refactor(agent): drop the globally-registered grafana MCP server

The server is only useful when working on homelab, which now carries it in its
own project-root .mcp.json. mcp-grafana stays in home.packages so that file can
invoke it."
```

---

### Task 9: Apply and verify end to end

**Files:** none.

- [ ] **Step 1: Apply on this machine**

```bash
cd ~/projects/dotfiles
./apply
```

Expected: no `warning: input '...' does not match any input`. If it appears, the
`lib/nix` grep in Task 6 Step 8 matched an input the flake does not declare.

- [ ] **Step 2: Assert the results**

```bash
git config --get push.default                       # current
git config --get push.autoSetupRemote               # true
ls ~/.claude/rules/                                  # anti-ai-slop.md concise-documentation.md no-tombstone-comments.md
jq '.enabledPlugins' ~/.claude/settings.json         # five plugins, all true
jq -r '.extraKnownMarketplaces | keys[]' ~/.claude/settings.json  # agentic, claude-plugins-official, openai-codex
grep -c 'anti-ai-slop' ~/.claude/CLAUDE.md           # 1 (the prose link; the @ import is gone)
```

`~/.claude/rules/` must not contain `feature-branch-push.md` or
`prefer-declarative-file-management.md`. Home-manager removes symlinks it no
longer manages, so no manual cleanup is needed.

- [ ] **Step 3: Restart Claude Code and confirm the plugins install**

```bash
claude plugin list
```

Expected: `dispatch@agentic`, `code-review@claude-plugins-official`,
`code-simplifier@claude-plugins-official`,
`typescript-lsp@claude-plugins-official`, `codex@openai-codex`.

- [ ] **Step 4: Open the dotfiles PR**

```bash
cd ~/projects/dotfiles
git push -u origin HEAD
gh pr create --base master --head chore/claude-config-and-agent-flake-cleanup \
  --title "chore: claude config cleanup + agent flake split" \
  --body "See \`docs/superpowers/specs/2026-07-09-claude-config-and-agent-flake-cleanup-design.md\`.

- \`push.default=current\` + \`autoSetupRemote\` replaces the feature-branch-push rule with config that enforces it
- \`@rules/anti-ai-slop.md\` removed — \`~/.claude/rules/\` auto-loads, so it was loading twice
- \`prefer-declarative-file-management.md\` moves to this repo's \`.claude/rules/\`
- \`anti-ai-slop-reviewer\` reads the rule instead of restating all 13 items
- new \`concise-documentation\` rule
- \`plugins.nix\` declares the five plugins for every environment — this is what puts \`/deliver\` in the dev container
- \`core/common/agent\` bundle + \`agent-interactive\` / \`agent-autonomous\` environments; \`agent\` and \`dev-container\` become aliases
- \`core/common/agent\` imports \`../claude\`, fixing the dev container's missing \`~/.claude\` tree
- grafana MCP moves to homelab's project \`.mcp.json\` (paired PR — merge that one first)"
```

Confirm the push output reads `chore/... -> chore/...`. Do not merge without asking.

- [ ] **Step 5: Verify in the dev container**

After both PRs merge, from an SSH session in the dev container:

```bash
dotfiles-apply
ls ~/.claude/CLAUDE.md ~/.claude/rules/
jq '.enabledPlugins' /etc/claude-code/managed-settings.json
```

Expected: `CLAUDE.md` exists, the rules directory is populated, and the policy
file lists all five plugins. Then start `claude` and confirm `/deliver` resolves.
