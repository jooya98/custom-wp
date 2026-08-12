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
# The official image keeps the immutable WordPress payload in /usr/src/wordpress;
# repopulate the document root when the mounted volume has no index.php.
if [[ ! -f /var/www/html/index.php ]]; then
    cp -a /usr/src/wordpress/. /var/www/html/
fi
chown -R www-data:www-data /var/www/html

# Initialize wp-config.php and then validate PHP-FPM before starting supervisor.
/usr/local/bin/docker-entrypoint.sh php-fpm -t

exec "$@"
