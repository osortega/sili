# shellcheck shell=bash
# sili create — create a new codespace, then start a tunnel inside it.

sili::cmd_create() {
  local quality
  quality=$(sili::resolve_quality "$@")

  local args=()
  while IFS= read -r a; do args+=("$a"); done < <(sili::strip_stable "$@")

  sili::log "creating codespace${args[*]:+ (}${args[*]}${args[*]:+)}"

  # `gh codespace create` prints the new codespace name on stdout.
  local name
  if ! name=$(gh codespace create "${args[@]}"); then
    sili::die "gh codespace create failed"
  fi
  name=$(printf '%s' "$name" | tail -n1 | tr -d '[:space:]')
  [[ -z $name ]] && sili::die "could not parse codespace name from gh output"

  sili::log "created: $name"

  sili::ensure_tunnel "$name" "$quality"
}
