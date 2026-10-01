#!/bin/sh
set -e
cd "$(dirname "$0")"
CC="${TOOLCHAIN:-/opt/mini}/bin/arm-linux-gnueabihf-"
${CC}gcc -O2 -fPIC -shared -Wall dspfix.c -o libdspfix.so -ldl
${CC}strip libdspfix.so
