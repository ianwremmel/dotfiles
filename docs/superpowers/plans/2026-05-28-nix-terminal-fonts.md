# Nix Terminal Fonts Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Make iTerm2 (Default + tmux profiles) and Terminal.app (Homebrew profile) render `MesloLGSNF-Regular 14` declaratively. iTerm via two Dynamic Profiles inheriting the existing profiles + `Default Bookmark Guid`; Terminal.app via a stored NSFont blob injected by a `defaults export → plutil -replace → defaults import` activation. Remove the stale, ignored iTerm font keys the nix-firstrun slice added to `nix/darwin/defaults.nix`.

**Architecture:** One atomic `feat` commit: new `nix/profiles/default/terminal-fonts.nix` (darwin-gated), import it in `nix/profiles/default/default.nix`, and remove the `com.googlecode.iterm2` block from `nix/darwin/defaults.nix`. A `docs` commit for `nix/README.md`. A verification task (heavy on manual visual checks — the payoff is glyph rendering).

**Tech Stack:** Nix flakes, home-manager (`release-26.05`), `home.file`, `targets.darwin.defaults`, `lib.hm.dag` activation, `lib.mkIf pkgs.stdenv.isDarwin`, `defaults`/`plutil` (Terminal.app injection).

---

## Notes for the executor

- **Reference spec:** `docs/superpowers/specs/2026-05-28-nix-terminal-fonts-design.md`. The full `terminal-fonts.nix` content (incl. GUIDs and the base64 blob) is authoritative.
- **No automated tests.** Verification is `nix eval` gates + post-apply `defaults read` + manual visual confirmation (Task 3).
- **Branch:** `nix-terminal-fonts`. Stacks on `nix-homedir` (#75). **Do NOT merge.**
- **Sandbox disable** for `nix`, `git commit` (gpg), anything reading/writing `~/Library/...`. `nix eval` form: `nix eval "path:./nix#…"`.
- **`./apply` needs interactive sudo (TTY).** At the apply step, run eval gates first, report NEEDS_CONTEXT, ask the user to run `./apply` (and to quit Terminal.app first — see below). Resume after.
- **Conventional commits**, no Claude attribution. **No push** without user approval.

### Pre-existing local state (assume)

- iTerm profiles: "Default" GUID `BC395EC2-C211-4986-9CE6-95AA344E7D49` (also the current `Default Bookmark Guid`), "tmux" GUID `B419BC64-4E86-469D-BFD0-BB754E078C1A`. Both currently `Monaco 20`.
- `~/Library/Application Support/iTerm2/DynamicProfiles/` exists, empty.
- Terminal.app default+startup profile is "Homebrew"; its `Font` is a binary NSFont blob.
- `nix/profiles/default/default.nix` imports `./claude.nix` and `./cli-tools.nix`.
- `nix/darwin/defaults.nix` has a `CustomUserPreferences."com.googlecode.iterm2"` block (stale font keys from nix-firstrun).
- The fixed GUIDs for this slice: Default `95362E86-C10E-48E3-9FA1-DC4596B0F677`, tmux `BF5B17AC-8CB2-4C36-942E-F45E91EAF11A`.

### Open-question gates (from spec)

1. **`targets.darwin.defaults` shape** — confirm `targets.darwin.defaults."com.googlecode.iterm2"."Default Bookmark Guid"` is a valid option at this pin (the `modules/targets/darwin/user-defaults` module exists). If it errors at eval, fall back to a small `home.activation` running `defaults write com.googlecode.iterm2 "Default Bookmark Guid" <guid>`.
2. **`plutil -replace` keypath** — at apply time, confirm `plutil -replace 'Window Settings.Homebrew.Font' -data <b64> <file>` targets the nested key. Fallback: Python `plistlib` round-trip (documented in spec open-question 1).
3. **iTerm dynamic-profile key casing** — `"Use Non-ASCII Font"` / `"Non Ascii Font"` read correctly from JSON. Verified visually at apply.

---

## Task 1: Atomic terminal-fonts migration

**Files:**
- Create: `nix/profiles/default/terminal-fonts.nix`
- Modify: `nix/profiles/default/default.nix` (import)
- Modify: `nix/darwin/defaults.nix` (remove iTerm block)

### Step-by-step

- [ ] **Step 1: Pre-flight capture**

```bash
{
  echo "=== iTerm profiles font (expect Monaco 20) ==="
  defaults read com.googlecode.iterm2 "New Bookmarks" 2>/dev/null | grep -E "Name =|Normal Font =|Guid ="
  echo "=== Default Bookmark Guid (expect BC395EC2-...) ==="
  defaults read com.googlecode.iterm2 "Default Bookmark Guid" 2>&1
  echo "=== DynamicProfiles dir ==="
  ls -la "$HOME/Library/Application Support/iTerm2/DynamicProfiles/" 2>&1
  echo "=== Terminal Homebrew font blob (current) ==="
  defaults read com.apple.Terminal "Window Settings.Homebrew.Font" 2>&1 | head -3
} > "$TMPDIR/termfonts-preflight.txt" 2>&1
cat "$TMPDIR/termfonts-preflight.txt"
```

- [ ] **Step 2: Confirm starting file state**

```bash
grep -n "com.googlecode.iterm2" nix/darwin/defaults.nix
cat nix/profiles/default/default.nix
ls nix/profiles/default/terminal-fonts.nix 2>&1 || echo "(not yet created — good)"
```

Expected: the `com.googlecode.iterm2` block present in defaults.nix; default.nix imports claude+cli-tools; terminal-fonts.nix absent.

- [ ] **Step 3: Create `nix/profiles/default/terminal-fonts.nix`**

Use the EXACT module content from the spec ("`nix/profiles/default/terminal-fonts.nix` (full content)") — including the `font` let-binding, the two GUIDs, the `terminalFontBlob` base64 string + its regen comment, the `iterm2DynamicProfiles` attrset, the `home.file` for the dynamic profile JSON, the `targets.darwin.defaults` Default Bookmark Guid, and the `home.activation.terminalAppFont` (export → plutil -replace → import). Wrap the whole config body in `lib.mkIf pkgs.stdenv.isDarwin`.

Copy the base64 blob verbatim from the spec (do not regenerate — the spec's blob is the reference value).

- [ ] **Step 4: Import in `nix/profiles/default/default.nix`**

Add `./terminal-fonts.nix` to the imports list (alphabetical: after `./cli-tools.nix`):

```nix
  imports = [
    ./claude.nix
    ./cli-tools.nix
    ./terminal-fonts.nix
  ];
```

Do NOT touch the `programs.git.settings` block below it.

- [ ] **Step 5: Remove the stale iTerm block from `nix/darwin/defaults.nix`**

Find the `# ----- iTerm 2 -----` comment block and the `"com.googlecode.iterm2" = { ... };` entry under `CustomUserPreferences`, and delete the whole entry (comment + attrset). Leave all other `CustomUserPreferences` domains intact.

Verify:
```bash
grep -n "com.googlecode.iterm2\|iTerm" nix/darwin/defaults.nix && echo "STILL PRESENT (FAIL)" || echo "OK: iTerm block removed"
```

- [ ] **Step 6: Eval gates (HARD — pre-apply)**

```bash
cd nix; git add -A ..  # stage so the flake (git source) sees terminal-fonts.nix; or: git add the new file
SYSTEM="$(nix eval --raw --impure --expr builtins.currentSystem)"

echo "=== dynamic-profile file present in home.file? ==="
nix eval --json "path:.#homeConfigurations.default@${SYSTEM}.config.home.file" --apply 'builtins.attrNames' 2>&1 | tr ',' '\n' | grep -i "DynamicProfiles/nix.json"

echo "=== Default Bookmark Guid set via targets.darwin.defaults? ==="
nix eval --raw "path:.#homeConfigurations.default@${SYSTEM}.config.targets.darwin.defaults.\"com.googlecode.iterm2\".\"Default Bookmark Guid\"" 2>&1 | tail -2

echo "=== terminalAppFont activation present? ==="
nix eval "path:.#homeConfigurations.default@${SYSTEM}.config.home.activation.terminalAppFont.data" 2>&1 | grep -ci "plutil\|defaults import" 

echo "=== darwin defaults.nix no longer references iterm2 ==="
nix eval "path:.#darwinConfigurations.default@${SYSTEM}.config.system.defaults.CustomUserPreferences" --apply 'p: builtins.hasAttr "com.googlecode.iterm2" p' 2>&1 | tail -1
cd ..
```

Expected: dynamic-profile path present; Default Bookmark Guid = `95362E86-…`; terminalAppFont contains plutil/defaults import; the darwin CustomUserPreferences `com.googlecode.iterm2` check → `false`.

If `targets.darwin.defaults` errors → open-question-1 fallback (home.activation defaults write). Re-eval until green. Do NOT apply until clean.

- [ ] **Step 7: Full flake eval (both profiles)**

```bash
SYSTEM="$(nix eval --raw --impure --expr builtins.currentSystem)"
nix flake check --no-build path:./nix 2>&1 | tail -20
nix eval "path:./nix#homeConfigurations.default@${SYSTEM}.config.home.activationPackage.drvPath" 2>&1 | tail -3
# Confirm the isDarwin guard makes the linux build a no-op (no DynamicProfiles file there):
nix eval --json "path:./nix#homeConfigurations.default@x86_64-linux.config.home.file" --apply 'fs: builtins.any (n: builtins.match ".*DynamicProfiles.*" n != null) (builtins.attrNames fs)' 2>&1 | tail -1
```

Expected: flake check + darwin drv eval succeed; the linux check → `false` (guard works).

- [ ] **Step 8: Run `./apply`**

Needs interactive sudo. Report NEEDS_CONTEXT and ask the user to **quit Terminal.app first**, then run `./apply`. Resume from Step 9. (iTerm can stay open — dynamic profiles are clobber-immune; but Terminal.app must be quit so the import isn't reverted on its next quit.)

- [ ] **Step 9: Verify iTerm dynamic profiles + default bookmark**

```bash
echo "=== dynamic profile file ==="
ls -la "$HOME/Library/Application Support/iTerm2/DynamicProfiles/nix.json"
cat "$HOME/Library/Application Support/iTerm2/DynamicProfiles/nix.json" | python3 -m json.tool 2>/dev/null | grep -E '"Name"|"Normal Font"|"Dynamic Profile Parent Name"|"Guid"'
echo "=== Default Bookmark Guid (expect 95362E86-...) ==="
defaults read com.googlecode.iterm2 "Default Bookmark Guid" 2>&1
```

Expected: nix.json is a symlink containing both profiles with `MesloLGSNF-Regular 14` and the right parents; Default Bookmark Guid = `95362E86-C10E-48E3-9FA1-DC4596B0F677`.

- [ ] **Step 10: Verify Terminal.app font blob**

```bash
echo "=== Homebrew profile font (decode the NSFont) ==="
defaults read com.apple.Terminal "Window Settings.Homebrew.Font" 2>&1 | head -3
# Decode to confirm it names MesloLGSNF-Regular:
python3 - <<'PY'
import subprocess, plistlib, base64
out = subprocess.run(["defaults","export","com.apple.Terminal","-"], capture_output=True).stdout
pl = plistlib.loads(out)
blob = pl["Window Settings"]["Homebrew"]["Font"]
# blob is bytes (NSFont archive); search for the font name
print("MesloLGSNF-Regular" in blob.decode("latin-1") and "OK: Terminal Homebrew font is MesloLGSNF-Regular" or "FAIL: font name not found in blob")
PY
```

Expected: the blob decodes to contain `MesloLGSNF-Regular`. If the round-trip didn't take (e.g. Terminal was running), note it; the user re-applies with Terminal quit.

- [ ] **Step 11: Manual visual verification (executor cannot do — flag for user)**

These require a human; document them for the user to confirm in Task 3:
- Relaunch iTerm → the Default window uses MesloLGS Nerd Font; starship's git-branch glyph renders (no missing-glyph box).
- In iTerm, select the `tmux (nix)` profile for a tmux window → Nerd Font renders there too.
- Quit + reopen Terminal.app → the Homebrew profile shows MesloLGS Nerd Font 14.

The executor records these as "pending user visual confirmation" rather than blocking the commit.

- [ ] **Step 12: Stage and commit**

```bash
git add nix/profiles/default/terminal-fonts.nix nix/profiles/default/default.nix nix/darwin/defaults.nix
git status
git commit -m "$(cat <<'EOF'
feat(nix): render Nerd Font in iTerm2 + Terminal.app declaratively

Close the terminal-font deferral. The nix-firstrun attempt wrote a top-level
iTerm `Normal Font` pref (ignored — the font lives per-profile in New Bookmarks)
with a typo'd PostScript name. This does it correctly:

- iTerm2: two Dynamic Profiles inherit the existing Default and tmux profiles and
  override the font to MesloLGSNF-Regular 14. The Default-inheriting profile is
  set as the default bookmark (targets.darwin.defaults). Dynamic profiles are
  read on launch and immune to iTerm rewriting its own prefs on quit.
- Terminal.app: the Homebrew profile's NSFont blob is set via a cfprefsd-safe
  defaults export -> plutil -replace -> defaults import activation.

Removes the stale, ignored com.googlecode.iterm2 font keys from
nix/darwin/defaults.nix (superseded; avoids two layers writing the domain).
EOF
)"
```

Sandbox disable for gpg. No Claude attribution.

- [ ] **Step 13: Verify commit + pre-flight diff**

```bash
git log --oneline -1
git show --stat HEAD
```

Expected: one feat commit; stat shows new terminal-fonts.nix, modified default.nix + defaults.nix.

---

## Task 2: Update `nix/README.md`

**Files:** Modify `nix/README.md`.

- [ ] **Step 1:** `grep -n "For the nix-homedir slice" nix/README.md`; insert the new block after the nix-homedir sub-block, before the closing "The same shape applies to future slices" paragraph.
- [ ] **Step 2:** Insert the spec's "For the nix-terminal-fonts slice" block verbatim (paragraph-heading style, no `###`).
- [ ] **Step 3:** Verify `grep -nE "^For the nix-terminal-fonts slice" nix/README.md` → one paragraph-form match.
- [ ] **Step 4:** Commit `git add nix/README.md && git commit -m "docs(nix): document nix-terminal-fonts slice migration"` (sandbox disable for gpg).
- [ ] **Step 5:** Verify `git log --oneline -3`.

---

## Task 3: Cross-slice verification

- [ ] **Step 1:** Clean reapply if needed (user-run, Terminal.app quit): inspect for warnings.
- [ ] **Step 2:** Re-confirm the eval/defaults invariants (Task 1 Steps 9-10): dynamic profile file, Default Bookmark Guid, Terminal blob decodes to MesloLGSNF-Regular.
- [ ] **Step 3:** **User visual confirmation** (the actual payoff): iTerm Default window renders the Nerd Font + starship glyph; `tmux (nix)` profile renders it; Terminal.app Homebrew profile renders it after quit+reopen. Record results; if any fails, capture the actual `defaults read` value and diagnose (likely font-name nuance → regen blob via the documented Swift snippet, or dynamic-profile key casing).
- [ ] **Step 4:** Confirm `nix/darwin/defaults.nix` no longer references iTerm; no other domains lost.
- [ ] **Step 5:** Confirm commit shape: `git log --oneline nix-homedir..HEAD` → spec + feat + docs.
- [ ] **Step 6:** Update `docs/superpowers/nix-migration-status.md` (LOCAL ONLY): mark the iTerm/Terminal font deferral CLOSED by slice 16 (nix-terminal-fonts); note the Terminal-quit-first caveat.
- [ ] **Step 7:** Open PR (gated on explicit user approval — memory `ask-before-merging`). `git push -u origin nix-terminal-fonts`; `gh pr create --base nix-homedir --title "feat(nix): render Nerd Font in iTerm2 + Terminal.app" --body "..."`.

---

## Self-review against the spec

- Decision 1 (iTerm dynamic profiles, both): Step 3 (`iterm2DynamicProfiles`, two profiles).
- Decision 2 (MesloLGSNF-Regular 14): the `font` binding.
- Decision 3 (auto-activate via Default Bookmark Guid): `targets.darwin.defaults`.
- Decision 4 (Terminal.app blob via export/plutil/import): `home.activation.terminalAppFont`.
- Decision 5 (stored blob + regen comment): the `terminalFontBlob` string.
- Decision 6 (remove stale iTerm block from defaults.nix): Step 5.
- Decision 7 (default profile, isDarwin-gated): `lib.mkIf pkgs.stdenv.isDarwin` + import in default.nix.
- Decision 8/9 (fonts only, non-sensitive): scope.

Placeholder scan: exact commands/code throughout (the module content is copied from the spec verbatim). Type consistency: `font`, `defaultGuid`, `tmuxGuid`, `terminalFontBlob`, `iterm2DynamicProfiles`, `terminalAppFont` consistent.

## Cross-references

- Design spec: `docs/superpowers/specs/2026-05-28-nix-terminal-fonts-design.md`
- Prior slice plan: `docs/superpowers/plans/2026-05-27-nix-homedir.md`
