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
echo "##########################"
echo "Performing apt upgrades..."
echo "##########################"
sudo apt update
sudo apt upgrade -y

# 
# OH MY ZSH
# 
if [ -d ~/.oh-my-zsh ]; then
	echo "oh-my-zsh is already installed"
 else
    echo "##########################"
    echo "installing zsh packages"
    echo "##########################"
    sudo apt install -y zsh kitty-terminfo
    echo "Setting up fonts..."
    zsh_fonts_dir="/usr/share/fonts/truetype/MesloLGS NF"
    sudo mkdir "$zsh_fonts_dir" && cd "$zsh_fonts_dir"
    sudo curl -L -O "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf" \
    -L -O "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf" \
    -L -O "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf" \
    -L -O "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf"
    cd ~
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

    # echo "Changing default shell..."
    # sudo chsh -s "$(which zsh)"
fi


# Install 7zip if not present
if ! dpkg -l | grep -q "^ii\W*7zip"; then
    echo "Installing 7zip"
    sudo apt install -y 7zip
else
    echo "7zip is already installed. Skipping installation."
fi

# Install podman if not present
if ! dpkg -l | grep -q "^ii\W*podman"; then
    echo "Installing podman"
    sudo apt install -y podman
else
    echo "Podman is already installed. Skipping installation."
fi

# 
# COCKPIT
#

# This requires switching to NetworkManager first
netplan_file_path="/etc/netplan/01.netcfg.yaml"
if [ ! -f "$netplan_file_path" ]; then
    # install packages
    sudo apt install -y network-manager net-tools
    # Use netowork manager as renderer
    printf "network:\n  version: 2\n  renderer: NetworkManager" | sudo tee "$netplan_file_path" > /dev/null
    sudo chmod 600 "$netplan_file_path"
    sudo netplan apply
    # disable networkd wait-online target
    sudo systemctl stop systemd-networkd-wait-online.service
    sudo systemctl disable systemd-networkd-wait-online.service
    sudo systemctl mask systemd-networkd-wait-online.service
else
    echo "Network manager already configured. No action taken."
fi

# Install cockpit if not present
if ! dpkg -l | grep -q "^ii.*cockpit"; then
    echo "Installing Cockpit packages"
    sudo apt install -y cockpit cockpit-pcp cockpit-machines cockpit-podman virt-manager
    wget https://github.com/ocristopfer/cockpit-sensors/releases/latest/download/cockpit-sensors.deb
    sudo apt -f install -y ./cockpit-sensors.deb --fix-broken
    rm ./cockpit-sensors.deb

    # Change cockpit port from default 9090 to 443
    # Variables for directories and file paths
    COCKPIT_SOCKET_TARGET_DIR="/etc/systemd/system/cockpit.socket.d"
    COCKPIT_SOCKET_CONFIG_FILE="${COCKPIT_SOCKET_TARGET_DIR}/listen.conf"
    # Create the directory if it doesn't exist
    if [ ! -d "$COCKPIT_SOCKET_TARGET_DIR" ]; then
    echo "Creating directory: $COCKPIT_SOCKET_TARGET_DIR"
    sudo mkdir -p "$COCKPIT_SOCKET_TARGET_DIR"
    fi
    # Create or overwrite the file with the specified content
    echo "Writing to file: $COCKPIT_SOCKET_CONFIG_FILE"
    sudo bash -c "cat > $COCKPIT_SOCKET_CONFIG_FILE" << 'EOF'
[Socket]
ListenStream=
ListenStream=443
EOF
    # Reload services
    sudo systemctl daemon-reload
    sudo systemctl restart cockpit.socket

else
    echo "Cockpit is already installed. Skipping installation."
fi


# Install certbot if not present
if ! dpkg -l | grep -q "^ii\W*certbot"; then
    echo "Installing certbot"
    sudo apt install -y certbot python3-certbot-dns-cloudflare
else
    echo "Certbot is already installed. Skipping installation."
fi


#
# Unattended upgrades config
#

# Define the local and remote files
UUPGR_LOCAL="/etc/apt/apt.conf.d/50unattended-upgrades"
UUPGR_REMOTE="https://raw.githubusercontent.com/bartlomn/macsetup/main/50unattended-upgrades.conf"

# Check if the local file starts with the specific comment
if ! grep -q '^// bnowak custom config' "$UUPGR_LOCAL"; then
    # Download the new configuration file
    curl -fsSL "$UUPGR_REMOTE" -o /tmp/50unattended-upgrades.conf

    # Replace the contents of the local file with the downloaded file
    sudo cat /tmp/50unattended-upgrades.conf | sudo tee "$UUPGR_LOCAL" > /dev/null
    
    # Generate a random time between 02:00 and 05:00
    RANDOM_HOUR=$((RANDOM % 4 + 2))  # This will give a value between 2 and 5
    RANDOM_MINUTE=$((RANDOM % 60))   # Random minute between 0 and 59
    
    # Format the time for the Unattended-Upgrade setting
    RANDOM_TIME=$(printf "%02d:%02d" "$RANDOM_HOUR" "$RANDOM_MINUTE")
    
    # Replace the line for Automatic-Reboot-Time with the random time
    sudo sed -i "s/Unattended-Upgrade::Automatic-Reboot-Time \".*\";/Unattended-Upgrade::Automatic-Reboot-Time \"$RANDOM_TIME\";/" "$UUPGR_LOCAL"
    sudo rm /tmp/50unattended-upgrades.conf
    echo "Successfully updated $UUPGR_LOCAL with new content and randomized the reboot time to $RANDOM_TIME."
else
    echo "$UUPGR_LOCAL already contains the custom config. No changes made."
fi