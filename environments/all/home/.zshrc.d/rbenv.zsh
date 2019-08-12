# shellcheck disable

if command -v rbenv >/dev/null 2>&1; then
  eval "$(rbenv init --no-rehash - zsh)"
fi
