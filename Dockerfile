# Version 0.0.2
FROM ubuntu:22.04
LABEL maintainer="Referral Factory <support@referral-factory.com>"
LABEL org.opencontainers.image.source=https://github.com/referral-factory/encryption-docker-base
LABEL org.opencontainers.image.description="Base Docker image for setting up an encrypted container for Referral Factory"

ENV DEBIAN_FRONTEND=noninteractive

# Set a volume for persistence of data
VOLUME /var/lib/mysql

# Add "encryption" user to be used throughout
RUN useradd -ms /bin/bash encryption
RUN usermod -aG www-data encryption

# Set the working directory and ownership
WORKDIR /var/www/html

RUN apt update \
  && apt install -y software-properties-common supervisor sudo && \
  add-apt-repository universe && \
  apt-get update && \
  apt-get install -y certbot python3-certbot-nginx memcached libmemcached-tools mcron
    
RUN add-apt-repository -y ppa:ondrej/php \
  && apt update

RUN apt install -y openssl \
  imagemagick \
  imagemagick-doc \ 
  git \
  curl \
  git \
  curl \
  libpng-dev \
  libonig-dev \
  libxml2-dev \
  zip \
  unzip \
  nginx \
  php8.1-fpm \
  php8.1-mysql \
  php8.1-pgsql \
  php8.1-xml \
  php8.1-common \
  php8.1-memcached \
  php8.1-mbstring \
  php8.1-gd \
  php8.1-imagick \
  php8.1-curl \
  php8.1-zip \
  mariadb-server \
  && apt clean

# Install Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Override PHP defaults and ensure logging is output to stdout for supervisor
RUN sed -i "s/max_execution_time = .*/max_execution_time = ${PHP_MAX_EXECUTION}/" /etc/php/8.1/fpm/php.ini
RUN sed -i "s#error_log = /var/log/php8.1-fpm.log#error_log = /proc/self/fd/2#" /etc/php/8.1/fpm/php-fpm.conf
RUN sed -i "s#listen = /run/php/php8.1-fpm.sock#listen = /home/encryption/socks/php8.1-fpm.sock#" /etc/php/8.1/fpm/pool.d/www.conf
RUN sed -i "s#listen.owner = www-data#;listen.owner = www-data#" /etc/php/8.1/fpm/pool.d/www.conf
RUN sed -i "s#listen.group = www-data#;listen.group = www-data#" /etc/php/8.1/fpm/pool.d/www.conf

RUN mkdir -p /run/php
RUN chown encryption:encryption /run/php
RUN chmod 755 /run/php
    
# Remove and override default Nginx configuration
RUN sed -i "s/user www-data;/#user www-data;/" /etc/nginx/nginx.conf
RUN sed -i "s#access_log /var/log/nginx/access.log;#access_log /home/encryption/log/nginx/access.log;#" /etc/nginx/nginx.conf
RUN sed -i "s#error_log /var/log/nginx/error.log;#error_log /home/encryption/log/nginx/error.log;#" /etc/nginx/nginx.conf
RUN sed -i "s#pid /run/nginx.pid;#pid /home/encryption/run/nginx.pid;#" /etc/nginx/nginx.conf

RUN echo "error_log /home/encryption/log/nginx/error.log;" > /etc/nginx/conf.d/error_log.conf

RUN mkdir -p /var/lib/nginx/body
RUN mkdir -p /var/lib/nginx/proxy
RUN mkdir -p /var/lib/nginx/fastcgi
RUN chown -R encryption:encryption /var/lib/nginx
RUN chown -R encryption:encryption /var/log/nginx
RUN chmod -R 755 /var/lib/nginx

RUN chown -R encryption:encryption /etc/nginx/
RUN rm /etc/nginx/sites-enabled/default
RUN rm /etc/nginx/sites-available/default

# Setup some default permissions
RUN mkdir -p /var/run/
RUN chown encryption:encryption /var/run/

RUN mkdir -p /home/encryption/socks/mysqld/ && \
    mkdir -p /home/encryption/run/mysqld/ && \
    mkdir -p /home/encryption/letsencrypt/ && \
    chown -R encryption:encryption /home/encryption/socks && \
    chown -R encryption:encryption /home/encryption/run && \
    chown -R encryption:encryption /home/encryption/letsencrypt

RUN chmod 755 /home/encryption/socks/
RUN chmod 755 /home/encryption/socks/mysqld
RUN chmod 755 /home/encryption/run
RUN chmod 755 /home/encryption/run/mysqld

# Add our own Nginx configuration for PHP
ADD ./nginx/nginx.conf /etc/nginx/sites-available/default
RUN ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/

# Setup supervisord
COPY ./supervisor/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
RUN chown -R encryption:encryption /etc/supervisor/conf.d/

# Setup mariadb permissions and configuration
RUN sed -i "s%socket = /run/mysqld/mysqld.sock%socket = /home/encryption/socks/mysqld/mysqld.sock%" "/etc/mysql/mariadb.cnf"
RUN sed -i "s%pid-file                = /run/mysqld/mysqld.pid%pid-file                = /home/encryption/run/mysqld/mysqld.pid%" "/etc/mysql/mariadb.conf.d/50-server.cnf"
RUN sed -i "s/#user                    = mysql/user                    = encryption/" "/etc/mysql/mariadb.conf.d/50-server.cnf"
RUN sed -i "s%#log_error = /var/log/mysql/error.log%log_error = /var/log/mysql/error.log%" "/etc/mysql/mariadb.conf.d/50-server.cnf"

RUN chown -R encryption:encryption /var/log/mysql/
RUN chown -R encryption:encryption /var/lib/mysql/

# Setup mcron
COPY ./crontabs/app-update.scm /etc/mcron/app-update.scm

WORKDIR /var/www/html
RUN rm -rf index*

# Create app directory
RUN mkdir app

# Copy scripts and ensure it can be run
COPY ./scripts/ docker-scripts
RUN chmod +x /var/www/html/docker-scripts/start-app.sh
RUN chmod +x /var/www/html/docker-scripts/update-app.sh

# Copy the .env.template file as .env
COPY .env.template .env

# Set permissions
RUN chown -R encryption:www-data /var/www/html

# Expose ports (8080 for HTTP, 8443 for HTTPS, 83306 for MySQL, 9001 for Supervisor)
EXPOSE 8080 8443 33306 9001

# Switch to the "encryption" user
USER encryption

# Setup user directories for sock files and logs
RUN mkdir -p /home/encryption/log/nginx
RUN mkdir /home/encryption/log/letsencrypt
RUN mkdir /home/encryption/log/referral-factory
RUN touch /home/encryption/log/mcron.log
RUN touch /home/encryption/log/mysql.log

RUN chmod 755 /home/encryption/log/nginx

RUN chown -R encryption:encryption /home/encryption/socks/mysqld/
RUN chown -R encryption:encryption /home/encryption/run/mysqld/

ENTRYPOINT ["/bin/bash", "-c", "/var/www/html/docker-scripts/start-app.sh"]