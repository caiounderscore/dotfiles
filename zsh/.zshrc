# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time Oh My Zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="robbyrussell"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(
    git
    zsh-autosuggestions
)
source $ZSH/oh-my-zsh.sh

# Every color below is an explicit 256-color (8-bit) code (%F{n}) rather than
# a basic color name (red/green/blue/...). Basic names are remapped by the
# terminal theme (e.g. Dracula turns "blue" into a pale lavender, and "white"
# into the same color as the default foreground) so they can look wrong or
# invisible depending on theme. 256-color codes 16-255 aren't remapped by
# themes, so they render identically everywhere.
#   82  = green (success)      196 = red (failure/error)
#   51  = cyan (path)          33  = blue (git parens)
#   220 = yellow (dirty/slow)  213 = pink (time)

# Two-line prompt. Line 1: cyan current dir + git info (context). Line 2: a
# clean input line — clock (🕒 HH:MM:SS), then the slow-command timer (only
# after a >15s command, in yellow), then ❯, which turns green on success / red
# on the previous command's failure (the exit-status signal the old ➜ carried).
# 🕒 is a wide (2-cell) glyph, so it's wrapped in %2{…%} for correct width calc.
PROMPT='%F{51}%c%f $(git_prompt_info)'
PROMPT+=$'\n'
PROMPT+='%2{🕒%} %F{213}%*%f ${_cmd_time_display}%(?:%B%F{82}:%B%F{196})%1{❯%}%b%f '

# Drop the "git:" label from the prompt's branch segment, e.g. "(main)" instead of "git:(main)"
ZSH_THEME_GIT_PROMPT_PREFIX="%B%F{33}%b(%F{196}"
ZSH_THEME_GIT_PROMPT_SUFFIX="%f "
ZSH_THEME_GIT_PROMPT_DIRTY="%F{33}) %F{220}%1{✗%}%f"
ZSH_THEME_GIT_PROMPT_CLEAN="%F{33})%f"

# Right prompt (attaches to line 1): the previous command's exit code in red
# with a short description — only when it failed (the ❯ on line 2 already turns
# red on failure). The clock and the slow-command timer now live on line 2.
RPROMPT='${_exit_status_display}'

# _exit_status_capture renders the whole red segment itself, e.g.
# "✗ 127 (command not found)", instead of relying on the raw %?/%(?..)
# prompt escapes -- it must run BEFORE any other precmd hook (prepended,
# like oh-my-zsh's own git async hook does), since reading $? is only
# reliable as the very first thing precmd does; later hooks' internal
# commands can silently change it before the prompt is drawn.
typeset -gA _exit_code_desc=(
  1   "general error"
  2   "misuse of shell builtin"
  126 "not executable / permission denied"
  127 "command not found"
  128 "invalid exit argument"
  130 "interrupted (ctrl-c)"
  131 "quit"
  137 "killed"
  139 "segmentation fault"
  143 "terminated"
)
_exit_status_display=""

_exit_status_capture() {
  local ec=$?
  if (( ec == 0 )); then
    _exit_status_display=""
  else
    local desc="${_exit_code_desc[$ec]:-}"
    [[ -z "$desc" ]] && (( ec > 128 )) && desc="signal $(( ec - 128 ))"
    _exit_status_display="%F{196}✗ ${ec}${desc:+ ($desc)} %f"
  fi
}
(( ${precmd_functions[(Ie)_exit_status_capture]} )) || precmd_functions=(_exit_status_capture $precmd_functions)

# Highlight commands that take longer than 15s to run, inline on the input line
# (line 2 of the prompt), between the clock and the ❯.
zmodload zsh/datetime
_cmd_timer_start=0
_cmd_time_display=""

_cmd_timer_preexec() {
  _cmd_timer_start=$EPOCHSECONDS
}

_cmd_timer_precmd() {
  local elapsed=0
  (( _cmd_timer_start > 0 )) && elapsed=$(( EPOCHSECONDS - _cmd_timer_start ))
  _cmd_timer_start=0
  if (( elapsed > 15 )); then
    _cmd_time_display="%F{220}⏱️  ${elapsed}s%f "
  else
    _cmd_time_display=""
  fi
}

autoload -Uz add-zsh-hook
add-zsh-hook preexec _cmd_timer_preexec
add-zsh-hook precmd _cmd_timer_precmd

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='nvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch $(uname -m)"

# Set personal aliases, overriding those provided by Oh My Zsh libs,
# plugins, and themes. Aliases can be placed here, though Oh My Zsh
# users are encouraged to define aliases within a top-level file in
# the $ZSH_CUSTOM folder, with .zsh extension. Examples:
# - $ZSH_CUSTOM/aliases.zsh
# - $ZSH_CUSTOM/macos.zsh
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"
[ -f "$HOME/.exports" ] && source "$HOME/.exports"

# Lazy-load nvm: sourcing nvm.sh eagerly adds ~800ms to every shell startup.
# These stubs load it on first real use, then hand off to the real command.
_nvm_lazy_load() {
  unset -f nvm node npm npx corepack
  mkdir -p "$NVM_DIR"
  # nvm.sh lives in $NVM_DIR with the official installer, but under the Homebrew
  # prefix when installed via `brew install nvm` (which is what the Brewfile
  # does). Source whichever exists — covers Apple Silicon and Intel brew paths.
  local d
  for d in "$NVM_DIR" /opt/homebrew/opt/nvm /usr/local/opt/nvm; do
    [ -s "$d/nvm.sh" ] && { \. "$d/nvm.sh"; break; }
  done
  for d in "$NVM_DIR/bash_completion" /opt/homebrew/opt/nvm/etc/bash_completion.d/nvm /usr/local/opt/nvm/etc/bash_completion.d/nvm; do
    [ -s "$d" ] && { \. "$d"; break; }
  done
}
nvm() { _nvm_lazy_load; nvm "$@"; }
node() { _nvm_lazy_load; node "$@"; }
npm() { _nvm_lazy_load; npm "$@"; }
npx() { _nvm_lazy_load; npx "$@"; }
corepack() { _nvm_lazy_load; corepack "$@"; }

[ -f "$HOME/.aliases" ] && source "$HOME/.aliases"

# Per-machine overrides (proxy, corp PATH, work KUBECONFIG, etc.). Untracked —
# sourced last so it wins. See .zshrc.local.example.
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"

# Keep $? clean for the first prompt: without this, a missing .zshrc.local
# (or any earlier failed check) leaves a stale nonzero status that
# _exit_status_capture misreports as a real command failure.
true
