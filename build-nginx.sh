#!/usr/bin/env bash
set -euo pipefail

# Versi (default, bisa di-override via env)
: "${NGINX_VERSION:=1.28.0}"
: "${OPENSSL_VERSION:=3.6.0}"

# Prefix instalasi & path kerja
PREFIX="/usr/local/nginx-perf"
WORKDIR="${WORKDIR:-$HOME/nginx-build}"
PKGROOT="${PKGROOT:-$WORKDIR/pkgroot}"

# URL Repo Modul Eksternal (Tanpa GeoIP)
MOD_BROTLI_REPO="https://github.com/google/ngx_brotli.git"
MOD_VTS_REPO="https://github.com/vozlt/nginx-module-vts.git"
MOD_LUA_REPO="https://github.com/openresty/lua-nginx-module.git"
MOD_NDK_REPO="https://github.com/vision5/ngx_devel_kit.git"
MOD_REDIS2_REPO="https://github.com/openresty/redis2-nginx-module.git"
MOD_TLS_DYN_REPO="https://github.com/nginx-modules/ngx_http_tls_dyn_size.git"

echo "[*] Workdir: $WORKDIR"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "[*] Install Build Dependencies (PCRE2 & Modern Libs)"
sudo apt-get update
# Menggunakan libpcre2-dev (PCRE modern) dan libluajit-5.1-dev
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  build-essential git wget ca-certificates \
  libpcre2-dev zlib1g-dev libxslt1-dev libxml2-dev \
  libgd-dev libperl-dev libunwind-dev \
  libluajit-5.1-dev ruby-full

# Install fpm (Packaging tool)
if ! command -v fpm >/dev/null 2>&1; then
  sudo gem install --no-document fpm
fi

echo "[*] Download Nginx ${NGINX_VERSION}"
if [ ! -d "nginx-${NGINX_VERSION}" ]; then
  wget -q "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz"
  tar xf "nginx-${NGINX_VERSION}.tar.gz"
fi

echo "[*] Download OpenSSL ${OPENSSL_VERSION}"
if [ ! -d "openssl-${OPENSSL_VERSION}" ]; then
  wget -q "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz"
  tar xf "openssl-${OPENSSL_VERSION}.tar.gz"
fi

echo "[*] Clone External Modules"
# Hanya clone yang diperlukan
[ -d ngx_brotli ] || git clone --recursive "$MOD_BROTLI_REPO" ngx_brotli
[ -d nginx-module-vts ] || git clone "$MOD_VTS_REPO" nginx-module-vts
[ -d ngx_devel_kit ] || git clone "$MOD_NDK_REPO" ngx_devel_kit
[ -d lua-nginx-module ] || git clone "$MOD_LUA_REPO" lua-nginx-module
[ -d redis2-nginx-module ] || git clone "$MOD_REDIS2_REPO" redis2-nginx-module
[ -d ngx_http_tls_dyn_size ] || git clone "$MOD_TLS_DYN_REPO" ngx_http_tls_dyn_size

cd "nginx-${NGINX_VERSION}"

echo "[*] Configure Nginx"
# Konfigurasi dengan PCRE2 (auto-detect), HTTP/3 Resmi, dan Hardening Flags
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
  --add-module="../ngx_http_tls_dyn_size" \
  --with-cc-opt="-O2 -g -pipe -Wall -Wp,-D_FORTIFY_SOURCE=2 -fexceptions -fstack-protector-strong --param=ssp-buffer-size=4 -grecord-gcc-switches -m64 -mtune=generic" \
  --with-ld-opt="-Wl,-z,relro -Wl,-z,now -Wl,--as-needed"

echo "[*] Build Nginx"
make -j"$(nproc)"

echo "[*] Install to Staging Directory"
rm -rf "$PKGROOT"
make install DESTDIR="$PKGROOT"

# Metadata Paket Deb
PKG_NAME="nginx-perf"
PKG_VERSION="${NGINX_VERSION}-openssl${OPENSSL_VERSION}"
PKG_ARCH="amd64"

echo "[*] Package .deb using fpm"
fpm -s dir -t deb \
  -n "$PKG_NAME" \
  -v "$PKG_VERSION" \
  -a "$PKG_ARCH" \
  --description "High-Perf Nginx ${NGINX_VERSION} (PCRE2) + HTTP/3 + OpenSSL ${OPENSSL_VERSION} + Brotli/Lua/VTS/Redis2" \
  --license "2-clause BSD-like" \
  --url "https://nginx.org/" \
  --maintainer "GitHub Action <action@github.com>" \
  --vendor "Nginx Custom Build" \
  --depends "libc6, libpcre2-8-0, zlib1g, libssl-dev, libluajit-5.1-2" \
  -C "$PKGROOT" \
  .

echo "[*] Build Complete."
