#!/usr/bin/env bash
set -euo pipefail
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:/usr/local/bin:$PATH"
missing=0
check() {
    local label="$1"
    shift
    if "$@"; then
        printf '通過 | %s\n' "$label"
    else
        printf '缺少 | %s\n' "$label"
        missing=$((missing + 1))
    fi
}
command_exists() { command -v "$1" >/dev/null 2>&1; }
alternative() { command_exists "$1" || command_exists "$2"; }
version_works() { "$1" --version; }
login_zsh() {
    local entry shell
    entry=$(getent passwd "$(id -un)") || return 1
    shell=${entry##*:}
    printf '登入 shell：%s\n' "$shell"
    [[ "$shell" == */zsh ]]
}
if [ "$#" -eq 0 ]; then
    echo '請指定已安裝的模組 id。' >&2
    exit 1
fi
printf '結果 | 檢查項目\n'
for module in "$@"; do
    case "$module" in
        base)
            for cmd in git curl rg fzf lsd tldr; do check "$module/$cmd" command_exists "$cmd"; done
            check 'base/fd 或 fdfind' alternative fd fdfind
            check 'base/bat 或 batcat' alternative bat batcat
            for cmd in lsd tldr; do check "$module/$cmd 可執行" version_works "$cmd"; done
            ;;
        python)
            for cmd in python3 uv; do check "$module/$cmd" command_exists "$cmd"; done
            ;;
        terminal)
            check 'terminal/zsh' command_exists zsh
            check 'terminal/oh-my-zsh' test -d "$HOME/.oh-my-zsh"
            check 'terminal/powerlevel10k' test -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
            check 'terminal/.p10k.zsh' test -f "$HOME/.p10k.zsh"
            check 'terminal/ZSH_THEME' grep -Eq "^[[:space:]]*ZSH_THEME=[\"']?powerlevel10k/powerlevel10k([\"']|[[:space:]]|$)" "$HOME/.zshrc"
            check 'terminal/登入 shell' login_zsh
            ;;
        dev)
            for cmd in nvim lazygit node cargo; do check "$module/$cmd" command_exists "$cmd"; done
            check 'dev/lazygit 可執行' version_works lazygit
            ;;
        monitoring)
            for cmd in htop btop iftop; do check "$module/$cmd" command_exists "$cmd"; done
            ;;
        *) check "未知模組：$module" false ;;
    esac
done
printf '缺少項目總數：%d\n' "$missing"
[ "$missing" -eq 0 ]
