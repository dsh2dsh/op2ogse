#!/bin/sh

ROOT=$1

rsync -aFv --no-g --no-p --delete --filter=':- .gitignore' \
      bin gamedata gamemtl particles ReadMe_dsh.txt shaders_xr shaders_xrlc_xr \
      ${ROOT}/
