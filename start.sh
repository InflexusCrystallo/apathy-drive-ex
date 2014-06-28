#!/usr/bin/env sh

if [ ! -f deps ]; then
  grunt sass && grunt coffee
fi

case $1 in
    "--no-shell")
        exec elixir --detached -S mix run --no-halt
        ;;
    *)
        exec iex -S mix
        ;;
esac