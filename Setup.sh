#!/bin/bash

#
#
# Setup Script to Deploy and Configure the Console VM
# Date: 17/04/2017
# Creator: Sergio Delgado
# Git Repo: https://github.com/susurros
#
#



# VARIABLES
ERROR_LOG=/tmp/ConsoleVM_error.log
APP_HOME=/opt/ConsoleVM
CONF=$PWD/conf

# Update OS (Centos)
echo "######################  Updating System #################################"


yum update -y 2> /tmp/ConsoleVM_error.log
yum install -y yum-utils 2> /tmp/ConsoleVM_error.log
yum install -y epel-release 2>  /tmp/ConsoleVM_error.log


# Install Development Software
yum install -y bison byacc cscope ctags diffstat doxygen flex gcc gcc-c++ gcc-gfortran gettext indent intltool libtool patch patchutils rcs redhat-rpm-config rpm-build swig systemtap


########################################
#   APP Deployment and Configuration   #
########################################



## Install Required Sofware
yum install -y  python34-pip.noarch python34 git openssl-devel libffi-devel python34-devel zlib-devel bzip2-devel sqlite sqlite-devel openssl-devel
yum install -y tomcat nginx.x86_64


pip3 install --upgrade pip
pip install virtualenv




echo "######################  Virtual Env and App Deployment #################################"

## Download APP source if necesary
git clone https://github.com/susurros/ConsoleVM.git $APP_HOME

## Create Virtualenv
virtualenv -p python3 $APP_HOME/venv
source $APP_HOME/venv/bin/activate

pip3 install Django==1.9
pip3 install paramiko
pip3 install gunicorn


echo "######################  App Setup #################################"


## APP Migration
$APP_HOME/manage.py migrate
$APP_HOME/manage.py makemigrations console
$APP_HOME/manage.py migrate
## Create Super USer
echo "from django.contrib.auth.models import User; User.objects.create_superuser('admin', 'admin@uem', 'UEM2017')" | $APP_HOME/manage.py  shell
## Add VType Info
echo "from console.models import VType; VType.objects.create(name='ESXi',version='5.5',vendor='VW')" |  $APP_HOME/manage.py shell
echo "from console.models import VType; VType.objects.create(name='Zones Solaris',version='11',vendor='ZN')" | $APP_HOME/manage.py shell
echo "from console.models import VType; VType.objects.create(name='Virtual Box',version='5.1',vendor='VB')" | $APP_HOME/manage.py  shell
## Collect static
echo "from django.core.management import call_command; call_command('collectstatic', verbosity=0, interactive=False)" | $APP_HOME/manage.py  shell



deactivate

##############################################
#   Guacamole Deployment and Configuration   #
##############################################


echo "######################  Gucamole Deployment #################################"


## Install Required Software
yum install -y cairo-devel libjpeg-turbo-devel libjpeg-devel libpng-devel uuid-devel freerdp-devel pango-devel libssh2-devel libtelnet-devel libvncserver-devel pulseaudio-libs-devel openssl-devel libvorbis-devel  libwebp-devel
yum install -y tomcat

## Create Directories

mkdir  -p /etc/guacamole/extensions /etc/guacamole/lib

ln -s /etc/guacamole /usr/share/tomcat/.guacamole

## Download and Compile Guacamole

mkdir -p /tmp/guacd
cd /tmp/guacd

curl -O https://www.apache.org/dist/incubator/guacamole/0.9.12-incubating/source/guacamole-server-0.9.12-incubating.tar.gz
curl -O https://www.apache.org/dist/incubator/guacamole/0.9.12-incubating/binary/guacamole-0.9.12-incubating.war
curl -O https://www.apache.org/dist/incubator/guacamole/0.9.12-incubating/binary/guacamole-auth-noauth-0.9.12-incubating.tar.gz

cp guacamole-0.9.12-incubating.war /var/lib/tomcat/webapps/guacamole.war

tar -zxf guacamole-server-0.9.12-incubating.tar.gz
cd guacamole-server-0.9.12-incubating
autoreconf -fi
./configure --with-init-dir=/etc/init.d --prefix=$APP_HOME/guacd
make
make install

cd ..
tar -zxf guacamole-auth-noauth-0.9.12-incubating.tar.gz
cp guacamole-auth-noauth-0.9.12-incubating/guacamole-auth-noauth-0.9.12-incubating.jar /etc/guacamole/extensions/


## Copy configuration Files
cp $CONF/guacamole_profile.sh  /etc/profile.d/
cp $CONF/guacd.conf /etc/guacamole
cp $CONF/guacamole.properties  /etc/guacamole
cp $CONF/noauth-config.xml  /etc/guacamole


## Delete installation files
rm -rf /tmp/guacd/

##############################################
#   Gunicorn Deployment and Configuration    #
##############################################


echo "######################  Gunicorn Deployment #################################"

mkdir -p $APP_HOME/run
mv /etc/systemd/system/gunicorn /etc/systemd/system/gunicorn.service

echo -e "\
[Unit]
Description=gunicorn daemon
After=network.target

[Service]
# Update all paths below
# Setting provided are for reference only !
User=nginx
Group=nginx
WorkingDirectory=/opt/ConsoleVM
ExecStart=$APP_HOME/venv/bin/gunicorn --workers 3 --bind unix:$APP_HOME/run/DjangoWeb.sock --chdir $APP_HOME DjangoWeb.wsgi:application

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/gunicorn.service

systemctl daemons-reload

 

##########################################
#   Ngix Deployment and Configuration    #
##########################################


echo "######################  Nginx Deployment #################################"


## Create SSL Dir
mkdir /etc/nginx/ssl

## Create Server Certificates
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/nginx/ssl/nginx-selfsigned.key -out /etc/nginx/ssl/nginx-selfsigned.crt -subj "/C=GE/OU=UEM/CN=consolevm"
openssl dhparam -out /etc/nginx/ssl/dhparam.pem 2048

## Replace Ngix configuration file
rm -f /etc/nginx/nginx.conf

echo -e "\
 # For more information on configuration, see:
#   * Official English Documentation: http://nginx.org/en/docs/
#   * Official Russian Documentation: http://nginx.org/ru/docs/

user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

# Load dynamic modules. See /usr/share/nginx/README.dynamic.
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

    server {
        listen 443 http2 ssl;
        listen [::]:443 http2 ssl;

        #server_name ;

        ssl_certificate /etc/nginx/ssl/nginx-selfsigned.crt;
        ssl_certificate_key /etc/nginx/ssl/nginx-selfsigned.key;
        ssl_dhparam /etc/nginx/ssl/dhparam.pem;

        access_log /var/log/nginx/access.log;
        error_log /var/log/nginx/error.log;

        index index.php index.html index.htm;

        location = /favicon.ico { access_log off; log_not_found off; }

        # serve static content
        location /static {
               # Update correct static folder path
                root $APP_HOME;
        }

        location / {
            auth_basic "Restricted Content";
            auth_basic_user_file $APP_HOME/secret/nginx.pass;
            proxy_set_header Host $http_host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;

            # use the sock created in above gunicorn file
            proxy_pass http://unix:$APP_HOME/run/DjangoWeb.sock;
        }

        location /guacamole/ {
            proxy_pass http://127.0.0.1:8080/guacamole/;
            proxy_buffering off;
            proxy_http_version 1.1;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $http_connection;
            access_log off;
        }

    }
}" >> /etc/nginx/nginx.conf



mkdir -p $APP_HOME/secret



echo "Plesae write a user for the nginx authentication, followed by [ENTER]:"
read http_user
sh -c "echo -n '$http_user:' >> $APP_HOME/secret/nginx.pass"
echo "Please write the password for the nginx authentication, followed by [ENTER]:"
sh -c "openssl passwd -apr1 >> $APP_HOME/secret/nginx.pass"


###############################
#  Generate SSL Private Key   #
###############################

ssh-keygen -f $APP_HOME/secret/labkey -t rsa -N ''


###############################
#  Firewalld Configure Rules  #
###############################

firewall-cmd --add-service=https
firewall-cmd --runtime-to-permanent
systemctl restart firewalld 

##########################
#     Start Services     #
##########################

/etc/init.d/guacd start
systemctl start tomcat
systemctl start gunicorn
systemctl start nginx
