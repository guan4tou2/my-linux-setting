# Linux 環境設定腳本

這個腳本可以幫助你快速設定 Linux 開發環境，包括：
- 基礎工具
- 終端機設定（zsh + oh-my-zsh + powerlevel10k）
- 開發工具（neovim + lazyvim + lazygit）
- 系統監控工具
- Python 開發環境
- Docker 相關工具

## 快速安裝

使用以下命令進行安裝：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/guan4tou2/my-linux-setting/main/install.sh)"
```

## 自定義安裝

如果你想使用自己的配置，有兩種方式：

1. 通過環境變數設定：
```bash
export REPO_URL="你的倉庫URL"
export SCRIPTS_URL="$REPO_URL/scripts"
export P10K_CONFIG_URL="$REPO_URL/.p10k.zsh"
bash -c "$(curl -fsSL https://raw.githubusercontent.com/guan4tou2/my-linux-setting/main/install.sh)"
```

2. 克隆後修改：
```bash
git clone https://github.com/guan4tou2/my-linux-setting.git
cd my-linux-setting
# 編輯 install.sh 中的 REPO_URL 等變數
bash install.sh
```

## 配置文件位置

- zsh：`~/.zshrc`
- powerlevel10k：`~/.p10k.zsh`
- neovim：`~/.config/nvim`

## 備份

所有原始配置文件都會被備份到：`~/.config/linux-setting-backup/`

## 日誌

安裝日誌保存在：`~/.local/log/linux-setting/`
