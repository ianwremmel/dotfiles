# Dotfiles _(dotfiles)_

> Reasonable defaults with customizations

I ([@ianwremmel](https://github.com/ianwremmel)) forked
[Mathias Bynens's Dotfiles](https://github.com/mathiasbynens/dotfiles) many
years ago. My customizations got to the point where I made the repo private
because it was easier than dealing with non-public things that might be in my
git history. Eventually, I shared the repo with
[Riley Marsh](https://github.com/rimarsh) and we sort of managed to not step on
eachother's configs.

Our customizations have diverged enough (and we've had reason enough to share
with others) that this repo is a ground-up rewrite inspired by Mathias's
original work, but supporting per-user and per-machine personalization, a clean
history (no secrets from former employers in this repo!), and a first-run script
that can be copied-and-pasted from this very README.

## Install

```bash
git clone https://github.com/ianwremmel/dotfiles
```

## Usage

Apply the repo to your system. You'll be prompted on first run.

```bash
cd dotfiles
./apply
```

Set `DOTFILES_DEBUG=1` for debug logging.

### Configuration

On first run, dotfiles will create `~/.dotfilesrc`. In general, this file should
not be edited directly, however, if you wish to change a setting, you may delete
that setting from the file to be reprompted on next run.

## Environments

Environments define config for a particular computer (or category of computers).
For example, you might have an environment called "home" and an environment
called "work".

There are two special environment names with extra behavior. Configuration in
the `all` environment gets applied to every device regardless of any other
environment name being set. `default` gets applied on any device that doesn't
have a specific environment set. It's entirely possible (likely, even) that
these are the only environments you'll need.

Environments are are defined in two place:

- `environments` - these are defined in this reposity. These are @ianwremmel's
  custom dotfiles. You may be happy with them or you may wish to customize them.
  They tend to change regularly (particularly his brewfile, so you'll likely
  want to copy `all` and `default` to your `custom_environments`)
- `custom_environments` - This folder is gitignored. You can choose to put your
  environments here and not track them, but you'll probably want to create a
  separate repo that you checkout to this folder. If you create a folder called
  e.g. `all` in `custom_environments`, it will be used exclusively in place of
  the `all` in `environments`. If that folder is empty, you'll be working from a
  completely clean slate (other than the work done by plugins)

## Plugins

Plugins do the bulk of the work here. Plugins are just bash scripts that
implement one or more [lifecycle hooks](#lifecycle-hooks). They're executued
automatically by `./apply`.

When authoring plugins, keep in mind that they're sourced into the framework
process, so there's no need to e.g. `set -euo pipefail`.

> Though unnecessary, it's fine to put `export` in from of e.g.
> `$DOTFILES_*_CONFIG` in order to prevent shellcheck from complaining about
> unused vars.

### Lifecycle Hooks

- `$DOTFILES_*_CONFIG` - an array containing the unprefixed names of the
  plugin's config variables
- `$DOTFILES_*_DEPS` - an array of plugin names that must execute before this
  plugin can be applied
- `dotfiles_*_apply ()` - does the plugin's work
- `dotfiles_*_prompt_string ()` - function that accepts a (non-namespaced) var
  name and echos the prompt string for `read` to present to the user

## Conventions

- Scripts are extensionless and rely on their shebang for interpreter.
- Environment variables and globals are all caps, with underscores as
  separaters.
- Functions and local variables are snake case.
- Shell scripts (including plugins, though technically only the plugin
  _entrypoint_ need be bash) are written for bash >= 4. At time of writing, this
  means bash 5. While you may choose any shell you wish as your default, the
  majority of the script files are loading by sourcing them into the current
  process. Moreover shellcheck supports bash, but not zsh.

## Contributing

PRs welcome, but please first open an issue for anything but the most trivial of
changes. While I'm very open to improvements, these are my customizations for my
personal machines, so you may be better off adding your own custom environment
rather than trying to make a change :)

## License

[MIT] &copy; Ian Remmel & Riley Marsh
