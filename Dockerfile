ARG PHP_VERSION=8.4.27

FROM php:${PHP_VERSION}-fpm-bookworm

LABEL maintainer="CvP (github.com/crimsonvspurple)" \
      org.opencontainers.image.title="osTicket" \
      org.opencontainers.image.description="osTicket v1.18.4 on PHP 8.4" \
      org.opencontainers.image.source="https://github.com/crimsonvspurple/docker-osticket" \
      org.opencontainers.image.licenses="MIT"

ARG OSTICKET_VERSION=v1.18.4
ARG OSTICKET_PLUGINS_VERSION=develop

ENV OSTICKET_VERSION=${OSTICKET_VERSION} \
    OSTICKET_PLUGINS_VERSION=${OSTICKET_PLUGINS_VERSION} \
    OSTICKET_REPO_URL=https://github.com/osTicket/osTicket \
    OSTICKET_PLUGINS_REPO_URL=https://github.com/osTicket/osTicket-plugins \
    DB_PREFIX=ost_ \
    DB_PORT=3306 \
    CRON_INTERVAL=10 \
    MEMCACHE_PORT=11211 \
    NGINX_USER=www-data \
    NGINX_GROUP=www-data \
    NGINX_WEBROOT=/www/osticket \
    TIMEZONE=UTC \
    IMAGE_NAME="crimsonvspurple/docker-osticket" \
    IMAGE_REPO_URL="https://github.com/crimsonvspurple/docker-osticket/"

COPY install/php/osticket.ini /usr/local/etc/php/conf.d/osticket.ini

RUN set -eux; \
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        cron \
        git \
        libfreetype6-dev \
        libicu-dev \
        libjpeg62-turbo-dev \
        libldap2-dev \
        libmemcached-dev \
        libpng-dev \
        libsasl2-dev \
        libssl-dev \
        libzip-dev \
        mariadb-client \
        msmtp \
        msmtp-mta \
        nginx \
        tzdata \
        unzip \
        zlib1g-dev \
    ; \
    docker-php-ext-configure gd --with-freetype --with-jpeg; \
    docker-php-ext-install -j"$(nproc)" \
        gd \
        gettext \
        intl \
        ldap \
        mysqli \
        opcache \
        zip \
    ; \
    pecl install apcu; \
    pecl install --configureoptions 'with-libmemcached-dir="yes" with-zlib-dir="yes" enable-memcached-igbinary="no" enable-memcached-msgpack="no" enable-memcached-json="no" enable-memcached-protocol="no" enable-memcached-sasl="no" enable-memcached-session="yes" with-system-fastlz="no"' memcached; \
    docker-php-ext-enable apcu memcached; \
    \
    git clone --depth 1 --branch "${OSTICKET_VERSION}" "${OSTICKET_REPO_URL}" /assets/install; \
    gitrev="$(git -C /assets/install rev-parse --short=12 HEAD)"; \
    sed -i \
        -e "s/define('GIT_VERSION','\$git');/define('GIT_VERSION','${gitrev}');/" \
        -e "s/define('THIS_VERSION', MAJOR_VERSION.'-git');/define('THIS_VERSION', '${OSTICKET_VERSION}');/" \
        -e "s/ini_set('display_errors', 1);/ini_set('display_errors', 0);/" \
        -e "s/ini_set('display_startup_errors', 1);/ini_set('display_startup_errors', 0);/" \
        /assets/install/bootstrap.php; \
    rm -rf /assets/install/.git; \
    chown -R "${NGINX_USER}:${NGINX_GROUP}" /assets/install; \
    chmod -R a+rX /assets/install; \
    chmod -R u+rw /assets/install; \
    mv /assets/install/setup /assets/install/setup_hidden; \
    chown -R root:root /assets/install/setup_hidden; \
    chmod 700 /assets/install/setup_hidden; \
    \
    git clone --depth 1 --branch "${OSTICKET_PLUGINS_VERSION}" "${OSTICKET_PLUGINS_REPO_URL}" /usr/src/plugins; \
    cd /usr/src/plugins; \
    php -d phar.readonly=0 make.php hydrate; \
    mkdir -p /assets/install/include/plugins; \
    for plugin in /usr/src/plugins/*/plugin.php; do \
        name="$(basename "$(dirname "${plugin}")")"; \
        cp -a "$(dirname "${plugin}")" "/assets/install/include/plugins/${name}"; \
    done; \
    cd /; \
    \
    git clone --depth 1 --branch master https://github.com/clonemeagain/osticket-plugin-archiver.git /assets/install/include/plugins/archiver; \
    git clone --depth 1 --branch master https://github.com/clonemeagain/attachment_preview.git /assets/install/include/plugins/attachment-preview; \
    git clone --depth 1 --branch master https://github.com/clonemeagain/plugin-autocloser.git /assets/install/include/plugins/auto-closer; \
    git clone --depth 1 --branch master https://github.com/bkonetzny/osticket-fetch-note.git /assets/install/include/plugins/fetch-note; \
    git clone --depth 1 --branch master https://github.com/clonemeagain/osticket-plugin-mentioner.git /assets/install/include/plugins/mentioner; \
    git clone --depth 1 --branch master https://github.com/philbertphotos/osticket-multildap-auth-plugin.git /assets/install/include/plugins/multi-ldap; \
    if [ -d /assets/install/include/plugins/multi-ldap/multi-ldap ]; then \
        mv /assets/install/include/plugins/multi-ldap /tmp/multi-ldap-src; \
        mkdir -p /assets/install/include/plugins/multi-ldap; \
        cp -a /tmp/multi-ldap-src/multi-ldap/. /assets/install/include/plugins/multi-ldap/; \
        rm -rf /tmp/multi-ldap-src; \
    fi; \
    git clone --depth 1 --branch master https://github.com/clonemeagain/osticket-plugin-preventautoscroll.git /assets/install/include/plugins/prevent-autoscroll; \
    git clone --depth 1 --branch master https://github.com/clonemeagain/plugin-fwd-rewriter.git /assets/install/include/plugins/rewriter; \
    git clone --depth 1 --branch master https://github.com/clonemeagain/osticket-slack.git /assets/install/include/plugins/slack; \
    git clone --depth 1 --branch master https://github.com/Data-Tech-International/osTicket-Microsoft-Teams-plugin.git /assets/install/include/plugins/teams; \
    find /assets/install/include/plugins -name .git -type d -print0 | xargs -0 rm -rf; \
    \
    rm -f /etc/nginx/sites-enabled/default; \
    sed -i 's|^listen = .*|listen = 127.0.0.1:9000|' /usr/local/etc/php-fpm.d/docker.conf; \
    mkdir -p /www/logs /var/log/nginx /run/nginx; \
    touch /var/log/msmtp.log; \
    chown "${NGINX_USER}:${NGINX_GROUP}" /var/log/msmtp.log /www/logs; \
    \
    apt-get purge -y --auto-remove git; \
    rm -rf /usr/src/plugins /tmp/pear /var/lib/apt/lists/*

COPY install/nginx/osticket.conf /etc/nginx/sites-available/osticket.conf
COPY install/assets /assets
COPY install/usr/local/bin/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY install/usr/local/bin/patch-php84.php /usr/local/bin/patch-php84.php

RUN ln -sf /etc/nginx/sites-available/osticket.conf /etc/nginx/sites-enabled/osticket.conf \
    && chmod 755 /usr/local/bin/docker-entrypoint.sh

EXPOSE 80

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
