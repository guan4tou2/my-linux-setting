#!/bin/sh

# time
echo  "\033[36m##########\ninstall date\n##########\n\033[m"
sudo timedatectl set-timezone "Asia/Taipei"

# package
echo  "\033[36m##########\ninstall apt\n##########\n\033[m"
sudo apt update
sudo apt install -y  lnav zsh fail2ban ca-certificates curl gnupg nodejs npm python-is-python3 unzip cargo gem fd-find ripgrep  net-tools iftop tldr fzf ncdu logwatch


# oh-my-zsh
echo  "\033[36m##########\ninstall oh-my-zsh\n##########\n\033[m"
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

sudo apt update
git clone https://github.com/romkatv/powerlevel10k.git $ZSH_CUSTOM/themes/powerlevel10k
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/agkozak/zsh-z $ZSH_CUSTOM/plugins/zsh-z
# ZSH_THEME="powerlevel10k/powerlevel10k"
sed -i -e 's/ZSH_THEME="robbyrussell"/ZSH_THEME="powerlevel10k\/powerlevel10k"/g' ~/.zshrc
# plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-z)
sed -i -e 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-z)/g' ~/.zshrc


# fonts
echo  "\033[36m##########\ninstall fonts\n##########\n\033[m"
sudo add-apt-repository universe
sudo apt install -y fonts-firacode

# thefuck
echo  "\033[36m##########\ninstall thefuck\n##########\n\033[m"
sudo apt update
sudo apt install -y python3-dev python3-pip python3-setuptools
sudo -H pip3 install thefuck
echo 'export PATH="$PATH:~/.local/bin"' >> ~/.zshrc
echo 'eval $(thefuck --alias)' >> ~/.zshrc
source ~/.zshrc

# nvim
echo  "\033[36m##########\ninstall nvim\n##########\n\033[m"
sudo snap install nvim --classic --channel=latest/edge
sudo apt install -y python3-neovim python3-venv
git clone https://github.com/LazyVim/starter ~/.config/nvim
rm -rf ~/.config/nvim/.git
npm install -g neovim

# lazygit
echo  "\033[36m##########\ninstall lazygit\n##########\n\033[m"
LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
tar xf lazygit.tar.gz lazygit
sudo install lazygit /usr/local/bin

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
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo groupadd -f docker
sudo usermod -aG docker $USER
newgrp docker

# lazydocker
echo  "\033[36m##########\ninstall lazydocker\n##########\n\033[m"
curl https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | bash
sudo mv .local/bin/lazydocker /usr/bin/ 

source ~/.zshrc
