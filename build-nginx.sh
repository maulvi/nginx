#!/usr/bin/env bash
set -euo pipefail

# Versi default (bisa di-override via ENV)
: "${NGINX_VERSION:=1.28.0}"
: "${OPENSSL_VERSION:=3.6.0}"

# Path build & instalasi
PREFIX="/usr/local/nginx-perf"
WORKDIR="${WORKDIR:-$HOME/nginx-build}"
PKGROOT="${PKGROOT:-$WORKDIR/pkgroot}"
DOWNLOAD_CACHE="${DOWNLOAD_CACHE:-$WORKDIR/downloads}"

# Repo modul eksternal
MOD_BROTLI_REPO="https://github.com/google/ngx_brotli.git"
MOD_VTS_REPO="https://github.com/vozlt/nginx-module-vts.git"
MOD_LUA_REPO="https://github.com/openresty/lua-nginx-module.git"
MOD_NDK_REPO="https://github.com/vision5/ngx_devel_kit.git"
MOD_REDIS2_REPO="https://github.com/openresty/redis2-nginx-module.git"

echo "[*] Setup direktori: $WORKDIR"
mkdir -p "$WORKDIR" "$DOWNLOAD_CACHE"
cd "$WORKDIR"

echo "[*] Install dependencies build & packaging"
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  build-essential git wget ca-certificates \
  libpcre2-dev zlib1g-dev libxslt1-dev libxml2-dev \
  libgd-dev libperl-dev libunwind-dev \
  libluajit-5.1-dev ruby-full ccache

# Gunakan ccache bila tersedia
CC_CMD="gcc"
if command -v ccache >/dev/null 2>&1; then
  echo "[*] CCache aktif"
  CC_CMD="ccache gcc"
  export CCACHE_DIR="$HOME/.ccache"
  export CCACHE_COMPRESS=1
fi

# fpm untuk build .deb
if ! command -v fpm >/dev/null 2>&1; then
  sudo gem install --no-document fpm
fi

download_src() {
  local url="$1"
  local file="$2"
  if [ ! -f "$DOWNLOAD_CACHE/$file" ]; then
    echo "Downloading $file ..."
    wget -q -O "$DOWNLOAD_CACHE/$file" "$url"
  else
    echo "Using cached $file"
  fi
  tar xf "$DOWNLOAD_CACHE/$file" -C "$WORKDIR"
}

echo "[*] Download source Nginx & Open
