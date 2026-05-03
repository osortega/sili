# shellcheck shell=bash
# ensure_tunnel: idempotently start `code [--insiders] tunnel` inside a codespace.

# sili::ensure_tunnel <codespace_name> <quality>
sili::ensure_tunnel() {
  local codespace=$1 quality=$2
  local bin
  bin=$(sili::quality_bin "$quality")

  local tunnel_name=${SILI_TUNNEL_NAME:-$codespace}

  sili::log "ensuring '$bin tunnel' is running in $codespace"

  # The remote script runs inside the codespace via `gh codespace ssh -- bash -s`.
  # Heredoc is unquoted on the local side because we want $bin/$tunnel_name
  # interpolated locally before the script ships. The remote shell sees a
  # pre-rendered script with no further expansions needed.
  local remote_script
  remote_script=$(cat <<EOF
set -e

bin="$bin"
tunnel_name="$tunnel_name"

if pgrep -f "\${bin} tunnel" >/dev/null 2>&1; then
  echo "[remote] tunnel already running"
  exit 0
fi

# Resolve binary; if requested quality isn't available, fall back to the other.
if ! command -v "\$bin" >/dev/null 2>&1; then
  if [ "\$bin" = code-insiders ] && command -v code >/dev/null 2>&1; then
    echo "[remote] code-insiders not found, falling back to code"
    bin=code
  elif [ "\$bin" = code ] && command -v code-insiders >/dev/null 2>&1; then
    echo "[remote] code not found, falling back to code-insiders"
    bin=code-insiders
  else
    echo "[remote] neither code nor code-insiders available on PATH" >&2
    exit 127
  fi
fi

mkdir -p "\$HOME/.sili"
log="\$HOME/.sili/tunnel.log"

nohup "\$bin" tunnel \\
  --accept-server-license-terms \\
  --name "\$tunnel_name" \\
  >> "\$log" 2>&1 &
disown || true

echo "[remote] started: \$bin tunnel --name \$tunnel_name"
echo "[remote] log: \$log"
EOF
)

  # `gh codespace ssh -- bash -s` runs the heredoc inside the codespace.
  if ! gh codespace ssh -c "$codespace" -- bash -s <<< "$remote_script"; then
    sili::die "failed to start tunnel inside $codespace"
  fi

  sili::print_url "$quality" "$tunnel_name"
}
