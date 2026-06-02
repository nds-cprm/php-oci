#!/bin/bash
set -e

PHP_FPM_ROOT_ARGS=""

if [[ $(id -u) -eq 0 ]]; then
    PHP_FPM_ROOT_ARGS="-R"
fi

php-fpm --daemonize $PHP_FPM_ROOT_ARGS

exec "$@"