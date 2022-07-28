#!/bin/bash

###### VARS
# change these
rootpass=changeme
dbname=changeme
dbuser=changeme
userpass=changeme
WPdomain=changeme
# if you don't, I will randomize them for you
for i in $rootpass $dbname $dbuser $userpass $WPdomain; do
    if [ "$i" = "changeme" ]; then
        echo "[!] Randomizing variables"
        rootpass=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
        dbname=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
        dbuser=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
        userpass=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
        if [[ "$WPdomain" = "changeme" ]]; then
            read -r -p "[?] Enter domain [e.g. mywebsite.com]: " WPdomain
        fi
    fi
done
echo -e "\nrootpass\t$rootpass\ndbname\t\t$dbname\ndbuser\t\t$dbuser\nuserpass\t$userpass\nWPdomain\t$WPdomain"
echo -e "=============================================="

# defaults vars
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

###### BANNER
echo -e "=============================================="
echo -e  "$(
cat << EOM
${YELLOW}╻ ╻┏━┓┏━┓╺┳┓┏━┓┏━┓┏━╸┏━┓┏━┓
┃╻┃┃ ┃┣┳┛ ┃┃┣━┛┣┳┛┣╸ ┗━┓┗━┓
┗┻┛┗━┛╹┗╸╺┻┛╹  ╹┗╸┗━╸┗━┛┗━┛ setup script${NC}
EOM
)"
echo -e "\t\t\t\t\e[3mby matmar\e[0m"
echo -e "=============================================="
echo -e "This script will install following components:"
echo -e "\t- NGINX Web Server\n\t- MariaDB SQL Server\n\t- Other dependencies like php, certbot\n\t- It will configure it all\n"

###### PRE CHECKS
# check if running on Ubuntu or Debian
distro=$(cat /etc/os-release | grep -E "^ID=" | head -n1 | cut -d= -f2)
if [ $distro != "ubuntu" ] && [ $distro != "debian" ]; then
    echo "This script is designed to work only on Ubuntu or Debian." 1>&2
    exit 1
fi
# root check
if [ "$EUID" -ne 0 ]
  then echo -e "\n${RED}[*] Please run as root${NC}"
  exit
fi

###### CONTINUE PROMPT
read -p '[?] Run WP setups script (Y/n) ' -n 1 -r; echo
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    exit
fi
clear

###### OS INIT
echo -e "[!] Upgrading OS and installing packages"
apt update -y &>/dev/null && apt upgrade -y &>/dev/null && echo -e "${GREEN}[+]${NC} OS updated"
apt install -y curl  &>/dev/null && echo -e "${GREEN}[+]${NC} curl installed" || echo $(echo "[o] curl installation error" && exit)
apt install -y wget  &>/dev/null && echo -e "${GREEN}[+]${NC} wget installed" || echo $(echo "[o] wget installation error" && exit)
apt install nginx -y &>/dev/null && echo -e "${GREEN}[+]${NC} nginx installed" || echo $(echo "[o] nginx installation error" && exit)
apt install mariadb-server -y &>/dev/null && echo -e "${GREEN}[+]${NC} mariadb installed" || echo $(echo "[o] mariadb installation error" && exit)
apt install certbot python3-certbot-nginx -y &>/dev/null && echo -e "${GREEN}[+]${NC} certbot installed" || echo $(echo "[o] certbot installation error" && exit)
#php
###     NOT WORKING WITH UBUNTU
# maybe: apt-get update --allow-unauthenticated
apt -y install apt-transport-https lsb-release ca-certificates &>/dev/null
curl -sSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg
sh -c 'echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list'
apt -y update &>/dev/null
apt install php8.1 php8.1-fpm php8.1-cli php8.1-mysql php-json php8.1-curl php8.1-xml php8.1-zip php8.1-mbstring php8.1-imagick php8.1-opcache php8.1-gd -y &>/dev/null && echo -e "${GREEN}[+]${NC} php installed" || echo $(echo "[o] php installation error" && exit)

###### NGINX INIT
echo -e "\n[!] Configuring NGINX, Database and WordPress"
service nginx start &>/dev/null && update-rc.d nginx enable
rm /etc/nginx/sites-enabled/default
# Create nginx virtual host
echo "
###### $WPdomain ######
server {
listen 80;
server_name *.$WPdomain $WPdomain;
client_max_body_size 200M;
root /var/www/$WPdomain/wordpress/;
rewrite ^/(.*.php)(/)(.*)$ /\$1?file=/\$3 last;
index index.htm index.html index.php;
autoindex on;
location / {
try_files \$uri \$uri/ /index.php?q=\$request_uri;
}
location ~ \.php$ {
	#include fastcgi.conf;
include snippets/fastcgi-php.conf;
fastcgi_split_path_info ^(.+\.php)(/.+)$;
	#fastcgi_pass 127.0.0.1:9000;
fastcgi_pass unix:/run/php/php8.1-fpm.sock;
fastcgi_read_timeout 999;
}
location ~ /\.ht {
	deny all;
}
if (!-e \$request_filename) {
set \$filephp 1;
}
# if the missing file is a php folder url
if (\$request_filename ~ \"\.php/\") {
set \$filephp \"\${filephp}1\";
}
if (\$filephp = 11) {
rewrite ^(.*).php/.*$ /\$1.php last;
break;
}
}
" >> /etc/nginx/sites-available/$WPdomain
# Enable the site
ln -s /etc/nginx/sites-available/$WPdomain /etc/nginx/sites-enabled/$WPdomain
nginx -t
service nginx reload &>/dev/null && service nginx status
echo -e "${GREEN}[!]${NC} NGINX successfully configured\n"


###### SQL INTI ######
service mysql start &>/dev/null && update-rc.d mysql enable &>/dev/null && echo -ne "[ ${GREEN}ok${NC} ] mysql is running." | head -n1 && echo -e "\t$(service mysql status | grep Uptime)"

echo "CREATE DATABASE $dbname;" | mysql -u root -p$rootpass
echo "[!] Database created"
echo "CREATE USER '$dbuser'@'localhost' IDENTIFIED BY '$userpass';" | mysql -u root -p$rootpass
echo "[!] Database user created"
echo "GRANT ALL PRIVILEGES ON $dbname.* TO $dbuser@localhost;" | mysql -u root -p$rootpass
echo "[!] Privileges granted"
echo "FLUSH PRIVILEGES;" | mysql -u root -p$rootpass
echo -e "${GREEN}[!]${NC} New MySQL database is successfully created\n"

###### PHP ######
#php_newest_stable_version=$(curl -s https://www.php.net/downloads | grep Stable -A1 | head -n2 | tail -n1 | cut -d" " -f6 )
#echo -e "\n[!] Newest PHP version is $php_newest_stable_version\n"
service php8.1-fpm start &>/dev/nul && update-rc.d php8.1-fpm enable && service php8.1-fpm status

###### WORDPRESS INIT
echo -e "\n[!] Setting up WordPress"
if [[ "$WPdomain" = "changeme" ]]
then
    read -r -p "Enter domain [e.g. mywebsite.com]: " WPdomain
fi
if [ -d /var/www/$WPdomain ]; then
        echo -e "${RED}[!] folder /var/www/$WPdomain exists, choose another domain name${NC}"
	read -r -p "Enter domain [e.g. mywebsite.com]: " WPdomain
fi

if [ -d /var/www/$WPdomain ]; then
	exit
fi
mkdir -p /var/www/$WPdomain
cd /var/www/$WPdomain
wget -q -O - "http://wordpress.org/latest.tar.gz" | tar -xzf -
chown www-data: -R /var/www/$WPdomain/wordpress/
cd wordpress
cp wp-config-sample.php wp-config.php
chmod 640 wp-config.php
mkdir uploads
grep -A 1 -B 50 'since 2.6.0' wp-config-sample.php > wp-config.php
curl -s https://api.wordpress.org/secret-key/1.1/salt/ >> wp-config.php
grep -A 50 -B 3 'WordPress database table prefix.' wp-config-sample.php >> wp-config.php
sed -i "s/database_name_here/$dbname/;s/username_here/$dbuser/;s/password_here/$userpass/" wp-config.php
#chown $USER:www-data -R * # Change user to current, group to server
chown www-data:www-data -R /var/www/$WPdomain/* # Change user to server, group to server
find /var/www/$WPdomain/wordpress -type d -exec chmod 755 {} \; # directory permissions rwxr-xr-x
find /var/www/$WPdomain/wordpress -type f -exec chmod 644 {} \; # file permissions rw-r--r--
chown www-data:www-data wp-content # Let server be owner of wp-content
WPVER=$(grep "wp_version = " /var/www/$WPdomain/wordpress/wp-includes/version.php |awk -F\' '{print $2}')
echo -e "${GREEN}[+]${NC} WordPress version $WPVER is successfully installed!"

####### CHECKS and INFO
echo "127.0.0.1	$WPdomain" >> /etc/hosts
echo -e "\t[*] Site can be browsed at${YELLOW} http://$WPdomain${NC}"
echo -e "\t[*] root directory of site:${YELLOW} /var/www/$WPdomain${NC}"
echo -e "\t[*] nginx configuration of site:${YELLOW} /etc/nginx/sites-available/$WPdomain${NC}"
echo -e "\t[*] Database user:${YELLOW} root${NC}"
echo -e "\t[*] Database password:${YELLOW} $rootpass${NC}"
echo -e "\t[*] Database name:${YELLOW} $dbname${NC}"
echo -e "\n${GREEN}[!] All done${NC}"


#TODO
#Setup for https
#maybe add var input prompt like in 


# https://gist.github.com/nginx-gists/bdc7da70b124c4f3e472970c7826cccc
# https://github.com/bhavin192/wpinstall/blob/master/wpinstall.sh
# https://github.com/hestiacp/hestiacp/blob/main/install/hst-install-debian.sh
