# Nix Claude Slice Design

**Date:** 2026-05-27
**Status:** Draft — pending user approval
**Branch:** `nix-claude` (stacks on `nix-vim` / PR #72 → `nix-firstrun` / PR #71 → `nix-darwin` / PR #70 → … → master)

## Goal

Retire the `claude` bash plugin (which does a "build" step — copies `plugins/claude/CLAUDE_DOT_MD.md` to `environments/default/home/.claude/CLAUDE.md`, then relies on the homedir rsync to deploy it) and the rsynced `environments/default/home/.claude/` tree. Manage the user's Claude Code config declaratively via home-manager: `~/.claude/CLAUDE.md`, `~/.claude/settings.json`, `~/.claude/guides/*.md`, plus an auto-discovering mechanism for `~/.claude/{agents,skills,commands,rules}/` so future extension files can be added by dropping them in the repo. Critically, manage **individual files only** — `~/.claude/` is full of live Claude Code state (projects/, plugins/, sessions/, history.jsonl, etc.) that must never be symlinked or shadowed.

## Background — what's in `~/.claude/`

`~/.claude/` on the user's machine contains a large amount of live, machine-local Claude Code state that is NOT ours to manage:

- `backups/`, `cache/`, `debug/`, `file-history/`, `history.jsonl`, `hooks/`, `ide/`, `paste-cache/`, `plans/`, `plugins/`, `projects/`, `sessions/`, `session-env/`, `shell-snapshots/`, `stats-cache.json`, `tasks/`, `.DS_Store`, `.last-cleanup`, `.update.lock`, etc.
- `commands/memory-dump.md` — a user-authored slash command (perms 700), **not in the dotfiles repo**. Per user decision, this is left alone.

What IS ours (currently deployed via rsync from `environments/default/home/.claude/`):

- `CLAUDE.md` (built from `plugins/claude/CLAUDE_DOT_MD.md` by the bash plugin's "build" step)
- `settings.json`
- `guides/conventional-commits.md`
- `guides/standard-readme-spec.md`

The implication is decisive: **we manage individual files, never directories.** A whole-directory symlink of `~/.claude/` or `~/.claude/commands/` into the Nix store would make those paths read-only and shadow live state like `commands/memory-dump.md`.

## Decisions (locked)

1. **Profile: `default` only.** Matches current placement (`environments/default/home/.claude/`). `settings.json` contains macOS-specific `afplay` hook commands, so it's inherently personal-machine. If Claude Code config is ever wanted on `agent` profiles, that's a follow-up slice (and would need the afplay hooks stripped/conditional).
2. **New module `nix/profiles/default/claude.nix`,** imported by `nix/profiles/default/default.nix`. Matches the per-feature submodule pattern (`cli-tools.nix`).
3. **Content subdir `nix/profiles/default/claude/`** holds the source files:
   - `CLAUDE_DOT_MD.md` — source for `~/.claude/CLAUDE.md` (kept as a separate markdown file, not inlined into Nix — preserves markdown editability and avoids Nix `''`-string `${}`/quote escaping. The `_DOT_` name prevents Claude Code from auto-loading it as project context when working in the dotfiles repo).
   - `guides/conventional-commits.md`, `guides/standard-readme-spec.md` — referenced by `CLAUDE.md` via relative `./guides/*.md` links.
   - `agents/.gitkeep`, `skills/.gitkeep`, `commands/.gitkeep`, `rules/.gitkeep` — stubbed extension-point dirs (empty for now).
4. **Per-file management via a Nix auto-discovery helper.** A `let`-bound function maps every regular file under `claude/<subdir>/` to a `home.file.".claude/<subdir>/<relpath>"` entry with `.source` pointing at the repo file. `.gitkeep` files are filtered out. This keeps `~/.claude/<subdir>/` writable (only managed files are symlinks) and never shadows live content. **Adding a new agent/skill/command/rule = drop a file under the matching `nix/profiles/default/claude/<subdir>/` and run `./apply`.**
5. **`settings.json` generated from a Nix attrset** via `pkgs.formats.json {}`'s `.generate`. Produces readable, stable-sorted JSON. The attrset reproduces the current settings verbatim:
   - `permissions.defaultMode = "plan"`
   - `hooks.Stop` → afplay Morse at volume 0.40
   - `hooks.Notification` → afplay Ping at volume 0.35
   - `alwaysThinkingEnabled = true`
   - `sandbox = { autoAllowBashIfSandboxed = true; enabled = true; excludedCommands = [ "git" ]; }`
6. **Move-aside migration for the four currently-rsynced regular files.** A `home.activation.migrateLegacyClaudeRsync` script (idempotent, `entryBefore [ "checkLinkTargets" ]`) moves aside:
   - `~/.claude/CLAUDE.md` (if regular file, not symlink) → `~/.claude/CLAUDE.md.legacy-backup`
   - `~/.claude/settings.json` → `~/.claude/settings.json.legacy-backup`
   - `~/.claude/guides/conventional-commits.md` → `.legacy-backup`
   - `~/.claude/guides/standard-readme-spec.md` → `.legacy-backup`
   - **Nothing else in `~/.claude/` is touched** — not `commands/memory-dump.md`, not any state dir.
7. **`memory-dump.md` left alone.** Per-file management means the slice never touches `~/.claude/commands/memory-dump.md`. The repo's `claude/commands/` stub is empty (`.gitkeep` only), so no `~/.claude/commands/*` entries are created and the existing command survives.
8. **Retire `plugins/claude/`** entirely (the `claude` script, `CLAUDE_DOT_MD.md`, `README.md`). The `CLAUDE_DOT_MD.md` content moves to `nix/profiles/default/claude/CLAUDE_DOT_MD.md`.
9. **Delete `environments/default/home/.claude/`** (all four files migrate to Nix management). `environments/default/home/` becomes empty and effectively disappears (git doesn't track empty dirs).
10. **`plugins/homedir/homedir`: `DOTFILES_HOMEDIR_DEPS=('claude')` → `()`,** and remove the now-stale `# Needs to come after claude because claude has a "build" step` comment. The homedir plugin itself stays (it still rsyncs `environments/all/home/` content — `.gemrc`, `.gitignore`, `.screenrc`, `.wgetrc`, `.ssh/config`, `bin/git-*`, etc., which are future slices).
11. **No content changes to CLAUDE.md, settings.json, or the guides.** This slice is a migration, not a rewrite. The `CLAUDE.md` body, the four settings keys, and the two guide files are carried over byte-for-byte (settings.json's serialization may differ — key ordering, whitespace — but the semantic content is identical).
12. **No work-specific values.** All claude content is personal (default profile); no private-flake additions. The signing-key-style public values already in `default.nix` are unaffected.

## Architecture

```text
NEW FILES:
  nix/profiles/default/claude.nix                       # the module
  nix/profiles/default/claude/CLAUDE_DOT_MD.md          # → ~/.claude/CLAUDE.md
  nix/profiles/default/claude/guides/conventional-commits.md
  nix/profiles/default/claude/guides/standard-readme-spec.md
  nix/profiles/default/claude/agents/.gitkeep           # stub extension point
  nix/profiles/default/claude/skills/.gitkeep           # stub extension point
  nix/profiles/default/claude/commands/.gitkeep         # stub extension point
  nix/profiles/default/claude/rules/.gitkeep            # stub extension point

MODIFIED FILES:
  nix/profiles/default/default.nix                      # imports ./claude.nix
  plugins/homedir/homedir                               # DOTFILES_HOMEDIR_DEPS → (); drop stale comment
  nix/README.md                                         # +migration guide sub-block

DELETED:
  plugins/claude/                                       # whole dir (claude, CLAUDE_DOT_MD.md, README.md)
  environments/default/home/.claude/                    # whole tree (4 files)

UNTOUCHED:
  ~/.claude/commands/memory-dump.md                     # live user content, never managed
  ~/.claude/{projects,plugins,sessions,...}             # live Claude Code state
  plugins/homedir/homedir's rsync behavior              # still deploys environments/all/home/
  environments/all/home/                                # future slices
  Other slices' nix files                               # no cross-slice coupling
```

## `nix/profiles/default/claude.nix` (full content)

```nix
{ pkgs, lib, ... }:
let
  claudeSrc = ./claude;

  jsonFormat = pkgs.formats.json { };

  # Map every regular file under ./claude/<subdir>/ to a home.file entry
  # rooted at ~/.claude/<subdir>/<relpath>. Managing individual files (not
  # whole directories) keeps ~/.claude/<subdir>/ writable and never shadows
  # live Claude Code content (e.g. an interactively-created command). To add
  # a new agent/skill/command/rule, drop a file in the matching subdir and
  # run ./apply. `.gitkeep` placeholders are filtered out.
  mapClaudeTree = subdir:
    let
      srcDir = claudeSrc + "/${subdir}";
      prefix = toString srcDir + "/";
      files = lib.filesystem.listFilesRecursive srcDir;
      keep = builtins.filter (p: baseNameOf (toString p) != ".gitkeep") files;
      mkEntry = p:
        lib.nameValuePair
          ".claude/${subdir}/${lib.removePrefix prefix (toString p)}"
          { source = p; };
    in
    lib.listToAttrs (map mkEntry keep);
in
{
  home.file =
    {
      ".claude/CLAUDE.md".source = claudeSrc + "/CLAUDE_DOT_MD.md";

      ".claude/settings.json".source = jsonFormat.generate "claude-settings.json" {
        permissions.defaultMode = "plan";
        hooks = {
          Stop = [
            { hooks = [{ type = "command"; command = "afplay -v 0.40 /System/Library/Sounds/Morse.aiff"; }]; }
          ];
          Notification = [
            { hooks = [{ type = "command"; command = "afplay -v 0.35 /System/Library/Sounds/Ping.aiff"; }]; }
          ];
        };
        alwaysThinkingEnabled = true;
        sandbox = {
          autoAllowBashIfSandboxed = true;
          enabled = true;
          excludedCommands = [ "git" ];
        };
      };
    }
    // mapClaudeTree "guides"
    // mapClaudeTree "agents"
    // mapClaudeTree "skills"
    // mapClaudeTree "commands"
    // mapClaudeTree "rules";

  home.activation.migrateLegacyClaudeRsync =
    lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
      for f in \
        "$HOME/.claude/CLAUDE.md" \
        "$HOME/.claude/settings.json" \
        "$HOME/.claude/guides/conventional-commits.md" \
        "$HOME/.claude/guides/standard-readme-spec.md"; do
        if [ -f "$f" ] && [ ! -L "$f" ]; then
          /bin/mv "$f" "$f.legacy-backup"
        fi
      done
    '';
}
```

Notes:
- `pkgs.formats.json { }` is the idiomatic home-manager way to emit JSON config; `.generate` produces a store file with sorted, readable JSON.
- The `mapClaudeTree` helper is the established home-manager idiom for "deploy a tree of files as individual symlinks." When a subdir contains only `.gitkeep`, `keep` is empty and no entries are produced — so empty extension points create nothing.
- The activation loop covers all four legacy files in one block; the `[ -f ] && [ ! -L ]` guard makes it idempotent (after the first move, the source is a symlink — or absent — so it's skipped).

## `nix/profiles/default/default.nix` change

Add `./claude.nix` to the imports list:

```nix
  imports = [
    ./cli-tools.nix
    ./claude.nix
  ];
```

(Alphabetical: `claude.nix` before `cli-tools.nix`. Verify exact ordering during implementation; both are fine functionally.)

## `plugins/homedir/homedir` change

After slice 12 (nix-vim), the current state is:

```bash
# Needs to come after claude because claude has a "build" step
export DOTFILES_HOMEDIR_DEPS=('claude')
```

After this slice:

```bash
export DOTFILES_HOMEDIR_DEPS=()
```

The `# Needs to come after claude…` comment is removed (the claude plugin no longer exists). The homedir plugin keeps functioning — it still rsyncs `environments/all/home/`.

## Deletion list

- `plugins/claude/claude`
- `plugins/claude/CLAUDE_DOT_MD.md` (content moves to `nix/profiles/default/claude/CLAUDE_DOT_MD.md`)
- `plugins/claude/README.md`
- `plugins/claude/` (the directory)
- `environments/default/home/.claude/CLAUDE.md`
- `environments/default/home/.claude/settings.json`
- `environments/default/home/.claude/guides/conventional-commits.md`
- `environments/default/home/.claude/guides/standard-readme-spec.md`
- `environments/default/home/.claude/` (the tree)
- `environments/default/home/` becomes empty (git stops tracking it once the last file is gone)

## Migration guide block in `nix/README.md`

Append after the "For the nix-vim slice" sub-block, paragraph-heading style:

```markdown
For the nix-claude slice (`claude` plugin retired; `~/.claude/` config now home-manager managed):

This slice migrates the bash `claude` plugin (which "built" `~/.claude/CLAUDE.md`
from a renamed source then rsynced it) into home-manager. The personal Claude
Code config — `CLAUDE.md`, `settings.json`, and `guides/` — is now managed
declaratively in the `default` profile. `settings.json` is generated from a Nix
attrset (`pkgs.formats.json`); `CLAUDE.md` and the guides are sourced from
`nix/profiles/default/claude/`.

**Individual files, not directories.** `~/.claude/` holds a lot of live Claude
Code state (projects, plugins, sessions, history, auto-memory). The slice
manages only the specific files it owns and never symlinks a whole directory,
so your state and any ad-hoc content (e.g. a hand-written `~/.claude/commands/`
entry) are left untouched.

**Adding agents, skills, commands, or rules.** Drop a file under the matching
directory in the repo and run `./apply`:

- `nix/profiles/default/claude/agents/<name>.md` → `~/.claude/agents/<name>.md`
- `nix/profiles/default/claude/skills/<name>/SKILL.md` → `~/.claude/skills/<name>/SKILL.md`
- `nix/profiles/default/claude/commands/<name>.md` → `~/.claude/commands/<name>.md`
- `nix/profiles/default/claude/rules/<name>.md` → `~/.claude/rules/<name>.md`

The Nix module auto-discovers every file under those directories. The target
dirs stay writable, so Claude-Code-authored files alongside your managed ones
coexist.

**One-time apply notes:**

- On first apply, the activation moves your existing rsynced `~/.claude/CLAUDE.md`,
  `~/.claude/settings.json`, and `~/.claude/guides/*.md` to `*.legacy-backup`
  siblings, then home-manager links the Nix-managed versions. Delete the
  `.legacy-backup` files once you've confirmed everything's in order.

- `settings.json` is now generated from `nix/profiles/default/claude.nix`. To
  change a setting, edit the Nix attrset and run `./apply` — editing
  `~/.claude/settings.json` directly has no lasting effect (it's a symlink into
  the Nix store).

**Private flake update (only if you have one):**

If your private flake adds `home.file.".claude/..."` entries or overrides
settings keys, Nix module merging handles additive entries; conflicting keys
need `lib.mkForce`.
```

## Open questions resolved during plan / implementation

1. **`lib.filesystem.listFilesRecursive` relative-path computation.** The `toString srcDir + "/"` prefix-strip is the standard idiom but must be verified at the nixpkgs pin. The implementation's `nix eval` step confirms `mapClaudeTree "guides"` produces exactly `.claude/guides/conventional-commits.md` and `.claude/guides/standard-readme-spec.md` (no store-path leakage in the attr names). If the prefix-strip misbehaves, fall back to `lib.filesystem.listFilesRecursive` + `lib.path.removePrefix` or an explicit `builtins.readDir` walk.
2. **Empty-subdir handling.** Confirm that `mapClaudeTree "agents"` (where `agents/` has only `.gitkeep`) produces an empty attrset, not an error. If `listFilesRecursive` on a `.gitkeep`-only dir behaves unexpectedly, the fallback is to guard with `lib.optionalAttrs (builtins.pathExists srcDir)`.
3. **`pkgs.formats.json` availability.** Standard in nixpkgs for years; verify at the pin. Fallback: `builtins.toJSON` wrapped in `pkgs.writeText`.
4. **`.gitkeep` and Nix store.** Confirm that committing `.gitkeep` files keeps the four extension-point dirs present for Nix to reference. (Git doesn't track empty dirs; `.gitkeep` is the conventional placeholder.)

## Testing

Per project convention (no automated tests), verification is manual. The plan will include:

1. **Pre-apply snapshot:** `ls -la ~/.claude/{CLAUDE.md,settings.json}`, `ls ~/.claude/guides/`, `ls ~/.claude/commands/` (confirm `memory-dump.md` present), `cat ~/.claude/settings.json` (capture current content for semantic comparison).
2. **After `./apply`:**
   - `~/.claude/CLAUDE.md`, `~/.claude/settings.json`, `~/.claude/guides/*.md` are symlinks into the Nix store.
   - `~/.claude/{CLAUDE.md,settings.json}.legacy-backup` and `~/.claude/guides/*.legacy-backup` exist.
   - `~/.claude/commands/memory-dump.md` is **unchanged** (still a regular file, perms 700, untouched).
   - `~/.claude/agents`, `~/.claude/skills`, `~/.claude/rules` are NOT created (empty stubs produce no entries) — or if created, only because home-manager made the parent for some managed file (shouldn't happen with empty stubs).
   - `diff <(jq -S . ~/.claude/settings.json.legacy-backup) <(jq -S . ~/.claude/settings.json)` shows no semantic difference (only formatting/key-order).
   - `diff ~/.claude/CLAUDE.md.legacy-backup ~/.claude/CLAUDE.md` shows no difference (byte-identical content).
3. **Extension-point smoke test:** Create `nix/profiles/default/claude/rules/test-rule.md` with a line of content, `./apply`, confirm `~/.claude/rules/test-rule.md` is a symlink with that content, then remove it and `./apply` again (confirm it disappears cleanly). Document this in the plan as an optional validation; the implementer may skip the round-trip if apply is gated on interactive sudo.
4. **Framework cleanup:** `grep -rn claude plugins/ environments/` returns nothing (except incidental matches); `plugins/claude/` and `environments/default/home/.claude/` are gone; `DOTFILES_HOMEDIR_DEPS=()`.
5. **Idempotence:** Second `./apply` no-ops the move-aside (guards skip), settings/CLAUDE.md links unchanged, no duplicate `.legacy-backup` files.

## Risk and rollback

**Risk profile:** Low-medium. The main risk is the `mapClaudeTree` helper misbehaving (wrong attr names, store-path leakage) — caught at `nix eval` time before any apply. The move-aside is conservative (regular-file + not-symlink guards), and the blast radius excludes all live `~/.claude/` state by construction (we touch only four named files).

**Rollback:**
1. `git revert` the slice's commits and re-`./apply` — home-manager unlinks the managed files; the `.legacy-backup` copies remain for manual restore.
2. `mv ~/.claude/CLAUDE.md.legacy-backup ~/.claude/CLAUDE.md` etc. to restore the rsynced versions.
3. `plugins/claude/` is recoverable from `git show`.

No live Claude Code state can be lost — the slice never touches projects/, plugins/, sessions/, history, auto-memory, or `commands/memory-dump.md`.

## Out of scope

- **Splitting CLAUDE.md into `~/.claude/rules/*.md`.** The current CLAUDE.md has several topic sections (Conversational Style, Git, GitHub, Documentation, Node.js, Task Execution) that *could* become modular rules files. That's a content-reorganization decision for the user, separate from this migration. This slice carries CLAUDE.md over as-is and merely provides the `rules/` extension point.
- **Agent-profile Claude config.** `agent` profiles get no Claude config in this slice (settings.json is macOS-specific). Future slice if wanted.
- **`vscode` plugin retirement.** Separate plugin; future slice.
- **`homedir` plugin retirement.** Still needed for `environments/all/home/` content; retires only once that content is migrated (future slices).
- **Importing `~/.claude/commands/memory-dump.md` into the repo.** Explicitly left as ad-hoc local content per user decision.

## Cross-references

- Master design: `docs/superpowers/specs/2026-05-22-nix-migration-design.md`
- Prior slice (nix-vim): `docs/superpowers/specs/2026-05-27-nix-vim-design.md`
- Status doc (local, uncommitted): `docs/superpowers/nix-migration-status.md`
- Claude Code rules docs: https://code.claude.com/docs/en/memory#organize-rules-with-claude/rules/
- Migration guide: `nix/README.md` (gains a "For the nix-claude slice" sub-block)
