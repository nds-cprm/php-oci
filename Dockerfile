ARG DEBIAN_VERSION=bookworm
ARG PHP_INSTALL_DIR=/usr/local/php
ARG OSGEO_INSTALL_DIR=/usr/local/osgeo

FROM debian:${DEBIAN_VERSION} AS source-php

# PHP version to build
# Ref: https://www.php.net/releases/
# Last 5.6 version: 5.6.40  sha256: 56fb9878d12fdd921f6a0897e919f4e980d930160e154cbde2cc6d9206a27cac
# Last 5.4 version: 5.4.45  sha256: 25bc4723955f4e352935258002af14a14a9810b491a19400d76fcdfa9d04b28f
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
        libcurl4-gnutls-dev \
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
    ln -sf $INSTANTCLIENT_DIR /opt/oracle-client && \
    echo /opt/oracle-client > /etc/ld.so.conf.d/oracle.conf && \
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


#############
# MapServer #
#############
FROM source-php AS source-mapserver

ARG OSGEO_INSTALL_DIR

ENV PATH=${OSGEO_INSTALL_DIR}/bin:${PATH}

RUN echo ${OSGEO_INSTALL_DIR}/lib > /etc/ld.so.conf.d/osgeo.conf 

# GEOS 3.3.x
ENV CXXFLAGS="-std=c++98" 

ARG GEOS_VERSION=3.3.9

ADD https://download.osgeo.org/geos/geos-${GEOS_VERSION}.tar.bz2 .

# enable php version: configure: WARNING: PHP Unit testing disabled (missing PHP or PHPUNIT)
RUN tar -jxvf geos-${GEOS_VERSION}.tar.bz2 && \
    ( \
        cd geos-${GEOS_VERSION} && \
        ./configure --prefix=${OSGEO_INSTALL_DIR} && \
        make && \
        make install \
    ) && \
    ldconfig

# PROJ < 5
ENV CXXFLAGS="" 

ARG PROJ_VERSION=4.4.9

ADD https://download.osgeo.org/proj/proj-${PROJ_VERSION}.tar.gz .

RUN tar -zxvf proj-${PROJ_VERSION}.tar.gz && \
    ( \
        cd proj-${PROJ_VERSION} && \
        ./configure --prefix=${OSGEO_INSTALL_DIR} && \
        make && \
        make install \
    ) && \
    ldconfig

# GDAL
ARG GDAL_VERSION=1.11.5

ADD https://download.osgeo.org/gdal/${GDAL_VERSION}/gdal-${GDAL_VERSION}.tar.gz .

ENV CXXFLAGS="-std=c++11 -fpermissive -Wno-write-strings" \
    CFLAGS="-fpermissive -Wno-write-strings"

# Oracle libs missing (Create libdir with softlinks?)
RUN tar -zxvf gdal-${GDAL_VERSION}.tar.gz && \
    ( \
        cd gdal-${GDAL_VERSION} && \
        ./configure --prefix=${OSGEO_INSTALL_DIR} \
            --with-libtiff=internal \
            --with-geotiff=internal && \
        make && \
        make install \
    ) && \
    ldconfig

# libtiff < 4
# ADD https://download.osgeo.org/libtiff/tiff-3.9.7.tar.gz .

# RUN tar -zxvf tiff-3.9.7.tar.gz && \
#     ( \
#         cd tiff-3.9.7 && \
#         ./configure --prefix=${OSGEO_INSTALL_DIR} && \
#         make && \
#         make install \
#     ) && \
#     ldconfig

# Mapserver
ADD https://download.osgeo.org/mapserver/mapserver-5.4.2.tar.gz .

RUN tar -zxvf mapserver-5.4.2.tar.gz && \
    ( \
        cd mapserver-5.4.2 && \
        CFLAGS="$CFLAGS -Dpval=zval -Dfunction_entry=zend_function_entry" && \
        CXXFLAGS="$CXXFLAGS -Dpval=zval -Dfunction_entry=zend_function_entry" && \
        ln -s $(find /usr -name libgd.so -print -quit) /usr/lib/libgd.so && \
        ./configure --prefix=${OSGEO_INSTALL_DIR} \
            --libdir=/usr/lib/x86_64-linux-gnu \
            --with-php=/usr/local/php \
            --with-gd \
            --enable-point-z-m \
            --with-zlib \
            --with-png \
            --with-jpeg \
            --with-xpm \
            --with-pdf \
            --with-eppl \
            --with-proj=/usr/local/osgeo \
            --with-threads \
            --with-geos \
            --with-ogr \
            --with-gdal=/usr/local/osgeo/bin/gdal-config \
            # --with-tiff \
            --with-postgis \
            --with-oraclespatial=/opt/oracle-client \
            # --with-fastcgi \
            --with-curl-config \
            --with-wmsclient \
            --with-wfsclient && \
        make && \
        make install && \
        # mapscript
        mkdir -p ${OSGEO_INSTALL_DIR}/lib/php/extensions && \
        cp -v $(find . -name php_mapscript.so) ${OSGEO_INSTALL_DIR}/lib/php/extensions && \
        ln -s ${OSGEO_INSTALL_DIR}/lib/php/extensions/php_mapscript.so $(php-config --extension-dir)/php_mapscript.so && \
        # binaries 
        echo "extension=php_mapscript.so" > /etc/php/modules/available/mapscript.ini && \
        cp -v \
            legend mapserv mapserver-config msencrypt scalebar \
            shp2img shp2mysql.pl shp2pdf shptree shptreetst shptreevis sortshp tile4ms \
        ${OSGEO_INSTALL_DIR}/bin \
    ) && \
    ldconfig


# Release standard
FROM debian:${DEBIAN_VERSION}-slim AS release-php

ARG PHP_INSTALL_DIR
ARG DEBIAN_VERSION

COPY --from=source-php ${PHP_INSTALL_DIR} ${PHP_INSTALL_DIR}
COPY --from=source-php /etc/php /etc/php
COPY --from=source-php /etc/ld.so.conf.d/oracle.conf /etc/ld.so.conf.d/oracle.conf
COPY --from=source-php /opt /opt
COPY --from=source-php /usr/lib/apache2/modules/libphp5.so /usr/lib/apache2/modules/
COPY --from=source-php /etc/apache2/mods-available/php5.load  /etc/apache2/mods-available/
COPY --from=source-php /etc/apache2/mods-enabled/php5.load  /etc/apache2/mods-enabled/
COPY conf/release /etc/php

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
        libcurl3-gnutls \
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


FROM release-php AS release-mapserver

ARG OSGEO_INSTALL_DIR

COPY --from=source-mapserver ${OSGEO_INSTALL_DIR} ${OSGEO_INSTALL_DIR}
COPY --from=source-mapserver /etc/ld.so.conf.d/osgeo.conf /etc/ld.so.conf.d/osgeo.conf

ENV PATH=${OSGEO_INSTALL_DIR}/bin:${PATH}

RUN cp ${OSGEO_INSTALL_DIR}/lib/php/extensions/php_mapscript.so $(php-config --extension-dir) && \
    ldconfig
