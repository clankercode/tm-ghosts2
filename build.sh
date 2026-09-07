#!/usr/bin/env bash
# Build / stage / hot-reload an Openplanet plugin for ManiaPlanet 4 (Openplanet4).
#   ./build.sh [dev|release]      (default: dev)
# Env: MP4_PLUGINS_DIR (NOT PLUGINS_DIR: that env var points at the TM2020 tree) (default ~/Openplanet4/Plugins), SKIP_LSP=1, SKIP_RELOAD=1
set -euo pipefail
cd "$(dirname "$0")"
mode="${1:-dev}"
plugins_dir="${MP4_PLUGINS_DIR:-$HOME/Openplanet4/Plugins}"
op_dir="$(dirname "$plugins_dir")"
slug="$(basename "$PWD")"
name="$(grep -m1 '^name' info.toml | cut -d= -f2 | tr -d ' "')"
version="$(grep -m1 '^version' info.toml | cut -d= -f2 | tr -d ' "')"

if [[ "${SKIP_LSP:-0}" != "1" ]] && command -v openplanet-lsp >/dev/null; then
  echo "== openplanet-lsp check (MP4)"
  openplanet-lsp check --game-target MP4 --typedb-dir "${MP4_TYPEDB_DIR:-$HOME/.cache/openplanet-lsp-typedb-mp4}" --plugins-dir "$plugins_dir" --plugins-dir "$(dirname "$PWD")" . || {
    echo "!! openplanet-lsp reported errors (SKIP_LSP=1 to bypass)"; exit 1; }
fi

case "$mode" in
  dev)
    dest="$plugins_dir/$slug"
    mkdir -p "$dest"
    rm -rf "${dest:?}"/*
    cp -R src/* "$dest/"
    cp info.toml "$dest/info.toml"
    sed -i 's/^\(name[ \t="]*\)\(.*\)"/\1\2 (Dev)"/' "$dest/info.toml"
    sed -i 's/^#__DEFINES__/defines = ["DEV"]/' "$dest/info.toml"
    echo "== staged $name $version -> $dest"
    if [[ "${SKIP_RELOAD:-0}" != "1" ]] && command -v tm-remote-build >/dev/null; then
      rb_host="$(ss -ltnH 2>/dev/null | awk '$4 ~ /:30001$/ { sub(/:[0-9]+$/, "", $4); print $4; exit }')"
      if [[ -n "$rb_host" ]]; then
        [[ "$rb_host" == "0.0.0.0" || "$rb_host" == "*" ]] && rb_host="127.0.0.1"
        echo "== tm-remote-build load folder $slug (Openplanet4 @ $rb_host)"
        tm-remote-build load folder "$slug" -op Openplanet4 --host "$rb_host" -d "$op_dir" -l 3 -i 0.5 || echo "!! remote load failed (see ~/Openplanet4/Openplanet.log)"
      else
        echo "!! RemoteBuild (:30001) not listening; restart the game or load the plugin manually"
      fi
    fi
    ;;
  release)
    out="$slug-$version.op"
    rm -f "$out"
    (cd src && 7z a -tzip "../$out" ./* >/dev/null)
    7z a -tzip "$out" info.toml >/dev/null
    echo "== built $out"
    ;;
  *) echo "usage: $0 [dev|release]"; exit 2;;
esac
