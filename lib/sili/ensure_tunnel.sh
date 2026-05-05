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

  # Prefer the codespace's displayName as the tunnel name — that's what
  # `sili create` sets to the repo name. Fall back to the codespace's
  # underlying random name if no displayName is set. SILI_TUNNEL_NAME
  # overrides everything.
  local tunnel_name
  if [[ -n ${SILI_TUNNEL_NAME:-} ]]; then
    tunnel_name=$SILI_TUNNEL_NAME
  else
    local display
    display=$(gh codespace list --json name,displayName \
      --jq ".[] | select(.name == \"$codespace\") | .displayName" 2>/dev/null) || display=""
    tunnel_name=${display:-$codespace}
  fi
  tunnel_name=$(sili::trim_tunnel_name "$tunnel_name")

  sili::log "ensuring '$bin_name tunnel' is running in $codespace (tunnel name: $tunnel_name)"

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

# Rotate previous log so the local watcher only sees output from this run.
[ -f "\$log" ] && mv "\$log" "\${log}.prev"
: > "\$log"

nohup "\$cli_path" tunnel \\
  --accept-server-license-terms \\
  --name "\$tunnel_name" \\
  >> "\$log" 2>&1 &
disown || true

echo "[remote] launched: \$cli_path tunnel --name \$tunnel_name"
echo "[remote] log: \$log"
EOF
)

  # Capture launch output so we can detect the "already running" short-circuit
  # without losing user-visible feedback.
  local launch_out
  launch_out=$(mktemp)
  gh codespace ssh -c "$codespace" -- bash -s <<< "$remote_script" 2>&1 | tee "$launch_out"
  local rc=${PIPESTATUS[0]}
  if (( rc != 0 )); then
    rm -f "$launch_out"
    sili::die "failed to start tunnel inside $codespace"
  fi

  if grep -q '\[remote\] tunnel already running' "$launch_out"; then
    rm -f "$launch_out"
    sili::print_url "$quality" "$tunnel_name"
    return 0
  fi
  rm -f "$launch_out"

  # New launch: wait until the tunnel registers (and surface device-code
  # auth if the user needs to grant access). Only print the URL once we've
  # confirmed the tunnel is live.
  if ! sili::wait_for_tunnel "$codespace"; then
    return 1
  fi

  sili::print_url "$quality" "$tunnel_name"
}

# Poll the remote tunnel log until either:
#   (a) we see the "Open this link..." line containing vscode.dev/tunnel/...
#       — the tunnel is live, return 0.
#   (b) timeout elapses — return 1.
# Along the way, surface any device-code prompt so the user can authorize.
sili::wait_for_tunnel() {
  local codespace=$1
  local timeout=${SILI_TUNNEL_TIMEOUT:-300}
  local interval=2

  sili::log "waiting for tunnel to register (timeout: ${timeout}s)"

  local saw_device=0 elapsed=0 log_content
  while (( elapsed < timeout )); do
    log_content=$(gh codespace ssh -c "$codespace" \
      -- 'cat ~/.sili/tunnel.log 2>/dev/null' 2>/dev/null) || log_content=""

    if (( saw_device == 0 )); then
      local device_line url code
      device_line=$(printf '%s\n' "$log_content" \
        | grep -E 'github\.com/login/device' | tail -1 || true)
      if [[ -n $device_line ]]; then
        saw_device=1
        url=$(printf '%s' "$device_line" \
          | grep -oE 'https://github\.com/login/device' | head -1)
        code=$(printf '%s' "$device_line" \
          | grep -oE '[A-Z0-9]{4}-[A-Z0-9]{4}' | head -1)
        sili::warn "first-run authentication required:"
        if [[ -n $url && -n $code ]]; then
          printf '\n  Open: %s\n  Code: %s\n\n' "$url" "$code" >&2
        else
          printf '\n  %s\n\n' "$device_line" >&2
        fi
      fi
    fi

    if printf '%s\n' "$log_content" \
        | grep -qE 'https://[a-z.]*vscode\.dev/tunnel/'; then
      sili::log "tunnel registered"
      return 0
    fi

    sleep "$interval"
    elapsed=$(( elapsed + interval ))
  done

  sili::warn "tunnel did not register within ${timeout}s"
  sili::warn "inspect the log: gh codespace ssh -c $codespace -- 'tail -f ~/.sili/tunnel.log'"
  return 1
}
