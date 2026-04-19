# Dotfiles Repository

Plugin-driven, environment-aware dotfiles management system.

## Structure

- `framework/` - Core framework (plugin lifecycle, config, environment detection)
- `plugins/` - Individual plugins (homebrew, shells, git, vim, nvm, etc.)
- `environments/` - Repo-managed environments (`all/` shared, `default/` machine-specific)
- `custom_environments/` - Git-ignored user customizations
- `apply` - Main entry script

## Running

```bash
./apply              # Full application
./apply -B           # Skip homebrew bundle
./apply -A           # Airplane mode (offline)
DOTFILES_DEBUG=1 ./apply  # Verbose logging
```

## Conventions

- Bash 5+ required
- Plugin functions: `dotfiles_<plugin>_apply()`, `dotfiles_<plugin>_prompt_string()`
- Plugin dependencies: `DOTFILES_<plugin>_DEPS` array
- Plugin config: `DOTFILES_<plugin>_CONFIG` array
- Config persisted to `~/.dotfilesrc`

## Testing

No automated tests. Manual testing via `./apply`.
