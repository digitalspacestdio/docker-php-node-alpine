ARG PHP_VERSION=8.1

# Prod image
FROM php:${PHP_VERSION}-fpm-alpine AS app_php

ARG NODE_VERSION=16.16.0

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
    jpegoptim \
    pngquant \
    optipng \
    gifsicle \
  ;

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
  docker-php-ext-install -j$(nproc) apcu; \
  \
  mkdir -p /usr/src/php/ext/igbinary; \
  curl -fsSL curl -fsSL https://github.com/igbinary/igbinary/archive/$EXT_IGBINARY_VERSION.tar.gz | tar xvz -C /usr/src/php/ext/igbinary --strip 1; \
  docker-php-ext-install -j$(nproc) igbinary; \
  \
  mkdir -p /usr/src/php/ext/redis; \
  curl -fsSL curl -fsSL https://github.com/phpredis/phpredis/archive/$EXT_REDIS_VERSION.tar.gz | tar xvz -C /usr/src/php/ext/redis --strip 1; \
  docker-php-ext-configure redis --enable-redis-igbinary; \
  docker-php-ext-install -j$(nproc) redis; \
  \
  mkdir -p /usr/src/php/ext/mongodb; \
  git clone --recursive --branch $EXT_MONGODB_VERSION --depth 1 https://github.com/mongodb/mongo-php-driver.git /usr/src/php/ext/mongodb; \
  docker-php-ext-configure mongodb; \
  docker-php-ext-install -j$(nproc) mongodb; \
  \
  mkdir -p /usr/src/php/ext/xdebug; \
  curl -fsSL curl -fsSL https://github.com/xdebug/xdebug/archive/refs/tags/$EXT_XDEBUG_VERSION.tar.gz | tar xvz -C /usr/src/php/ext/xdebug --strip 1; \
  docker-php-ext-configure xdebug; \
  docker-php-ext-install -j$(nproc) xdebug; \
  \
  docker-php-ext-install -j$(nproc) \
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
    && apk add --no-cache \
        libstdc++ \
    && apk add --no-cache --virtual .build-deps \
        curl \
    && ARCH= && alpineArch="$(apk --print-arch)" \
      && case "${alpineArch##*-}" in \
        x86_64) \
          ARCH='x64' \
          CHECKSUM="2b74f0baaaa931ffc46573874a7d7435b642d28f1f283104ac297499fba99f0a" \
          ;; \
        *) ;; \
      esac \
  && if [ -n "${CHECKSUM}" ]; then \
    set -eu; \
    curl -fsSLO --compressed "https://unofficial-builds.nodejs.org/download/release/v$NODE_VERSION/node-v$NODE_VERSION-linux-$ARCH-musl.tar.xz"; \
    echo "$CHECKSUM  node-v$NODE_VERSION-linux-$ARCH-musl.tar.xz" | sha256sum -c - \
      && tar -xJf "node-v$NODE_VERSION-linux-$ARCH-musl.tar.xz" -C /usr/local --strip-components=1 --no-same-owner \
      && ln -s /usr/local/bin/node /usr/local/bin/nodejs; \
  else \
    echo "Building from source" \
    # backup build
    && apk add --no-cache --virtual .build-deps-full \
        binutils-gold \
        g++ \
        gcc \
        gnupg \
        libgcc \
        linux-headers \
        make \
        python3 \
    # gpg keys listed at https://github.com/nodejs/node#release-keys
    && for key in \
      4ED778F539E3634C779C87C6D7062848A1AB005C \
      141F07595B7B3FFE74309A937405533BE57C7D57 \
      94AE36675C464D64BAFA68DD7434390BDBE9B9C5 \
      74F12602B6F1C4E913FAA37AD3A89613643B6201 \
      71DCFD284A79C3B38668286BC97EC7A07EDE3FC1 \
      61FC681DFB92A079F1685E77973F295594EC4689 \
      8FCCA13FEF1D0C2E91008E09770F7A9A5AE15600 \
      C4F0DFFF4E8C1A8236409D08E73BC641CC11F4C8 \
      890C08DB8579162FEE0DF9DB8BEAB4DFCF555EF4 \
      C82FA3AE1CBEDC6BE46B9360C43CEC45C17AB93C \
      DD8F2338BAE7501E3DD5AC78C273792F7D83545D \
      A48C2BEE680E841632CD4E44F07496B3EB3C1762 \
      108F52B48DB57BB0CC439B2997B01419BD92F80A \
      B9E2F5981AA6E0CD28160D9FF13993A75599653C \
    ; do \
      gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys "$key" || \
      gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "$key" ; \
    done \
    && curl -fsSLO --compressed "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION.tar.xz" \
    && curl -fsSLO --compressed "https://nodejs.org/dist/v$NODE_VERSION/SHASUMS256.txt.asc" \
    && gpg --batch --decrypt --output SHASUMS256.txt SHASUMS256.txt.asc \
    && grep " node-v$NODE_VERSION.tar.xz\$" SHASUMS256.txt | sha256sum -c - \
    && tar -xf "node-v$NODE_VERSION.tar.xz" \
    && cd "node-v$NODE_VERSION" \
    && ./configure \
    && make -j$(getconf _NPROCESSORS_ONLN) V= \
    && make install \
    && apk del .build-deps-full \
    && cd .. \
    && rm -Rf "node-v$NODE_VERSION" \
    && rm "node-v$NODE_VERSION.tar.xz" SHASUMS256.txt.asc SHASUMS256.txt; \
  fi \
  && rm -f "node-v$NODE_VERSION-linux-$ARCH-musl.tar.xz" \
  && apk del .build-deps \
  # smoke tests
  && node --version \
  && npm --version

ENV YARN_VERSION 1.22.19

RUN apk add --no-cache --virtual .build-deps-yarn curl gnupg tar \
  && for key in \
    6A010C5166006599AA17F08146C2130DFD2497F5 \
  ; do \
    gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys "$key" || \
    gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "$key" ; \
  done \
  && curl -fsSLO --compressed "https://yarnpkg.com/downloads/$YARN_VERSION/yarn-v$YARN_VERSION.tar.gz" \
  && curl -fsSLO --compressed "https://yarnpkg.com/downloads/$YARN_VERSION/yarn-v$YARN_VERSION.tar.gz.asc" \
  && gpg --batch --verify yarn-v$YARN_VERSION.tar.gz.asc yarn-v$YARN_VERSION.tar.gz \
  && mkdir -p /opt \
  && tar -xzf yarn-v$YARN_VERSION.tar.gz -C /opt/ \
  && ln -s /opt/yarn-v$YARN_VERSION/bin/yarn /usr/local/bin/yarn \
  && ln -s /opt/yarn-v$YARN_VERSION/bin/yarnpkg /usr/local/bin/yarnpkg \
  && rm yarn-v$YARN_VERSION.tar.gz.asc yarn-v$YARN_VERSION.tar.gz \
  && apk del .build-deps-yarn \
  # smoke test
  && yarn --version


WORKDIR /var/www

RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"
RUN rm -rf /var/www/* && chown ${PHP_USER_NAME}:${PHP_USER_GROUP} /var/www

COPY app.ini $PHP_INI_DIR/conf.d/
COPY php-fpm.conf /usr/local/etc/php-fpm.conf

RUN mkdir -p /var/run/php

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint
RUN chmod +x /usr/local/bin/docker-entrypoint

ENTRYPOINT ["docker-entrypoint"]
CMD ["bash"]

# https://getcomposer.org/doc/03-cli.md#composer-allow-superuser
ENV COMPOSER_ALLOW_SUPERUSER=1
ENV PATH="${PATH}:/root/.composer/vendor/bin"

# Install composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Install ofelia
COPY --from=mcuadros/ofelia:latest /usr/bin/ofelia /usr/bin/ofelia

# Dev image
FROM app_php AS app_php_dev

ENV APP_ENV=dev XDEBUG_MODE=off

RUN rm -f $PHP_INI_DIR/conf.d/app.prod.ini; \
  mv "$PHP_INI_DIR/php.ini" "$PHP_INI_DIR/php.ini-production"; \
  mv "$PHP_INI_DIR/php.ini-development" "$PHP_INI_DIR/php.ini"

COPY app.dev.ini $PHP_INI_DIR/conf.d/

# RUN set -eux; \
#   apk add --no-cache --virtual .build-deps $PHPIZE_DEPS; \
#   pecl install xdebug; \
#   docker-php-ext-enable xdebug; \
#   apk del .build-deps

USER ${PHP_USER_NAME}
VOLUME "/home/php" "/root" '/var/www'
CMD [ "bash" ]