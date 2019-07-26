#!/usr/bin/env bash

# See ~/.bash_profile for an explanation of shell startup files

# macOS handles bash_profile and bashrc in unexpected ways, largely incompatible
# with how they're intended to be used on linux/unix. As such, all config needs
# to go in .bash_profile. In the cases where .bashrc is loaded instead of
# .bash_profile, defer .bash_profile

# shellcheck disable=SC1090
[ -n "$PS1" ] && source ~/.bash_profile;
