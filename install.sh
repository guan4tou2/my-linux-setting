#!/bin/bash

ARCH=$(uname -m)
case $ARCH in
    i386|i686|armv6*|armv7*|aarch64*) ARCH=match ;;
    *) ARCH=$(uname -m) ;;
esac

# time
echo  "\033[36m##########\nsetting date\n##########\n\033[m"
sudo timedatectl set-timezone "Asia/Taipei"
timedatectl

# package
echo  "\033[36m##########\ninstall apt\n##########\n\033[m"
sudo apt update
sudo apt install -y  lnav zsh fail2ban ca-certificates curl gnupg nodejs npm python-is-python3 unzip cargo gem fd-find ripgrep  net-tools iftop tldr fzf ncdu logwatch \
                      lua5.4 stress
sudo pip install s-tui --break-system-packages

# fail2bam
echo  "\033[36m##########\nsetting fail2ban\n##########\n\033[m"
sudo systemctl start fail2ban

# oh-my-zsh
echo  "\033[36m##########\ninstall oh-my-zsh\n##########\n\033[m"
sudo -k chsh -s $(command -v zsh) "$USER"
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"  "" --skip-chsh

sudo git clone https://github.com/romkatv/powerlevel10k.git $ZSH_CUSTOM/themes/powerlevel10k
sudo git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
sudo git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
sudo git clone https://github.com/agkozak/zsh-z $ZSH_CUSTOM/plugins/zsh-z
sed -i -e 's/ZSH_THEME="robbyrussell"/ZSH_THEME="powerlevel10k\/powerlevel10k"/g' ~/.zshrc
sed -i -e 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-z)/g' ~/.zshrc

# p10k
echo  "\033[36m##########\nsetting p10k\n##########\n\033[m"
wget https://raw.githubusercontent.com/guan4tou2/my-linux-setting/main/.p10k.zsh -O ~/.p10k.zsh

# fonts
echo  "\033[36m##########\ninstall fonts\n##########\n\033[m"
sudo add-apt-repository universe
sudo apt install -y fonts-firacode

# thefuck
echo  "\033[36m##########\ninstall thefuck\n##########\n\033[m"
sudo apt update
sudo apt install -y python3-dev python3-pip python3-setuptools
sudo -H pip3 install thefuck --break-system-packages
echo 'export PATH="$PATH:~/.local/bin"' >> ~/.zshrc
echo 'eval $(thefuck --alias)' >> ~/.zshrc

# nvim
echo  "\033[36m##########\ninstall nvim\n##########\n\033[m"
sudo snap install nvim --classic --channel=latest/edge
sudo apt install -y python3-neovim python3-venv
git clone https://github.com/LazyVim/starter ~/.config/nvim
rm -rf ~/.config/nvim/.git
sudo npm install -g neovim
echo 'alias nv="nvim"' >> ~/.zshrc

# lazygit
echo  "\033[36m##########\ninstall lazygit\n##########\n\033[m"
LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
tar xf lazygit.tar.gz lazygit
sudo install lazygit /usr/local/bin
rm -rf lazygit
rm lazygit.tar.gz

# docker
echo  "\033[36m##########\ninstall docker\n##########\n\033[m"
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-compose
sudo groupadd -f docker
sudo usermod -aG docker $USER

# lazydocker
echo  "\033[36m##########\ninstall lazydocker\n##########\n\033[m"
curl https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | bash

. ~/.zshrc

echo  "\033[36m########## Done! ##########\033[m"
