# shellcheck shell=bash
# ensure_tunnel: idempotently start `code [--insiders] tunnel` inside a codespace.
# Downloads a standalone VS Code CLI into ~/.sili/cli/ on first run so we don't
# depend on whatever the codespace base image happens to ship.

# sili::ensure_tunnel <codespace_name> <quality>
sili::ensure_tunnel() {
  local codespace=$1 quality=$2
  local bin_name
  bin_name=$(sili::quality_bin "$quality")

  # Microsoft's update channel slug differs from sili's quality label:
  # "insiders" (sili) maps to "insider" (download URL), "stable" stays "stable".
  local channel
  case $quality in
    insiders) channel=insider ;;
    stable)   channel=stable ;;
    *)        sili::die "unknown quality: $quality" ;;
  esac

  local tunnel_name=${SILI_TUNNEL_NAME:-$codespace}

  sili::log "ensuring '$bin_name tunnel' is running in $codespace"

  # Heredoc is unquoted on the local side: $bin_name / $channel / $tunnel_name
  # are interpolated locally. Anything escaped with \$ is preserved literally
  # and evaluated on the remote side.
  local remote_script
  remote_script=$(cat <<EOF
set -e

bin_name="$bin_name"
channel="$channel"
tunnel_name="$tunnel_name"

cli_dir="\$HOME/.sili/cli/\$channel"
cli_path="\$cli_dir/\$bin_name"

# Idempotency: if a tunnel is already running, we're done.
if pgrep -f "\$bin_name tunnel" >/dev/null 2>&1; then
  echo "[remote] tunnel already running"
  exit 0
fi

# Detect architecture for the CLI download URL.
arch=\$(uname -m)
case "\$arch" in
  x86_64)        arch_seg=x64 ;;
  aarch64|arm64) arch_seg=arm64 ;;
  *)
    echo "[remote] unsupported architecture: \$arch" >&2
    exit 1
    ;;
esac

# Fetch the standalone CLI on first run; cache it for next time.
if [ ! -x "\$cli_path" ]; then
  url="https://update.code.visualstudio.com/latest/cli-linux-\${arch_seg}/\${channel}"
  echo "[remote] downloading VS Code CLI from \$url"
  mkdir -p "\$cli_dir"
  tmp=\$(mktemp)
  if ! curl -fsSL -o "\$tmp" "\$url"; then
    rm -f "\$tmp"
    echo "[remote] CLI download failed" >&2
    exit 1
  fi
  tar -xzf "\$tmp" -C "\$cli_dir"
  rm -f "\$tmp"
  if [ ! -x "\$cli_path" ]; then
    echo "[remote] CLI extraction did not produce \$cli_path" >&2
    exit 1
  fi
fi

mkdir -p "\$HOME/.sili"
log="\$HOME/.sili/tunnel.log"

nohup "\$cli_path" tunnel \\
  --accept-server-license-terms \\
  --name "\$tunnel_name" \\
  >> "\$log" 2>&1 &
disown || true

echo "[remote] started: \$cli_path tunnel --name \$tunnel_name"
echo "[remote] log: \$log"
EOF
)

  if ! gh codespace ssh -c "$codespace" -- bash -s <<< "$remote_script"; then
    sili::die "failed to start tunnel inside $codespace"
  fi

  sili::print_url "$quality" "$tunnel_name"
}
