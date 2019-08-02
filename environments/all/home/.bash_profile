#!/usr/bin/env bash

# ~/.profile: executed by the command interpreter for login shells.
# This file is not read by bash(1), if ~/.bash_profile or ~/.bash_login
# exists.
# Since this file is superceded by .bash_profile, .bash_profile should probably
# source it

# ~/.bash_profile: The personal initialization file, executed for login shells.
# On OSX, this file is read by every Terminal.app instance

# ~/.bashrc: The individual per-interactive-shell startup file (for non-login
# shells), On OSX, this file is only read when executing e.g. `bash` or
# `su <username>`

# non-login shells: a shell launched from another shell (e.g. running `bash`,
# running `su <username>` the command line, or launching xterm)

# login shells: a shell resultant from entering a username and password (e.g.
# logging into a linux box on startup, connecting via ssh).
# Note: on macOS, all Terminal.app instances are treated as long shells.

load_profile_file() {
  BASE_NAME=$1
  # Note that this prefers $HOME rather than $HOME/.bash_profile.d for backwards
  # compatibility reasons
  if [ -f "$HOME/.$BASE_NAME" ]; then
    # shellcheck disable=SC1090
    source "$HOME/.$BASE_NAME"
  elif [ -f "$HOME/.bash_$BASE_NAME" ]; then
    # shellcheck disable=SC1090
    source "$HOME/.bash_$BASE_NAME"
  elif [ -f "$HOME/.bash_profile.d/$BASE_NAME" ]; then
    # shellcheck disable=SC1090
    source "$HOME/.bash_profile.d/$BASE_NAME"
  fi
}

# Set a reasonable ulimit because Apple
ulimit -n 8192

# Load non-bash specific config
if [ -f ~/.profile ]; then
  # shellcheck disable=SC1090
  source ~/.profile
fi

# Load SSH keys
ssh-add -K > /dev/null 2> /dev/null

# Load the non-interactive shell dotfiles, and then some:
FILES="path exports aliases functions extra secure"
for FILE in $FILES; do
  # shellcheck disable=SC1090
	load_profile_file "$FILE"
done
unset FILE
unset FILES

# If not running interactively, stop further processing
[ -z "$PS1" ] && return

# Setup nvm and node so that .bash_prompt can use it
if [ -d "$HOME/.nvm" ]; then
  # shellcheck disable=SC1090
	source "$HOME/.nvm/nvm.sh"
fi

# Load the interactive shell dotfiles, and then some:
FILES="completion prompt"
for FILE in $FILES; do
  # shellcheck disable=SC1090
	load_profile_file "$FILE"
done
unset FILE
unset FILES

# Append to the Bash history file, rather than overwriting it
shopt -s histappend

# Enable some Bash 4 features when possible:
# * `autocd`, e.g. `**/qux` will enter `./foo/bar/baz/qux`
# * Recursive globbing, e.g. `echo **/*.txt`
for option in autocd globstar; do
	shopt -s "$option" 2> /dev/null
done

# Configure rbenv
if command -v rbenv >/dev/null 2>&1; then
  eval "$(rbenv init -)"
fi
