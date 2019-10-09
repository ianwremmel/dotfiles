# shellcheck disable


export GOROOT

# Add Homebrew. We have pretty much no PATH at this point, so use its full path
if command -v /usr/local/bin/brew > /dev/null 2>&1 ; then
  BREW_PREFIX="$(/usr/local/bin/brew --prefix)"

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

# Add GO
if command -v go > /dev/null 2>&1 ; then
  GOROOT=/usr/local/opt/go/libexec
  PATH=$PATH:$GOROOT/bin
fi

# set PATH so it includes user's private bin
PATH="$HOME/bin:$PATH"

# Avoid issues with `gpg` as installed via Homebrew.
# https://stackoverflow.com/a/42265848/96656
export GPG_TTY
GPG_TTY=$(tty)

# Prefer the user's default keychain
export AWS_VAULT_KEYCHAIN_NAME
AWS_VAULT_KEYCHAIN_NAME=login
