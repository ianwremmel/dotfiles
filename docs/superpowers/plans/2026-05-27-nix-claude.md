# Nix Claude Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Retire the `claude` bash plugin and its rsynced `environments/default/home/.claude/` tree. Manage the user's Claude Code config declaratively via home-manager in the `default` profile: `~/.claude/CLAUDE.md`, `~/.claude/settings.json` (generated from a Nix attrset), `~/.claude/guides/*.md`, plus an auto-discovering helper for `~/.claude/{agents,skills,commands,rules}/`. Manage **individual files only** — never whole directories — so live Claude Code state and ad-hoc content (`~/.claude/commands/memory-dump.md`) are never shadowed.

**Architecture:** Single atomic `feat` commit creates `nix/profiles/default/claude.nix` + a `nix/profiles/default/claude/` content subdir (CLAUDE_DOT_MD.md, two guides, four `.gitkeep`-stubbed extension dirs), modifies `nix/profiles/default/default.nix` (imports), modifies `plugins/homedir/homedir` (`DOTFILES_HOMEDIR_DEPS` → `()`), and deletes `plugins/claude/` + `environments/default/home/.claude/`. A second `docs` commit updates `nix/README.md`. A third task is verification-only.

**Tech Stack:** Nix flakes, home-manager (`release-26.05`), `home.file`, `pkgs.formats.json`, `lib.filesystem.listFilesRecursive`, `lib.hm.dag` activation ordering, Bash 5 framework (`plugins/homedir/homedir` only).

---

## Notes for the executor

- **Reference spec:** `docs/superpowers/specs/2026-05-27-nix-claude-design.md`. Read it first; the decisions and the full `claude.nix` content are the authoritative source of truth.
- **No automated test framework.** "Tests" are verification commands with expected output (Task 3).
- **Branch:** `nix-claude`. Stacks on `nix-vim` (PR #72) → `nix-firstrun` (#71) → … → master. **Do NOT merge anything.**
- **Sandbox disable required for:** `nix`, `git commit` (gpg signing), anything writing under `~/.claude/`. Use Bash with `dangerouslyDisableSandbox: true`.
- **`nix eval` invocation:** use `nix eval "path:./nix#…"` (repo root has no flake.nix; it's at `nix/flake.nix`). May need sandbox-disable for nix's fetcher-lock dir.
- **`./apply` requires interactive sudo (TTY)** which the Bash tool lacks. When you reach the apply step, run flake-eval first, then report NEEDS_CONTEXT and request the user run `./apply` interactively. The controller relays the result.
- **Run commands from repo root** (`/Users/ian/projects/dotfiles`).
- **Conventional commits**, NO Claude attribution trailers.
- **No work-specific values.**

### Pre-existing local state (assume)

- `nix/host.nix` = `{ username = "ian"; profile = "default"; }`, untracked.
- `~/.claude/CLAUDE.md`, `~/.claude/settings.json`, `~/.claude/guides/{conventional-commits,standard-readme-spec}.md` exist as regular files (rsynced).
- `~/.claude/commands/memory-dump.md` exists (user-authored, perms 700, NOT in repo). **Must remain untouched.**
- `~/.claude/` contains extensive live state (projects/, plugins/, sessions/, history.jsonl, etc.). **Must remain untouched.**
- `~/.claude/agents/`, `~/.claude/skills/`, `~/.claude/rules/` are absent.
- `plugins/homedir/homedir` currently has `DOTFILES_HOMEDIR_DEPS=('claude')` (slice 12 already dropped `'vim'`).
- `darwin-rebuild` installed; login shell `~/.nix-profile/bin/zsh`.

### Open-question fallback handling (from spec)

1. **`mapClaudeTree` relative-path computation.** After writing `claude.nix`, the Step "evaluate the helper" below dumps the produced `home.file` attr names. They MUST be exactly `.claude/guides/conventional-commits.md` and `.claude/guides/standard-readme-spec.md` (no `/nix/store/...` leakage). If the attr names contain store paths, the `toString srcDir + "/"` prefix-strip failed — switch to `lib.path.removePrefix` or an explicit `builtins.readDir` recursion. Do not proceed to apply until the attr names are correct.
2. **Empty-subdir handling.** `mapClaudeTree "agents"` (only `.gitkeep` present) must yield `{}`, not an error. If `listFilesRecursive` errors on a `.gitkeep`-only dir, wrap with `lib.optionalAttrs (builtins.pathExists srcDir)` or pre-check.
3. **`pkgs.formats.json` availability.** Standard; verify at eval. Fallback: `pkgs.writeText "claude-settings.json" (builtins.toJSON {...})`.

---

## Task 1: Atomic claude migration

Every change in one commit so the repo never sits half-migrated.

**Files:**

- Create: `nix/profiles/default/claude.nix`
- Create: `nix/profiles/default/claude/CLAUDE_DOT_MD.md` (moved from `plugins/claude/CLAUDE_DOT_MD.md`)
- Create: `nix/profiles/default/claude/guides/conventional-commits.md`
- Create: `nix/profiles/default/claude/guides/standard-readme-spec.md`
- Create: `nix/profiles/default/claude/agents/.gitkeep`
- Create: `nix/profiles/default/claude/skills/.gitkeep`
- Create: `nix/profiles/default/claude/commands/.gitkeep`
- Create: `nix/profiles/default/claude/rules/.gitkeep`
- Modify: `nix/profiles/default/default.nix` (import `./claude.nix`)
- Modify: `plugins/homedir/homedir` (`DOTFILES_HOMEDIR_DEPS` → `()`, drop stale comment)
- Delete: `plugins/claude/` (whole dir)
- Delete: `environments/default/home/.claude/` (whole tree)

### Step-by-step

- [ ] **Step 1: Capture pre-flight state**

```bash
{
  echo "=== ~/.claude managed files (current) ==="
  ls -la "$HOME/.claude/CLAUDE.md" "$HOME/.claude/settings.json" 2>&1
  echo ""
  echo "=== ~/.claude/guides/ ==="
  ls -la "$HOME/.claude/guides/" 2>&1
  echo ""
  echo "=== ~/.claude/commands/ (memory-dump.md MUST survive) ==="
  ls -la "$HOME/.claude/commands/" 2>&1
  echo ""
  echo "=== extension dirs (expect agents/skills/rules absent) ==="
  for d in agents skills commands rules; do echo -n "$d: "; ls -d "$HOME/.claude/$d" 2>&1; done
  echo ""
  echo "=== settings.json content (semantic baseline) ==="
  cat "$HOME/.claude/settings.json" 2>&1
  echo ""
  echo "=== repo state ==="
  ls plugins/claude/ environments/default/home/.claude/ 2>&1
  grep -n DOTFILES_HOMEDIR_DEPS plugins/homedir/homedir
} > "$TMPDIR/claude-preflight.txt" 2>&1
cat "$TMPDIR/claude-preflight.txt"
```

Save `$TMPDIR/claude-preflight.txt`. Note the `memory-dump.md` entry and the settings.json content for later comparison.

- [ ] **Step 2: Confirm starting file state**

```bash
ls plugins/claude/claude plugins/claude/CLAUDE_DOT_MD.md plugins/claude/README.md
ls environments/default/home/.claude/CLAUDE.md environments/default/home/.claude/settings.json
ls environments/default/home/.claude/guides/
grep -n DOTFILES_HOMEDIR_DEPS plugins/homedir/homedir
cat nix/profiles/default/default.nix
```

Expected: all source paths exist; `DOTFILES_HOMEDIR_DEPS=('claude')`; `default.nix` imports `./cli-tools.nix`.

- [ ] **Step 3: Move the CLAUDE.md source and guides into the repo's nix tree**

```bash
mkdir -p nix/profiles/default/claude/guides
mkdir -p nix/profiles/default/claude/agents nix/profiles/default/claude/skills nix/profiles/default/claude/commands nix/profiles/default/claude/rules

git mv plugins/claude/CLAUDE_DOT_MD.md nix/profiles/default/claude/CLAUDE_DOT_MD.md
git mv environments/default/home/.claude/guides/conventional-commits.md nix/profiles/default/claude/guides/conventional-commits.md
git mv environments/default/home/.claude/guides/standard-readme-spec.md nix/profiles/default/claude/guides/standard-readme-spec.md

# Stub the four extension-point dirs
touch nix/profiles/default/claude/agents/.gitkeep
touch nix/profiles/default/claude/skills/.gitkeep
touch nix/profiles/default/claude/commands/.gitkeep
touch nix/profiles/default/claude/rules/.gitkeep
git add nix/profiles/default/claude/agents/.gitkeep nix/profiles/default/claude/skills/.gitkeep nix/profiles/default/claude/commands/.gitkeep nix/profiles/default/claude/rules/.gitkeep
```

Note: `git mv` preserves history for the moved files. The `CLAUDE.md` and `settings.json` under `environments/default/home/.claude/` are NOT moved — `CLAUDE.md` is regenerated from `CLAUDE_DOT_MD.md` (already moved) and `settings.json` becomes a Nix attrset (Step 4). They'll be deleted in Step 6.

- [ ] **Step 4: Create `nix/profiles/default/claude.nix`**

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

- [ ] **Step 5: Import `./claude.nix` in `nix/profiles/default/default.nix`**

Current imports:

```nix
  imports = [
    ./cli-tools.nix
  ];
```

Change to:

```nix
  imports = [
    ./claude.nix
    ./cli-tools.nix
  ];
```

Use Edit to add the single line. Do NOT touch the `programs.git.settings` block below it.

- [ ] **Step 6: Delete the claude plugin and rsync sources**

```bash
git rm -r plugins/claude/
git rm -r environments/default/home/.claude/
```

(`plugins/claude/CLAUDE_DOT_MD.md` was already `git mv`'d in Step 3, so `plugins/claude/` now contains only `claude` and `README.md`. The guides under `environments/default/home/.claude/guides/` were also `git mv`'d; `git rm -r` removes the remaining `CLAUDE.md` and `settings.json` plus the now-empty tree.)

Verify:

```bash
git status
ls plugins/claude/ environments/default/home/.claude/ environments/default/home/ 2>&1
```

Expected: `plugins/claude/` and `environments/default/home/.claude/` gone; `environments/default/home/` empty or gone.

- [ ] **Step 7: Update `plugins/homedir/homedir`**

Current:

```bash
# Needs to come after claude because claude has a "build" step
export DOTFILES_HOMEDIR_DEPS=('claude')
```

Change to (remove the comment AND empty the array):

```bash
export DOTFILES_HOMEDIR_DEPS=()
```

Verify: `grep -n DOTFILES_HOMEDIR_DEPS plugins/homedir/homedir` shows `export DOTFILES_HOMEDIR_DEPS=()`.

- [ ] **Step 8: Evaluate the helper output (open question #1 + #2)**

```bash
SYSTEM="$(nix eval --raw --impure --expr builtins.currentSystem)"

# Dump the home.file attr names this module produces, to confirm mapClaudeTree
# yields clean relative paths (not store paths) and empty stubs yield nothing.
nix eval --json "path:./nix#homeConfigurations.default@${SYSTEM}.config.home.file" \
  --apply 'builtins.attrNames' 2>&1 | tr ',' '\n' | grep -i claude
```

Expected output includes exactly:
```
.claude/CLAUDE.md
.claude/settings.json
.claude/guides/conventional-commits.md
.claude/guides/standard-readme-spec.md
```
and NO `.claude/agents/...`, `.claude/skills/...`, `.claude/commands/...`, `.claude/rules/...` entries (the stubs are empty), and NO entries containing `/nix/store/`.

If store paths leak into the attr names → open question #1 fallback (fix the prefix-strip, re-eval). If an empty-stub error occurs → open question #2 fallback. Do NOT proceed until the attr names are exactly the four above.

- [ ] **Step 9: Full flake eval**

```bash
SYSTEM="$(nix eval --raw --impure --expr builtins.currentSystem)"
nix flake check --no-build path:./nix 2>&1 | tail -20
nix eval "path:./nix#homeConfigurations.default@${SYSTEM}.config.home.activationPackage.drvPath" 2>&1 | tail -3
```

Expected: both succeed. If `pkgs.formats.json` is unavailable → open question #3 fallback.

- [ ] **Step 10: Run `./apply`**

This needs interactive sudo. Report NEEDS_CONTEXT and ask the user to run `./apply` interactively. Resume from Step 11 once they confirm.

- [ ] **Step 11: Verify managed files are symlinks + legacy-backups exist**

```bash
echo "=== managed files (should be symlinks into /nix/store) ==="
ls -la "$HOME/.claude/CLAUDE.md" "$HOME/.claude/settings.json"
ls -la "$HOME/.claude/guides/conventional-commits.md" "$HOME/.claude/guides/standard-readme-spec.md"
echo ""
echo "=== legacy backups (should exist) ==="
ls -la "$HOME/.claude/CLAUDE.md.legacy-backup" "$HOME/.claude/settings.json.legacy-backup"
ls -la "$HOME/.claude/guides/conventional-commits.md.legacy-backup" "$HOME/.claude/guides/standard-readme-spec.md.legacy-backup"
```

Expected: the four managed files are symlinks into `/nix/store/...`; the four `.legacy-backup` siblings are regular files.

- [ ] **Step 12: Verify live state untouched (CRITICAL)**

```bash
echo "=== memory-dump.md MUST be unchanged ==="
ls -la "$HOME/.claude/commands/memory-dump.md"
echo ""
echo "=== it must NOT be a symlink ==="
[ -L "$HOME/.claude/commands/memory-dump.md" ] && echo "FAIL: it's a symlink!" || echo "OK: still a regular file"
echo ""
echo "=== empty stubs should NOT have created managed entries ==="
for d in agents skills rules; do
  if [ -L "$HOME/.claude/$d" ]; then echo "FAIL: ~/.claude/$d is a symlink"; else echo "OK: ~/.claude/$d not a managed symlink"; fi
done
echo ""
echo "=== live state dirs still present ==="
ls -d "$HOME/.claude/projects" "$HOME/.claude/plugins" "$HOME/.claude/sessions" 2>&1
```

Expected: `memory-dump.md` is a regular file (perms 700), NOT a symlink. No managed symlinks for the empty stub dirs. Live state dirs present. If `memory-dump.md` became a symlink or disappeared — STOP, report BLOCKED (data shadow/loss).

- [ ] **Step 13: Verify settings.json semantic equivalence**

```bash
if command -v jq >/dev/null; then
  diff <(jq -S . "$HOME/.claude/settings.json.legacy-backup") <(jq -S . "$HOME/.claude/settings.json") \
    && echo "OK: settings.json semantically identical" \
    || echo "DIFF: review the keys above"
else
  echo "jq absent; manual compare:"
  echo "--- legacy ---"; cat "$HOME/.claude/settings.json.legacy-backup"
  echo "--- new ---"; cat "$HOME/.claude/settings.json"
fi
echo ""
echo "=== CLAUDE.md byte-identical? ==="
diff "$HOME/.claude/CLAUDE.md.legacy-backup" "$HOME/.claude/CLAUDE.md" \
  && echo "OK: CLAUDE.md identical" || echo "DIFF in CLAUDE.md (investigate)"
```

Expected: settings.json has no semantic diff (only formatting/key-order from the legacy hand-written JSON); CLAUDE.md is byte-identical.

- [ ] **Step 14: Extension-point round-trip smoke test (optional — requires a second apply)**

If a second interactive `./apply` is feasible, validate the auto-discovery:

```bash
echo "# test rule" > nix/profiles/default/claude/rules/zzz-smoke-test.md
# (user runs ./apply)
# then:
ls -la "$HOME/.claude/rules/zzz-smoke-test.md"   # expect symlink with the content
rm nix/profiles/default/claude/rules/zzz-smoke-test.md
# (user runs ./apply again)
ls -la "$HOME/.claude/rules/zzz-smoke-test.md" 2>&1   # expect: gone
```

If a second apply isn't feasible (no TTY), SKIP and note that auto-discovery is verified structurally by Step 8's attr-name dump.

- [ ] **Step 15: Verify framework cleanup**

```bash
grep -rn "claude" plugins/ 2>/dev/null | grep -v "^Binary" | head -10
echo "---"
grep -n DOTFILES_HOMEDIR_DEPS plugins/homedir/homedir
echo "---"
ls plugins/claude/ environments/default/home/.claude/ 2>&1
```

Expected: no `plugins/claude/` references; `DOTFILES_HOMEDIR_DEPS=()`; both paths gone. (Incidental "claude" matches in other plugins, if any, are reviewed individually — there shouldn't be any.)

- [ ] **Step 16: Stage and commit**

```bash
git status
git diff --stat
git add nix/profiles/default/claude.nix nix/profiles/default/claude/ nix/profiles/default/default.nix plugins/homedir/homedir
git add -u  # picks up git mv + deletions
git status   # final check
```

Commit (sandbox disable for gpg). Exact message:

```
feat(nix): migrate claude config to home-manager; retire bash claude plugin

Move ~/.claude/{CLAUDE.md,settings.json,guides} from the bash claude plugin +
rsync framework into home-manager's `default` profile. settings.json is now
generated from a Nix attrset (pkgs.formats.json); CLAUDE.md and the guides are
sourced from nix/profiles/default/claude/. A mapClaudeTree helper auto-discovers
files under claude/{agents,skills,commands,rules}/ and installs them as
individual ~/.claude/<dir>/ symlinks — adding a new one is a drop-a-file-and-apply
operation.

Manages individual files only (never whole directories), so live Claude Code
state (projects, plugins, sessions, history) and ad-hoc content like
~/.claude/commands/memory-dump.md are never shadowed. On first apply, the legacy
rsynced CLAUDE.md/settings.json/guides are moved aside to *.legacy-backup.

Retires plugins/claude/ and empties plugins/homedir/homedir's
DOTFILES_HOMEDIR_DEPS array.
```

Use HEREDOC. No Claude attribution.

- [ ] **Step 17: Verify commit**

```bash
git log --oneline -1
git show --stat HEAD
```

Expected: one `feat(nix): migrate claude config…` commit. Stat shows the new `claude.nix` + content files (some as renames from `git mv`), modified `default.nix`/`homedir`, deleted `plugins/claude/{claude,README.md}` and `environments/default/home/.claude/{CLAUDE.md,settings.json}`.

- [ ] **Step 18: Compare against pre-flight**

```bash
diff "$TMPDIR/claude-preflight.txt" <(
  echo "=== ~/.claude managed files (current) ==="
  ls -la "$HOME/.claude/CLAUDE.md" "$HOME/.claude/settings.json" 2>&1
  echo ""
  echo "=== ~/.claude/commands/ (memory-dump.md MUST survive) ==="
  ls -la "$HOME/.claude/commands/" 2>&1
) 2>&1 | head -40
```

Expected differences: `CLAUDE.md`/`settings.json` flipped from regular files to symlinks; `commands/memory-dump.md` unchanged. Anything else — investigate.

---

## Task 2: Update `nix/README.md`

Separate `docs` commit.

**Files:** Modify `nix/README.md`.

### Step-by-step

- [ ] **Step 1: Locate insertion point**

```bash
grep -nE "^For the nix-vim slice|^For the " nix/README.md | tail -3
```

Find the "For the nix-vim slice" sub-block; the new claude block goes after it (before the closing "The same shape applies to future slices" paragraph if present).

- [ ] **Step 2: Append the nix-claude sub-block**

Insert (paragraph-heading style, matching prior slices):

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

- [ ] **Step 3: Verify**

```bash
grep -A 2 "For the nix-claude slice" nix/README.md | head -5
```

- [ ] **Step 4: Commit**

```bash
git add nix/README.md
git commit -m "docs(nix): document nix-claude slice migration"
```

Sandbox disable for gpg.

- [ ] **Step 5: Verify**

```bash
git log --oneline -3
```

Expected: `docs(nix): document nix-claude slice migration`, then the feat commit, then `7b3698d docs: add nix-claude slice design spec`.

---

## Task 3: Cross-slice verification

Verification only.

### Step-by-step

- [ ] **Step 1: Clean reapply**

```bash
exec zsh -l -c 'cd /Users/ian/projects/dotfiles && ./apply 2>&1 | tee /tmp/claude-slice-apply.log'
```

(Requires interactive sudo; if not feasible in-agent, the user already ran it in Task 1 — note that and skip.) Inspect log for warnings.

- [ ] **Step 2: Confirm legacy bash codepath gone**

```bash
DOTFILES_DEBUG=1 ./apply 2>&1 | grep -i "claude config installed" | head -3
grep -rn "dotfiles_claude\|plugins/claude" framework/ plugins/ environments/ 2>/dev/null
```

Expected: no "Claude config installed" log line (that was the bash plugin's); no references to the deleted plugin.

- [ ] **Step 3: Re-verify the critical invariants**

```bash
# memory-dump.md survives
[ -f "$HOME/.claude/commands/memory-dump.md" ] && [ ! -L "$HOME/.claude/commands/memory-dump.md" ] && echo "OK: memory-dump.md intact" || echo "FAIL"
# managed files are symlinks
[ -L "$HOME/.claude/CLAUDE.md" ] && echo "OK: CLAUDE.md managed" || echo "FAIL"
[ -L "$HOME/.claude/settings.json" ] && echo "OK: settings.json managed" || echo "FAIL"
# settings semantically identical
command -v jq >/dev/null && diff <(jq -S . "$HOME/.claude/settings.json.legacy-backup") <(jq -S . "$HOME/.claude/settings.json") && echo "OK: settings identical"
```

- [ ] **Step 4: Confirm commit shape**

```bash
git log --oneline nix-vim..HEAD
```

Expected: docs(spec) + feat + docs(readme) = three commits above `nix-vim`.

- [ ] **Step 5: Update status doc (LOCAL ONLY — do NOT commit)**

Update `docs/superpowers/nix-migration-status.md`:
- Slice 13 nix-claude added to shipped table.
- Bash plugins retired count 10 → 11 (`claude`).
- "Plugin layer (still bash)" list: remove `claude`; note `homedir` now has empty deps but still rsyncs `environments/all/home/`.

- [ ] **Step 6: Open the PR (gated on explicit user approval)**

DO NOT push/open without explicit user go-ahead (memory `ask-before-merging`). When approved:

```bash
git push -u origin nix-claude
gh pr create --base nix-vim --title "feat(nix): migrate claude config to home-manager" --body "$(cat <<'EOF'
## Summary

- Migrates the bash `claude` plugin and rsynced `environments/default/home/.claude/` into home-manager's `default` profile.
- `~/.claude/CLAUDE.md` and `~/.claude/guides/*.md` sourced from `nix/profiles/default/claude/`; `~/.claude/settings.json` generated from a Nix attrset via `pkgs.formats.json`.
- A `mapClaudeTree` helper auto-discovers files under `claude/{agents,skills,commands,rules}/` and installs them as individual `~/.claude/<dir>/` symlinks — adding a new one is drop-a-file-and-apply.
- Manages individual files only (never whole dirs), so live Claude Code state and ad-hoc content (`~/.claude/commands/memory-dump.md`) are never shadowed.
- Move-aside-not-delete: legacy rsynced files go to `*.legacy-backup` on first apply.
- Retires `plugins/claude/`; empties `plugins/homedir/homedir`'s `DOTFILES_HOMEDIR_DEPS`.

## Test plan

- [ ] `./apply` succeeds.
- [ ] `~/.claude/{CLAUDE.md,settings.json,guides/*}` are symlinks into the Nix store.
- [ ] `*.legacy-backup` siblings exist after first apply.
- [ ] `~/.claude/commands/memory-dump.md` is unchanged (regular file, not a symlink).
- [ ] `jq -S` diff shows settings.json semantically identical to the legacy file.
- [ ] CLAUDE.md byte-identical to legacy.
- [ ] Dropping a file in `claude/rules/` then `./apply` creates `~/.claude/rules/<file>` (and removing it cleans up).
- [ ] Second `./apply` is idempotent.

## Stacks on

#72 (nix-vim)
EOF
)"
```

---

## Self-review against the spec

Spec coverage:

- Decision 1 (default profile): claude.nix lives in `nix/profiles/default/`, imported by default profile's `default.nix` (Task 1 Steps 4-5).
- Decision 2 (module file): Task 1 Step 4.
- Decision 3 (content subdir + CLAUDE_DOT_MD.md + guides + stubs): Task 1 Step 3.
- Decision 4 (per-file auto-discovery helper): `mapClaudeTree` in Task 1 Step 4; verified by Step 8.
- Decision 5 (settings.json via pkgs.formats.json): Task 1 Step 4's `jsonFormat.generate`.
- Decision 6 (move-aside four files): Task 1 Step 4's `migrateLegacyClaudeRsync`; verified Steps 11/13.
- Decision 7 (memory-dump.md untouched): verified Step 12 (CRITICAL gate).
- Decision 8 (retire plugins/claude/): Task 1 Step 6.
- Decision 9 (delete environments/default/home/.claude/): Task 1 Step 6.
- Decision 10 (DOTFILES_HOMEDIR_DEPS → ()): Task 1 Step 7.
- Decision 11 (no content changes): Step 13 verifies CLAUDE.md byte-identical, settings semantically identical.
- Decision 12 (no work-specific values): no private-flake changes.

Placeholder scan: every step has exact commands/code/criteria. No TBD/TODO/"appropriate handling"/"similar to Task N".

Type consistency: `mapClaudeTree`, `migrateLegacyClaudeRsync`, `claudeSrc`, `jsonFormat` referenced consistently. `nix/profiles/default/claude.nix` and `nix/profiles/default/claude/` consistent.

---

## Cross-references

- Design spec: `docs/superpowers/specs/2026-05-27-nix-claude-design.md`
- Status doc (local, uncommitted): `docs/superpowers/nix-migration-status.md`
- Prior slice plan (style/stack ref): `docs/superpowers/plans/2026-05-27-nix-vim.md`
- Master design: `docs/superpowers/specs/2026-05-22-nix-migration-design.md`
