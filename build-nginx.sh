#!/usr/bin/env bash
set -euo pipefail

# Versi default (bisa dioverride via ENV)
: "${NGINX_VERSION:=1.28.0}"
: "${OPENSSL_VERSION:=3.6.0}"

WORKDIR="${WORKDIR:-$HOME/nginx-build}"
PKGROOT="${PKGROOT:-$WORKDIR/pkgroot}"
DOWNLOAD_CACHE="${DOWNLOAD_CACHE:-$WORKDIR/downloads}"

MOD_BROTLI_REPO=https://github.com/google/ngx_brotli.git
MOD_VTS_REPO=https://github.com/vozlt/nginx-module-vts.git
MOD_LUA_REPO=https://github.com/openresty/lua-nginx-module.git
MOD_NDK_REPO=https://github.com/vision5/ngx_devel_kit.git
MOD_REDIS2_REPO=https://github.com/openresty/redis2-nginx-module.git

echo "[*] Setup dir: $WORKDIR"
mkdir -p "$WORKDIR" "$DOWNLOAD_CACHE"
cd "$WORKDIR"

echo "[*] Install deps"
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  build-essential git wget ca-certificates \
  libpcre2-dev zlib1g-dev libxslt1-dev libxml2-dev \
  libgd-dev libperl-dev libunwind-dev \
  libluajit-5.1-dev ruby-full ccache

CC_CMD=gcc
if command -v ccache >/dev/null 2>&1; then
  echo "[*] CCache on"
  CC_CMD="ccache gcc"
  export CCACHE_DIR="$HOME/.ccache"
  export CCACHE_COMPRESS=1
fi

if ! command -v fpm >/dev/null 2>&1; then
  sudo gem install --no-document fpm
fi

download_src() {
  url=$1
  file=$2
  if [ ! -f "$DOWNLOAD_CACHE/$file" ]; then
    echo "Downloading $file ..."
    wget -q -O "$DOWNLOAD_CACHE/$file" "$url"
  else
    echo "Using cached $file"
  fi
  tar xf "$DOWNLOAD_CACHE/$file" -C "$WORKDIR"
}

echo "[*] Download Nginx & OpenSSL"
if [ ! -d "nginx-$NGINX_VERSION" ]; then
  download_src "https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz" "nginx-$NGINX_VERSION.tar.gz"
fi

if [ ! -d "openssl-$OPENSSL_VERSION" ]; then
  download_src "https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz" "openssl-$OPENSSL_VERSION.tar.gz"
fi

echo "[*] Clone modules"
rm -rf ngx_brotli nginx-module-vts ngx_devel_kit lua-nginx-module redis2-nginx-module

git clone --depth 1 --recursive "$MOD_BROTLI_REPO" ngx_brotli
git clone --depth 1 "$MOD_VTS_REPO" nginx-module-vts
git clone --depth 1 "$MOD_NDK_REPO" ngx_devel_kit
git clone --depth 1 "$MOD_LUA_REPO" lua-nginx-module
git clone --depth 1 "$MOD_REDIS2_REPO" redis2-nginx-module

cd "nginx-$NGINX_VERSION"

echo "[*] Setup LuaJIT env"
LUAJIT_INC_PATH=$(find /usr/include -maxdepth 1 -type d -name luajit-2\* | head -n 1 || true)
if [ -z "$LUAJIT_INC_PATH" ]; then
  echo "Error: LuaJIT headers not found"
  exit 1
fi
export LUAJIT_LIB=/usr/lib/x86_64-linux-gnu
export LUAJIT_INC="$LUAJIT_INC_PATH"

echo "[*] Configure Nginx $NGINX_VERSION + OpenSSL $OPENSSL_VERSION"
./configure \
  --prefix=/etc/nginx \
  --sbin-path=/usr/sbin/nginx \
  --modules-path=/usr/lib/nginx/modules \
  --conf-path=/etc/nginx/nginx.conf \
  --error-log-path=/var/log/nginx/error.log \
  --http-log-path=/var/log/nginx/access.log \
  --pid-path=/run/nginx.pid \
  --lock-path=/run/nginx.lock \
  --http-client-body-temp-path=/var/cache/nginx/client_temp \
  --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
  --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
  --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
  --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
  --user=www-data \
  --group=www-data \
  --with-cc="$CC_CMD" \
  --with-pcre-jit \
  --with-file-aio \
  --with-threads \
  --with-http_ssl_module \
  --with-http_v2_module \
  --with-http_v3_module \
  --with-http_realip_module \
  --with-http_addition_module \
  --with-http_sub_module \
  --with-http_gunzip_module \
  --with-http_gzip_static_module \
  --with-http_secure_link_module \
  --with-http_stub_status_module \
  --with-stream \
  --with-stream_ssl_module \
  --with-stream_realip_module \
  --with-stream_ssl_preread_module \
  --without-http_autoindex_module \
  --without-http_ssi_module \
  --without-http_userid_module \
  --without-http_geo_module \
  --without-http_split_clients_module \
  --without-http_uwsgi_module \
  --without-http_scgi_module \
  --without-http_memcached_module \
  --without-http_empty_gif_module \
  --without-http_browser_module \
  --with-openssl="../openssl-$OPENSSL_VERSION" \
  --with-openssl-opt="no-weak-ssl-ciphers enable-ec_nistp_64_gcc_128" \
  --add-module="../ngx_brotli" \
  --add-module="../nginx-module-vts" \
  --add-module="../ngx_devel_kit" \
  --add-module="../lua-nginx-module" \
  --add-module="../redis2-nginx-module" \
  --with-cc-opt="-O2 -march=x86-64 -mtune=generic -pipe -fstack-protector-strong" \
  --with-ld-opt="-Wl,--as-needed -Wl,-z,relro -Wl,-z,now"

echo "[*] Build"
make -j"$(nproc)"

echo "[*] Install to staging"
rm -rf "$PKGROOT"
make install DESTDIR="$PKGROOT"

echo "[*] Create additional directories"
mkdir -p "$PKGROOT/etc/nginx/sites-available"
mkdir -p "$PKGROOT/etc/nginx/sites-enabled"
mkdir -p "$PKGROOT/etc/nginx/conf.d"
mkdir -p "$PKGROOT/var/log/nginx"
mkdir -p "$PKGROOT/var/cache/nginx/client_temp"
mkdir -p "$PKGROOT/var/cache/nginx/proxy_temp"
mkdir -p "$PKGROOT/var/cache/nginx/fastcgi_temp"
mkdir -p "$PKGROOT/var/cache/nginx/uwsgi_temp"
mkdir -p "$PKGROOT/var/cache/nginx/scgi_temp"
mkdir -p "$PKGROOT/var/lib/nginx"

echo "[*] Create systemd service file"
mkdir -p "$PKGROOT/lib/systemd/system"
cat > "$PKGROOT/lib/systemd/system/nginx.service" <<'EOF'
[Unit]
Description=Nginx HTTP/3 High Performance Web Server
Documentation=https://nginx.org/en/docs/
After=network-online.target remote-fs.target nss-lookup.target
Wants=network-online.target

[Service]
Type=forking
PIDFile=/run/nginx.pid
ExecStartPre=/usr/sbin/nginx -t -q -g 'daemon on; master_process on;'
ExecStart=/usr/sbin/nginx -g 'daemon on; master_process on;'
ExecReload=/bin/sh -c "/bin/kill -s HUP $(/bin/cat /run/nginx.pid)"
ExecStop=/bin/sh -c "/bin/kill -s TERM $(/bin/cat /run/nginx.pid)"
PrivateTmp=true
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

echo "[*] Create logrotate config"
mkdir -p "$PKGROOT/etc/logrotate.d"
cat > "$PKGROOT/etc/logrotate.d/nginx" <<'EOF'
/var/log/nginx/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 www-data adm
    sharedscripts
    prerotate
        if [ -d /etc/logrotate.d/httpd-prerotate ]; then \
            run-parts /etc/logrotate.d/httpd-prerotate; \
        fi
    endscript
    postrotate
        invoke-rc.d nginx rotate >/dev/null 2>&1 || true
    endscript
}
EOF

PKG_NAME=nginx
PKG_VERSION="${NGINX_VERSION}-openssl${OPENSSL_VERSION}"
PKG_ARCH=amd64

echo "[*] Build .deb"
fpm -s dir -t deb \
  -n "$PKG_NAME" \
  -v "$PKG_VERSION" \
  -a "$PKG_ARCH" \
  --description "Nginx $NGINX_VERSION + HTTP/3 + OpenSSL $OPENSSL_VERSION + Brotli/Lua/VTS/Redis2" \
  --license "BSD" \
  --url "https://nginx.org/" \
  --maintainer "GitHub Action" \
  --vendor "Custom Build" \
  --depends "libc6, libpcre2-8-0, zlib1g, libssl-dev, libluajit-5.1-2" \
  --conflicts "nginx, nginx-common, nginx-core, nginx-full, nginx-light, nginx-extras" \
  --provides "nginx" \
  --replaces "nginx, nginx-common, nginx-core" \
  --config-files "/etc/nginx/nginx.conf" \
  --config-files "/etc/logrotate.d/nginx" \
  --directories "/etc/nginx" \
  --directories "/var/log/nginx" \
  --directories "/var/cache/nginx" \
  --directories "/var/lib/nginx" \
  --after-install <(cat <<'AFTER_INSTALL'
#!/bin/sh
set -e
if [ "$1" = "configure" ] || [ "$1" = "abort-upgrade" ]; then
    if ! getent passwd www-data >/dev/null; then
        adduser --system --group --home /var/www --no-create-home --disabled-login www-data >/dev/null
    fi
    chown -R www-data:www-data /var/log/nginx /var/cache/nginx /var/lib/nginx 2>/dev/null || true
    systemctl daemon-reload >/dev/null 2>&1 || true
    if [ -x /usr/sbin/nginx ]; then
        systemctl enable nginx.service >/dev/null 2>&1 || true
    fi
fi
AFTER_INSTALL
) \
  -C "$PKGROOT" .

echo "[*] Done."
