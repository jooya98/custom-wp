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

# Enable a subdirectory WordPress network on the canonical platform hostname.
# The domain is configurable so the persistent wp-config.php can be migrated
# without touching WordPress site records or child-site routing.
: "${WORDPRESS_NETWORK_DOMAIN:=network.denizagency.ir}"
export WORDPRESS_NETWORK_DOMAIN

domain_line="define( 'DOMAIN_CURRENT_SITE', '${WORDPRESS_NETWORK_DOMAIN}' );"
if [[ -f /var/www/html/wp-config.php ]]; then
    if grep -q "define( 'MULTISITE'" /var/www/html/wp-config.php; then
        # Reconcile only the network root constant on an existing volume.
        awk -v domain_line="$domain_line" '/DOMAIN_CURRENT_SITE/ { print domain_line; next } { print }' \
            /var/www/html/wp-config.php > /var/www/html/wp-config.php.tmp
    else
        # Add the multisite constants during first initialization.
        awk -v domain_line="$domain_line" '/\/\* That.s all, stop editing/ {
            print "define( '\''MULTISITE'\'', true );"
            print "define( '\''SUBDOMAIN_INSTALL'\'', false );"
            print domain_line
            print "define( '\''PATH_CURRENT_SITE'\'', '\''/'\'' );"
            print "define( '\''SITE_ID_CURRENT_SITE'\'', 1 );"
            print "define( '\''BLOG_ID_CURRENT_SITE'\'', 1 );"
        }
        { print }' /var/www/html/wp-config.php > /var/www/html/wp-config.php.tmp
    fi
    mv /var/www/html/wp-config.php.tmp /var/www/html/wp-config.php
    chown www-data:www-data /var/www/html/wp-config.php
fi

exec "$@"
