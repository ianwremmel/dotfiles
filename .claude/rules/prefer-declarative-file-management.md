# Prefer declarative file management

When wiring files into a target tree (a home directory, a config dir, an output
package), prefer a "define the file and it works" approach: one rule that
auto-discovers files from a source directory and maps them to their
destination, so adding or removing a file needs no further edit.

Concretely, in Nix / home-manager:

- Map a source tree into `$HOME` by scanning it
  (`lib.filesystem.listFilesRecursive`) and generating `home.file` entries,
  rather than listing each file by hand or assembling them in a `runCommand`
  derivation. Dropping a file into the tree should be the only step needed.
- Reach for a `programs.<name>` module or `home.file` over a bespoke activation
  script when the typed option exists.

The test: once the mechanism is in place, "I want this file managed" is
satisfied by putting the file in the right directory — nothing else.
