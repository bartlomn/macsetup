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
    # then Set ZSH_THEME="powerlevel10k/powerlevel10k" in ~/.zshrc.
    mv ~/.zshrc ~/.zshrc.bak
    sed 's/ZSH_THEME="robbyrussell"/ZSH_THEME="powerlevel10k\/powerlevel10k"/g' ~/.zshrc.bak > ~/.zshrc
    # and enable  plugins: plugins=(aws docker docker-compose encode64 git helm kubectl zsh-autosuggestions zsh-syntax-highlighting)
    mv ~/.zshrc ~/.zshrc.bak
    sed 's/^plugins=.*$/plugins=(aws docker docker-compose encode64 git helm kubectl zsh-autosuggestions zsh-syntax-highlighting)/g' ~/.zshrc.bak > ~/.zshrc
    # Download required fonts
    cd /Library/Fonts || exit
    curl -L -O "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf" \
    -L -O "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf" \
    -L -O "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf" \
    -L -O "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf"
    cd ~ || exit
fi

# 
# APPS
# 

echo "Installing docker"
brew install --appdir="/Applications" --cask docker

echo "Installing commandline apps..."
brew install \
aws-cdk \
awscli \
git \
fnm \
helm \
k9s \
kubectl

# Add fnm to the zshrc file
echo "Adding fnm to zshrc..."
# Define the lines to be added
fnm_line1="# Enable FNM"
fnm_line2='eval "$(fnm env --use-on-cd)"'

# File to update
zshrc_file="$HOME/.zshrc"

# Check if the second line is already in the file
if ! grep -qF "$fnm_line2" "$zshrc_file"; then
    # If it's not found, add the lines at the beginning of the file
    echo -e "$fnm_line1\n$fnm_line2\n$(cat "$zshrc_file")" > "$zshrc_file"
    echo "Added FNM to $zshrc_file."
else
    echo "FNM already present in $zshrc_file."
fi

echo "Installing Browsers..."
brew install --appdir="/Applications" --cask arc
brew install --appdir="/Applications" --cask firefox
brew install --appdir="/Applications" --cask google-chrome
brew install --appdir="/Applications" --cask microsoft-edge

echo "Installing MS Office..."
brew install --appdir="/Applications" --cask microsoft-outlook
brew install --appdir="/Applications" --cask microsoft-word
brew install --appdir="/Applications" --cask microsoft-excel
brew install --appdir="/Applications" --cask microsoft-powerpoint

echo "Installing Other apps..."
brew install --appdir="/Applications" --cask aldente
brew install --appdir="/Applications" --cask alfred
brew install --appdir="/Applications" --cask balenaetcher
brew install --appdir="/Applications" --cask diffmerge
brew install --appdir="/Applications" --cask evernote
brew install --appdir="/Applications" --cask kitty
brew install --appdir="/Applications" --cask sourcetree
brew install --appdir="/Applications" --cask spotify
brew install --appdir="/Applications" --cask visual-studio-code
brew install --appdir="/Applications" --cask vlc
