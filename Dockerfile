ARG PHP_VERSION=8.4.27

FROM php:${PHP_VERSION}-fpm-trixie

LABEL maintainer="CvP (github.com/crimsonvspurple)" \
      org.opencontainers.image.title="osTicket" \
      org.opencontainers.image.description="osTicket v1.18.4 on PHP 8.4" \
      org.opencontainers.image.source="https://github.com/crimsonvspurple/docker-osticket" \
      org.opencontainers.image.licenses="MIT"

ARG OSTICKET_VERSION=v1.18.4
ARG OSTICKET_PLUGINS_SHA=67a1450f2f79cec0524385de6ad35207369f32e4
ARG PLUGIN_ARCHIVER_SHA=a1e20bb230f0943769c0e548539d553881ecfb1e
ARG PLUGIN_ATTACHMENT_PREVIEW_SHA=50bbb30c20251f25f43cc1854fcacd45ee6d0c0e
ARG PLUGIN_AUTO_CLOSER_SHA=e367b013bb89eb2b27d69c25db920b3e7c0359ec
ARG PLUGIN_FETCH_NOTE_SHA=7bd28052a33d448db68e0393ca5d92f1b1744283
ARG PLUGIN_MENTIONER_SHA=4a39ba6b34f46b3f9749f0d60753a504e6d8ec2a
ARG PLUGIN_MULTI_LDAP_SHA=3e4d23273b87ab1310490d2467e382fa1de8923c
ARG PLUGIN_PREVENT_AUTOSCROLL_SHA=2b5c51200d0f64da15d1f504e9294d877577fc46
ARG PLUGIN_REWRITER_SHA=2c5e3bad0f0cb94a1b51a33a854cfd551ea67e30
ARG PLUGIN_SLACK_SHA=15c0cadfbc0c0548cde5750eda5f29d36381683b
ARG PLUGIN_TEAMS_SHA=7326b8d5b8ac4314e825a88f8dad07e93ac4c59b

ENV OSTICKET_VERSION=${OSTICKET_VERSION} \
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
    mkdir -p /usr/src/plugins; \
    git -C /usr/src/plugins init; \
    git -C /usr/src/plugins remote add origin "${OSTICKET_PLUGINS_REPO_URL}"; \
    git -C /usr/src/plugins fetch --depth 1 origin "${OSTICKET_PLUGINS_SHA}"; \
    git -C /usr/src/plugins checkout --detach FETCH_HEAD; \
    cd /usr/src/plugins; \
    php -d phar.readonly=0 make.php hydrate; \
    mkdir -p /assets/install/include/plugins; \
    for plugin in /usr/src/plugins/*/plugin.php; do \
        name="$(basename "$(dirname "${plugin}")")"; \
        cp -a "$(dirname "${plugin}")" "/assets/install/include/plugins/${name}"; \
    done; \
    cd /; \
    \
    mkdir -p /assets/install/include/plugins/archiver; \
    git -C /assets/install/include/plugins/archiver init; \
    git -C /assets/install/include/plugins/archiver remote add origin https://github.com/clonemeagain/osticket-plugin-archiver.git; \
    git -C /assets/install/include/plugins/archiver fetch --depth 1 origin "${PLUGIN_ARCHIVER_SHA}"; \
    git -C /assets/install/include/plugins/archiver checkout --detach FETCH_HEAD; \
    mkdir -p /assets/install/include/plugins/attachment-preview; \
    git -C /assets/install/include/plugins/attachment-preview init; \
    git -C /assets/install/include/plugins/attachment-preview remote add origin https://github.com/clonemeagain/attachment_preview.git; \
    git -C /assets/install/include/plugins/attachment-preview fetch --depth 1 origin "${PLUGIN_ATTACHMENT_PREVIEW_SHA}"; \
    git -C /assets/install/include/plugins/attachment-preview checkout --detach FETCH_HEAD; \
    mkdir -p /assets/install/include/plugins/auto-closer; \
    git -C /assets/install/include/plugins/auto-closer init; \
    git -C /assets/install/include/plugins/auto-closer remote add origin https://github.com/clonemeagain/plugin-autocloser.git; \
    git -C /assets/install/include/plugins/auto-closer fetch --depth 1 origin "${PLUGIN_AUTO_CLOSER_SHA}"; \
    git -C /assets/install/include/plugins/auto-closer checkout --detach FETCH_HEAD; \
    mkdir -p /assets/install/include/plugins/fetch-note; \
    git -C /assets/install/include/plugins/fetch-note init; \
    git -C /assets/install/include/plugins/fetch-note remote add origin https://github.com/bkonetzny/osticket-fetch-note.git; \
    git -C /assets/install/include/plugins/fetch-note fetch --depth 1 origin "${PLUGIN_FETCH_NOTE_SHA}"; \
    git -C /assets/install/include/plugins/fetch-note checkout --detach FETCH_HEAD; \
    mkdir -p /assets/install/include/plugins/mentioner; \
    git -C /assets/install/include/plugins/mentioner init; \
    git -C /assets/install/include/plugins/mentioner remote add origin https://github.com/clonemeagain/osticket-plugin-mentioner.git; \
    git -C /assets/install/include/plugins/mentioner fetch --depth 1 origin "${PLUGIN_MENTIONER_SHA}"; \
    git -C /assets/install/include/plugins/mentioner checkout --detach FETCH_HEAD; \
    mkdir -p /assets/install/include/plugins/multi-ldap; \
    git -C /assets/install/include/plugins/multi-ldap init; \
    git -C /assets/install/include/plugins/multi-ldap remote add origin https://github.com/philbertphotos/osticket-multildap-auth-plugin.git; \
    git -C /assets/install/include/plugins/multi-ldap fetch --depth 1 origin "${PLUGIN_MULTI_LDAP_SHA}"; \
    git -C /assets/install/include/plugins/multi-ldap checkout --detach FETCH_HEAD; \
    if [ -d /assets/install/include/plugins/multi-ldap/multi-ldap ]; then \
        mv /assets/install/include/plugins/multi-ldap /tmp/multi-ldap-src; \
        mkdir -p /assets/install/include/plugins/multi-ldap; \
        cp -a /tmp/multi-ldap-src/multi-ldap/. /assets/install/include/plugins/multi-ldap/; \
        rm -rf /tmp/multi-ldap-src; \
    fi; \
    mkdir -p /assets/install/include/plugins/prevent-autoscroll; \
    git -C /assets/install/include/plugins/prevent-autoscroll init; \
    git -C /assets/install/include/plugins/prevent-autoscroll remote add origin https://github.com/clonemeagain/osticket-plugin-preventautoscroll.git; \
    git -C /assets/install/include/plugins/prevent-autoscroll fetch --depth 1 origin "${PLUGIN_PREVENT_AUTOSCROLL_SHA}"; \
    git -C /assets/install/include/plugins/prevent-autoscroll checkout --detach FETCH_HEAD; \
    mkdir -p /assets/install/include/plugins/rewriter; \
    git -C /assets/install/include/plugins/rewriter init; \
    git -C /assets/install/include/plugins/rewriter remote add origin https://github.com/clonemeagain/plugin-fwd-rewriter.git; \
    git -C /assets/install/include/plugins/rewriter fetch --depth 1 origin "${PLUGIN_REWRITER_SHA}"; \
    git -C /assets/install/include/plugins/rewriter checkout --detach FETCH_HEAD; \
    mkdir -p /assets/install/include/plugins/slack; \
    git -C /assets/install/include/plugins/slack init; \
    git -C /assets/install/include/plugins/slack remote add origin https://github.com/clonemeagain/osticket-slack.git; \
    git -C /assets/install/include/plugins/slack fetch --depth 1 origin "${PLUGIN_SLACK_SHA}"; \
    git -C /assets/install/include/plugins/slack checkout --detach FETCH_HEAD; \
    mkdir -p /assets/install/include/plugins/teams; \
    git -C /assets/install/include/plugins/teams init; \
    git -C /assets/install/include/plugins/teams remote add origin https://github.com/Data-Tech-International/osTicket-Microsoft-Teams-plugin.git; \
    git -C /assets/install/include/plugins/teams fetch --depth 1 origin "${PLUGIN_TEAMS_SHA}"; \
    git -C /assets/install/include/plugins/teams checkout --detach FETCH_HEAD; \
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
