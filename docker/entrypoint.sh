#!/usr/bin/env bash
set -Eeuo pipefail

# Run the official WordPress image initialization first.  This copies the
# bundled WordPress tree into a persistent /var/www/html volume and creates
# wp-config.php from WORDPRESS_* variables when requested.
/usr/local/bin/docker-entrypoint.sh php-fpm -t

exec "$@"