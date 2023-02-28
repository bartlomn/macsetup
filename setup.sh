#!/usr/bin/env bash

# 
# SUDO
# 

# Ask for the administrator password upfront.
sudo -v

# Keep-alive: update existing `sudo` time stamp until the script has finished.
while true; do
    sudo -n true
    sleep 60
    kill -0 "$$" || exit
done 2>/dev/null &


# 
# DOCK CONFIG
#

# Autohide and magnification for dock
osascript -e "tell application \"System Events\" to set the autohide of the dock preferences to true"
osascript -e "tell application \"System Events\" to set the magnification of the dock preferences to true"

# When you quit an app, the icon will disappear from your Dock
defaults write com.apple.dock static-only -bool true

# Show hidden apps
defaults write com.apple.dock showhidden -bool true

# 
# FINDER CONFIG
#

# Show Library Folder in Finder
chflags nohidden ~/Library

# Show Hidden Files in Finder
defaults write com.apple.finder AppleShowAllFiles -bool true

# Show all extensions in Finder
defaults write com.apple.finder AppleShowAllExtensions -bool true

# Show Path Bar in Finder
defaults write com.apple.finder ShowPathbar -bool true

# Show Status Bar in Finder
defaults write com.apple.finder ShowStatusBar -bool true

# Set the default view style to detailed list
defaults write com.apple.finder FXPreferredViewStyle Nlsv

# 
# Homebrew
# 

# Check for Homebrew, and then install it
if test ! "$(which brew)"; then
    echo "Installing homebrew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    echo '# Set PATH, MANPATH, etc., for Homebrew.' >> ~/.zprofile
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
    source ~/.zprofile
    eval "$(/opt/homebrew/bin/brew shellenv)"
    echo "Homebrew installed successfully"
else
    echo "Homebrew already installed!"
fi

# Install XCode Command Line Tools
echo 'Checking to see if XCode Command Line Tools are installed...'
brew config

# Updating Homebrew.
echo "Updating Homebrew..."
brew update

# Upgrade any already-installed formulae.
echo "Upgrading Homebrew..."
brew upgrade

# 
# OH MY ZSH
# 
if [ -d ~/.oh-my-zsh ]; then
	echo "oh-my-zsh is already installed"
 else
 	echo "installing oh-my-zsh"
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
    git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
    # then manually Set ZSH_THEME="powerlevel10k/powerlevel10k" in ~/.zshrc.
    # and enable  plugins: plugins=(aws docker docker-compose encode64 git helm kubectl zsh-autosuggestions zsh-syntax-highlighting)
fi

# 
# APPS
# 

# Install command line apps
# echo "Installing commandline apps..."
# brew install \
# git \
# z \
# fnm \
# kubectl \
# helm

# Misc Apps
# echo "Installing Browsers..."
# brew install --appdir="/Applications" --cask arc
# brew install --appdir="/Applications" --cask firefox
# brew install --appdir="/Applications" --cask google-chrome
# brew install --appdir="/Applications" --cask microsoft-edge

# echo "Installing MS Office..."
# brew install --appdir="/Applications" --cask microsoft-outlook
# brew install --appdir="/Applications" --cask microsoft-word
# brew install --appdir="/Applications" --cask microsoft-excel

# echo "Installing Other apps..."
# brew install --appdir="/Applications" --cask alfred
# brew install --appdir="/Applications" --cask authy
# brew install --appdir="/Applications" --cask diffmerge
# brew install --appdir="/Applications" --cask docker
# brew install --appdir="/Applications" --cask evernote
# brew install --appdir="/Applications" --cask franz
# brew install --appdir="/Applications" --cask hyper
# brew install --appdir="/Applications" --cask licecap
# brew install --appdir="/Applications" --cask postman
# brew install --appdir="/Applications" --cask sourcetree
# brew install --appdir="/Applications" --cask spotify
# brew install --appdir="/Applications" --cask visual-studio-code
# brew install --appdir="/Applications" --cask vlc
