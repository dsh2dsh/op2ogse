#!/bin/sh

ROOT=$1

find gamedata -depth -type f |
    while read f; do
        echo "$f"
        cp "${ROOT}/$f" "$f"
    done
