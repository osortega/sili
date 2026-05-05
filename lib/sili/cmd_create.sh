# shellcheck shell=bash
# sili create — create a new codespace, then start a tunnel inside it.

sili::cmd_create() {
  local quality
  quality=$(sili::resolve_quality "$@")

  local args=()
  while IFS= read -r a; do args+=("$a"); done < <(sili::strip_stable "$@")

  # Look for -R/-r/--repo and -d/--display-name in the forwarded args. If a
  # repo is supplied and the user didn't pick a display name themselves,
  # default the display name to the repo's basename — collision-suffixed
  # against existing codespaces (foo, foo-1, foo-2, ...). The display name
  # also drives the tunnel name (see ensure_tunnel.sh) so the URL ends up
  # like https://insiders.vscode.dev/tunnel/<repo>.
  local repo="" has_display=0
  local i=0
  while (( i < ${#args[@]} )); do
    case "${args[i]}" in
      -R|-r|--repo)
        (( i + 1 < ${#args[@]} )) && repo="${args[i+1]}"
        i=$((i + 2)) ;;
      --repo=*)
        repo="${args[i]#*=}"
        i=$((i + 1)) ;;
      -d|--display-name)
        has_display=1
        i=$((i + 2)) ;;
      --display-name=*)
        has_display=1
        i=$((i + 1)) ;;
      *)
        i=$((i + 1)) ;;
    esac
  done

  if (( has_display == 0 )) && [[ -n $repo ]]; then
    local repo_base=${repo##*/}
    local display
    display=$(sili::next_unique_display_name "$repo_base")
    args+=(--display-name "$display")
    sili::log "display name: $display"
  fi

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
