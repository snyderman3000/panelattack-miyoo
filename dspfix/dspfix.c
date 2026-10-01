/*
 * dspfix: lets programs built with large-file support reach OnionOS's
 * audio server.
 *
 * OnionOS plays OSS audio through libpadsp.so (LD_PRELOAD), which intercepts
 * open("/dev/dsp") and sends the samples to its audioserver. Libraries built
 * with _FILE_OFFSET_BITS=64, like the OpenAL Soft in the Miyoo toolchain,
 * call open64() instead, which libpadsp doesn't hook, so they hit the real
 * /dev/dsp (owned by audioserver: "Device or resource busy").
 *
 * This library defines open64() and forwards /dev/dsp to libpadsp's open().
 * Preload it before libpadsp: LD_PRELOAD="libdspfix.so libpadsp.so"
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>
#include <string.h>
#include <sys/types.h>

typedef int (*open_fn)(const char *, int, ...);

int open64(const char *path, int flags, ...)
{
    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode = (mode_t)va_arg(ap, int);
        va_end(ap);
    }
    if (path && strncmp(path, "/dev/dsp", 8) == 0) {
        static open_fn padsp_open;
        if (!padsp_open)
            padsp_open = (open_fn)dlsym(RTLD_DEFAULT, "open");
        if (padsp_open)
            return padsp_open(path, flags & ~O_LARGEFILE, mode);
    }
    static open_fn real_open64;
    if (!real_open64)
        real_open64 = (open_fn)dlsym(RTLD_NEXT, "open64");
    return real_open64(path, flags, mode);
}
