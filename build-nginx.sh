#!/usr/bin/env bash
set -euo pipefail

# --- Konfigurasi Versi ---
: "${NGINX_VERSION:=1.28.0}"
: "${OPENSSL_VERSION:=3.6.0}"

# --- Konfigurasi Path ---
PREFIX="/usr/local/nginx-perf"
WORKDIR="${WORKDIR:-$HOME/nginx-build}"
PKGROOT="${PKGROOT:-$WORKDIR/pkgroot}"
DOWNLOAD_CACHE="${DOWNLOAD_CACHE:-$WORKDIR/downloads}"

# --- Repo Modul Eksternal ---
MOD_BROTLI_REPO="https://github.com/google/ngx_brotli.git"
MOD_VTS_REPO="https://github.com/vozlt/nginx-module-vts.git"
MOD_LUA_REPO="https://github.com/openresty/lua-nginx-module.git"
MOD_NDK_REPO="https://github.com/vision5/ngx_devel_kit.git"
MOD_REDIS2_REPO="https://github.com/openresty/redis2-nginx-module.git"
MOD_TLS_DYN_REPO="https://github.com/nginx-modules/ngx_http_tls_dyn_size.git"

echo "[*] Setup Direktori: $WORKDIR"
mkdir -p "$WORKDIR" "$DOWNLOAD_CACHE"
cd "$WORKDIR"

echo "[*] Install Dependencies"
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  build-essential git wget ca-certificates \
  libpcre2-dev zlib1g-dev libxslt1-dev libxml2-dev \
  libgd-dev libperl-dev libunwind-dev \
  libluajit-5.1-dev ruby-full ccache

# Deteksi ccache untuk mempercepat build ulang
CC_CMD="gcc"
if command -v ccache >/dev/null 2>&1; then
  echo "[*] CCache aktif."
  CC_CMD="ccache gcc"
  export CCACHE_DIR="$HOME/.ccache"
  export CCACHE_COMPRESS=1
fi

# Install fpm jika belum ada
if ! command -v fpm >/dev/null 2>&1; then
  sudo gem install --no-document fpm
fi

# --- Fungsi Download dengan Cache ---
download_src() {
  local url=$1
  local file=$2
  if [ ! -f "$DOWNLOAD_CACHE/$file" ]; then
    echo "Downloading $file..."
    wget -q -O "$DOWNLOAD_CACHE/$file" "$url"
  else
    echo "Menggunakan cache: $file"
  fi
  # Ekstrak ke workdir
  tar xf "$DOWNLOAD_CACHE/$file" -C "$WORKDIR"
}

echo "[*] Download Source Code"
if [ ! -d "nginx-${NGINX_VERSION}" ]; then
  download_src "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" "nginx-${NGINX_VERSION}.tar.gz"
fi

if [ ! -d "openssl-${OPENSSL_VERSION}" ]; then
  download_src "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz" "openssl-${OPENSSL_VERSION}.tar.gz"
fi

echo "[*] Clone Modul (Shallow Clone)"
# Gunakan --depth 1 agar lebih cepat
[ -d ngx_brotli ] || git clone --depth 1 --recursive "$MOD_BROTLI_REPO" ngx_brotli
[ -d nginx-module-vts ] || git clone --depth 1 "$MOD_VTS_REPO" nginx-module-vts
[ -d ngx_devel_kit ] || git clone --depth 1 "$MOD_NDK_REPO" ngx_devel_kit
[ -d lua-nginx-module ] || git clone --depth 1 "$MOD_LUA_REPO" lua-nginx-module
[ -d redis2-nginx-module ] || git clone --depth 1 "$MOD_REDIS2_REPO" redis2-nginx-module
[ -d ngx_http_tls_dyn_size ] || git clone --depth 1 "$MOD_TLS_DYN_REPO" ngx_http_tls_dyn_size

cd "nginx-${NGINX_VERSION}"

echo "[*] Konfigurasi Environment LuaJIT"
# FIX: Cari path include LuaJIT 2.0/2.1 secara otomatis
LUAJIT_INC_PATH=$(find /usr/include -maxdepth 1 -type d -name "luajit-2*" | head -n 1)

if [ -z "$LUAJIT_INC_PATH" ]; then
  echo "Error: Header LuaJIT tidak ditemukan di /usr/include/luajit-2*!"
  exit 1
fi

export LUAJIT_LIB="/usr/lib/x86_64-linux-gnu"
export LUAJIT_INC="$LUAJIT_INC_PATH"

echo "LuaJIT Detected -> INC: $LUAJIT_INC | LIB: $LUAJIT_LIB"

echo "[*] Configure Nginx"
./configure \
  --prefix="${PREFIX}" \
  --sbin-path="${PREFIX}/sbin/nginx" \
  --conf-path="${PREFIX}/conf/nginx.conf" \
  --pid-path="${PREFIX}/logs/nginx.pid" \
  --lock-path="${PREFIX}/logs/nginx.lock" \
  --http-log-path="${PREFIX}/logs/access.log" \
  --error-log-path="${PREFIX}/logs/error.log" \
  --with-cc="$CC_CMD" \
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

echo "[*] Install ke Staging (Packaging)"
rm -rf "$PKGROOT"
make install DESTDIR="$PKGROOT"

PKG_NAME="nginx-perf"
PKG_VERSION="${NGINX_VERSION}-openssl${OPENSSL_VERSION}"
PKG_ARCH="amd64"

echo "[*] Membuat Paket .deb"
fpm -s dir -t deb \
  -n "$PKG_NAME" \
  -v "$PKG_VERSION" \
  -a "$PKG_ARCH" \
  --description "Optimized Nginx ${NGINX_VERSION} (PCRE2) + HTTP/3 + OpenSSL ${OPENSSL_VERSION} + Brotli/Lua/VTS" \
  --license "BSD" \
  --url "https://nginx.org/" \
  --maintainer "GitHub Action" \
  --vendor "Custom Build" \
  --depends "libc6, libpcre2-8-0, zlib1g, libssl-dev, libluajit-5.1-2" \
  -C "$PKGROOT" \
  .

echo "[*] Selesai."
