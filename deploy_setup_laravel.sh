#!/bin/bash

# remove apache
sudo yum remove httpd -y
# nginx
sudo amazon-linux-extras install nginx1 -y
sudo systemctl enable nginx
# php-pfm
sudo yum install php-fpm -y
sudo systemctl enable php-fpm

# modify /etc/nginx/nginx.conf
## backup
NGINX_CONF=/etc/nginx/nginx.conf
if [ ! -f ${NGINX_CONF}.org ]; then
  sudo cp ${NGINX_CONF} ${NGINX_CONF}.org
fi

sudo cp ${NGINX_CONF} ${NGINX_CONF}.`date +%Y%m%d%H%M%S`

if [ -f ${NGINX_CONF}.org ]; then
  sudo cp ${NGINX_CONF}.org ${NGINX_CONF}
fi

sudo tee ${NGINX_CONF} <<'EOF' >/dev/null
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

include /usr/share/nginx/modules/*.conf;

events {
    worker_connections 1024;
}

http {
    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    keepalive_timeout   65;
    types_hash_max_size 2048;

    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;

    include /etc/nginx/conf.d/*.conf;
    server {
        listen       80 default_server;
        listen       [::]:80 default_server;
        server_name  _;

        root /usr/share/nginx/public;
        client_max_body_size 20M;

        add_header X-Frame-Options "SAMEORIGIN";
        add_header X-Content-Type-Options "nosniff";
 
        index index.php;
 
        charset utf-8;
 
        location / {
            try_files $uri $uri/ /index.php?$query_string;
        }
 
        location = /favicon.ico { access_log off; log_not_found off; }
        location = /robots.txt  { access_log off; log_not_found off; }
 
        error_page 404 /index.php;
 
        location ~ \.php$ {
            fastcgi_pass unix:/var/run/php-fpm/www.sock;
            fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
            include fastcgi_params;
        }
 
        location ~ /\.(?!well-known).* {
            deny all;
        }
    }
}
EOF

# modify /etc/php-fpm.d/www.conf
## backup
PFM_CONF=/etc/php-fpm.d/www.conf
sudo cp ${PFM_CONF} ${PFM_CONF}.`date +%Y%m%d%H%M%S`

sudo ed - ${PFM_CONF} <<EOF
,s/user\ =\ apache/user\ =\ nginx/g
,s/group\ =\ apache/group\ =\ nginx/g
wq
EOF

# add rx permission to ec2-user group
sudo chmod g+rx ${HOME}
# add ec2-user to nginx gourp
sudo usermod -aG $(whoami) nginx

# install Let's Encrypt certbot
sudo yum install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm -y
sudo yum install -y certbot python-certbot-nginx

# start processes
sudo systemctl restart nginx
sudo systemctl restart php-fpm

# create cron.txt
CRON_TXT=~/environment/cron.txt
tee ${CRON_TXT} <<'EOF' >/dev/null
# cron configuration
## MyDNS User/Password ###########
MYDNS_USER="your_mydns_id"
MYDNS_PASSWORD="your_password"
##################################

## Invalidate Mail notification
MAILTO=""

# mydns notification, at 04:00 everyday
0 4 * * * ///usr/bin/wget -O - "http://$MYDNS_USER:$MYDNS_PASSWORD@www.mydns.jp/login.html" > /dev/null 2>&1

# renew let's encrypt certificates, at 03:00 1st of every month
0 3 1 * * sudo /usr/bin/certbot renew --no-self-upgrade > /dev/null 2>&1
EOF

# final checks
COMPLETED=1
## nginx
which nginx >/dev/null 2>&1
if [ $? -eq  1 ]; then
  echo "nginx is not installed!"
  COMPLETED=0
fi
## php-fsm
which php-fpm >/dev/null 2>&1
if [ $? -eq  1 ]; then
  echo "php-fpm is not installed!"
  COMPLETED=0
fi
## Let's Encrypt certbot
which certbot >/dev/null 2>&1
if [ $? -eq  1 ]; then
  echo "certbot is not installed!"
  COMPLETED=0
fi
if [ $COMPLETED -eq  1 ]; then
  echo "deploy_setup_laravel.sh successfully completed."
fi
