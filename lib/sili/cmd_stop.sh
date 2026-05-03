# shellcheck shell=bash
# sili stop — stop a codespace (interactive picker if no name given).

sili::cmd_stop() {
  local name=${1:-}
  if [[ -z $name ]]; then
    name=$(sili::pick_codespace)
  fi
  [[ -z $name ]] && sili::die "no codespace selected"
  sili::log "stopping $name"
  gh codespace stop -c "$name"
}
