# The real shell config, sourced by the stub ~/.zshrc. This repo is public: secrets and
# machine-specific settings go in ~/.zshrc, below the stub line. If `p10k configure` offers to edit
# ~/.zshrc, decline, as this file already loads the prompt.
#
# Nothing here may assume a tool is installed, because tools can be declined or fail to install.

# Homebrew, for shells that did not get it from ~/.zprofile.
if (( ! $+commands[brew] )); then
  for _macsetup_brew in ${(s.:.)${MACSETUP_BREW_PATHS-/opt/homebrew/bin/brew:/usr/local/bin/brew}}; do
    if [[ -x $_macsetup_brew ]]; then
      eval "$($_macsetup_brew shellenv)"
      break
    fi
  done
  unset _macsetup_brew
fi

# fnm stays above instant prompt, as it prints "Using Node ..." in a folder with a .node-version.
if (( $+commands[fnm] )); then
  eval "$(fnm env --use-on-cd)"
fi

# Powerlevel10k instant prompt. Anything that may need console input must go above this block.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export ZSH="$HOME/.oh-my-zsh"

if [[ -d $ZSH/custom/themes/powerlevel10k ]]; then
  ZSH_THEME="powerlevel10k/powerlevel10k"
fi

plugins=(encode64 git)
(( $+commands[aws] )) && plugins+=(aws)
(( $+commands[docker] )) && plugins+=(docker docker-compose)
(( $+commands[helm] )) && plugins+=(helm)
(( $+commands[kubectl] )) && plugins+=(kubectl)
(( $+commands[direnv] )) && plugins+=(direnv)
[[ -d $ZSH/custom/plugins/zsh-autosuggestions ]] && plugins+=(zsh-autosuggestions)
[[ -d $ZSH/custom/plugins/zsh-syntax-highlighting ]] && plugins+=(zsh-syntax-highlighting)

if [[ -r $ZSH/oh-my-zsh.sh ]]; then
  source "$ZSH/oh-my-zsh.sh"
else
  print -r -- "Oh My Zsh is not installed. Run ~/.macsetup/install.sh to set it up."
fi

# Aliases and other overrides go after Oh My Zsh, which would otherwise replace them.
if (( $+commands[eza] )); then
  alias ls="eza --icons --group-directories-first"
fi

if [[ -d ${MACSETUP_APPS_DIR:-/Applications}/Docker.app ]]; then
  export DOCKER_HOST="unix://$HOME/.docker/run/docker.sock"
fi

[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
