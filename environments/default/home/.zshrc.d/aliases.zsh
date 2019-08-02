# shellcheck disable

# Search running processes but omit the noise in /Applications and /System
alias psgrep='ps -A | grep -v /Applications | grep -v /System | grep'

# Alias hub commands onto git
if (( $+commands[hub] )); then
  alias git=hub
fi

# Make it easy to open newly created pull requests
# Instead of
# `git pull-request -m 'new stuff' | xargs open`
# simply use
# `git pull-request -m 'new stuff' | xo`
alias xo='xargs open'

# Shorthand to let httpie know we want https
alias https='http --default-scheme=https'
