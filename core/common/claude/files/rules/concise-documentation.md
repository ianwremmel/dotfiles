# Write less documentation, and write it shorter

The anti-AI-slop rules govern how a sentence reads. This one governs whether the
sentence, the paragraph, or the whole document should exist. Cut ruthlessly:
every extra paragraph costs a reader — human or agent — the same as an extra
sentence. Length is not thoroughness.

## Don't write documents nobody asked for

- Edit an existing document before adding one. A new file fragments the place a
  reader looks.
- If a commit message explains a change, it does not also need a design note, a
  summary file, or a `NOTES.md`. Write the commit message.
- Do not leave the scaffolding of your own work behind — status files, migration
  checklists, "what I did" summaries. Delete it.
- When asked to "document" something, answer the question the reader will arrive
  with, then stop.

## Keep what you do write short

- A section earns its place by answering a question a reader will have. Cut
  sections that exist for symmetry or to look thorough.
- One accurate sentence beats three hedged ones. A code block beats a paragraph
  describing it.
- When a document outgrows what someone will read, cut it — do not reorganize
  it, add a table of contents, or split it into a directory nobody reads.
- Comments follow the same rule: explain a constraint the code cannot show,
  never narrate what the next line does.

## The test

Of each paragraph, ask: if I deleted this, what would the reader fail to do? If
the answer is "nothing", delete it.
