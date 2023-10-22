ARG PHP_VERSION=8.2
ARG CADDY_VERSION=2.4.6

FROM php:${PHP_VERSION}-fpm-alpine AS php

RUN apk add --update linux-headers

RUN apk add --no-cache \
		acl \
		fcgi \
        freetype \
		file \
        freetype-dev  \
		gettext \
		git \
		gnu-libiconv \
        jpegoptim \
        libjpeg-turbo  \
        libpng-dev  \
        libpng \
        libjpeg-turbo-dev \
		npm \
		yarn \
		graphviz \
		pngquant \
	;

# install gnu-libiconv and set LD_PRELOAD env to make iconv work fully on Alpine image.
# see https://github.com/docker-library/php/issues/240#issuecomment-763112749
ENV LD_PRELOAD /usr/lib/preloadable_libiconv.so


RUN set -eux; \
	apk add --no-cache --virtual .build-deps \
    icu-dev \
    libzip-dev \
    libpng-dev \
    libzip-dev \
    ;\
    docker-php-ext-configure zip; \
    docker-php-ext-install -j$(nproc) \
    intl \
    zip \
    gd \
    ; \
    \
    runDeps="$( \
    		scanelf --needed --nobanner --format '%n#p' --recursive /usr/local/lib/php/extensions \
    			| tr ',' '\n' \
    			| sort -u \
    			| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
    	)"; \
    apk add --no-cache --virtual .api-phpexts-rundeps $runDeps; \
    	\
    	apk del .build-deps;

RUN docker-php-ext-install mysqli pdo pdo_mysql gd
RUN docker-php-ext-enable gd

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

RUN ln -s $PHP_INI_DIR/php.ini-production $PHP_INI_DIR/php.ini
COPY docker/php/conf.d/app.prod.ini $PHP_INI_DIR/conf.d/app.ini

COPY docker/php/php-fpm.d/zz-docker.conf /usr/local/etc/php-fpm.d/zz-docker.conf

WORKDIR /app

VOLUME /var/run/php
ENV COMPOSER_ALLOW_SUPERUSER=1

RUN sync

COPY docker/php/docker-healthcheck.sh /usr/local/bin/docker-healthcheck
RUN chmod +x /usr/local/bin/docker-healthcheck

HEALTHCHECK --interval=10s --timeout=3s --retries=3 CMD ["docker-healthcheck"]

# "caddy" stage
# depends on the "php" stage above
FROM caddy:${CADDY_VERSION} AS caddy
WORKDIR /app

COPY --from=php /app/public public/
COPY docker/caddy/Caddyfile /etc/caddy/Caddyfile

FROM php as php_dev

RUN set -eux; \
	apk add --no-cache --virtual .build-deps $PHPIZE_DEPS; \
	pecl install xdebug; \
	docker-php-ext-enable xdebug; \
	apk del .build-deps
