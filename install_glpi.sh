#!/bin/bash
clear

function warn() {
    echo -e '\e[31m'$1'\e[0m';
}

function info() {
    echo -e '\e[36m'$1'\e[0m';
}

#Check that the script is running as root
function check_root() {
    if [ "$EUID" -ne 0 ]; then
        warn "Please run as root (su -)"
        exit
    fi
}

info "This script will install GLPI with its dependencies, set up a vhost, and generate a self-signed SSL certificate"
read -p $'\e[1;32mChoose a name for the database:\e[0m ' DBNAME
read -p $'\e[1;32mChoose a name for the database user:\e[0m ' USERDB
read -p $'\e[1;32mChoose a password for the database user:\e[0m ' USERDBPASSWORD
read -p $'\e[1;32mApache2 Virtual Host - Please enter ServerName (www.exemple.local):\e[0m ' SERVERNAME
info Creating a self-signed SSL certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/glpi.key -out /etc/ssl/certs/glpi.crt

function install_packages() {
    info "Installing dependencies (apache2, mariadb-server, php8.2, php8.2-fpm, PHP extensions, curl and jq)"
    apt install apache2 mariadb-server php8.2 php8.2-{fpm,curl,gd,intl,xml,common,mysql,bz2,zip,ldap,mbstring} curl jq wget -y
}

function apache_configuration() {
    info "Configuring apache2"
    a2enmod proxy_fcgi setenvif
    a2enmod ssl
    a2enmod rewrite
    a2enconf php8.2-fpm
}

function vhost_configuration() {
    info "Creating vhost file"
    echo "
<VirtualHost *:443>
    ServerName $SERVERNAME
    DocumentRoot /var/www/glpi/public/
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/glpi.crt
    SSLCertificateKeyFile /etc/ssl/private/glpi.key

    <Directory /var/www/glpi/public/>
        Require all granted

        RewriteEngine On

        # Redirect all requests to GLPI router, unless file exists.
         RewriteCond %{REQUEST_FILENAME} !-f
         RewriteRule ^(.*)$ index.php [QSA,L]
    </Directory>
</VirtualHost>

<VirtualHost *:80>
    ServerName $SERVERNAME
    Redirect / https://$SERVERNAME
</VirtualHost>" > /etc/apache2/sites-available/glpi.conf
    a2ensite glpi.conf
    systemctl restart apache2
}

function db_configuration() {
    info "Creating DB and its user"
    echo "CREATE DATABASE $DBNAME;" | mysql
    echo "GRANT ALL PRIVILEGES ON $DBNAME.* TO '$USERDB'@'localhost' IDENTIFIED BY '$USERDBPASSWORD';" | mysql
    echo "FLUSH PRIVILEGES;" | mysql
}

function install_glpi() {
    info "Downloading and installing the latest version of GLPI"
    DOWNLOAD_URL=$(curl -s https://api.github.com/repos/glpi-project/glpi/releases/latest | jq -r '.assets[0].browser_download_url')
    wget -O /tmp/glpi-latest.tgz $DOWNLOAD_URL
    tar xvf /tmp/glpi-latest.tgz -C /var/www/

# Prevent files from being accessed by the webserver directly - https://glpi-install.readthedocs.io/en/latest/install/index.html#files-and-directories-locations
    mkdir /etc/glpi/ && cp -r /var/www/glpi/config/. /etc/glpi/ && chown -R www-data:www-data /etc/glpi/
    mkdir /var/lib/glpi/ && cp -r /var/www/glpi/files/. /var/lib/glpi && chown -R www-data:www-data /var/lib/glpi/
    mkdir /var/log/glpi/ && chown -R www-data:www-data /var/log/glpi/
# Permission for marketplace directory
    chown -R www-data:www-data /var/www/glpi/marketplace/

# Creation of the file downstream.php
    echo "
<?php
define('GLPI_CONFIG_DIR', '/etc/glpi/');

if (file_exists(GLPI_CONFIG_DIR . '/local_define.php')) {
   require_once GLPI_CONFIG_DIR . '/local_define.php';
}" > /var/www/glpi/inc/downstream.php

# Creation of the file local_define.php
    echo "
<?php
define('GLPI_VAR_DIR', '/var/lib/glpi');
define('GLPI_LOG_DIR', '/var/log/glpi');" > /etc/glpi/local_define.php

# Security configuration for sessions
    sed -i 's/;session.cookie_secure =/session.cookie_secure = On/' /etc/php/8.2/fpm/php.ini
    sed -i 's/session.cookie_httponly =/session.cookie_httponly = On/' /etc/php/8.2/fpm/php.ini
    systemctl restart php8.2-fpm
}

function display_creditentials() {
    info "==========> GLPI installation details <=========="
    warn "Record this informations !"
    info "You can access GLPI with this link and continue the installation  : https://$SERVERNAME"
    info "Database name : $DBNAME"
    info "Database user : $USERDB"
    info "Databaser user password : $USERDBPASSWORD"
# DELETE install/install.php ! https://glpi-install.readthedocs.io/en/latest/install/index.html#post-installation
    warn "After completing the installation of GLPI, delete the file install/install.php for security reasons."
    info "================================================="


}
check_root
install_packages
apache_configuration
vhost_configuration
db_configuration
install_glpi
display_creditentials
