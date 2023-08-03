# shellcheck disable

# Search running processes but omit the noise in /Applications and /System
alias psgrep='ps -A | grep -v /Applications | grep -v /System | grep'

alias xo='xargs open'

# Shorthand to let httpie know we want https
alias https='http --default-scheme=https'

alias r2='env /usr/bin/arch -x86_64'
