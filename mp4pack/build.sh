#!/usr/bin/env bash
# Stage the tm-ghosts2-mp4pack companion plugin (see ../build.sh for the main plugin).
#   ./build.sh dev             (default; only mode this plugin needs)
#   GAME=turbo ./build.sh dev  same pack against the Turbo build of tm-mp4-control
# Env: GAME (mp4|turbo), MP4_PLUGINS_DIR (default ~/Openplanet4/Plugins),
#      TURBO_PLUGINS_DIR (default ~/OpenplanetTurbo/Plugins), SKIP_LSP=1, SKIP_RELOAD=1
set -euo pipefail
cd "$(dirname "$0")"
game="${GAME:-mp4}"
case "$game" in
  mp4)   plugins_dir="${MP4_PLUGINS_DIR:-$HOME/Openplanet4/Plugins}";       lsp_target=MP4;   op_name=Openplanet4;     rb_port=30001 ;;
  turbo) plugins_dir="${TURBO_PLUGINS_DIR:-$HOME/OpenplanetTurbo/Plugins}"; lsp_target=TURBO; op_name=OpenplanetTurbo; rb_port=30002 ;;
  *) echo "unknown GAME=$game (mp4|turbo)" >&2; exit 2 ;;
esac
op_dir="$(dirname "$plugins_dir")"
slug="tm-ghosts2-mp4pack"
name="$(grep -m1 '^name' info.toml | cut -d= -f2 | tr -d ' "')"
version="$(grep -m1 '^version' info.toml | cut -d= -f2 | tr -d ' "')"

if [[ "${SKIP_LSP:-0}" != "1" ]] && command -v openplanet-lsp >/dev/null; then
  echo "== openplanet-lsp check ($lsp_target)"
  lsp_args=(--game-target "$lsp_target" --plugins-dir "$plugins_dir" --plugins-dir "$(dirname "$(dirname "$PWD")")")
  [[ "$game" == mp4 ]] && lsp_args+=(--typedb-dir "${MP4_TYPEDB_DIR:-$HOME/.cache/openplanet-lsp-typedb-mp4}")
  openplanet-lsp check "${lsp_args[@]}" . || {
    echo "!! openplanet-lsp reported errors (SKIP_LSP=1 to bypass)"; exit 1; }
fi

dest="$plugins_dir/$slug"
mkdir -p "$dest"
rm -rf "${dest:?}"/*
cp -R src/* "$dest/"
cp info.toml "$dest/info.toml"
sed -i 's/^\(name[ \t="]*\)\(.*\)"/\1\2 (Dev)"/' "$dest/info.toml"
sed -i 's/^#__DEFINES__/defines = ["DEV"]/' "$dest/info.toml"
echo "== staged $name $version -> $dest"

if [[ "${SKIP_RELOAD:-0}" != "1" ]] && command -v tm-remote-build >/dev/null; then
  rb_host="$(ss -ltnH 2>/dev/null | awk -v p=":$rb_port\$" '$4 ~ p { sub(/:[0-9]+$/, "", $4); print $4; exit }')"
  if [[ -n "$rb_host" ]]; then
    [[ "$rb_host" == "0.0.0.0" || "$rb_host" == "*" ]] && rb_host="127.0.0.1"
    echo "== tm-remote-build load folder $slug ($op_name @ $rb_host:$rb_port)"
    tm-remote-build load folder "$slug" -op "$op_name" --host "$rb_host" -d "$op_dir" -l 3 -i 0.5 || echo "!! remote load failed (see $op_dir/Openplanet.log)"
  else
    echo "!! RemoteBuild (:$rb_port) not listening; restart the game or load the plugin manually"
  fi
fi
