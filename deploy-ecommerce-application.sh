#!/bin/bash

function log() {
    no_color='\033[0m' # No color
    case $1 in
        "green") color='\033[0;32m'
                ;;
        "red") color='\033[0;31m'
                ;;
        "*") color=$no_color
                ;;
    esac
    echo -e "${color} $2 ${no_color}"
}

function check_service_status() {
    is_active=$(sudo systemctl is-active $1)
    if [ $is_active = "active" ]
    then
        log "green" "$1 is active and running"
    else
        log "red" "$1 is not active"
        exit 1
    fi
}

function check_firewall_port_rule() {
    ports=$(sudo firewall-cmd --list-all --zone=public | grep ports)
    if [[ $ports = *$1* ]]
    then
        log "green" "Port $1 configured"
    else
        log "red" "Port $1 is not configured" 
        exit 1
    fi
}

function install_packages() {
    if [[ ! -z $1 ]]
    then
        purpose=$1
        packages=$( cat ./prerequisites | grep $purpose | awk '{split($0,a,","); print a[2]}' )
    else
        packages=$( cat ./prerequisites | awk '{split($0,a,","); print a[2]}' )
    fi

    for package in $packages
    do
        sudo yum install -y $package
    done
}

function setup_firewall() {
    log "green" "Setting up the firewall"
    install_packages firewall

    sudo service firewalld start
    sudo systemctl enable firewalld
    check_service_status firewalld

    sudo firewall-cmd --permanent --zone=public --add-port=3306/tcp
    sudo firewall-cmd --reload
    sudo firewall-cmd --permanent --zone=public --add-port=80/tcp
    sudo firewall-cmd --reload
    check_firewall_port_rule "3306"
    check_firewall_port_rule "80"
}

function setup_mariadb() {
    log "green" "Setting up the DB"
    install_packages db

    sudo service mariadb start
    sudo systemctl enable mariadb
    check_service_status mariadb
}

function configure_app_db() {
log "green" "Creating the application's DB"

cat > setup-db.sql <<-EOF
CREATE DATABASE ecomdb;
CREATE USER 'ecomuser'@'localhost' IDENTIFIED BY 'ecompassword';
GRANT ALL PRIVILEGES ON *.* TO 'ecomuser'@'localhost';
FLUSH PRIVILEGES;
EOF

sudo mysql < setup-db.sql
}

function seeding_app_db() {
log "green" "Seeding the inventory data"

cat > db-load-script.sql <<-EOF
USE ecomdb;
CREATE TABLE products (id mediumint(8) unsigned NOT NULL auto_increment,Name varchar(255) default NULL,Price varchar(255) default NULL, ImageUrl varchar(255) default NULL,PRIMARY KEY (id)) AUTO_INCREMENT=1;
INSERT INTO products (Name,Price,ImageUrl) VALUES ("Laptop","100","c-1.png"),("Drone","200","c-2.png"),("VR","300","c-3.png"),("Tablet","50","c-5.png"),("Watch","90","c-6.png"),("Phone Covers","20","c-7.png"),("Phone","80","c-8.png"),("Laptop","150","c-4.png");
EOF

sudo mysql < db-load-script.sql

mysql_db_results=$(sudo mysql -e "use ecomdb; select * from products;")
if [[ $mysql_db_results == *Laptop* ]]
then
  log "green" "Inventory data loaded into DB"
else
  log "green" "Inventory data not loaded into DB"
  exit 1
fi
}

function setup_web_app() {
    log "green" "Setting up the web app"
    install_packages web

    sudo sed -i 's/index.html/index.php/g' /etc/httpd/conf/httpd.conf

    sudo service httpd start
    sudo systemctl enable httpd
    check_service_status httpd

    sudo git clone https://github.com/kodekloudhub/learning-app-ecommerce.git /var/www/html/

    sudo sed -i 's/172.20.1.101/localhost/g' /var/www/html/index.php
}

function check_item() {
    if [[ $1 = *$2* ]]
    then
        log "green" "Item $2 is present on the web page"
    else 
        log "red" "Item $2 is not present on the web page"
    fi
}

log "green" "--------------------------------Setup Firewall"
setup_firewall
log "green" "--------------------------------Setup DB"
setup_mariadb
configure_app_db
seeding_app_db
log "green" "--------------------------------Setup Web App"
setup_web_app

log "green" "--------------------------------Testing Web App"
web_page=$(curl http://localhost)
for item in Laptop Drone VR Watch Phone
do
  check_item "$web_page" $item
done