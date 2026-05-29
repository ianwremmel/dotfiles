# No Tombstone Comments

Do not write comments that describe code which is no longer present, or
narrate the history of how the code reached its current state. Comments must
explain the code as it exists now — what it does and why — to a reader who
never saw the prior version. Git history already records what changed.

A tombstone is a comment whose subject is *this repository's own* removed or
superseded code. Avoid comments like:

- "There used to be X here, but we removed it because…"
- "Formerly the Y plugin; the framework was collapsed in slice N…"
- "This used to do W" / "Renamed from our old Z"
- "No longer needed because…" describing absent code

If the *current* design needs justifying (a non-obvious choice, a workaround,
a constraint), explain the present rationale directly without referencing what
the code used to be. If the only thing a comment conveys is that our code
changed, delete it — that belongs in the commit message.

This does **not** ban comments that document an *external* fact to justify a
surprising current value. Those are present-day rationale, not history of our
code, and should stay. For example, `# renamed from aws-vault in homebrew-cask`
explains why a package token looks the way it does today and stops someone
"correcting" it and breaking the build.
