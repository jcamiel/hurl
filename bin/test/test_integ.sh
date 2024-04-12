#!/bin/bash
set -Eeuo pipefail
set -x

echo "----- integration tests -----"

# hurl infos
command -v hurl || (echo "ERROR - hurl not found" ; exit 1)
command -v hurlfmt || (echo "ERROR - hurlfmt not found" ; exit 1)
hurl --version
hurlfmt --version

# Check that hurl is dynamically linked with libcurl
# if libcurl-dev is not installed, Hurl is built implicitly with an old static libcurl
# https://github.com/alexcrichton/curl-rust/issues/523
# TODO: Add MacOS
if [[ "$(uname -s)" = "Linux*" ]]; then
    libcurl_lib=$(ldd "$(which hurl)" | grep libcurl || test $? = 1)
    if [ -z "$libcurl_lib" ]; then
        echo "hurl has not been built with libcurl dynamically"
        echo "you are probably missing the libcurl-dev package"
        exit 1
    else
        echo "Using libcurl library"
        echo "$libcurl_lib"
    fi
fi


cd integration/hurl
tests_ok/parallel_all.sh

