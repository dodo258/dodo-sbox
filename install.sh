#!/usr/bin/env bash
# Bootstrap only: download the complete release before running it.
bootstrap() (
    set -euo pipefail
    [[ $(uname -s) == Linux && $EUID == 0 ]] || { echo '请在 Debian/Ubuntu 服务器上以 root 运行。' >&2; exit 1; }
    umask 077
    local work base expected actual
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    base=https://github.com/dodo258/dodo-sbox/releases/latest/download
    download() {
        if command -v curl >/dev/null; then curl --proto '=https' --tlsv1.2 -fLsS --retry 2 --connect-timeout 15 --max-time 180 "$1" -o "$2"
        elif command -v wget >/dev/null; then wget --https-only -q --timeout=30 --tries=3 -O "$2" "$1"
        else echo '缺少下载工具，请先安装 curl 或 wget。' >&2; return 1; fi
    }
    echo '正在下载 dodo-sbox 最新发布版…'
    download "$base/dodo-sbox" "$work/dodo-sbox"
    download "$base/SHA256SUMS" "$work/SHA256SUMS"
    expected=$(awk '$2=="dodo-sbox" {print $1}' "$work/SHA256SUMS")
    [[ $expected =~ ^[a-f0-9]{64}$ ]] || { echo '发布校验信息异常，停止安装。' >&2; exit 1; }
    actual=$(sha256sum "$work/dodo-sbox"); actual=${actual%% *}
    [[ $actual == "$expected" ]] || { echo '文件校验失败，请重试。未执行安装包。' >&2; exit 1; }
    bash -n "$work/dodo-sbox"
    echo '校验通过，正在打开管理菜单。'
    bash "$work/dodo-sbox" "$@"
)
bootstrap "$@"
