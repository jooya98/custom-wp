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

# Enable a subdirectory WordPress network on the platform hostname. These
# constants are inserted only once and remain in the persistent wp-config.php.
# Additional sites may use independent domains at the WordPress site layer.
if [[ -f /var/www/html/wp-config.php ]] && ! grep -q "define( 'MULTISITE'" /var/www/html/wp-config.php; then
    awk '/\/\* That.s all, stop editing/ {
        print "define( '\''MULTISITE'\'', true );"
        print "define( '\''SUBDOMAIN_INSTALL'\'', false );"
        print "define( '\''DOMAIN_CURRENT_SITE'\'', '\''deniz-wp.gerdoo.app'\'' );"
        print "define( '\''PATH_CURRENT_SITE'\'', '\''/'\'' );"
        print "define( '\''SITE_ID_CURRENT_SITE'\'', 1 );"
        print "define( '\''BLOG_ID_CURRENT_SITE'\'', 1 );"
    }
    { print }' /var/www/html/wp-config.php > /var/www/html/wp-config.php.tmp
    mv /var/www/html/wp-config.php.tmp /var/www/html/wp-config.php
    chown www-data:www-data /var/www/html/wp-config.php
fi

exec "$@"
