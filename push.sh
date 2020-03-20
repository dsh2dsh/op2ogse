#!/bin/sh

ROOT=$1

rsync -aFv --no-g --no-p --delete --filter=':- .gitignore' \
      bin game.graph gamedata gamemtl particles ReadMe_dsh.txt shaders_xr \
      shaders_xrlc_xr stkutils \
      ${ROOT}/
