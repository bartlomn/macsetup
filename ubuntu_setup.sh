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
    echo "installing packages"
    sudo apt install -y zsh kitty-terminfo
    echo "Setting up fonts..."
    sudo mkdir "/usr/share/fonts/truetype/MesloLGS NF" && cd "$_" || exit
    sudo curl -L -O "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf" \
    -L -O "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf" \
    -L -O "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf" \
    -L -O "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf"
    cd ~ || exit
 	echo "installing oh-my-zsh"
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
    git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
    # then Set ZSH_THEME="powerlevel10k/powerlevel10k" in ~/.zshrc.
    mv ~/.zshrc ~/.zshrc.bak
    sed 's/ZSH_THEME="robbyrussell"/ZSH_THEME="powerlevel10k\/powerlevel10k"/g' ~/.zshrc.bak > ~/.zshrc
    # and enable  plugins: plugins=(aws docker docker-compose encode64 git helm kubectl zsh-autosuggestions zsh-syntax-highlighting)
    mv ~/.zshrc ~/.zshrc.bak
    sed 's/^plugins=.*$/plugins=(aws docker docker-compose encode64 git helm kubectl zsh-autosuggestions zsh-syntax-highlighting)/g' ~/.zshrc.bak > ~/.zshrc

    echo "Changing default shell..."
    sudo chsh -s "$(which zsh)"
fi

# 
# COCKPIT
#
# This requires switching to NetworkManager first
netplan_file_path="/etc/netplan/01.netcfg.yaml"
if [ ! -f "$netplan_file_path" ]; then
    # Use netowork manager as renderer
    echo -e "network:\n  version: 2\n  renderer: NetworkManager" | sudo tee "$netplan_file_path" > /dev/null
    sudo chmod 600 "$netplan_file_path"
    sudo netplan apply
    # disable networkd
    sudo systemctl stop systemd-networkd
    sudo systemctl disable systemd-networkd
    sudo systemctl mask systemd-networkd

    sudo systemctl stop systemd-networkd-wait-online.service
    sudo systemctl disable systemd-networkd-wait-online.service
    sudo systemctl mask systemd-networkd-wait-online.service
    # enable NetworkManager 
    sudo systemctl unmask NetworkManager
    sudo systemctl enable NetworkManager
    sudo systemctl start NetworkManager
else
    echo "Network manager already configured. No action taken."
fi
# Packages
echo "Installing Cockpit packages"
sudo apt install -y cockpit cockpit-pcp cockpit-machines cockpit-podman
wget https://github.com/ocristopfer/cockpit-sensors/releases/latest/download/cockpit-sensors.deb
sudo apt -f install -y ./cockpit-sensors.deb --fix-broken
rm ./cockpit-sensors.deb
wget https://github.com/45Drives/cockpit-benchmark/releases/download/v2.1.1/cockpit-benchmark_2.1.1-1focal_all.deb
sudo apt -f install -y ./cockpit-benchmark_2.1.1-1focal_all.deb --fix-broken
rm ./cockpit-benchmark_2.1.1-1focal_all.deb
