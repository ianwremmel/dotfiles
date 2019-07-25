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

TODO

## Usage

TODO

### Bootstrap

TODO

## Environments

- `all` - config in here will always be applied
- `default` - if no environment is set, this environment will be used
- any other name - if the current environment matches the folder name, that
  folder's config will be applied _instead of `default`_. Specify an environment
  using `DOTFILES_HOMEBREW_CONFIG_ENV=<environment name>` where
  `<environment name>` matches the folder

## Plugins

Plugins do the bulk of the work here. Plugins are just bash scripts that
implement wone or more [lifecycle hooks](#lifecycle-hooks). They're executued
automatically and by `./apply`.

When authoring plugins, keep in mind that they're sourced into the framework
process, so there's no need to e.g. `set -euo pipefail`.

> Though unnecessary, it's fine to put `export` in from of e.g.
> `$DOTFILES_*_CONFIG` in order to prevent shellcheck from complaining about
> unused vars.

### Lifecycle Hooks

- `$DOTFILES_*_CONFIG` - an array containing the unprefixed names of the
  plugin's config variables
- (future) `dotfiles_*_prompt` - declares the strings needed to prompt the user
  for any missing config values
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
  _entrypoint_ need be bash) are written for bash > 3. At time of writing, this
  means bash 5. While you may choose any shell you wish as your default, the
  majority of the script files are loading by sourcing them into the current
  process. Moreover shellcheck supports bash, but not zsh.
- All framework files should support being source multiple times.

## Contributing

TODO

## License

[MIT] &copy; Ian Remmel & Riley Marsh
