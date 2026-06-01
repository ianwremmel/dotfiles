#!/usr/bin/env python3
"""Patch terminal fonts in place via a cfprefsd-safe defaults export/import.

Usage: patch-terminal-fonts.py <font> <terminal-nsfont-blob-base64>

- iTerm2 (com.googlecode.iterm2): set Normal Font / Non Ascii Font on every
  "New Bookmarks" profile named "Default" or "tmux" (matched by name, so it's
  order- and count-independent and leaves other profiles alone).
- Terminal.app (com.apple.Terminal): set the "Homebrew" profile's Font to the
  NSKeyedArchiver NSFont blob (bytes -> <data>), creating the key if absent.

Each domain is round-tripped through `defaults export`/`defaults import` so the
write goes through cfprefsd cleanly. The owning app must NOT be running during
apply, or it will rewrite its prefs on quit and revert these changes.
"""
import base64
import os
import plistlib
import subprocess
import sys
import tempfile

DEFAULTS = "/usr/bin/defaults"


def patch_domain(domain, mutate):
    fd, tmp = tempfile.mkstemp(suffix=".plist")
    os.close(fd)
    try:
        if subprocess.run([DEFAULTS, "export", domain, tmp]).returncode != 0:
            return
        with open(tmp, "rb") as f:
            pl = plistlib.load(f)
        if not mutate(pl):
            return
        with open(tmp, "wb") as f:
            plistlib.dump(pl, f)
        # Propagate a failed import instead of silently succeeding — otherwise
        # ./apply reports success while the font was never actually written.
        subprocess.run([DEFAULTS, "import", domain, tmp], check=True)
    finally:
        os.unlink(tmp)


def main():
    font = sys.argv[1]
    term_blob = base64.b64decode(sys.argv[2])

    def iterm(pl):
        bookmarks = pl.get("New Bookmarks")
        if not isinstance(bookmarks, list):
            return False
        changed = False
        for profile in bookmarks:
            if isinstance(profile, dict) and profile.get("Name") in ("Default", "tmux"):
                profile["Normal Font"] = font
                profile["Non Ascii Font"] = font
                changed = True
        return changed

    def terminal(pl):
        settings = pl.get("Window Settings")
        if not isinstance(settings, dict) or not isinstance(settings.get("Homebrew"), dict):
            return False
        settings["Homebrew"]["Font"] = term_blob
        return True

    patch_domain("com.googlecode.iterm2", iterm)
    patch_domain("com.apple.Terminal", terminal)


if __name__ == "__main__":
    main()
