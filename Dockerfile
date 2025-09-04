ARG DEBIAN_VERSION=bullseye

FROM debian:${DEBIAN_VERSION} AS source

# PHP version to build
# Ref: https://www.php.net/releases/
# ARG PHP_VERSION=5.6.40
ARG PHP_VERSION=5.4.45
ARG PHP_DOWNLOAD_URL=https://www.php.net/distributions/php-${PHP_VERSION}.tar.gz
ARG PHP_BUILD_ARGS="--with-openssl --with-ldap --with-gd --enable-mbstring --enable-bcmath \
    -with-mssql --with-pdo-pgsql --with-pgsql --with-zlib --with-bz2 --enable-calendar \
    --enable-exif --enable-ftp --enable-sysvsem --enable-sysvshm --enable-sysvmsg \
    --enable-wddx --enable-zip --with-jpeg-dir=/usr --with-png-dir=/usr --with-iconv \
    --with-mhash --enable-sockets --with-pdo-dblib --with-gettext --with-xsl \
    --enable-shmop --with-gmp --with-xpm-dir --with-curl"
ARG PHP_APACHE_BUILD_ARGS="--with-apxs2"
ARG PHP_FPM_BUILD_ARGS="--enable-fpm"

# latest of 1.0.2 series
# Ref: https://openssl-library.org/source/old/1.0.2/
ARG OPENSSL_VERSION=1.0.2u 
ARG OPENSSL_DOWNLOAD_URL=https://github.com/openssl/openssl/releases/download/OpenSSL_1_0_2u/openssl-1.0.2u.tar.gz
ARG OPENSSL_BUILD_ARGS="-fPIC shared --prefix=/usr/local/ssl --openssldir=/usr/local/ssl/openssl"

# Oracle Instant Client
ARG ORACLE_CLIENT_PATH="/opt/instantclient_11_2"

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
        apache2 \
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
        # libmcrypt-dev \
        # libtidy-dev \
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
    # && \
    # # fix freetype include
    # ln -s $(find /usr/include -name ft2build.h -print -quit) /usr/include/ft2build.h && \
    # ln -s $(find /usr/include -name freetype -type d -print -quit) /usr/include/freetype && \
    # echo "#!/bin/bash\npkg-config freetype2 $@\n" > /usr/local/bin/freetype-config

# Build OpenSSL
RUN wget ${OPENSSL_DOWNLOAD_URL} && \
    tar -xvzf openssl-${OPENSSL_VERSION}.tar.gz && \
    ( \
        cd openssl-${OPENSSL_VERSION} && \
        ./config ${OPENSSL_BUILD_ARGS} && \
        make && make install \
    )

# PHP Source
# --with-freetype-dir -> falhando
ENV PATH=/usr/local/ssl/bin:${PATH} \
    PKG_CONFIG_PATH=/usr/local/ssl/lib/pkgconfig

# COPY ./legacy/php /usr/local/php/etc

RUN wget ${PHP_DOWNLOAD_URL} && \
    tar -xvzf php-${PHP_VERSION}.tar.gz && \
    ( \
        cd php-${PHP_VERSION} && \
        mkdir -p /usr/local/php/etc/php.d && \
        ./configure \
            --prefix=/usr/local/php \
            --with-libdir=lib/x86_64-linux-gnu \
            --with-config-file-path=/usr/local/php/etc \
            --with-config-file-scan-dir=/usr/local/php/etc/php.d \
            ${PHP_APACHE_BUILD_ARGS} \
            ${PHP_FPM_BUILD_ARGS} \
            ${PHP_BUILD_ARGS} && \
        make && make install \
    )

ENV PATH=/usr/local/php/bin:${PATH} 

# Oracle
# https://forums.oracle.com/ords/apexds/post/ldap-and-oci8-doesnot-work-together-4823
COPY oracle/instantclient-basic-linux.x64-11.2.0.4.0.tar.gz .
COPY oracle/instantclient-sdk-linux.x64-11.2.0.4.0.tar.gz .

RUN tar -zxf instantclient-basic-linux.x64-11.2.0.4.0.tar.gz -C /opt && \
    tar -zxf instantclient-sdk-linux.x64-11.2.0.4.0.tar.gz -C /opt && \
    ln -s ${ORACLE_CLIENT_PATH}/libclntsh.so.11.1 ${ORACLE_CLIENT_PATH}/libclntsh.so && \
    ln -s ${ORACLE_CLIENT_PATH}/libocci.so.11.1 ${ORACLE_CLIENT_PATH}/libocci.so && \
    echo ${ORACLE_CLIENT_PATH} > /etc/ld.so.conf.d/instantclient.conf && \
    ldconfig


# Oracle PHP extension
RUN wget https://pecl.php.net/get/oci8-2.0.12.tgz && \
    tar -xvzf oci8-2.0.12.tgz && \
    ( \
        cd oci8-2.0.12 && \
        /usr/local/php/bin/phpize && \
        ./configure --with-oci8=shared,instantclient,/opt/instantclient_11_2 && \
        make && make install \
    ) && \
    echo "extension=oci8.so" > /usr/local/php/etc/php.d/oci8.ini

WORKDIR /etc/apache2

# Apache (for tests only)
RUN a2dismod mpm_event mpm_worker && \
    a2enmod mpm_prefork && \
    echo "<?php phpinfo(); ?>" > /var/www/html/index.php && \
    # change default ports
    sed -i 's/80/8080/g' ports.conf && \
    sed -i 's/443/8443/g' ports.conf && \
    sed -i 's/80/8080/g' sites-enabled/000-default.conf && \
    sed -i '/<\/VirtualHost>/i \    <FilesMatch \\.php$>\n        SetHandler application/x-httpd-php\n    </FilesMatch>' \
        sites-enabled/000-default.conf

EXPOSE 8080 8443

# Enable apache to run in foreground
CMD ["apache2ctl", "-D", "FOREGROUND"]
