# shellcheck shell=bash
# Shared helpers for sili subcommands. Sourced by bin/sili.

set -o pipefail

sili::log()  { printf '\033[1;34m[sili]\033[0m %s\n' "$*" >&2; }
sili::warn() { printf '\033[1;33m[sili]\033[0m %s\n' "$*" >&2; }
sili::die()  { printf '\033[1;31m[sili]\033[0m %s\n' "$*" >&2; exit 1; }

sili::require_cmd() {
  local cmd=$1 hint=${2:-}
  if ! command -v "$cmd" >/dev/null 2>&1; then
    sili::die "missing required command: $cmd${hint:+ (}${hint}${hint:+)}"
  fi
}

sili::check_deps() {
  sili::require_cmd gh "install: https://cli.github.com/"
  sili::require_cmd ssh
  if ! gh auth status >/dev/null 2>&1; then
    sili::die "gh is not authenticated. Run: gh auth login"
  fi
}

# resolve_quality <args...>  -> echoes "insiders" or "stable"
# Default is insiders. --stable flag wins. SILI_QUALITY env var overrides default.
sili::resolve_quality() {
  for arg in "$@"; do
    if [[ $arg == --stable ]]; then
      echo stable
      return
    fi
  done
  if [[ -n ${SILI_QUALITY:-} ]]; then
    echo "$SILI_QUALITY"
    return
  fi
  echo insiders
}

# Strip --stable from args, echoing the remaining ones one per line.
# Usage: mapfile -t out < <(sili::strip_stable "$@")
sili::strip_stable() {
  for arg in "$@"; do
    [[ $arg == --stable ]] && continue
    printf '%s\n' "$arg"
  done
}

sili::quality_bin() {
  case $1 in
    insiders) echo code-insiders ;;
    stable)   echo code ;;
    *)        sili::die "unknown quality: $1" ;;
  esac
}

# VS Code tunnel names must be ≤20 chars and match [a-z0-9][a-z0-9-]*.
# Sanitize (lowercase, replace invalid chars), then squeeze if too long by
# keeping a 12-char prefix and appending a 7-char hash for uniqueness.
sili::trim_tunnel_name() {
  local name=$1
  name=$(printf '%s' "$name" \
    | tr 'A-Z' 'a-z' \
    | tr -c 'a-z0-9-' '-' \
    | tr -s '-' \
    | sed 's/^-*//; s/-*$//')
  [[ -z $name ]] && name=tunnel
  if (( ${#name} <= 20 )); then
    printf '%s' "$name"
    return
  fi
  local prefix=${name:0:12}
  prefix=${prefix%-}
  local hash
  if command -v shasum >/dev/null 2>&1; then
    hash=$(printf '%s' "$name" | shasum -a 256 | cut -c1-7)
  elif command -v sha256sum >/dev/null 2>&1; then
    hash=$(printf '%s' "$name" | sha256sum | cut -c1-7)
  else
    hash=$(printf '%s' "$name" | cksum | awk '{printf "%07x", $1}')
  fi
  printf '%s-%s' "$prefix" "$hash"
}

# Pick the next available display name in a "<base>", "<base>-1", "<base>-2"…
# series, comparing against the displayNames already used by the user's
# codespaces.
sili::next_unique_display_name() {
  local base=$1
  local existing
  existing=$(gh codespace list --json displayName --jq '.[].displayName' 2>/dev/null) \
    || existing=""

  if ! grep -Fxq -- "$base" <<<"$existing"; then
    printf '%s' "$base"
    return
  fi

  local n=1
  while grep -Fxq -- "${base}-${n}" <<<"$existing"; do
    n=$((n + 1))
  done
  printf '%s-%d' "$base" "$n"
}

sili::tunnel_url() {
  local quality=$1 name=$2
  case $quality in
    insiders) echo "https://insiders.vscode.dev/tunnel/$name" ;;
    stable)   echo "https://vscode.dev/tunnel/$name" ;;
  esac
}

# Print a tunnel URL block to stdout. Stdout is the user-facing channel.
sili::print_url() {
  local quality=$1 name=$2
  printf '\nTunnel: %s\n\n' "$(sili::tunnel_url "$quality" "$name")"
}

# Pick a codespace name interactively. fzf when available, numbered prompt otherwise.
# Echoes the chosen name on stdout.
sili::pick_codespace() {
  local names
  names=$(gh codespace list --json name --jq '.[].name' 2>/dev/null) \
    || sili::die "failed to list codespaces"
  [[ -z $names ]] && sili::die "no codespaces found. Try: sili create"

  if command -v fzf >/dev/null 2>&1; then
    echo "$names" | fzf --prompt="codespace> " --height=40% --reverse \
      || sili::die "no selection"
  else
    local IFS=$'\n' i=1
    local arr=()
    while IFS= read -r line; do arr+=("$line"); done <<< "$names"
    {
      for n in "${arr[@]}"; do
        printf '  %2d) %s\n' "$i" "$n"
        i=$((i + 1))
      done
      printf '\nselect codespace [1-%d]: ' "${#arr[@]}"
    } >&2
    local choice
    read -r choice </dev/tty
    [[ $choice =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#arr[@]} )) \
      || sili::die "invalid selection"
    echo "${arr[$((choice - 1))]}"
  fi
}
