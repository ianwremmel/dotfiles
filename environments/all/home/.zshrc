# shellcheck disable

if [ -d "$HOME/powerlevel10k" ]; then
  # Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
  # Initialization code that may require console input (password prompts, [y/n]
  # confirmations, etc.) must go above this block; everything else may go below.
  if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
    source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
  fi
fi

# Load additional zsh config
for FILE ($HOME/.zshrc.d/*); do
  source $FILE
done

# Use case-sensitive tab completion
CASE_SENSITIVE="true"

# Specify where shell history gets written
HISTFILE=~/.zsh_history

# Don't store duplicates
HISTDUPE=erase

# Apparently unlimited history isn't a thing in zsh, so store a lot
HISTSIZE=10000
SAVEHIST=10000

# Don't overwrite when multiple terminals are in use
setopt appendhistory

# Share history across terminals
setopt sharehistory

# Append immediately, not on shell exit
setopt incappendhistory
# support **/* globs
setopt extendedglob

# error on unmatched globs
setopt nomatch

# unbreak git caret selector caused by 'nomatch'
setopt no_nomatch

# Don't beep
unsetopt autocd beep notify

# Use emacs keybindings (because it turns out that's what I've already been using for years)
bindkey -e

# Enable shell completion
zstyle :compinstall filename "$HOME/.zshrc"
autoload -Uz compinit
compinit

if [ -d "$HOME/powerlevel10k" ]; then
  source ~/powerlevel10k/powerlevel10k.zsh-theme
fi

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
