# shellcheck disable

# Avoid issues with `gpg` as installed via Homebrew.
# https://stackoverflow.com/a/42265848/96656
export GPG_TTY
GPG_TTY=$(tty)

# Prefer the user's default keychain
export AWS_VAULT_KEYCHAIN_NAME
AWS_VAULT_KEYCHAIN_NAME=login
