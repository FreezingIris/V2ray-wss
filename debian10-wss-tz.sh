#!/bin/sh

if [[ $EUID -ne 0 ]]; then
    clear
    echo "Error: This script must be run as root!" 1>&2
    exit 1
fi

timedatectl set-timezone Asia/Shanghai

echo "====输入已经DNS解析好的域名===="
read domain

apt install -y certbot php7.3 php7.3-fpm build-essential libtool libpcre3 libpcre3-dev zlib1g-dev openssl libssl-dev

echo "A" | certbot certonly --renew-by-default --register-unsafely-without-email --standalone -d $domain

echo -e "0 2 1 * * /usr/bin/certbot renew --pre-hook \"service nginx stop\" --post-hook \"service nginx start\"" >> /var/spool/cron/crontabs/root

sed -ri 's|listen = /run/php/php7.3-fpm.sock|listen = 127.0.0.1:9000|' /etc/php/7.3/fpm/pool.d/www.conf

systemctl restart php7.3-fpm.service

mkdir -p /var/www/html

wget https://phus.lu/tz.php?method=raw -O /var/www/html/tz.php

v2path=$(cat /dev/urandom | head -1 | md5sum | head -c 6)

    wget https://nginx.org/download/nginx-1.21.1.tar.gz -O - | tar -xz
    cd nginx-1.21.1
    ./configure --prefix=/etc/nginx \
    --sbin-path=/usr/sbin/nginx \
    --modules-path=/usr/lib/nginx/modules \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --pid-path=/var/run/nginx.pid \
    --lock-path=/var/run/nginx.lock \
    --with-http_v2_module \
    --with-http_ssl_module \
    --with-http_gzip_static_module \
    --with-http_stub_status_module \
    --with-http_sub_module \
    --with-stream \
    --with-stream_ssl_module
    
    make && make install
    cd ..
    rm -rf nginx-1.21.1
    
cat >/lib/systemd/system/nginx.service<<EOF
[Unit]
Description=The NGINX HTTP and reverse proxy server
After=syslog.target network-online.target remote-fs.target nss-lookup.target
Wants=network-online.target
[Service]
Type=forking
PIDFile=/var/run/nginx.pid
ExecStartPre=/usr/sbin/nginx -t
ExecStart=/usr/sbin/nginx
ExecReload=/usr/sbin/nginx -s reload
ExecStop=/bin/kill -s QUIT \$MAINPID
PrivateTmp=true
[Install]
WantedBy=multi-user.target
EOF

cat >/etc/nginx/nginx.conf<<EOF
pid /var/run/nginx.pid;
worker_processes auto;
worker_rlimit_nofile 51200;
events {
    worker_connections 10240;
    multi_accept on;
    use epoll;
}
http {
    server_tokens off;
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 120s;
    keepalive_requests 10000;
    types_hash_max_size 2048;
    include /etc/nginx/mime.types;
    access_log off;
    error_log /dev/null;
    server {
        listen 80;
        listen [::]:80;
        server_name $domain;
        root /var/www/html;
        location / {
            return 301 https://\$server_name\$request_uri;
        }
    }

    server {
        listen 443 ssl http2;
        listen [::]:443 ssl http2;
        server_name $domain;
        root /var/www/html;
        ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:HIGH:!aNULL:!MD5:!RC4:!DHE;
        ssl_prefer_server_ciphers on;
        ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;

        location /$v2path {
            proxy_redirect off;
            proxy_pass http://127.0.0.1:8080;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host \$http_host;
        }

        location ~ tz\.php$ {
            try_files \$uri =404;
            fastcgi_split_path_info ^(.+\.php)(/.+)$;
            fastcgi_pass 127.0.0.1:9000;
            fastcgi_index index.php;
            fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
            fastcgi_param HTTPS on;
            include fastcgi_params;
        }
    }
}
EOF

wget https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh && bash install-release.sh

v2uuid=$(cat /proc/sys/kernel/random/uuid)

cat >/usr/local/etc/v2ray/config.json<<EOF
{
  "inbounds": [
    {
      "port": 8080,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$v2uuid"
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
        "path": "/$v2path"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF

systemctl enable nginx.service && systemctl start nginx.service

systemctl enable v2ray.service && systemctl start v2ray.service

rm -f install-release.sh debian10-wss-tz.sh

cat >/usr/local/etc/v2ray/client.json<<EOF
{
===========配置参数=============
地址：${domain}
端口：443/8080
UUID：${v2uuid}
加密方式：aes-128-gcm
传输协议：ws
路径：/${v2path}
底层传输：tls
探针地址：https://${domain}/tz.php
注意：8080端口不需要打开tls
}
EOF

clear
echo
echo "安装已经完成"
echo
echo "===========配置参数============"
echo "地址：${domain}"
echo "端口：443/8080"
echo "UUID：${v2uuid}"
echo "加密方式：aes-128-gcm"
echo "传输协议：ws"
echo "路径：/${v2path}"
echo "底层传输：tls"
echo "探针地址：https://${domain}/tz.php"
echo "注意：8080端口不需要打开tls"
echo
