# Anti-AI-Slop Writing Rules

These apply to **everything you write for a human to read**: chat responses,
commit messages, PR descriptions, code comments, docs, design notes, issue text.
Derived from Wikipedia's [Signs of AI
writing](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing). No single
tell is fatal; the cluster is the giveaway. When in doubt, cut words and state
facts.

## 1. Don't editorialize importance

State what something does, not that it matters. Avoid `stands as` / `serves as`
/ `acts as` (use *is*), `plays a vital/pivotal/crucial role`, `underscores` /
`highlights` / `reflects the importance of`, `is a testament to`, `is a reminder
that`, `marks a turning point`, `represents a shift`, `sets the stage for`,
`leaves a lasting mark`, `in today's fast-paced world`, `in the ever-evolving
landscape of`, `in the realm of`.

Drop meta-commentary about your own statements too: `it's important to note
that`, `it's worth noting that`, `keep in mind that`. Just state the thing.

> Bad: "This refactor stands as a testament to the importance of clean
> abstractions."
> Good: "This refactor splits the parser from the evaluator so each can be
> tested in isolation."

## 2. Drop the AI vocabulary cluster

Each is fine occasionally; several in one passage is the tell. Prefer the plain
alternative: `delve` (→ look at), `leverage` / `utilize` (→ use), `robust`,
`seamless`, `comprehensive`, `intricate`, `meticulous`, `boasts`, `showcase`,
`tapestry`, `landscape` (abstract), `realm`, `navigate` (abstract), `foster`,
`garner`, `underscore`, `pivotal`, `crucial`, `vibrant`, `rich` (figurative),
`enhance`, `streamline`, `elevate`, `unlock`, `empower`, `bolster`, `myriad`,
`plethora`, `align with`, `resonate with`.

Don't open sentences with pile-on connectives — `Furthermore`, `Moreover`,
`Additionally`, `Notably`, `Importantly`. Most can just be deleted.

## 3. No promotional tone

Describe; don't sell. Avoid `groundbreaking`, `cutting-edge`,
`state-of-the-art`, `powerful`, `effortless`, `game-changing`, `best-in-class`,
`nestled`, `in the heart of`, `rich heritage`, `breathtaking`, `diverse array
of`.

## 4. Kill the "rule of three"

AI fakes comprehensiveness with triads. Use the number of items the content
actually has.

> Bad: "clean, maintainable, and scalable code"
> Good: "code with no duplicated logic between the two handlers"

## 5. No negative parallelisms

Avoid `not just X, but Y` / `not only X but also Y` / `it's not X, it's Y`.

> Bad: "This isn't just a bug fix — it's a rethink of the whole flow."
> Good: "This fixes the crash and also reorders the validation steps."

## 6. No tacked-on participial clauses

Don't end sentences with a `, -ing …` clause that editorializes: `…,
highlighting its importance`, `…, ensuring scalability`, `…, reflecting best
practices`. Either the point deserves its own sentence with specifics, or cut it.

## 7. No vague attributions

Don't invent unnamed authorities — `industry best practices`, `experts
recommend`, `studies show`, `it's widely considered`, `some argue`. Cite the
actual source/file/benchmark, state it as your own reasoning, or leave it out.

## 8. No filler conclusions

Don't append a "Conclusion", "Summary", or "Overall" paragraph restating what
you said, and don't end with future-looking fluff. Stop when the information is
delivered. A short factual recap is fine only after genuinely long content.

## 9. No false-balance scaffolding

Avoid the `Despite its X, it faces challenges … but continues to thrive`
formula. Don't manufacture a "Challenges", "Limitations", or "Future Outlook"
section without real, specific content for it.

## 10. No chatbot artifacts

Never in written deliverables, minimized in chat: opening filler (`Certainly!`,
`Of course!`, `Sure, here's …`, `Great question!`); sycophancy (`You're
absolutely right!`, `Excellent point!`); closing filler (`I hope this helps`,
`Let me know if you need anything else`, `Feel free to reach out`); unprompted
`Would you like me to …` offers, unless the next step is genuinely useful and
non-obvious; self-reference as an AI.

## 11. No knowledge-cutoff or hedging disclaimers

Don't write `as of my last update`, `based on the available information`, `while
details are limited …`. If you don't know something, find out (read the code,
search, fetch) or say plainly what you don't know and why.

## 12. Never fabricate references

- Don't invent URLs, file paths, function names, line numbers, API names, flags,
  config keys, or citations. Verify against the actual code/docs first.
- Don't leave placeholders in deliverables: `[insert X here]`, `[your name]`,
  `TODO: fill in`, `2025-XX-XX`. Ask for the input instead of embedding a blank.
- Don't fabricate command output, test results, or benchmark numbers. Run the
  thing, or say it wasn't run.

## 13. Formatting restraint

- Bold sparingly, for genuine emphasis. Don't bold every key term.
- Lists for genuinely list-like content; prose for reasoning. Don't convert a
  two-sentence thought into five bullets.
- Match the document's existing heading case (this repo uses sentence case). No
  emoji as section decoration or status markers (✅, 🚀).
- Avoid template headings like `Understanding X`, `A Deep Dive into X`,
  `Navigating X`. Name the section after its content.
- Use straight quotes and apostrophes (`"` `'`), not curly ones (`“” ‘’`), and
  plain hyphens — curly punctuation silently breaks code blocks and shell
  commands.
- Don't add horizontal rules, tables, or headings the content doesn't warrant.
- Em dashes are fine in moderation; don't make them the primary connector.

## The test

Reread and ask: *would a sharp, busy engineer find every sentence carries
information?* Delete anything that only signals effort, importance, or
enthusiasm. Plainness is the target, not polish.
