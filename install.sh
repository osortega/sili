#!/usr/bin/env bash
# Symlink bin/sili into a directory on PATH (default: ~/.local/bin).

set -euo pipefail

target_dir=${SILI_INSTALL_DIR:-$HOME/.local/bin}
src=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bin/sili

if [[ ! -x $src ]]; then
  echo "error: $src not found or not executable" >&2
  exit 1
fi

mkdir -p "$target_dir"
ln -sf "$src" "$target_dir/sili"

echo "linked: $target_dir/sili -> $src"

case ":$PATH:" in
  *":$target_dir:"*) ;;
  *) echo "warning: $target_dir is not in PATH; add it to your shell rc" >&2 ;;
esac
