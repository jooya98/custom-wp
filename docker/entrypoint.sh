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
    network_tables="$(php -r '$m=@mysqli_connect(getenv("WORDPRESS_DB_HOST"),getenv("WORDPRESS_DB_USER"),getenv("WORDPRESS_DB_PASSWORD"),getenv("WORDPRESS_DB_NAME")); if (!$m) exit; $r=@mysqli_query($m,"SHOW TABLES LIKE \\\"wp_blogs\\\""); echo ($r && mysqli_num_rows($r) > 0) ? "present" : "absent";' 2>/dev/null || true)"
fi
if [[ -f /var/www/html/wp-config.php ]]; then
    if [[ "$network_tables" == "present" ]]; then
        # Network Setup has completed; reconcile only the network root constant.
        if grep -q "define( 'MULTISITE'" /var/www/html/wp-config.php; then
            awk -v domain_line="$domain_line" '/DOMAIN_CURRENT_SITE/ { print domain_line; next } { print }' \
                /var/www/html/wp-config.php > /var/www/html/wp-config.php.tmp
            mv /var/www/html/wp-config.php.tmp /var/www/html/wp-config.php
        fi
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
        awk '/\\/\\* That.s all, stop editing/ { print "define( '\''WP_ALLOW_MULTISITE'\'', true );" } { print }' \
            /var/www/html/wp-config.php > /var/www/html/wp-config.php.tmp
        mv /var/www/html/wp-config.php.tmp /var/www/html/wp-config.php
    fi
    chown www-data:www-data /var/www/html/wp-config.php
fi

# Reconcile database connection constants on persistent volumes. The official
# WordPress entrypoint intentionally does not rewrite an existing wp-config.php,
# but Gerdoo may rotate managed-addon credentials or connection metadata.
if [[ -f /var/www/html/wp-config.php && -n "${WORDPRESS_DB_HOST:-}" ]]; then
    db_name_line="define( 'DB_NAME', '${WORDPRESS_DB_NAME//\\/\\\\}' );"
    db_user_line="define( 'DB_USER', '${WORDPRESS_DB_USER//\\/\\\\}' );"
    db_password_line="define( 'DB_PASSWORD', '${WORDPRESS_DB_PASSWORD//\\/\\\\}' );"
    db_host_line="define( 'DB_HOST', '${WORDPRESS_DB_HOST//\\/\\\\}' );"
    db_name_line=${db_name_line//\\\'/\\\\\'}
    db_user_line=${db_user_line//\\\'/\\\\\'}
    db_password_line=${db_password_line//\\\'/\\\\\'}
    db_host_line=${db_host_line//\\\'/\\\\\'}
    awk -v db_name_line="$db_name_line" \
        -v db_user_line="$db_user_line" \
        -v db_password_line="$db_password_line" \
        -v db_host_line="$db_host_line" \
        '/DB_NAME/ { print db_name_line; next }
         /DB_USER/ { print db_user_line; next }
         /DB_PASSWORD/ { print db_password_line; next }
         /DB_HOST/ { print db_host_line; next }
         { print }' /var/www/html/wp-config.php > /var/www/html/wp-config.php.tmp
    mv /var/www/html/wp-config.php.tmp /var/www/html/wp-config.php
    chown www-data:www-data /var/www/html/wp-config.php
fi

exec "$@"
