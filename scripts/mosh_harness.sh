#!/usr/bin/env bash
set -euo pipefail

# Local mosh-server harness (Docker)
#
# Prerequisites:
# - Docker
# - OpenSSH tools (ssh-keygen, ssh-keyscan)
# - mosh client (optional; for manual CLI testing)
#
# Usage:
#   scripts/mosh_harness.sh start
#   scripts/mosh_harness.sh stop
#   scripts/mosh_harness.sh status

STATE_FILE=${MOSH_HARNESS_STATE_FILE:-/tmp/mosh-harness.state}
IMAGE_TAG=${MOSH_HARNESS_IMAGE_TAG:-mosh-harness:latest}
MOSH_USER=${MOSH_HARNESS_USER:-mosh}
MOSH_HOST=${MOSH_HARNESS_HOST:-127.0.0.1}
MOSH_UDP_RANGE=${MOSH_HARNESS_UDP_RANGE:-60000-61000}

usage() {
  echo "Usage: $0 start|stop|status" >&2
}

die() {
  echo "Error: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

maybe_warn_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Warning: '$1' not found; optional for manual testing." >&2
  fi
}

ssh_keyscan_with_retry() {
  local host=$1
  local port=$2
  local out=$3
  local attempts=10
  local delay=0.3

  for _ in $(seq 1 "$attempts"); do
    if ssh-keyscan -p "$port" "$host" > "$out" 2>/dev/null; then
      return 0
    fi
    sleep "$delay"
  done

  return 1
}

build_image_if_needed() {
  if docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
    return
  fi

  local build_dir
  build_dir=$(mktemp -d -t mosh-harness-build.XXXXXX)

  cat > "$build_dir/Dockerfile" <<'DOCKERFILE'
FROM alpine:3.20
RUN apk add --no-cache openssh-server mosh bash
RUN mkdir -p /var/run/sshd
COPY sshd_config /etc/ssh/sshd_config
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
EXPOSE 22 60000-61000/udp
ENTRYPOINT ["/entrypoint.sh"]
DOCKERFILE

  cat > "$build_dir/sshd_config" <<'SSHD_CONFIG'
Port 22
ListenAddress 0.0.0.0
Protocol 2
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key
PasswordAuthentication no
ChallengeResponseAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
UsePAM no
Subsystem sftp /usr/lib/ssh/sftp-server
SSHD_CONFIG

  cat > "$build_dir/entrypoint.sh" <<'ENTRYPOINT'
#!/bin/sh
set -e

USER_NAME="${MOSH_USER:-mosh}"
if ! id -u "$USER_NAME" >/dev/null 2>&1; then
  adduser -D "$USER_NAME"
fi

HOME_DIR="/home/$USER_NAME"
SSH_DIR="$HOME_DIR/.ssh"
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
cat /authorized_keys > "$SSH_DIR/authorized_keys"
chmod 600 "$SSH_DIR/authorized_keys"
chown -R "$USER_NAME:$USER_NAME" "$HOME_DIR"

ssh-keygen -A
exec /usr/sbin/sshd -D -e -f /etc/ssh/sshd_config
ENTRYPOINT

  docker build -t "$IMAGE_TAG" "$build_dir" >/dev/null
  rm -rf "$build_dir"
}

start_harness() {
  require_cmd docker
  require_cmd ssh-keygen
  require_cmd ssh-keyscan
  maybe_warn_cmd mosh

  if [ -f "$STATE_FILE" ]; then
    die "Harness already running. Stop it first: $0 stop"
  fi

  local state_dir container_name container_id host_port
  state_dir=$(mktemp -d -t mosh-harness.XXXXXX)

  cleanup_start() {
    if [ -n "${container_id:-}" ]; then
      docker rm -f "$container_id" >/dev/null 2>&1 || true
    fi
    rm -rf "$state_dir"
  }
  trap cleanup_start EXIT

  ssh-keygen -t ed25519 -N "" -f "$state_dir/ssh_key" >/dev/null
  cp "$state_dir/ssh_key.pub" "$state_dir/authorized_keys"

  build_image_if_needed

  container_name="mosh-harness-$$"
  container_id=$(docker run -d --rm \
    --name "$container_name" \
    -e MOSH_USER="$MOSH_USER" \
    -p "$MOSH_HOST"::22 \
    -p "$MOSH_HOST":"$MOSH_UDP_RANGE":"$MOSH_UDP_RANGE"/udp \
    -v "$state_dir/authorized_keys":/authorized_keys:ro \
    "$IMAGE_TAG")

  host_port=$(docker port "$container_id" 22/tcp | head -n1 | awk -F: '{print $NF}')
  if [ -z "$host_port" ]; then
    die "Failed to determine host port for SSH"
  fi

  if ! ssh_keyscan_with_retry "$MOSH_HOST" "$host_port" "$state_dir/known_hosts"; then
    die "Failed to capture SSH host key from $MOSH_HOST:$host_port"
  fi

  cat > "$state_dir/connection.env" <<ENVEOF
export MOSH_HOST="$MOSH_HOST"
export MOSH_SSH_PORT="$host_port"
export MOSH_USER="$MOSH_USER"
export MOSH_KEY_PATH="$state_dir/ssh_key"
export MOSH_KNOWN_HOSTS_PATH="$state_dir/known_hosts"
export MOSH_UDP_PORT_RANGE="$MOSH_UDP_RANGE"
ENVEOF

  echo "$container_id" > "$state_dir/container.id"
  echo "$IMAGE_TAG" > "$state_dir/image.tag"
  echo "$state_dir" > "$STATE_FILE"

  trap - EXIT

  echo "Mosh harness started."
  echo "Connection env: $state_dir/connection.env"
  echo "Stop with: $0 stop"
}

stop_harness() {
  require_cmd docker

  if [ ! -f "$STATE_FILE" ]; then
    die "No harness state found. Nothing to stop."
  fi

  local state_dir container_id
  state_dir=$(cat "$STATE_FILE")

  if [ -f "$state_dir/container.id" ]; then
    container_id=$(cat "$state_dir/container.id")
    docker rm -f "$container_id" >/dev/null 2>&1 || true
  fi

  rm -rf "$state_dir"
  rm -f "$STATE_FILE"

  echo "Mosh harness stopped."
}

status_harness() {
  if [ ! -f "$STATE_FILE" ]; then
    echo "Mosh harness not running."
    return
  fi

  local state_dir container_id
  state_dir=$(cat "$STATE_FILE")
  if [ -f "$state_dir/container.id" ]; then
    container_id=$(cat "$state_dir/container.id")
    if docker ps -q --no-trunc | grep -q "$container_id"; then
      echo "Mosh harness running (container: $container_id)."
      echo "Connection env: $state_dir/connection.env"
      return
    fi
  fi

  echo "Mosh harness state exists but container not running."
  echo "State dir: $state_dir"
}

case "${1:-}" in
  start)
    start_harness
    ;;
  stop)
    stop_harness
    ;;
  status)
    status_harness
    ;;
  *)
    usage
    exit 1
    ;;
esac
