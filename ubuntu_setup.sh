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
# APT
#
echo "Performing apt upgrades..."
sudo apt update
sudo apt upgrade -y

# 
# OH MY ZSH
# 
if [ -d ~/.oh-my-zsh ]; then
	echo "oh-my-zsh is already installed"
 else
    echo "Setting up fonts..."
    sudo mkdir /usr/share/fonts/truetype/MesloLGS NF && cd "$_" || exit
    sudo curl -L -O "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf" \
    -L -O "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf" \
    -L -O "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf" \
    -L -O "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf"
    cd ~ || exit
 	# echo "installing oh-my-zsh"
    # sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    # git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
    # git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
    # git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
    # # then Set ZSH_THEME="powerlevel10k/powerlevel10k" in ~/.zshrc.
    # mv ~/.zshrc ~/.zshrc.bak
    # sed 's/ZSH_THEME="robbyrussell"/ZSH_THEME="powerlevel10k\/powerlevel10k"/g' ~/.zshrc.bak > ~/.zshrc
    # # and enable  plugins: plugins=(aws docker docker-compose encode64 git helm kubectl zsh-autosuggestions zsh-syntax-highlighting)
    # mv ~/.zshrc ~/.zshrc.bak
    # sed 's/^plugins=.*$/plugins=(aws docker docker-compose encode64 git helm kubectl zsh-autosuggestions zsh-syntax-highlighting)/g' ~/.zshrc.bak > ~/.zshrc

    # echo "Changing default shell..."
    # chsh -s "$(which zsh)"
fi

