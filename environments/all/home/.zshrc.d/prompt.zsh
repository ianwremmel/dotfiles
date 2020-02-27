# shellcheck disable

autoload -U colors && colors

local function git_branch_name() {
  local ref
  ref=$(command git symbolic-ref HEAD 2> /dev/null) || \
  ref=$(command git rev-parse --short HEAD 2> /dev/null) || return 0
  echo "${ref#refs/heads/}"
}

local function git_flags() {
  echo "$(command git status 2>/dev/null)" | awk 'BEGIN {r=""}
    /Changes to be committed:/        {r=r "+"}
    /Changes not staged for commit:/  {r=r "!"}
    /Untracked files:/                {r=r "?"}
    END {print r}'
}

local function git_stash_count() {
  local count
  count="$(git stash list | wc -l | sed 's/ *//')"
  if [[ "$count" != "0" ]]; then
    local color
    if [[ $count -gt 5 ]]; then
      color="%{$fg_bold[red]%}"
    fi
    echo " ${color}($count)%{$reset_color%}"
  fi
}

local function git_prompt_info() {
  local EXIT_CODE
  git branch > /dev/null 2>&1
  EXIT_CODE=$?

  if [[ "$EXIT_CODE" == "0" ]]; then
    echo "$(git_branch_name)$(git_flags)$(git_stash_count) "
  fi
}

if [ ! -d "$HOME/powerlevel10k" ]; then
  # Interpret prompt string after each command
  setopt PROMPT_SUBST

  local USER_AT_MACHINE="%n@%M"
  local TIMESTAMP="%T"
  local WORKING_DIRECTORY="%{$fg[cyan]%}%~%{$reset_color%}"
  local SUCCESS_INDICATOR="%(?:%{$fg_bold[green]%}➜ :%{$fg_bold[red]%}➜ )"
  PROMPT='${SUCCESS_INDICATOR} ${TIMESTAMP} ${USER_AT_MACHINE} ${WORKING_DIRECTORY} $(git_prompt_info)%# '
fi
