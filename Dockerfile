FROM wordpress:php8.3-fpm-alpine

# nginx + supervisord on top of the official fpm-alpine WordPress image
RUN apk add --no-cache nginx supervisor bash

# nginx config (fastcgi_cache, serves /var/www/html)
COPY docker/nginx.conf /etc/nginx/nginx.conf

# supervisord config: runs php-fpm + nginx in one container
COPY docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# cache dir for fastcgi_cache
RUN mkdir -p /var/cache/nginx/fastcgi && \
    mkdir -p /run/nginx && \
    chown -R www-data:www-data /var/cache/nginx /var/www/html

EXPOSE 80

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf", "-n"]
