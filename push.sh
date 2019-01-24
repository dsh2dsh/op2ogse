#!/bin/sh

ROOT=$1

rsync -aFv --no-g --no-p --delete --filter=':- .gitignore' \
      bin gamedata gamemtl ReadMe_dsh.txt \
      ${ROOT}/
