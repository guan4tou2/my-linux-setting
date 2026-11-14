#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
export CONTAINER_NAME="${CONTAINER_NAME:-ci-remote-install-$$}"
./docker-test.sh build
# run 的最後一個指令就是 docker run；保留容器內的結束碼。
./docker-test.sh run 'bash tests/simulate_remote_install.sh'
