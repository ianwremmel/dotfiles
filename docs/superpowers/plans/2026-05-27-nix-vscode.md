# Nix VSCode Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (or just execute inline — this slice is a single-task pure deletion). Steps use checkbox (`- [ ]`) syntax.

**Goal:** Delete the `vscode` bash plugin (a redundant `code`-CLI symlinker). The `visual-studio-code` cask already provides `code`/`code-tunnel` via binary artifacts. Add a README migration note. No nix code, no framework changes.

**Architecture:** One `feat` commit deletes `plugins/vscode/`. One `docs` commit adds the `nix/README.md` migration sub-block. (Can be a single commit if preferred, but keeping the docs separate matches prior slices.)

**Tech Stack:** Bash framework (deletion only), Homebrew cask (existing).

---

## Notes for the executor

- **Reference spec:** `docs/superpowers/specs/2026-05-27-nix-vscode-design.md`.
- **Branch:** `nix-vscode`. Stacks on `nix-claude` (PR #73). **Do NOT merge.**
- **Sandbox disable** for `git commit` (gpg signing) and `./apply` (sudo). `./apply` needs interactive TTY — if running in-agent, ask the user to run it.
- **Conventional commits**, no Claude attribution.
- **No push** without explicit user approval.

---

## Task 1: Delete the vscode plugin + document

**Files:**
- Delete: `plugins/vscode/` (whole dir)
- Modify: `nix/README.md` (+migration sub-block)

### Step-by-step

- [ ] **Step 1: Pre-flight**

```bash
command -v code; ls -la "$(command -v code)" 2>&1
ls plugins/vscode/
grep -rn "vscode\|VSCODE" framework/ plugins/ environments/ apply 2>/dev/null | grep -v "plugins/vscode/vscode" || echo "(no external refs)"
```

Expected: `code` → `/opt/homebrew/bin/code` → the app helper; `plugins/vscode/vscode` exists; no external references.

- [ ] **Step 2: Delete the plugin**

```bash
git rm -r plugins/vscode/
```

Verify: `ls plugins/vscode/ 2>&1` → "No such file or directory"; `git status` shows the deletion staged.

- [ ] **Step 3: Add the README migration sub-block**

Find the "For the nix-claude slice" block (`grep -n "For the nix-claude slice" nix/README.md`); insert after it (before the closing "The same shape applies to future slices" paragraph if present). Insert verbatim:

```markdown
For the nix-vscode slice (`vscode` plugin retired; `code` CLI now provided by the cask):

The bash `vscode` plugin only symlinked VS Code's `code` CLI helper onto PATH.
That's now redundant: the `visual-studio-code` cask (declared in nix-darwin since
the nix-darwin slice) lists `code` and `code-tunnel` as binary artifacts, so
Homebrew links them into `/opt/homebrew/bin/` (on PATH) when it installs the
cask. The plugin is deleted with no replacement — Homebrew owns the symlink.

**One-time apply notes:**

- No action needed. If `code` ever goes missing after a VS Code reinstall, run
  `brew reinstall --cask visual-studio-code` to relink the binary artifacts, or
  use VS Code's "Shell Command: Install 'code' command in PATH" from the command
  palette.
```

Verify: `grep -nE "^For the nix-vscode slice" nix/README.md` → one paragraph-form match, no `###`.

- [ ] **Step 4: Commit the deletion (feat)**

```bash
git add -u   # stages plugins/vscode/ deletion
git status   # confirm only the deletion staged (README staged separately in Step 5)
git commit -m "$(cat <<'EOF'
feat(nix): retire vscode plugin; code CLI provided by the cask

The vscode plugin only symlinked VS Code's `code` helper onto PATH. The
visual-studio-code cask (declared in nix-darwin) lists code/code-tunnel as
binary artifacts, so Homebrew links them into /opt/homebrew/bin/ on install —
making the plugin redundant. Plugins are auto-discovered from plugins/*, so
deleting the directory removes it with no framework changes.
EOF
)"
```

Sandbox disable for gpg. No Claude attribution.

- [ ] **Step 5: Commit the README (docs)**

```bash
git add nix/README.md
git commit -m "docs(nix): document nix-vscode slice migration"
```

- [ ] **Step 6: Verify commits**

```bash
git log --oneline -3
git show --stat HEAD~1   # feat: shows plugins/vscode/vscode deleted
```

Expected:
```
<hash> docs(nix): document nix-vscode slice migration
<hash> feat(nix): retire vscode plugin; code CLI provided by the cask
<hash> docs: add nix-vscode slice design spec + plan   (or two separate doc commits)
```

- [ ] **Step 7: Apply + verify (needs interactive sudo)**

Ask the user to run `./apply`, then verify:

```bash
command -v code            # still /opt/homebrew/bin/code
code --version 2>&1 | head -1
DOTFILES_DEBUG=1 ./apply 2>&1 | grep -i vscode || echo "(vscode plugin no longer loads — good)"
grep -rn vscode framework/ plugins/ environments/ 2>/dev/null || echo "(clean)"
```

Expected: `code` still resolves and runs; no vscode plugin in the apply flow; no framework references.

(Deleting the plugin does NOT remove the existing `/opt/homebrew/bin/code` symlink — the apply just stops trying to create it. So `code` works immediately, before and after apply.)

---

## Task 2 (local-only): Update status doc

Update `docs/superpowers/nix-migration-status.md` (NOT committed):
- Slice 14 nix-vscode added to shipped table.
- Bash plugins retired 11 → 12 (`vscode`).
- Plugin layer list: remove `vscode` (leaving `nix`, `homedir`).

---

## Self-review against spec

- Decision 1 (pure deletion, trust cask): Task 1 Step 2.
- Decision 2 (leave /opt/homebrew/bin/code): not touched anywhere.
- Decision 3 (no nix/framework changes): only README + deletion.
- Decision 4 (README block): Task 1 Step 3.
- Decision 5 (no work-specific values): none.

No placeholders; exact commands throughout.

## Cross-references

- Design spec: `docs/superpowers/specs/2026-05-27-nix-vscode-design.md`
- Prior slice plan: `docs/superpowers/plans/2026-05-27-nix-claude.md`
