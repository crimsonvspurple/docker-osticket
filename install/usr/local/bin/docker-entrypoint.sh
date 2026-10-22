#!/bin/bash
set -euo pipefail

: "${NGINX_WEBROOT:=/www/osticket}"
: "${NGINX_USER:=www-data}"
: "${NGINX_GROUP:=www-data}"
: "${DB_PORT:=3306}"
: "${DB_PREFIX:=ost_}"
: "${CRON_INTERVAL:=10}"
: "${MEMCACHE_PORT:=11211}"
: "${TIMEZONE:=UTC}"

if [ -n "${CRON_PERIOD:-}" ]; then
    CRON_INTERVAL="${CRON_PERIOD}"
fi

die() {
    echo "** [osticket] $*" >&2
    exit 1
}

[ -n "${DB_HOST:-}" ] || die "DB_HOST is required"
[ -n "${DB_NAME:-}" ] || die "DB_NAME is required"
[ -n "${DB_USER:-}" ] || die "DB_USER is required"
[ -n "${DB_PASS:-}" ] || die "DB_PASS is required"
[ -n "${ADMIN_PASS:-}" ] || die "ADMIN_PASS is required"
[ -n "${ADMIN_EMAIL:-}" ] || die "ADMIN_EMAIL is required"
[ -n "${ADMIN_USER:-}" ] || die "ADMIN_USER is required"
[ "${#ADMIN_USER}" -ge 5 ] || die "ADMIN_USER must be at least 5 characters"

if [ -f "/usr/share/zoneinfo/${TIMEZONE}" ]; then
    ln -sfn "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
    echo "${TIMEZONE}" > /etc/timezone
    sed -i "s#^;\\?date.timezone =.*#date.timezone = ${TIMEZONE}#" /usr/local/etc/php/conf.d/osticket.ini
fi

echo "** [osticket] Waiting for database ${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
ready=0
for _ in $(seq 1 60); do
    if php -r '
        $m = mysqli_init();
        $m->options(MYSQLI_OPT_CONNECT_TIMEOUT, 3);
        try {
            if ($m->real_connect(getenv("DB_HOST"), getenv("DB_USER"), getenv("DB_PASS"), "", (int) getenv("DB_PORT"))) {
                exit(0);
            }
        } catch (Throwable $e) {
        }
        exit(1);
    '; then
        ready=1
        break
    fi
    sleep 2
done
[ "${ready}" = 1 ] || die "Database did not become ready"

install_script="$(mktemp)"
sed "s#<WEBROOT>#${NGINX_WEBROOT}#g" /assets/setup/install.php > "${install_script}"

if [ ! -f "${NGINX_WEBROOT}/index.php" ]; then
    echo "** [osticket] New installation detected"
    mkdir -p "${NGINX_WEBROOT}"
    cp -a /assets/install/. "${NGINX_WEBROOT}/"
fi
mkdir -p /www/logs "${NGINX_WEBROOT}"

php "${install_script}"
rm -f "${install_script}"

if [ -n "${MEMCACHE_HOST:-}" ]; then
    echo "** [osticket] Enabling memcache sessions"
    sed -i \
        -e "s|# define('SESSION_BACKEND', 'memcache');|define('SESSION_BACKEND', 'memcache');|g" \
        -e "s|# define('MEMCACHE_SERVERS', 'server1:11211,server2:11211');|define('MEMCACHE_SERVERS', '${MEMCACHE_HOST}:${MEMCACHE_PORT}');|g" \
        "${NGINX_WEBROOT}/include/ost-config.php"
fi

if [ -n "${VIRTUAL_HOST:-}" ]; then
    echo "** [osticket] Trusting reverse proxy headers"
    sed -i "s/define('TRUSTED_PROXIES', '');/define('TRUSTED_PROXIES', '*');/g" \
        "${NGINX_WEBROOT}/include/ost-config.php"
fi

chmod 644 "${NGINX_WEBROOT}/include/ost-config.php"
chown -R "${NGINX_USER}:${NGINX_GROUP}" "${NGINX_WEBROOT}" /www/logs
chmod -R a+rX "${NGINX_WEBROOT}"
chmod -R u+rw "${NGINX_WEBROOT}"
if [ -d "${NGINX_WEBROOT}/setup_hidden" ]; then
    chown -R root:root "${NGINX_WEBROOT}/setup_hidden"
    chmod 700 "${NGINX_WEBROOT}/setup_hidden"
fi

cat > /etc/cron.d/osticket <<EOF
*/${CRON_INTERVAL} * * * * root TZ=${TIMEZONE} php -q ${NGINX_WEBROOT}/api/cron.php >/proc/1/fd/1 2>/proc/1/fd/2
EOF
chmod 644 /etc/cron.d/osticket

echo "** [osticket] Starting cron, php-fpm, and nginx"
cron -f &
cron_pid=$!
php-fpm &
fpm_pid=$!
nginx -g 'daemon off;' &
nginx_pid=$!

stop() {
    kill "${cron_pid}" "${fpm_pid}" "${nginx_pid}" 2>/dev/null || true
    wait "${cron_pid}" "${fpm_pid}" "${nginx_pid}" 2>/dev/null || true
}

trap 'stop; exit 0' TERM INT
wait -n "${fpm_pid}" "${nginx_pid}"
status=$?
stop
exit "${status}"
