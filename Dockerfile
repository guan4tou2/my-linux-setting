# Linux Setting Scripts - Docker 測試環境
FROM ubuntu:22.04

# 設定環境變數
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Taipei
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV TEST_ENVIRONMENT=docker
ENV SKIP_NETWORK_TESTS=true

# 建立工作目錄
WORKDIR /opt/linux-setting

# 更新套件列表並安裝基礎依賴
RUN apt-get update && \
    apt-get install -y \
        curl \
        wget \
        git \
        sudo \
        python3 \
        python3-pip \
        python3-venv \
        build-essential \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release \
        tzdata && \
    # 設定時區
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone && \
    # 清理
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 建立測試用戶
RUN useradd -m -s /bin/bash testuser && \
    echo 'testuser ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers && \
    mkdir -p /home/testuser/.local/bin && \
    chown -R testuser:testuser /home/testuser && \
    chown -R testuser:testuser /opt/linux-setting

# 切換到測試用戶
USER testuser

# 複製專案文件
COPY --chown=testuser:testuser . /opt/linux-setting/

# 設定執行權限
RUN find /opt/linux-setting -name "*.sh" -exec chmod +x {} \;

# 設定環境變數
ENV HOME=/home/testuser
ENV PATH="/home/testuser/.local/bin:/home/testuser/.cargo/bin:$PATH"

# 建立必要目錄
RUN mkdir -p $HOME/.config && \
    mkdir -p $HOME/.local/log && \
    mkdir -p $HOME/.local/bin

# 設定預設命令
CMD ["/bin/bash"]

# 健康檢查
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python3 --version || exit 1

# 元數據標籤
LABEL maintainer="Linux Setting Scripts" \
      description="測試環境 for Linux Setting Scripts" \
      version="1.0" \
      architecture="amd64"