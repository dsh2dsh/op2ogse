#!/bin/sh

ROOT=$1

rsync -aFv --no-g --no-p --delete --filter=':- .gitignore' \
      ${ROOT}/bin \
      ${ROOT}/gamedata \
      ${ROOT}/gamemtl \
      ${ROOT}/ReadMe_dsh.txt \
      ${ROOT}/shaders_xr \
      ${ROOT}/shaders_xrlc_xr \
      ./
