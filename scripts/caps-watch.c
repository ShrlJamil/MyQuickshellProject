/*
 * caps-watch — event-driven Caps Lock watcher for the Quickshell OSD.
 *
 * Drop-in replacement for scripts/caps-watch.py (same stdout protocol):
 * watches every keyboard event node, blocks on kernel input events, and
 * prints exactly one "toggle" line per physical Caps Lock press
 * (EV_KEY / KEY_CAPSLOCK / value == 1; release and autorepeat ignored).
 *
 * Stdout is the whole protocol (consumed by a Quickshell SplitParser);
 * stdout carries nothing else. A reader thread that fails simply ends
 * quietly — the OSDService sysfs read remains the fallback, so partial
 * failure only narrows coverage instead of breaking the watcher.
 *
 * Why C: the Python version costs a whole interpreter (~23 MB PSS) running
 * 24/7 for one key. This is plain libc + <linux/input.h>, no libevdev,
 * no extra package: `cc -O2 -o caps-watch caps-watch.c` is the whole build.
 *
 * Usage: caps-watch            (glob by-id, suffix -event-kbd)
 *        caps-watch <path>...  (explicit device paths; testing only)
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <glob.h>
#include <linux/input.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void *watch(void *arg)
{
    char *path = arg;
    int fd = open(path, O_RDONLY);
    free(path);
    if (fd < 0)
        return NULL;

    struct input_event ev;
    for (;;) {
        ssize_t n = 0;
        while (n < (ssize_t)sizeof(ev)) {
            ssize_t r = read(fd, (char *)&ev + n, sizeof(ev) - n);
            if (r == 0) {          /* device gone */
                close(fd);
                return NULL;
            }
            if (r < 0) {
                if (errno == EINTR)
                    continue;
                close(fd);         /* read error: end quietly, like the .py */
                return NULL;
            }
            n += r;
        }
        if (ev.type == EV_KEY && ev.code == KEY_CAPSLOCK && ev.value == 1) {
            fputs("toggle\n", stdout);
            fflush(stdout);
        }
    }
}

int main(int argc, char **argv)
{
    const char **paths = NULL;
    size_t count = 0;
    glob_t g;

    if (argc > 1) {
        paths = (const char **)argv + 1;
        count = (size_t)argc - 1;
    } else if (glob("/dev/input/by-id/*-event-kbd", 0, NULL, &g) == 0) {
        paths = (const char **)g.gl_pathv;
        count = g.gl_pathc;
    }

    pthread_t *threads = calloc(count ? count : 1, sizeof(*threads));
    if (!threads)
        return 1;
    for (size_t i = 0; i < count; i++) {
        char *copy = strdup(paths[i]);
        if (!copy)
            continue;
        if (pthread_create(&threads[i], NULL, watch, copy) != 0)
            free(copy);
    }
    for (size_t i = 0; i < count; i++)
        pthread_join(threads[i], NULL);
    if (argc <= 1)
        globfree(&g);
    free(threads);
    return 0;   /* no devices: same as the .py version — exit, QML restarts us */
}
