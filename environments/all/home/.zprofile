# shellcheck disable

# Ordinarily, PATH setup should be in .zshenv, but apple runs a script via 
# `/etc/zprofile`` which tampers with path ordering, so we need to configure 
# PATH here instead.

export PATH

# Add Homebrew. We have pretty much no PATH at this point, so use its full path
if command -v /opt/homebrew/bin/brew > /dev/null 2>&1 ; then
  BREW_PREFIX="$(/opt/homebrew/bin/brew --prefix)"

  # Put brew binaries at the start of PATH so they override system binaries
  PATH=$BREW_PREFIX/bin:$BREW_PREFIX/sbin:$PATH;

  # Put all of the gnubin binaries in front of system binares
  for FILE in "$(brew --prefix)"/opt/*/libexec/gnubin; do
    PATH=$FILE:$PATH
  done
fi

# Add Java
if command -v /usr/libexec/java_home > /dev/null 2>&1 ; then
  PATH=$PATH:$(/usr/libexec/java_home)/bin;
fi

# set PATH so it includes user's private bin
PATH="$HOME/bin:$PATH"
