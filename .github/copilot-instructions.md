# Copilot Instructions for ianwremmel/dotfiles

## Repository Overview

**Purpose**: macOS dotfiles management system with plugin-based architecture for shell configs, app settings, and package management via Homebrew.

**Target**: macOS only (Intel/Apple Silicon) | **Language**: Bash 4+ (typically Bash 5) | **Size**: ~100 files | **Tech**: Homebrew, Bash, Zsh, rsync, Git

## Key Architecture

### Directory Structure
- **`apply`**: Main entry point (executable). Flags: `-A` (airplane mode), `-B` (skip brew bundle), `-h` (help)
- **`framework/`**: Core bash modules (compat, framework, config, plugin, environment, customize, firstrun, logging, util) - all extensionless
- **`plugins/`**: Plugin modules. Each in own dir: `[name]/[name]` (script) + optional `Brewfile`
  - Key plugins: homebrew, git, shells, homedir, vim, vscode, node, nvm, commit_signing, xcode
- **`environments/`**: Config directories (`all/`, `default/`). Contains: `firstrun`, `Brewfile`, `home/` (files to rsync to $HOME)
- **`custom_environments/`**: Gitignored user-specific configs (optional, managed separately)
- **`.github/workflows/push.yml`**: CI blocks fixup/nopush commits only. **No shellcheck, linting, or tests in CI**.

### Critical Execution Model
**WARNING**: Framework/plugin files are **sourced** into running process, NOT executed separately.
- **Never use `exit`** in framework/plugin files (kills entire process). Use `return`.
- **No need for `set -euo pipefail`** in sourced files (already set in `apply`).
- **Only `apply` and `firstrun`** scripts execute independently (can use `exit`).

### Execution Flow
1. `./apply` → sources `framework/compat` (ensures Bash 5 + Homebrew) → runs `framework_apply` in subshell
2. `framework_apply` → sudo prompt → `framework_init` → `plugin_run_plugins` → `firstrun_main` → reloads shell
3. Plugins: Implement hooks (`DOTFILES_[PLUGIN]_CONFIG`, `DOTFILES_[PLUGIN]_DEPS`, `dotfiles_[plugin]_apply()`, `dotfiles_[plugin]_prompt_string()`). Run in dependency order.
4. Environments: Resolution order `$current` → `default` → `all`. `homedir` plugin rsyncs `home/` to `$HOME`.

## Build & Validation

### Running
```bash
./apply                          # Standard run
./apply -B                       # Skip brew bundle (faster for testing)
DOTFILES_DEBUG=1 ./apply        # Debug logging
```

**Prerequisites**: macOS, system bash (auto-upgrades), Homebrew (auto-installs), internet (unless `-A`)

**Expected Behavior**: First run prompts for sudo, git config, environment. Subsequent runs use `~/.dotfilesrc`. Ends with shell reload.

### Validation
**NO automated tests exist.** Manual validation only.

**Shellcheck**: Available. Run `shellcheck ./apply` or `shellcheck framework/framework`. Acceptable warnings: SC1091 (sourced files), SC2046 (unquoted substitution in some plugins).

**Manual Testing**:
1. Test on VM/non-primary Mac when possible
2. Backup `~/.dotfilesrc` before testing
3. Use `-B` flag for faster iteration (skip brew updates)
4. Run `./apply` to validate changes
5. Use `DOTFILES_DEBUG=1` to see detailed flow

**Common Issues**:
- **Hang on first run**: Xcode tools installing (wait 10-30 min)
- **Brew formula errors**: Run `brew update` or remove formula
- **custom_environments errors**: Use `-A` flag or manage manually
- **Shell doesn't change**: Close/reopen terminal
- **Permission denied in firstrun**: Grant terminal full disk access in System Preferences

## Development Patterns

### Plugin Naming Conventions
- Dir name = script name (e.g., `git/git`)
- Functions: `dotfiles_[plugin]_[hook]()` (e.g., `dotfiles_git_apply()`)
- Config vars: `DOTFILES_[PLUGIN]_CONFIG_[NAME]` (uppercase)
- Deps: `DOTFILES_[PLUGIN]_DEPS=('other_plugin')`

### Adding a Plugin
```bash
mkdir plugins/myplugin
cat > plugins/myplugin/myplugin << 'EOF'
#!/usr/bin/env bash
export DOTFILES_MYPLUGIN_DEPS=('homebrew')
export DOTFILES_MYPLUGIN_CONFIG=('api_key')
dotfiles_myplugin_prompt_string() { case $1 in api_key) echo 'Enter API key';; esac; }
dotfiles_myplugin_apply() { log "Running myplugin"; }
EOF
echo "brew 'my-tool'" > plugins/myplugin/Brewfile
```

### Helper Functions
- `plugin_config_get 'plugin' 'config_key'` - Get config value
- `environment_get_path "env" "file"` - Get path to env file
- `environment_list_environments` - List active envs
- `environment_map_func function_name` - Run func in each env
- `log "msg"`, `debug "msg"`, `error "msg"` - Logging
- `array_contains arrayname needle` - Check array membership

### Shell Conventions
- Scripts: extensionless, rely on shebang. Use `.sh` ONLY for non-executed files.
- Variables/globals: ALL_CAPS_SNAKE_CASE
- Functions/locals: snake_case
- Quote expansions: `"${var}"`, `"${array[@]}"`
- Bash 4+ features OK (assoc arrays, nameref, etc)

## Framework Modules Reference

- **framework**: Main orchestrator (`framework_apply()`, `framework_init()`)
- **compat**: Ensures Homebrew + Bash 5+ installed
- **config**: Manages `~/.dotfilesrc` (read/write/load)
- **plugin**: Discovery, loading, dependency resolution, execution
- **environment**: Env resolution, path helpers, mapping
- **customize**: Manages custom_environments via `gh` CLI
- **firstrun**: Runs env `firstrun` once (sets FIRSTRUN_APPLIED flag)
- **logging**: `log()`, `debug()`, `error()` functions
- **util**: `array_contains()`, `array_map()`, `function_exists()`, `is_set()`, `remind()`

## Important Plugins

- **homebrew**: Runs `brew bundle` with merged Brewfile from all envs/plugins. Template: `Brewfile.erb` (ERB)
- **homedir**: Rsyncs env `home/` dirs to `$HOME`
- **git**: Prompts for user.name/email, configures git
- **shells**: Adds homebrew bash/zsh to `/etc/shells`, runs `chsh`

## Configuration Files

- `.editorconfig`: 2-space indent, UTF-8, trim trailing whitespace
- `.prettierrc`: 2-space tabs, single quotes
- `.gitignore`: Excludes vim bundles, custom_environments
- `~/.dotfilesrc`: Runtime config (auto-created, stores choices)

## Testing Checklist

1. Always run `./apply` after changes (only real validation)
2. Use `DOTFILES_DEBUG=1 ./apply` for detailed logs
3. Use `-B` flag to skip brew updates (faster iteration)
4. Run shellcheck on modified bash files
5. Test on non-production Mac for significant changes

## Environment Variables

- `DOTFILES_DEBUG=1`: Enable verbose logging
- `DOTFILES_AIRPLANE_MODE=1`: Skip network ops
- `DOTFILES_HOMEBREW_SKIP=1`: Skip brew bundle

## Root Files

- `apply`: Entry point | `README.md`: Docs (111 lines) | `LICENSE`: MIT | `.editorconfig`, `.prettierrc`, `.gitignore`

## Notes

- **No package.json/Gemfile** - deps via Homebrew only
- **No build process** - scripts execute directly
- **No test suite** - manual testing only
- **macOS-specific** - uses `defaults`, `osascript`, won't work on Linux
- **Homebrew required** - auto-installs via pkg if missing
- **ERB templating** only in `Brewfile.erb`

## Trust These Instructions

Follow patterns documented here. Only search/explore if instructions incomplete, incorrect, or implementation details needed. Remember: framework/plugins are sourced, not executed. Test with `./apply`.
