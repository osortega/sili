# shellcheck shell=bash
# sili create — create a new codespace, then start a tunnel inside it.

sili::cmd_create() {
  local quality
  quality=$(sili::resolve_quality "$@")

  local args=()
  while IFS= read -r a; do args+=("$a"); done < <(sili::strip_stable "$@")

  sili::log "creating codespace${args[*]:+ (}${args[*]}${args[*]:+)}"

  # Snapshot existing codespaces before invoking gh. We *cannot* use command
  # substitution to capture gh's stdout — that would close the TTY and gh
  # bails with "error getting machine: no terminal" instead of using its
  # default picker. Run gh attached to the terminal, then diff list output
  # to find the new codespace.
  local before after name
  before=$(gh codespace list --json name --jq '.[].name' 2>/dev/null | sort)

  if ! gh codespace create "${args[@]}"; then
    sili::die "gh codespace create failed"
  fi

  after=$(gh codespace list --json name --jq '.[].name' 2>/dev/null | sort)
  name=$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | head -n1)
  [[ -z $name ]] && sili::die "could not determine new codespace name from gh codespace list"

  sili::log "created: $name"

  sili::ensure_tunnel "$name" "$quality"
}
