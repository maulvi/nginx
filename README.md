# 📘 Nginx Performance Modules Tutorial

Panduan lengkap penggunaan modul performa yang terintegrasi dalam build custom Nginx ini. Build ini mencakup modul-modul penting untuk meningkatkan kecepatan, keamanan, dan kemudahan monitoring server.

***

## 📦 Daftar Modul

1. [**Brotli Compression**](#1-brotli-compression-module) - Kompresi modern yang lebih efisien dari Gzip.
2. [**VTS (Virtual Traffic Status)**](#2-vts-virtual-traffic-status-module) - Real-time monitoring traffic.
3. [**Headers More**](#3-headers-more-module) - Kontrol penuh HTTP headers.
4. [**Cache Purge**](#4-cache-purge-module) - Penghapusan cache on-demand.

***

## 1. Brotli Compression Module

**Fungsi:** Mengompresi aset web (HTML, CSS, JS) menggunakan algoritma Brotli yang memberikan hasil kompresi 15-25% lebih kecil dibandingkan Gzip, mengurangi penggunaan bandwidth dan mempercepat loading page.

### 🛠️ Konfigurasi Dasar

Tambahkan konfigurasi ini di blok `http {}` pada `/etc/nginx/nginx.conf`:

```nginx
http {
    # Aktifkan Brotli
    brotli on;
    
    # Level kompresi (1-11). Level 6 adalah keseimbangan terbaik antara speed & size.
    brotli_comp_level 6;
    
    # Izinkan melayani file .br statis jika sudah ada di disk
    brotli_static on;
    
    # Tipe file yang akan dikompresi
    brotli_types 
        text/plain 
        text/css 
        text/xml 
        text/javascript 
        application/json 
        application/javascript 
        application/xml+rss 
        application/rss+xml 
        font/truetype 
        font/opentype 
        image/svg+xml;
}
```


### ⚙️ Konfigurasi Lanjutan (Tuning)

```nginx
http {
    brotli on;
    brotli_comp_level 6;
    
    # Hanya kompres file > 1KB (file kecil tidak efisien dikompres)
    brotli_min_length 1000;
    
    # Ukuran buffer
    brotli_buffers 16 8k;
    brotli_window 512k;
    
    # Tipe MIME lengkap
    brotli_types
        text/plain text/css text/xml text/javascript text/x-component
        application/json application/javascript application/x-javascript
        application/xml application/xml+rss application/rss+xml
        font/truetype font/opentype application/vnd.ms-fontobject
        image/svg+xml image/x-icon;
}
```


### ✅ Verifikasi

Gunakan `curl` untuk mengecek apakah server mengirimkan Brotli:

```bash
curl -H "Accept-Encoding: br" -I https://yourdomain.com
```

**Output yang diharapkan:**

```http
HTTP/2 200
content-encoding: br  <-- Ini tandanya Brotli aktif
```


***

## 2. VTS (Virtual Traffic Status) Module

**Fungsi:** Menyediakan dashboard monitoring real-time untuk melihat statistik request, bandwidth, kode respon (2xx, 4xx, 5xx), dan status cache langsung dari Nginx.

### 🛠️ Konfigurasi Dasar

Tambahkan di blok `http {}` untuk mengaktifkan zona monitoring:

```nginx
http {
    # Alokasikan memori 10MB untuk menyimpan statistik
    vhost_traffic_status_zone shared:vhost_traffic_status:10m;
    
    server {
        listen 80;
        server_name localhost;
        
        # Endpoint untuk melihat statistik
        location /status {
            vhost_traffic_status_display;
            vhost_traffic_status_display_format html;
            
            # PENTING: Batasi akses hanya dari IP terpercaya
            allow 127.0.0.1;
            allow YOUR_OFFICE_IP;
            deny all;
        }
    }
}
```


### ⚙️ Konfigurasi Per-Server (Virtual Host)

```nginx
server {
    listen 443 ssl http2;
    server_name example.com;
    
    # Aktifkan tracking spesifik untuk server block ini
    vhost_traffic_status on;
    
    location / {
        # Tracking spesifik per lokasi (opsional)
        vhost_traffic_status_filter_by_set_key $geoip_country_code country::*;
    }
}
```


### 📊 Format Output

VTS mendukung output dalam berbagai format untuk integrasi monitoring:

- **HTML Dashboard:** `http://domain.com/status`
- **JSON (untuk Prometheus/Grafana):** `http://domain.com/status/format/json`
- **Prometheus Format:** `http://domain.com/status/format/prometheus`

***

## 3. Headers More Module

**Fungsi:** Memberikan kontrol penuh untuk menambah, mengubah, atau menghapus HTTP headers (input maupun output). Lebih fleksibel daripada direktif `add_header` bawaan Nginx.

### 🛠️ Security Hardening

Gunakan modul ini untuk menyembunyikan informasi server dan memperkuat keamanan.

```nginx
http {
    # Sembunyikan versi Nginx dan info OS
    more_clear_headers 'Server';
    more_clear_headers 'X-Powered-By';
    more_clear_headers 'X-Runtime';
    
    # Tambahkan Security Headers Global
    more_set_headers 'X-Frame-Options: SAMEORIGIN';
    more_set_headers 'X-Content-Type-Options: nosniff';
    more_set_headers 'X-XSS-Protection: 1; mode=block';
    more_set_headers 'Referrer-Policy: strict-origin-when-cross-origin';
}
```


### ⚙️ Kontrol Cache \& CORS

```nginx
server {
    # Cache Control untuk aset statis (Immutable Cache)
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff2)$ {
        more_set_headers 'Cache-Control: public, max-age=31536000, immutable';
        more_clear_headers 'Pragma';
    }
    
    # CORS Headers untuk API
    location /api/ {
        more_set_headers 'Access-Control-Allow-Origin: *';
        more_set_headers 'Access-Control-Allow-Methods: GET, POST, OPTIONS';
        more_set_headers 'Access-Control-Allow-Headers: Authorization, Content-Type';
        
        if ($request_method = 'OPTIONS') {
            return 204;
        }
    }
}
```


***

## 4. Cache Purge Module

**Fungsi:** Memungkinkan penghapusan cache FastCGI, Proxy, uWSGI, atau SCGI secara spesifik berdasarkan key. Sangat penting untuk CMS seperti WordPress agar konten yang diupdate langsung terlihat tanpa menunggu cache expire.

### 🛠️ Konfigurasi FastCGI Cache (WordPress/PHP)

```nginx
http {
    # Definisi path cache
    fastcgi_cache_path /var/cache/nginx/fastcgi_temp levels=1:2 keys_zone=WORDPRESS:100m inactive=60m;
    fastcgi_cache_key "$scheme$request_method$host$request_uri";

    server {
        set $skip_cache 0;
        
        # Jangan cache POST request
        if ($request_method = POST) { set $skip_cache 1; }
        
        # Jangan cache query string tertentu
        if ($query_string != "") { set $skip_cache 1; }

        # Endpoint untuk Purge Cache
        # Diakses oleh plugin WordPress (Nginx Helper)
        location ~ /purge(/.*) {
            allow 127.0.0.1;  # Hanya izinkan dari localhost
            deny all;
            fastcgi_cache_purge WORDPRESS "$scheme$request_method$host$1";
        }

        location ~ \.php$ {
            fastcgi_pass unix:/run/php/php-fpm.sock;
            fastcgi_cache WORDPRESS;
            fastcgi_cache_valid 200 60m;
            fastcgi_cache_bypass $skip_cache;
            fastcgi_no_cache $skip_cache;
            include fastcgi_params;
        }
    }
}
```


### ⚙️ Konfigurasi Proxy Cache (Reverse Proxy)

```nginx
http {
    proxy_cache_path /var/cache/nginx/proxy_temp levels=1:2 keys_zone=MY_PROXY:10m inactive=60m;
    proxy_cache_key "$scheme$request_method$host$request_uri";

    server {
        # Endpoint Purge
        location ~ /purge(/.*) {
            allow 127.0.0.1;
            deny all;
            proxy_cache_purge MY_PROXY "$scheme$request_method$host$1";
        }

        location / {
            proxy_pass http://backend_server;
            proxy_cache MY_PROXY;
            proxy_cache_valid 200 10m;
        }
    }
}
```


### 🔄 Cara Menggunakan Purge

Untuk menghapus cache halaman `https://example.com/blog/post-1`:

```bash
# Request ke endpoint purge (harus dari IP yang diizinkan)
curl -I https://example.com/purge/blog/post-1
```

**Output Sukses:**

```http
HTTP/1.1 200 OK
Content-Type: text/html
Content-Length: 20
Successful purge
```


***

### 🚀 Kesimpulan

Dengan kombinasi modul-modul ini, server Nginx Anda akan:

1. Menghemat bandwidth secara signifikan (**Brotli**).
2. Mudah dipantau traffic-nya (**VTS**).
3. Lebih aman dan bersih headernya (**Headers More**).
4. Dapat memperbarui konten dinamis secara instan (**Cache Purge**).
