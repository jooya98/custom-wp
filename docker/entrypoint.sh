#!/usr/bin/env bash
set -Eeuo pipefail

# Gerdoo's managed MariaDB add-on exposes MYSQL_* variables. Normalize them
# to the names understood by the official WordPress entrypoint.
: "${WORDPRESS_DB_HOST:=${MYSQL_HOST:-}}"
: "${WORDPRESS_DB_NAME:=${MYSQL_DATABASE:-}}"
: "${WORDPRESS_DB_USER:=${MYSQL_USER:-}}"
: "${WORDPRESS_DB_PASSWORD:=${MYSQL_PASSWORD:-}}"
export WORDPRESS_DB_HOST WORDPRESS_DB_NAME WORDPRESS_DB_USER WORDPRESS_DB_PASSWORD

# A stale/empty application volume must not turn into nginx's directory 403.
if [[ ! -f /var/www/html/index.php ]]; then
    cp -a /usr/src/wordpress/. /var/www/html/
fi
chown -R www-data:www-data /var/www/html

# Let the official entrypoint create wp-config.php from the normalized values.
/usr/local/bin/docker-entrypoint.sh php-fpm -t

# Gerdoo's plain env editor may not preserve WORDPRESS_CONFIG_EXTRA. Make the
# required network-install flag deterministic in the image instead.
if [[ -f /var/www/html/wp-config.php ]] && ! grep -q "WP_ALLOW_MULTISITE" /var/www/html/wp-config.php; then
    awk '/\/\* That.s all, stop editing/ { print "define( '\''WP_ALLOW_MULTISITE'\'', true );" } { print }' \
        /var/www/html/wp-config.php > /var/www/html/wp-config.php.tmp
    mv /var/www/html/wp-config.php.tmp /var/www/html/wp-config.php
    chown www-data:www-data /var/www/html/wp-config.php
fi

exec "$@"
