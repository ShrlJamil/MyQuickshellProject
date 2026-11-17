#!/bin/sh
# Build the caps-watch helper (plain libc + <linux/input.h>, no extra deps).
set -e
cc -O2 -Wall -o "$(dirname "$0")/caps-watch" "$(dirname "$0")/caps-watch.c"
