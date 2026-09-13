# Package and module docs

A package is a directory, other than the repo root, that contains a
`package.json`. A module is a directory that is not a package and contains a
`BUILD.bazel` or an `index.{js,jsx,ts,tsx,mjs,mts}`.

- Every package has a README.md; a module may have one. README: purpose, entry
  points, and for packages build/test/run. How the code works goes here, not in
  CLAUDE.md.
- A directory gets a CLAUDE.md only if it has content in these categories:
  commands specific to it; conventions that differ from ancestor CLAUDE.md files
  or tool defaults; pitfalls; rationale for non-obvious choices.
- Never in a CLAUDE.md: anything derivable from the code, anything already in an
  ancestor CLAUDE.md. Under 40 lines.
- Changing code near a CLAUDE.md is not a reason to add to it. Descriptive
  content found in one moves to the nearest README.
