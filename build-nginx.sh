#!/usr/bin/env bash
set -euo pipefail

# --- Versi default (bisa di-override via ENV) ---
: "${NGINX_VERSION:=1.28.0}"        # stable [web:124]
: "${OPENSSL_VERSION:=3.6.0}"

# --- Path build & instalasi ---
PREFIX="/usr/local/nginx-perf"
WORKDIR="${WORKDIR:-$HOME/nginx-build}"
PKGROOT="${PKGROOT:-$WORKDIR/pkgroot}"
DOWNLOAD_CACHE="${DOWNLOAD_CACHE:-$WORKDIR/downloads}"

# --- Repo modul eksternal ---
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

# CCache untuk percepat build ulang
CC_CMD="gcc"
if command -v ccache >/dev/null 2>&1; then
  echo "[*] CCache aktif"
  CC_CMD="ccache gcc"
  export CCACHE_DIR="$HOME/.ccache"
  export CCACHE_COMPRESS=1
fi

# fpm untuk bikin .deb
if ! command -v fpm >/dev/null 2>&1; then
  sudo gem install --no-document fpm
fi

# --- helper download dengan cache ---
download_src() {
  local url=$1
  local file=$2
  if [ ! -f "$DOWNLOAD_CACHE/$file" ]; then
    echo "Downloading $file ..."
    wget -q -O "$DOWNLOAD_CACHE/$file" "$url"
  else
    echo "Using cached $file"
  fi
  tar xf "$DOWNLOAD_CACHE/$file" -C "$WORKDIR"
}

echo "[*] Download source Nginx & OpenSSL"
if [ ! -d "nginx-${NGINX_VERSION}" ]; then
  download_src "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" "nginx-${NGINX_VERSION}.tar.gz"
fi

if [ ! -d "openssl-${OPENSSL_VERSION}" ]; then
  download_src "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz" "openssl-${OPENSSL_VERSION}.tar.gz"
fi

echo "[*] Clone modul eksternal (shallow)"
rm -rf ngx_brotli nginx-module-vts ngx_devel_kit lua-nginx-module redis2-nginx-module

git clone --depth 1 --recursive "$MOD_BROTLI_REPO" ngx_brotli
git clone --depth 1 "$MOD_VTS_REPO" nginx-module-vts
git clone --depth 1 "$MOD_NDK_REPO" ngx_devel_kit
git clone --depth 1 "$MOD_LUA_REPO" lua-nginx-module
git clone --depth 1 "$MOD_REDIS2_REPO" redis2-nginx-module

cd "nginx-${NGINX_VERSION}"

echo "[*] Konfigurasi environment LuaJIT"
LUAJIT_INC_PATH=$(find /usr/include -maxdepth 1 -type d -name "luajit-2*" | head -n 1 || true)
if [ -z "$LUAJIT_INC_PATH" ]; then
  echo "Error: Header LuaJIT tidak ditemukan di /usr/include/luajit-2*"
  exit 1
fi
export LUAJIT_LIB="/usr/lib/x86_64-linux-gnu"
export LUAJIT_INC="$LUAJIT_INC_PATH"

echo "[*] ./configure Nginx ${NGINX_VERSION} + OpenSSL ${OPENSSL_VERSION}"
./configure \
  --prefix="${PREFIX}" \
  --sbin-path="${PREFIX}/sbin/nginx
