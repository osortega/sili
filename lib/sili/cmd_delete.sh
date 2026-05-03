# shellcheck shell=bash
# sili delete — delete a codespace (interactive picker if no name given).

sili::cmd_delete() {
  local name=${1:-}
  if [[ -z $name ]]; then
    name=$(sili::pick_codespace)
  fi
  [[ -z $name ]] && sili::die "no codespace selected"
  sili::log "deleting $name"
  gh codespace delete -c "$name"
}
