#!/usr/bin/env bash
set -euo pipefail

# Versi
NGINX_VERSION="1.28.0"          # mainline contoh, cek versi terbaru di nginx.org
OPENSSL_VERSION="3.6.0"

# Direktori kerja
WORKDIR="$HOME/nginx-build"
PREFIX="/opt/nginx-perf"

# Modul eksternal (ganti path kalau perlu fork sendiri)
MOD_BROTLI_REPO="https://github.com/google/ngx_brotli.git"
MOD_VTS_REPO="https://github.com/vozlt/nginx-module-vts.git"
MOD_LUA_REPO="https://github.com/openresty/lua-nginx-module.git"
MOD_NDK_REPO="https://github.com/vision5/ngx_devel_kit.git"
MOD_REDIS2_REPO="https://github.com/openresty/redis2-nginx-module.git"
MOD_TLS_DYN_REPO="https://github.com/nginx-modules/ngx_http_tls_dyn_size.git"

mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "[*] Install build dependencies"
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  build-essential git wget ca-certificates \
  libpcre3-dev zlib1g-dev libxslt1-dev libxml2-dev \
  libgd-dev libgeoip-dev libperl-dev \
  libunwind-dev

echo "[*] Download Nginx"
wget -q "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz"
tar xf "nginx-${NGINX_VERSION}.tar.gz"

echo "[*] Download OpenSSL"
wget -q "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz"
tar xf "openssl-${OPENSSL_VERSION}.tar.gz"

echo "[*] Clone external modules"
# Brotli
if [ ! -d ngx_brotli ]; then
  git clone --recursive "$MOD_BROTLI_REPO" ngx_brotli
fi
# VTS
if [ ! -d nginx-module-vts ]; then
  git clone "$MOD_VTS_REPO" nginx-module-vts
fi
# NDK + Lua
if [ ! -d ngx_devel_kit ]; then
  git clone "$MOD_NDK_REPO" ngx_devel_kit
fi
if [ ! -d lua-nginx-module ]; then
  git clone "$MOD_LUA_REPO" lua-nginx-module
fi
# Redis2
if [ ! -d redis2-nginx-module ]; then
  git clone "$MOD_REDIS2_REPO" redis2-nginx-module
fi
# TLS dyn size
if [ ! -d ngx_http_tls_dyn_size ]; then
  git clone "$MOD_TLS_DYN_REPO" ngx_http_tls_dyn_size
fi

cd "nginx-${NGINX_VERSION}"

echo "[*] Configure Nginx"
./configure \
  --prefix="${PREFIX}" \
  --sbin-path="${PREFIX}/sbin/nginx" \
  --conf-path="${PREFIX}/conf/nginx.conf" \
  --pid-path="${PREFIX}/logs/nginx.pid" \
  --lock-path="${PREFIX}/logs/nginx.lock" \
  --http-log-path="${PREFIX}/logs/access.log" \
  --error-log-path="${PREFIX}/logs/error.log" \
  --with-pcre-jit \
  --with-file-aio \
  --with-threads \
  --with-http_ssl_module \
  --with-http_v2_module \
  --with-http_v3_module \
  --with-http_gzip_static_module \
  --with-http_stub_status_module \
  --with-stream \
  --with-stream_ssl_module \
  --with-stream_realip_module \
  --with-openssl="../openssl-${OPENSSL_VERSION}" \
  --with-openssl-opt="no-weak-ssl-ciphers enable-ec_nistp_64_gcc_128" \
  --add-module="../ngx_brotli" \
  --add-module="../nginx-module-vts" \
  --add-module="../ngx_devel_kit" \
  --add-module="../lua-nginx-module" \
  --add-module="../redis2-nginx-module" \
  --add-module="../ngx_http_tls_dyn_size"

echo "[*] Build"
make -j"$(nproc)"

echo "[*] Install to ${PREFIX}"
sudo rm -rf "${PREFIX}"
sudo make install

echo "[*] Archive build artifacts"
cd "${PREFIX}/.."
tar czf "nginx-perf-${NGINX_VERSION}-openssl-${OPENSSL_VERSION}-linux-amd64.tar.gz" "$(basename "${PREFIX}")"

echo "Done."
echo "Artifact: ${PREFIX}/../nginx-perf-${NGINX_VERSION}-openssl-${OPENSSL_VERSION}-linux-amd64.tar.gz"
