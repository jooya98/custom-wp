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

# Keep a fresh database in normal WordPress mode until the administrator runs
# Network Setup. Once wp_blogs exists, reconcile the network root hostname.
: "${WORDPRESS_NETWORK_DOMAIN:=network.denizagency.ir}"
export WORDPRESS_NETWORK_DOMAIN

domain_line="define( 'DOMAIN_CURRENT_SITE', '${WORDPRESS_NETWORK_DOMAIN}' );"
network_tables="unknown"
if [[ -n "${WORDPRESS_DB_HOST:-}" && -n "${WORDPRESS_DB_NAME:-}" ]]; then
    # A direct table probe avoids shell/PHP/SQL quote-escaping layers.
    network_tables="$(php -r 'mysqli_report(MYSQLI_REPORT_OFF); $m=@mysqli_connect(getenv("WORDPRESS_DB_HOST"),getenv("WORDPRESS_DB_USER"),getenv("WORDPRESS_DB_PASSWORD"),getenv("WORDPRESS_DB_NAME")); if (!$m) exit; $r=@mysqli_query($m,"SELECT 1 FROM wp_blogs LIMIT 1"); echo $r ? "present" : "absent";' 2>/dev/null || true)"
fi
if [[ -f /var/www/html/wp-config.php ]]; then
    if [[ "$network_tables" == "present" ]]; then
        # Network Setup has completed. Remove stale/duplicate bootstrap lines,
        # then write one complete canonical subdirectory-network definition.
        sed -E \
            -e "/define\\( 'WP_ALLOW_MULTISITE'/d" \
            -e "/define\\( 'MULTISITE'/d" \
            -e "/define\\( 'SUBDOMAIN_INSTALL'/d" \
            -e "/define\\( 'DOMAIN_CURRENT_SITE'/d" \
            -e "/define\\( 'PATH_CURRENT_SITE'/d" \
            -e "/define\\( 'SITE_ID_CURRENT_SITE'/d" \
            -e "/define\\( 'BLOG_ID_CURRENT_SITE'/d" \
            -e "/\\/\\* That's all, stop editing/ i define( 'MULTISITE', true );" \
            -e "/\\/\\* That's all, stop editing/ i define( 'SUBDOMAIN_INSTALL', false );" \
            -e "/\\/\\* That's all, stop editing/ i ${domain_line}" \
            -e "/\\/\\* That's all, stop editing/ i define( 'PATH_CURRENT_SITE', '/' );" \
            -e "/\\/\\* That's all, stop editing/ i define( 'SITE_ID_CURRENT_SITE', 1 );" \
            -e "/\\/\\* That's all, stop editing/ i define( 'BLOG_ID_CURRENT_SITE', 1 );" \
            /var/www/html/wp-config.php > /var/www/html/wp-config.php.tmp
        mv /var/www/html/wp-config.php.tmp /var/www/html/wp-config.php
    elif [[ "$network_tables" == "absent" ]]; then
        # The normal installer has run, but Network Setup has not. Remove only
        # the premature network constants from this image's prior bootstrap.
        sed -E \
            -e "/define\\( 'MULTISITE'/d" \
            -e "/define\\( 'SUBDOMAIN_INSTALL'/d" \
            -e "/define\\( 'DOMAIN_CURRENT_SITE'/d" \
            -e "/define\\( 'PATH_CURRENT_SITE'/d" \
            -e "/define\\( 'SITE_ID_CURRENT_SITE'/d" \
            -e "/define\\( 'BLOG_ID_CURRENT_SITE'/d" \
            -e "/\\/\\* That's all, stop editing/ i define( 'WP_ALLOW_MULTISITE', true );" \
            /var/www/html/wp-config.php > /var/www/html/wp-config.php.tmp
        mv /var/www/html/wp-config.php.tmp /var/www/html/wp-config.php
    elif ! grep -q "define( 'MULTISITE'" /var/www/html/wp-config.php; then
        # A database that is not yet reachable still needs the Network Setup
        # capability, but must not be forced into Multisite prematurely.
        sed -E "/\\/\\* That's all, stop editing/ i define( 'WP_ALLOW_MULTISITE', true );" \
            /var/www/html/wp-config.php > /var/www/html/wp-config.php.tmp
        mv /var/www/html/wp-config.php.tmp /var/www/html/wp-config.php
    fi
    chown www-data:www-data /var/www/html/wp-config.php
fi

exec "$@"
