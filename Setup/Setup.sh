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

echo "######################  APP Deployment #################################"

## Install Required Sofware
yum install -y  python34-pip.noarch python34 git openssl-devel libffi-devel python34-devel zlib-devel bzip2-devel sqlite sqlite-devel openssl-devel



pip3 install --upgrade pip
pip install virtualenv

## Download APP source if necesary
git clone https://github.com/susurros/ConsoleVM.git $APP_HOME

## Create Virtualenv
virtualenv -p python3 $APP_HOME/venv
source $APP_HOME/venv/bin/activate

pip3 install Django==1.9
pip3 install paramiko


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


$APP_HOME/venv/bin/deactivate

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



## Install Required Software

mkdir -p $APP_HOME/run
pip3 install gunicorn
cp $CONF/gunicorn.service etc/systemd/system/



##########################################
#   Ngix Deployment and Configuration    #
##########################################


echo "######################  Nginx Deployment #################################"


## Install Required Software
yum install -y tomcat nginx.x86_64

## Create SSL Dir
mkdir /etc/nginx/ssl

## Create Server Certificates
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/nginx/ssl/nginx-selfsigned.key -out /etc/nginx/ssl/nginx-selfsigned.crt -subj "/C=GE/OU=UEM/CN=consolevm"
openssl dhparam -out /etc/nginx/ssl/dhparam.pem 2048

## Replace Ngix configuration file
rm -f /etc/nginx/nginx.conf
cp $CONF/nginx.conf /etc/nginx/

mkdir -p $APP_HOME/secret


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
