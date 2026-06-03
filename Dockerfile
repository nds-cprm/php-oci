ARG DEBIAN_VERSION=bookworm
ARG PHP_INSTALL_DIR=/usr/local/php

FROM debian:${DEBIAN_VERSION} AS source

# PHP version to build
# Ref: https://www.php.net/releases/
# Last 5.6 version: 5.6.40
# Last 5.4 version: 5.4.45
ARG PHP_INSTALL_DIR
ARG PHP_VERSION=5.6.40
ARG PHP_DOWNLOAD_URL=https://www.php.net/distributions/php-${PHP_VERSION}.tar.gz
ARG PHP_TAR_HASH=56fb9878d12fdd921f6a0897e919f4e980d930160e154cbde2cc6d9206a27cac

ARG PHP_APACHE_BUILD_ARGS="--with-apxs2"
ARG PHP_FPM_BUILD_ARGS="--enable-fpm"

ARG PHP_PECL_XDEBUG_VERSION=2.4.1

# latest of 1.0.2 series
# Ref: https://openssl-library.org/source/old/1.0.2/
ARG OPENSSL_VERSION=1.0.2u 
ARG OPENSSL_DOWNLOAD_URL=https://github.com/openssl/openssl/releases/download/OpenSSL_1_0_2u/openssl-1.0.2u.tar.gz
ARG OPENSSL_TAR_HASH=ecd0c6ffb493dd06707d38b14bb4d8c2288bb7033735606569d8f90f89669d16

ARG OPENSSL_BUILD_ARGS="-fPIC shared --prefix=${PHP_INSTALL_DIR} --openssldir=${PHP_INSTALL_DIR}/openssl"

# Oracle
ARG ORACLE_CLIENT_DOWNLOAD_URL=https://download.oracle.com/otn_software/linux/instantclient/1928000/instantclient-basiclite-linux.x64-19.28.0.0.0dbru.zip
ARG ORACLE_CLIENT_SDK_DOWNLOAD_URL=https://download.oracle.com/otn_software/linux/instantclient/1928000/instantclient-sdk-linux.x64-19.28.0.0.0dbru.zip

WORKDIR /tmp

RUN apt-get -y update && \
    # install pgdg repo
    apt-get install -y --no-install-recommends --no-install-suggests \
        postgresql-common \
        gnupg && \
    YES=yes && . /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh && \
    # install libraries and tools
    apt-get install -y --no-install-recommends --no-install-suggests \
        ca-certificates \
        git \
        wget \
        unzip \
        less \
        vim \
        apache2 \
        sendmail \
        build-essential \
        autoconf \
        libtool \
        # Oracle
        libaio1 \
        # devels
        apache2-dev \
        freetds-dev \ 
        libbz2-dev \
        libcurl4-nss-dev \
        libgd-dev \
        libgmp-dev \
        libldap2-dev \
        libmcrypt-dev \
        libtidy-dev \
        libxml2-dev \
        libxslt1-dev \
        # from pgdg
        libpq-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    # fix gmp include
    ln -s $(find /usr/include -name gmp.h -print -quit) /usr/include/gmp.h && \
    # fix curl include
    ln -s $(find /usr/include -name curl -type d -print -quit) /usr/include/curl 

# Build OpenSSL
RUN wget -nv ${OPENSSL_DOWNLOAD_URL} && \
    echo "${OPENSSL_TAR_HASH}  openssl-${OPENSSL_VERSION}.tar.gz" | sha256sum -c - && \
    tar -xvzf openssl-${OPENSSL_VERSION}.tar.gz && \
    ( \
        cd openssl-${OPENSSL_VERSION} && \
        ./config ${OPENSSL_BUILD_ARGS} && \
        make && make install \
    )

# PHP Source
# --with-freetype-dir -> falhando
ENV PATH=${PHP_INSTALL_DIR}/bin:${PATH} \
    PKG_CONFIG_PATH=${PHP_INSTALL_DIR}/lib/pkgconfig   

RUN wget -nv ${PHP_DOWNLOAD_URL} && \
    echo "${PHP_TAR_HASH}  php-${PHP_VERSION}.tar.gz" | sha256sum -c - && \
    tar -xzf php-${PHP_VERSION}.tar.gz && \
    ( \
        cd php-${PHP_VERSION} && \
        mkdir -p ${PHP_INSTALL_DIR}/etc/php.d && \
        ./configure \
            --prefix=${PHP_INSTALL_DIR} \
            --with-libdir=lib/x86_64-linux-gnu \
            --with-config-file-path=/etc/php \
            --with-config-file-scan-dir=/etc/php/modules/enabled \
            --disable-short-tags \
            --disable-cgi \
            # extensions
            --with-bz2=shared \
            --with-curl=shared \
            --with-iconv=shared \
            --with-gd=shared \
            --with-gettext \
            --with-gmp=shared \
            --with-jpeg-dir=/usr \
            --with-ldap=shared \
            --with-openssl \
            --with-png-dir=/usr \
            --with-mhash \
            --with-mssql=shared \
            --with-pdo-dblib=shared \
            --with-pdo-pgsql=shared \
            --with-pgsql=shared \
            --with-tidy=shared \
            --with-xpm-dir \
            --with-xmlrpc=shared \
            --with-xsl=shared \
            --with-zlib=shared \
            --enable-bcmath=shared \ 
            --enable-calendar=shared \
            --enable-exif=shared \
            --enable-ftp=shared \
            --enable-mbstring=shared \
            --enable-shmop=shared \
            --enable-sockets=shared \
            --enable-sysvsem=shared \
            --enable-sysvshm=shared \
            --enable-sysvmsg=shared \
            --enable-wddx=shared \
            --enable-zip=shared \
            ${PHP_APACHE_BUILD_ARGS} \
            ${PHP_FPM_BUILD_ARGS} && \
        make && make install \
    )

# Oracle
# Prefer PECL https://forums.oracle.com/ords/apexds/post/ldap-and-oci8-doesnot-work-together-4823
RUN set -xe && wget -qO instantclient.zip ${ORACLE_CLIENT_DOWNLOAD_URL} && \
    wget -qO instantclient-sdk.zip ${ORACLE_CLIENT_SDK_DOWNLOAD_URL} && \
    unzip instantclient.zip -d /opt && \
    unzip -o instantclient-sdk.zip -d /opt && \
    INSTANTCLIENT_DIR=$(find /opt -name 'instantclient*' -print -quit) && \
    echo $INSTANTCLIENT_DIR > /etc/ld.so.conf.d/oracle.conf && \
    ldconfig && \
    # Oracle PHP extension
    wget -nv https://pecl.php.net/get/oci8-2.0.12.tgz && \
    tar -xzf oci8-2.0.12.tgz && \
    ( \
        cd oci8-2.0.12 && \
        phpize && \
        ./configure --with-oci8=shared,instantclient,$INSTANTCLIENT_DIR && \
        make && make install \
    )

# XDebug
# https://pecl.php.net/package/xdebug
# https://xdebug.org/docs/compat
RUN wget -nv https://pecl.php.net/get/xdebug-${PHP_PECL_XDEBUG_VERSION}.tgz && \
    tar -xzf xdebug-${PHP_PECL_XDEBUG_VERSION}.tgz && \
    ( \
        cd xdebug-${PHP_PECL_XDEBUG_VERSION} && \
        phpize && \
        ./configure --enable-xdebug && \
        make && make install \
    )

# Suhosin
# https://suhosin.org/
RUN wget -nv https://download.suhosin.org/suhosin-0.9.38.tar.gz && \
    tar -xzf suhosin-0.9.38.tar.gz && \
    ( \
        cd suhosin-0.9.38 && \
        phpize && \
        ./configure && \
        make && make install \
    )

# copy configs
COPY conf/release /etc/php


# Release common
FROM debian:${DEBIAN_VERSION}-slim AS release-common

ARG PHP_INSTALL_DIR
ARG DEBIAN_VERSION

COPY --from=source ${PHP_INSTALL_DIR} ${PHP_INSTALL_DIR}
COPY --from=source /etc/php /etc/php
COPY --from=source /etc/ld.so.conf.d /etc/ld.so.conf.d22
COPY --from=source /opt /opt

ENV PATH=${PHP_INSTALL_DIR}/bin:${PATH}

RUN apt-get -y update && \
    # install pgdg repo
    apt-get install -y --no-install-recommends --no-install-suggests \
        postgresql-common \
        gnupg && \
    YES=yes && . /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh && \
    # install libraries and tools
    apt-get install -y --no-install-recommends --no-install-suggests \
        ca-certificates \
        # apache2 \
        sendmail \
        # Oracle
        libaio1 \
        # from pgdg
        libpq5 \
        # PHP deps
        freetds-bin \ 
        libbz2-1.0 \
        libcurl3-nss \
        libgd3 \
        libgmp10 \
        libldap-2.* \
        libmcrypt4 \
        libtidy5deb1 \
        libxml2 \
        libxslt1.1 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    ldconfig 


FROM release-common AS release-httpd

COPY --from=source /usr/lib/apache2/modules/libphp5.so /usr/lib/apache2/modules/
COPY --from=source /etc/apache2/mods-available/php5.load  /etc/apache2/mods-available/
COPY --from=source /etc/apache2/mods-enabled/php5.load  /etc/apache2/mods-enabled/

RUN apt-get -y update && \
    apt-get -y upgrade && \
    apt-get install -y --no-install-recommends --no-install-suggests \
        apache2 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /etc/apache2

RUN a2dismod mpm_event mpm_worker && \
    a2enmod mpm_prefork && \
    # grant to root group write permissions
    mkdir -p /var/run/apache2/socks /var/lock/apache2 /var/log/apache2 && \
    chown -R root:root /var/log/apache2 && \
    chmod -R g=u /var/run/apache2 /var/lock/apache2 /var/log/apache2 /var/www/html && \
    # change default ports
    sed -i 's/80/8080/g' ports.conf && \
    sed -i 's/443/8443/g' ports.conf && \
    sed -i 's/80/8080/g' sites-enabled/000-default.conf && \
    # enable php on virtualhost
    sed -i '/<\/VirtualHost>/i \    <FilesMatch \\.php$>\n        SetHandler application/x-httpd-php\n    </FilesMatch>' \
        sites-enabled/000-default.conf

EXPOSE 8080 8443 9000

STOPSIGNAL SIGQUIT

# Enable apache to run in foreground
CMD ["apache2ctl", "-D", "FOREGROUND"]


FROM release-common AS release-nginx

RUN apt-get -y update && \
    apt-get -y upgrade && \
    apt-get install -y --no-install-recommends --no-install-suggests \
        nginx && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY flavours/nginx/docker-entrypoint.sh /usr/local/bin/
COPY flavours/nginx/conf/default.conf /etc/nginx/sites-available/default

RUN mkdir -p /run/php && \
    chown -R www-data:root /run/php && \
    chmod -R g=u /run/php /usr/local/php/var/log && \
    cp /usr/local/php/etc/php-fpm.conf.default /etc/php/php-fpm.conf && \
    ln -sf /etc/php/php-fpm.conf /usr/local/php/etc/php-fpm.conf && \
    sed -i 's/^user.*/user = www-data/g' /etc/php/php-fpm.conf && \
    sed -i 's/^group.*/group = www-data/g' /etc/php/php-fpm.conf && \
    sed -i 's|127\.0\.0\.1:9000|/run/php/php-fpm.sock|g' /etc/php/php-fpm.conf && \
    chmod +x /usr/local/bin/docker-entrypoint.sh && \
    ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default

# Set nginx to run as non-privileged user
# https://github.com/nginx/docker-nginx-unprivileged/blob/70e79be19cbe83092ed6c86f461967fe44012674/Dockerfile-debian.template#L128
RUN sed -i '/user www-data;/d' /etc/nginx/nginx.conf && \
    sed -i 's|error_log \/var\/log\/nginx\/error.log;|error_log /dev/stderr;|g' /etc/nginx/nginx.conf && \
    sed -i 's|access_log \/var\/log\/nginx\/access.log;|access_log /dev/stdout;|g' /etc/nginx/nginx.conf && \
    sed -i '/user www-data;/d' /etc/nginx/nginx.conf && \
    sed -i 's,\(/var\)\{0\,1\}/run/nginx.pid,/tmp/nginx.pid,' /etc/nginx/nginx.conf && \
    sed -i "/^http {/a \    proxy_temp_path /tmp/proxy_temp;\n    client_body_temp_path /tmp/client_temp;\n    fastcgi_temp_path /tmp/fastcgi_temp;\n    uwsgi_temp_path /tmp/uwsgi_temp;\n    scgi_temp_path /tmp/scgi_temp;\n" /etc/nginx/nginx.conf && \
    sed -i 's,PIDFILE=${PIDFILE:-/run/nginx.pid},PIDFILE=${PIDFILE:-/tmp/nginx.pid},' /etc/init.d/nginx && \
    # nginx user must own the cache and etc directory to write cache and tweak the nginx config
    # chown -R 33:0 /var/cache/nginx \
    # chmod -R g+w /var/cache/nginx \
    chown -R 33:0 /etc/nginx && \
    chmod -R g+w /etc/nginx 

ENV PATH=${PHP_INSTALL_DIR}/sbin:${PATH}

WORKDIR /etc/nginx

STOPSIGNAL SIGQUIT

EXPOSE 8080 8443

ENTRYPOINT [ "docker-entrypoint.sh" ]

# Enable nginx to run in foreground
CMD ["nginx", "-g", "daemon off;"]
