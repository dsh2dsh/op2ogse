#!/bin/sh

CLANG_FORMAT="clang-format15 -style=file -i"

find common r3 \
     '(' -name '*.h' -or -name '*.ds' -or -name '*.hs' -or -name '*.cs' -or \
     -name '*.gs' -or -name '*.ps' -or -name '*.vs' ')' \
     -exec $CLANG_FORMAT '{}' '+'
