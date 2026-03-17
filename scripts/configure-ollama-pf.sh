#!/bin/sh

set -eu

ANCHOR_NAME="com.litellm.ollama"
PORT="11434"
REMOVE_EXISTING=0
DRY_RUN=0
REMOTE_SUBNETS=""
PF_CONF="/etc/pf.conf"
MARKER_BEGIN="# BEGIN litellm-ollama-docker-compose"
MARKER_END="# END litellm-ollama-docker-compose"

usage() {
  cat <<EOF
Usage: sudo sh ./scripts/configure-ollama-pf.sh [options]

Options:
  --remote-subnet CIDR   Allow this source subnet to reach Ollama on port $PORT.
                         Repeat the option to allow multiple subnets.
  --port PORT            Ollama TCP port to protect. Default: $PORT.
  --anchor-name NAME     pf anchor name. Default: $ANCHOR_NAME.
  --remove-existing      Remove the managed pf anchor and pf.conf include block.
  --dry-run              Print detected subnets and generated rules without applying them.
  -h, --help             Show this help.

If --remote-subnet is omitted, the script attempts to detect a common Docker Desktop
private subnet on macOS, such as 192.168.64.0/24 or 192.168.65.0/24.
EOF
}

append_subnet() {
  subnet="$1"
  if [ -z "$REMOTE_SUBNETS" ]; then
    REMOTE_SUBNETS="$subnet"
  else
    REMOTE_SUBNETS="$REMOTE_SUBNETS
$subnet"
  fi
}

detect_docker_subnets() {
  /usr/sbin/netstat -rn -f inet | /usr/bin/awk '
    $1 ~ /^192\.168\.(64|65|127)$/ && $3 == "255.255.255.0" { print $1 ".0/24"; next }
    $1 ~ /^192\.168\.(64|65|127)\.0$/ && $3 == "255.255.255.0" { print $1 "/24"; next }
    $1 ~ /^192\.168\.(64|65|127)\/24$/ { print $1; next }
  ' | /usr/bin/sort -u
}

remove_anchor_block() {
  tmp_file=$(/usr/bin/mktemp)
  /usr/bin/awk -v begin="$MARKER_BEGIN" -v end="$MARKER_END" '
    $0 == begin { skip=1; next }
    $0 == end { skip=0; next }
    !skip { print }
  ' "$PF_CONF" > "$tmp_file"
  /bin/cp "$tmp_file" "$PF_CONF"
  /bin/rm -f "$tmp_file"
}

write_anchor_file() {
  target_file="$1"
  {
    echo "# Managed by litellm-ollama-docker-compose"
    echo "pass in quick inet proto tcp from 127.0.0.1 to any port $PORT"
    printf '%s\n' "$REMOTE_SUBNETS" | while IFS= read -r subnet; do
      [ -n "$subnet" ] && echo "pass in quick inet proto tcp from $subnet to any port $PORT"
    done
    echo "block in quick inet proto tcp from any to any port $PORT"
  } > "$target_file"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --remote-subnet)
      shift
      [ $# -gt 0 ] || { echo "Missing value for --remote-subnet" >&2; usage; exit 1; }
      append_subnet "$1"
      ;;
    --port)
      shift
      [ $# -gt 0 ] || { echo "Missing value for --port" >&2; usage; exit 1; }
      PORT="$1"
      ;;
    --anchor-name)
      shift
      [ $# -gt 0 ] || { echo "Missing value for --anchor-name" >&2; usage; exit 1; }
      ANCHOR_NAME="$1"
      ;;
    --remove-existing)
      REMOVE_EXISTING=1
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

ANCHOR_FILE="/etc/pf.anchors/$ANCHOR_NAME"

if [ "$(/usr/bin/id -u)" -ne 0 ]; then
  echo "This script must be run as root. Example: sudo sh ./scripts/configure-ollama-pf.sh" >&2
  exit 1
fi

if [ "$REMOVE_EXISTING" -eq 1 ]; then
  if [ -f "$PF_CONF" ]; then
    remove_anchor_block
  fi
  /bin/rm -f "$ANCHOR_FILE"
  /sbin/pfctl -f "$PF_CONF"
  echo "Removed managed pf rules for Ollama port $PORT."
  exit 0
fi

if [ -z "$REMOTE_SUBNETS" ]; then
  REMOTE_SUBNETS="$(detect_docker_subnets)"
fi

if [ -z "$REMOTE_SUBNETS" ]; then
  echo "Could not detect a common Docker Desktop subnet on this Mac." >&2
  echo "Re-run with --remote-subnet, for example: sudo sh ./scripts/configure-ollama-pf.sh --remote-subnet 192.168.65.0/24" >&2
  exit 1
fi

tmp_anchor=$(/usr/bin/mktemp)
write_anchor_file "$tmp_anchor"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "Detected/selected remote subnets:"
  printf '%s\n' "$REMOTE_SUBNETS"
  echo
  echo "Generated pf anchor rules:"
  /bin/cat "$tmp_anchor"
  /bin/rm -f "$tmp_anchor"
  exit 0
fi

/bin/mkdir -p /etc/pf.anchors
/bin/cp "$tmp_anchor" "$ANCHOR_FILE"
/bin/rm -f "$tmp_anchor"

if ! /usr/bin/grep -Fq "$MARKER_BEGIN" "$PF_CONF"; then
  {
    echo
    echo "$MARKER_BEGIN"
    echo "anchor \"$ANCHOR_NAME\""
    echo "load anchor \"$ANCHOR_NAME\" from \"$ANCHOR_FILE\""
    echo "$MARKER_END"
  } >> "$PF_CONF"
fi

/sbin/pfctl -e >/dev/null 2>&1 || true
/sbin/pfctl -f "$PF_CONF"

echo "Configured pf rules for Ollama port $PORT."
echo "Allowed remote subnets:"
printf '%s\n' "$REMOTE_SUBNETS"
echo "Use --remove-existing to remove the managed pf rules later."