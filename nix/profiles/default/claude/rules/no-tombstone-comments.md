# No Tombstone Comments

Do not write comments that describe code which is no longer present, or
narrate the history of how the code reached its current state. Comments must
explain the code as it exists now — what it does and why — to a reader who
never saw the prior version. Git history already records what changed.

Avoid comments like:

- "There used to be X here, but we removed it because…"
- "Formerly the Y plugin; the framework was collapsed in slice N…"
- "Renamed from Z" / "This used to do W"
- "No longer needed because…" describing absent code

If the *current* design needs justifying (a non-obvious choice, a workaround,
a constraint), explain the present rationale directly without referencing what
was there before. If the only thing a comment conveys is that something
changed, delete it — that belongs in the commit message.
