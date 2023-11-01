#!/bin/bash

# remove apache
sudo yum remove httpd -y
# nginx
sudo amazon-linux-extras install nginx1 -y
sudo systemctl enable nginx

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

# Load dynamic modules. See /usr/share/doc/nginx/README.dynamic.
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

    # Load modular configuration files from the /etc/nginx/conf.d directory.
    # See http://nginx.org/en/docs/ngx_core_module.html#include
    # for more information.
    include /etc/nginx/conf.d/*.conf;

    upstream puma {
      server unix:///usr/share/nginx/rails/tmp/sockets/puma.sock;
    }
    server {
        listen       80 default_server;
        listen       [::]:80 default_server;
        server_name  _;

        root /usr/share/nginx/rails/public;
        client_max_body_size 20M;

        charset utf-8;
 
        location / {
            try_files $uri $uri/index.html $uri.html @app;
        }

        location = /favicon.ico { access_log off; log_not_found off; }
        location = /robots.txt  { access_log off; log_not_found off; }
 
        error_page 404 /index.php;
 
        location @app {
            proxy_read_timeout 300;
            proxy_connect_timeout 300;
            proxy_redirect off;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Host $http_host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_pass http://puma;
        }
 
        location ~ /\.(?!well-known).* {
            deny all;
        }
    }
}
EOF

# add rx permission to ec2-user group
sudo chmod g+rx ${HOME}
# add ec2-user to nginx gourp
sudo usermod -aG $(whoami) nginx

#  install Let's Encrypt certbot
sudo yum install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm -y
sudo yum install -y certbot python-certbot-nginx

# start processes
sudo systemctl restart nginx

# create restart_puma.sh
# create cron.txt
PUMA_SH=~/environment/restart_puma.sh
tee ${PUMA_SH} <<'EOF' >/dev/null
#!/bin/bash

# check current rails directory
echo "Checking current directory..."
if [ ! -f ./Gemfile ]; then 
  echo "$(pwd) might be not Rails project."
  echo "operation terminated."
  exit 1
fi

echo "Killing current puma..."
killall ruby

echo "Starting new puma..."
puma -C $(pwd)/config/puma/production.rb
EOF

chmod 766 ~/environment/restart_puma.sh

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
## Let's Encrypt certbot
which certbot >/dev/null 2>&1
if [ $? -eq  1 ]; then
  echo "certbot is not installed!"
  COMPLETED=0
fi
if [ $COMPLETED -eq  1 ]; then
  echo "deploy_setup_rails.sh successfully completed."
fi
