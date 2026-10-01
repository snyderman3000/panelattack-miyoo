#!/bin/sh
set -e
cd "$(dirname "$0")"
# MI_GFX/MI_SYS headers and libs from steward-fu/sdl2 (mini/inc, mini/lib)
M="${MI_SDK:-../../sdl2/mini}"
CC="${TOOLCHAIN:-/opt/mini}/bin/arm-linux-gnueabihf-"
${CC}gcc -O3 -mcpu=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard -fPIC -shared -Wall -I$M/inc mini2d.c -o libmini2d.so -L$M/lib -lmi_gfx -lmi_sys -lmi_common -lpthread
${CC}strip libmini2d.so
gcc -O2 -g -DM2D_HOST -fPIC -shared -Wall mini2d.c -o libmini2d_host.so
${CC}gcc -O2 -mcpu=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard -DM2D_HOST -fPIC -shared mini2d.c -o libmini2d_armstub.so
