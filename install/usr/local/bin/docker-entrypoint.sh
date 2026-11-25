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
[ -n "${INSTALL_SECRET:-}" ] || die "INSTALL_SECRET is required"

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

# The image records the osTicket code it ships in this marker file. The
# webroot is a persistent volume, so the marker copied into it says which
# code is installed there. include/ is denied by nginx, so it is not served.
version_marker="include/.docker-osticket-version"
image_version="$(cat "/assets/install/${version_marker}" 2>/dev/null || echo "${OSTICKET_VERSION}")"
installed_version="$(cat "${NGINX_WEBROOT}/${version_marker}" 2>/dev/null || true)"

if [ ! -f "${NGINX_WEBROOT}/index.php" ]; then
    echo "** [osticket] New installation detected"
    mkdir -p "${NGINX_WEBROOT}"
    cp -a /assets/install/. "${NGINX_WEBROOT}/"
elif [ "${installed_version}" != "${image_version}" ]; then
    echo "** [osticket] Updating osTicket code from '${installed_version:-unknown}' to '${image_version}'"
    # Keep a copy of the code being replaced (config and plugins included)
    # next to it, and only the newest few copies.
    backup_dir="${NGINX_WEBROOT}/include/.code-backups"
    mkdir -p "${backup_dir}"
    chmod 700 "${backup_dir}"
    backup_file="${backup_dir}/osticket-code-$(date -u +%Y%m%dT%H%M%SZ).tar.gz"
    tar -C "${NGINX_WEBROOT}" --exclude=./include/.code-backups -czf "${backup_file}" .
    chmod 600 "${backup_file}"
    echo "** [osticket] Previous code saved to ${backup_file}"
    find "${backup_dir}" -maxdepth 1 -name 'osticket-code-*.tar.gz' -type f | sort -r | tail -n +4 | while read -r old_backup; do
        rm -f -- "${old_backup}"
    done
    # Overwrite the osTicket code. include/ost-config.php is not in the image
    # and is never touched. Installed plugins are kept as they are; plugins
    # the image adds are copied in only when missing.
    tar -C /assets/install --exclude=./include/plugins --exclude=./include/ost-config.php -cf - . \
        | tar -C "${NGINX_WEBROOT}" -xpf -
    mkdir -p "${NGINX_WEBROOT}/include/plugins"
    for plugin in /assets/install/include/plugins/*; do
        name="$(basename "${plugin}")"
        if [ ! -e "${NGINX_WEBROOT}/include/plugins/${name}" ]; then
            echo "** [osticket] Adding plugin ${name}"
            cp -a "${plugin}" "${NGINX_WEBROOT}/include/plugins/${name}"
        fi
    done
    code_updated=1
fi
if [ -f "${NGINX_WEBROOT}/include/class.util.php" ]; then
    php /usr/local/bin/patch-php84.php "${NGINX_WEBROOT}"
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

# TRUSTED_PROXIES: comma separated IPs or CIDRs of the reverse proxies in
# front of osTicket (for example the Docker network of Traefik and the
# Cloudflare ranges). osTicket then takes the client IP from
# X-Forwarded-For. VIRTUAL_HOST alone keeps the old behaviour of trusting
# every proxy ('*'), which lets clients fake their IP.
if [ -n "${TRUSTED_PROXIES:-}" ]; then
    case "${TRUSTED_PROXIES}" in
        *[!0-9A-Fa-f.:/,\ ]*) die "TRUSTED_PROXIES may only contain IP addresses, CIDRs and commas" ;;
    esac
    echo "** [osticket] Trusting reverse proxy headers from TRUSTED_PROXIES"
    sed -i "s|define('TRUSTED_PROXIES', '[^']*');|define('TRUSTED_PROXIES', '${TRUSTED_PROXIES}');|" \
        "${NGINX_WEBROOT}/include/ost-config.php"
elif [ -n "${VIRTUAL_HOST:-}" ]; then
    echo "** [osticket] Trusting reverse proxy headers from any proxy (set TRUSTED_PROXIES to restrict)"
    sed -i "s/define('TRUSTED_PROXIES', '');/define('TRUSTED_PROXIES', '*');/g" \
        "${NGINX_WEBROOT}/include/ost-config.php"
fi

chmod 644 "${NGINX_WEBROOT}/include/ost-config.php"
chown -R "${NGINX_USER}:${NGINX_GROUP}" "${NGINX_WEBROOT}" /www/logs
chmod -R a+rX "${NGINX_WEBROOT}"
chmod -R u+rw "${NGINX_WEBROOT}"
if [ -d "${NGINX_WEBROOT}/include/.code-backups" ]; then
    chown -R root:root "${NGINX_WEBROOT}/include/.code-backups"
    chmod -R go-rwx "${NGINX_WEBROOT}/include/.code-backups"
fi
if [ -d "${NGINX_WEBROOT}/setup_hidden" ]; then
    chown -R root:root "${NGINX_WEBROOT}/setup_hidden"
    chmod 700 "${NGINX_WEBROOT}/setup_hidden"
fi

# Apply database migrations after a code update. Nothing happens when the
# schema is already current.
if [ "${code_updated:-0}" = 1 ]; then
    if upgrade_out="$(cd "${NGINX_WEBROOT}" && su -s /bin/sh "${NGINX_USER}" -c "php manage.php upgrade" 2>&1)"; then
        echo "** [osticket] Database upgrade: ${upgrade_out}"
    else
        case "${upgrade_out}" in
            *"No upgrade is pending"*) echo "** [osticket] Database schema is current" ;;
            *) echo "** [osticket] WARNING: database upgrade failed, finish it at /scp/upgrade.php: ${upgrade_out}" >&2 ;;
        esac
    fi
fi

cat > /etc/cron.d/osticket <<EOF
*/${CRON_INTERVAL} * * * * root TZ=${TIMEZONE} /usr/local/bin/php -q ${NGINX_WEBROOT}/api/cron.php >/proc/1/fd/1 2>/proc/1/fd/2
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
