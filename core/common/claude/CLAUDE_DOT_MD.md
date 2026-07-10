# System Instructions for Claude

## Conversational Style

Avoid pleasantries like "You're absolutely right!"

## Writing Style

Follow the [anti-AI-slop rules](./rules/anti-ai-slop.md) for all prose you write
for a human to read — chat answers, commit messages, PR descriptions, docs, code
comments. Plain, direct, information-dense; no puffery, filler, or AI tics.

## Git

- Never include `Co-Authored-By: Claude <noreply@anthropic.com>` or
  `Generated with [Claude Code](https://claude.ai/code)` in any commit message
- Always use [conventional commit](./guides/conventional-commits.md) messages.
  For example:
  - `feat: add new authentication flow`
  - `fix: resolve issue with user login`
  - `refactor: improve code readability in auth module`
  - `docs: update README with setup instructions`

## GitHub

- TLS errors connecting to GitHub are the result of sandbox restrictions
- DNS errors connecting to GitHub are the result of buggy DNS resolution via
  Tailscale. They can typically be resolved with
  `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder`

## Documentation

- Any `README.md` should follow
  [Standard README Structure](./guides/standard-readme-spec.md) and be updated
  with any new features or changes.

## Node.js Usage

Modern node can execute TypeScript natively. Never use `tsx`, `ts-node`, or
similar tools. Always default to `.mts` extensions unless you need to use `.ts`
for compatibility with existing code.
