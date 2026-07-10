# Write less documentation, and write it shorter

The anti-AI-slop rules govern how a sentence reads. This one governs whether the
sentence should exist.

## Don't write documents nobody asked for

- Default to editing an existing document rather than adding one. A new file
  fragments the place a reader looks.
- A change that a commit message explains does not also need a design note, a
  summary file, or a `NOTES.md`. Write the commit message.
- Do not leave behind the scaffolding of your own work — status files, migration
  checklists, "what I did" summaries. If it was useful to you and not to the
  next reader, delete it.
- When asked to "document" something, ask what question the reader will arrive
  with. Answer that question. Stop.

## Keep what you do write short

- A section earns its place by answering a question a reader will actually have.
  Delete sections that exist for symmetry or to look thorough.
- Prefer one accurate sentence to three hedged ones. Prefer a code block to a
  paragraph describing the code block.
- When a document grows past what someone will read, cut it. Do not reorganize
  it, add a table of contents, or split it into a directory of smaller documents
  that collectively nobody reads.
- Comments follow the same rule: explain a constraint the code cannot show.
  Never narrate what the next line does.

## The test

Read what you wrote and ask, of each paragraph: if I deleted this, what would
the reader fail to do? If the answer is "nothing", delete it.
