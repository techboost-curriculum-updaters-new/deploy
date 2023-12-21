#!/bin/bash

cd ~

sudo yum -y update

# install mbstring
sudo yum -y install php-mbstring

# uninstall MariaDB, install MySQL 5.7
sudo service mariadb stop
sudo yum -y erase mariadb-config mariadb-common mariadb-libs mariadb
sudo yum -y localinstall https://repo.mysql.com/mysql80-community-release-el7-1.noarch.rpm
sudo yum-config-manager --disable mysql80-community
sudo yum-config-manager --enable mysql57-community
sudo rpm --import https://repo.mysql.com/RPM-GPG-KEY-mysql-2022
sudo yum -y install mysql-community-server
sudo systemctl start mysqld.service
sudo systemctl enable mysqld.service

DB_PASSWORD=$(sudo grep "A temporary password is generated" /var/log/mysqld.log | sed -s 's/.*root@localhost: //')
mysql -uroot -p${DB_PASSWORD} --connect-expired-password -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'TB@shibuya1';uninstall plugin validate_password;set password for root@localhost=password('');"

# install composer
curl -sS https://getcomposer.org/installer | php
sudo mv composer.phar /usr/bin/composer

# reload shell config
source $HOME/.bash_profile
