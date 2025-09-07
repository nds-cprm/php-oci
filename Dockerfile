ARG DEBIAN_VERSION=bullseye

FROM debian:${DEBIAN_VERSION} AS source

# PHP version to build
# Ref: https://www.php.net/releases/
# Last 5.6 version: 5.6.40
# Last 5.4 version: 5.4.45
ARG PHP_INSTALL_DIR=/usr/local/php
ARG PHP_VERSION=5.4.45
ARG PHP_DOWNLOAD_URL=https://www.php.net/distributions/php-${PHP_VERSION}.tar.gz
ARG PHP_TAR_HASH=25bc4723955f4e352935258002af14a14a9810b491a19400d76fcdfa9d04b28f

ARG PHP_APACHE_BUILD_ARGS="--with-apxs2"
ARG PHP_FPM_BUILD_ARGS="--enable-fpm"

ARG PHP PECL_OCI8_VERSION=2.0.12
ARG PHP PECL_XDEBUG_VERSION=2.4.1

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
    wget -nv https://pecl.php.net/get/oci8-${PECL_OCI8_VERSION}.tgz && \
    tar -xzf oci8-${PECL_OCI8_VERSION}.tgz && \
    ( \
        cd oci8-${PECL_OCI8_VERSION} && \
        phpize && \
        ./configure --with-oci8=shared,instantclient,$INSTANTCLIENT_DIR && \
        make && make install \
    )

# XDebug
# https://pecl.php.net/package/xdebug
# https://xdebug.org/docs/compat
RUN wget -nv https://pecl.php.net/get/xdebug-${PECL_XDEBUG_VERSION}.tgz && \
    tar -xzf xdebug-${PECL_XDEBUG_VERSION}.tgz && \
    ( \
        cd xdebug-${PECL_XDEBUG_VERSION} && \
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

WORKDIR /etc/apache2

# Apache (for tests only)
RUN a2dismod mpm_event mpm_worker && \
    a2enmod mpm_prefork && \
    echo "<?php phpinfo(); ?>" > /var/www/html/index.php && \
    # change default ports
    sed -i 's/80/8080/g' ports.conf && \
    sed -i 's/443/8443/g' ports.conf && \
    sed -i 's/80/8080/g' sites-enabled/000-default.conf && \
    # enable php on virtualhost
    sed -i '/<\/VirtualHost>/i \    <FilesMatch \\.php$>\n        SetHandler application/x-httpd-php\n    </FilesMatch>' \
        sites-enabled/000-default.conf

EXPOSE 8080 8443 9000

# Enable apache to run in foreground
CMD ["apache2ctl", "-D", "FOREGROUND"]
