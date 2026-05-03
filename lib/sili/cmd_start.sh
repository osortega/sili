# shellcheck shell=bash
# sili start — wake an existing codespace (resume if stopped), then ensure tunnel.

sili::cmd_start() {
  local quality
  quality=$(sili::resolve_quality "$@")

  local positional=()
  while IFS= read -r a; do positional+=("$a"); done < <(sili::strip_stable "$@")

  local name=${positional[0]:-}
  if [[ -z $name ]]; then
    name=$(sili::pick_codespace)
  fi
  [[ -z $name ]] && sili::die "no codespace selected"

  sili::log "waking $name (gh auto-resumes if stopped)"
  # `gh codespace ssh -- true` connects, which forces a resume on a stopped
  # codespace. We discard its output; only the exit status matters.
  if ! gh codespace ssh -c "$name" -- true >/dev/null 2>&1; then
    sili::die "failed to wake codespace $name"
  fi

  sili::ensure_tunnel "$name" "$quality"
}
