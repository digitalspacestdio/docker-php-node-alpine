ARG ALPINE_VERSION=3.16
ARG NODE_VERSION=16.16.0
ARG PHP_VERSION=8.1

# Nodejs image
FROM node:${NODE_VERSION}-alpine${ALPINE_VERSION} AS app_node

# Php image
FROM php:${PHP_VERSION}-fpm-alpine${ALPINE_VERSION} AS app_php

ARG PHP_UID=1000
ARG PHP_GID=1000
ARG PHP_USER_NAME=developer
ARG PHP_USER_GROUP=developer

ARG EXT_APCU_VERSION=5.1.21
ARG EXT_REDIS_VERSION=5.3.7 
ARG EXT_IGBINARY_VERSION=3.2.7
ARG EXT_MONGODB_VERSION=1.14.0
ARG EXT_XDEBUG_VERSION=3.1.5

# persistent / runtime deps
RUN apk add --no-cache \
    acl \
    fcgi \
    file \
    gettext \
    git \
    bash \
    curl \
    msmtp-openrc \
    msmtp \
    jpegoptim \
    pngquant \
    optipng \
    gifsicle \
    libstdc++ \
  ;

# Copy nodejs binaries
COPY --from=app_node /usr/local /usr/local
COPY --from=app_node /opt /opt

 # smoke test
RUN node --version && npm --version && yarn --version

RUN set -eux; \
  apk add --no-cache --virtual .build-deps \
    $PHPIZE_DEPS \
    icu-data-full \
    icu-dev \
    libzip-dev \
    zlib-dev \
    libxml2-dev \
    libxslt-dev \
    postgresql-dev \
    openldap-dev \
    freetype-dev \
    libjpeg-turbo-dev \
    libpng-dev \
    libwebp-dev \
    gmp-dev \
    tidyhtml-dev \
    imap-dev \
    oniguruma-dev \
  ; \
  \
  docker-php-source extract; \
  docker-php-ext-configure zip; \
  docker-php-ext-configure imap --with-imap --with-imap-ssl; \
  docker-php-ext-configure gd --with-freetype --with-webp --with-jpeg; \
  \
  mkdir -p /usr/src/php/ext/apcu; \
  curl -fsSL https://github.com/krakjoe/apcu/archive/v$EXT_APCU_VERSION.tar.gz | tar xvz -C /usr/src/php/ext/apcu --strip 1; \
  docker-php-ext-install -j$(printf "2\n$(nproc)" | sort -g | head -n1) apcu; \
  \
  mkdir -p /usr/src/php/ext/igbinary; \
  curl -fsSL curl -fsSL https://github.com/igbinary/igbinary/archive/$EXT_IGBINARY_VERSION.tar.gz | tar xvz -C /usr/src/php/ext/igbinary --strip 1; \
  docker-php-ext-install -j$(printf "2\n$(nproc)" | sort -g | head -n1) igbinary; \
  \
  mkdir -p /usr/src/php/ext/redis; \
  curl -fsSL curl -fsSL https://github.com/phpredis/phpredis/archive/$EXT_REDIS_VERSION.tar.gz | tar xvz -C /usr/src/php/ext/redis --strip 1; \
  docker-php-ext-configure redis --enable-redis-igbinary; \
  docker-php-ext-install -j$(printf "2\n$(nproc)" | sort -g | head -n1) redis; \
  \
  mkdir -p /usr/src/php/ext/mongodb; \
  git clone --recursive --branch $EXT_MONGODB_VERSION --depth 1 https://github.com/mongodb/mongo-php-driver.git /usr/src/php/ext/mongodb; \
  docker-php-ext-configure mongodb; \
  docker-php-ext-install -j$(printf "2\n$(nproc)" | sort -g | head -n1) mongodb; \
  \
  mkdir -p /usr/src/php/ext/xdebug; \
  curl -fsSL curl -fsSL https://github.com/xdebug/xdebug/archive/refs/tags/$EXT_XDEBUG_VERSION.tar.gz | tar xvz -C /usr/src/php/ext/xdebug --strip 1; \
  docker-php-ext-configure xdebug; \
  docker-php-ext-install -j$(printf "2\n$(nproc)" | sort -g | head -n1) xdebug; \
  \
  docker-php-ext-install -j$(printf "2\n$(nproc)" | sort -g | head -n1) \
    pdo_pgsql \
    pdo_mysql \
    intl \
    zip \
    soap \
    ldap \
    gd \
    gmp \
    xsl \
    tidy \
    pcntl \
    imap \
    sockets \
    bcmath \
    mbstring \
    opcache \
  ; \
  docker-php-source delete; \
  \
  runDeps="$( \
    scanelf --needed --nobanner --format '%n#p' --recursive /usr/local/lib/php/extensions \
      | tr ',' '\n' \
      | sort -u \
      | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
  )"; \
  apk add --no-cache --virtual .app-phpexts-rundeps $runDeps; \
  \
  apk del .build-deps

RUN addgroup -g $PHP_GID ${PHP_USER_GROUP} \
    && adduser -u $PHP_UID -G ${PHP_USER_GROUP} -s /bin/sh -D ${PHP_USER_NAME} \
    && rm -rf /var/www/*  \
    && chown ${PHP_USER_NAME}:${PHP_USER_GROUP} /var/www

RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

COPY app.ini $PHP_INI_DIR/conf.d/
COPY php-fpm.conf /usr/local/etc/php-fpm.conf

RUN mkdir -p /var/run/php

COPY docker-healthcheck.sh /usr/local/bin/docker-healthcheck
RUN chmod +x /usr/local/bin/docker-healthcheck

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint
RUN chmod +x /usr/local/bin/docker-entrypoint

ENTRYPOINT ["docker-entrypoint"]

RUN rm -f $PHP_INI_DIR/conf.d/app.prod.ini; \
  mv "$PHP_INI_DIR/php.ini" "$PHP_INI_DIR/php.ini-production"; \
  mv "$PHP_INI_DIR/php.ini-development" "$PHP_INI_DIR/php.ini"

COPY app.dev.ini $PHP_INI_DIR/conf.d/

# Install composer
# https://getcomposer.org/doc/03-cli.md#composer-allow-superuser
ENV COMPOSER_ALLOW_SUPERUSER=1
ENV PATH="${PATH}:/root/.composer/vendor/bin"
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Install ofelia
COPY --from=mcuadros/ofelia:latest /usr/bin/ofelia /usr/bin/ofelia

WORKDIR /var/www
USER ${PHP_USER_NAME}
VOLUME "/home/php" "/root" '/var/www'
CMD [ "bash" ]