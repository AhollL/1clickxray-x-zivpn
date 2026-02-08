#!/usr/bin/env bash
# xray-zivpn-dual-installer (Debian 11)
# Installs:
#  - 1clickxray (Xray stack, typically TCP 80/443)
#  - udp-zivpn (UDP redirect 6000-19999 -> 5667 by default)
#
# NOTE:
# - This wrapper downloads and executes upstream scripts from GitHub.
# - Review the upstream scripts before use, and use at your own risk.

set -Eeuo pipefail

# ----------------------------- Config -----------------------------
XRAY_INSTALL_URL="${XRAY_INSTALL_URL:-https://raw.githubusercontent.com/dugong-lewat/1clickxray/main/install2.sh}"

ZIVPN_INSTALL_URL="${ZIVPN_INSTALL_URL:-https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/zi.sh}"

# Firewall ports
HTTP_PORT="${HTTP_PORT:-80}"
HTTPS_PORT="${HTTPS_PORT:-443}"
ZIVPN_UDP_RANGE="${ZIVPN_UDP_RANGE:-6000:19999}"
ZIVPN_UDP_INTERNAL_PORT="${ZIVPN_UDP_INTERNAL_PORT:-5667}"

# Set to 1 to also relax rp_filter (helps some UDP/NAT cases)
RELAX_RPFILTER="${RELAX_RPFILTER:-0}"

# Where to log
LOG_FILE="${LOG_FILE:-/var/log/xray-zivpn-dual-installer.log}"
# -----------------------------------------------------------------

_color() { printf "\033[%sm%s\033[0m" "$1" "$2"; }
info()  { echo -e "$(_color '1;34' '[i]') $*"; }
ok()    { echo -e "$(_color '1;32' '[+]') $*"; }
warn()  { echo -e "$(_color '1;33' '[!]' ) $*"; }
err()   { echo -e "$(_color '1;31' '[x]' ) $*"; }
die()   { err "$*"; exit 1; }

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "Please run as root: sudo -i  (or: sudo bash $0)"
  fi
}

detect_os() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
  else
    die "Cannot read /etc/os-release"
  fi

  if [[ "${ID:-}" != "debian" ]]; then
    die "This script is intended for Debian. Detected ID=${ID:-unknown}"
  fi

  if [[ "${VERSION_ID:-}" != "11" ]]; then
    warn "Detected Debian VERSION_ID=${VERSION_ID:-unknown}. This repo targets Debian 11."
    warn "It may still work, but proceed carefully."
  fi
}

tee_log() {
  mkdir -p "$(dirname "$LOG_FILE")"
  touch "$LOG_FILE"
  chmod 600 "$LOG_FILE"
  exec > >(tee -a "$LOG_FILE") 2>&1
}

apt_install() {
  export DEBIAN_FRONTEND=noninteractive
  info "Installing prerequisites…"
  apt-get update -y
  apt-get install -y --no-install-recommends \
    ca-certificates curl wget gnupg \
    ufw iptables iptables-persistent netfilter-persistent \
    lsb-release
}

sysctl_tune() {
  info "Enabling IP forwarding…"
  cat >/etc/sysctl.d/99-xray-zivpn-forward.conf <<'EOF'
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
EOF

  if [[ "$RELAX_RPFILTER" == "1" ]]; then
    warn "RELAX_RPFILTER=1: disabling rp_filter (helps some UDP/NAT scenarios)"
    cat >/etc/sysctl.d/99-xray-zivpn-rpfilter.conf <<'EOF'
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
EOF
  fi

  sysctl --system
}

get_ssh_port() {
  local p
  p="$(awk '/^\s*Port\s+/{print $2}' /etc/ssh/sshd_config 2>/dev/null | tail -n1 || true)"
  if [[ -n "$p" ]]; then
    echo "$p"
  else
    echo "22"
  fi
}

ufw_setup() {
  info "Configuring UFW firewall…"
  local ssh_port
  ssh_port="$(get_ssh_port)"

  # Always allow SSH first to avoid lockouts
  ufw allow "${ssh_port}/tcp" >/dev/null || true
  ufw allow "${HTTP_PORT}/tcp" >/dev/null || true
  ufw allow "${HTTPS_PORT}/tcp" >/dev/null || true

  # ZIVPN UDP ports
  ufw allow "${ZIVPN_UDP_INTERNAL_PORT}/udp" >/dev/null || true
  ufw allow "${ZIVPN_UDP_RANGE}/udp" >/dev/null || true

  # Enable if not enabled
  if ufw status | grep -qi "Status: inactive"; then
    warn "Enabling UFW… (SSH port allowed: ${ssh_port}/tcp)"
    ufw --force enable
  fi

  ok "UFW rules applied."
  ufw status verbose || true
}

download_and_run() {
  local url="$1"
  local name="$2"
  local tmp="/tmp/${name}.$$.$RANDOM.sh"

  info "Downloading: $url"
  curl -fsSL "$url" -o "$tmp" || die "Failed to download $url"
  chmod +x "$tmp"

  info "Running: $name (this may be interactive)…"
  bash "$tmp"
  rm -f "$tmp"
}

post_checks() {
  info "Post-install checks…"
  echo
  echo "== Listening ports (80/443/5667) =="
  ss -tulpn | egrep ":(80|443|${ZIVPN_UDP_INTERNAL_PORT})\b" || true
  echo
  echo "== NAT rules containing UDP range / 5667 =="
  iptables -t nat -S PREROUTING | grep -E "(${ZIVPN_UDP_RANGE//:/-}|${ZIVPN_UDP_INTERNAL_PORT})" || true
  echo
}

persist_iptables() {
  info "Saving iptables rules (netfilter-persistent)…"
  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save || true
    systemctl enable netfilter-persistent >/dev/null 2>&1 || true
    ok "iptables rules saved."
  else
    warn "netfilter-persistent not found. Skipping iptables persistence."
  fi
}

main() {
  require_root
  detect_os
  tee_log

  info "Log file: $LOG_FILE"
  echo

  apt_install
  sysctl_tune
  ufw_setup

  echo
  info "Step 1/2: Install 1clickxray"
  download_and_run "$XRAY_INSTALL_URL" "1clickxray-install2"

  echo
  info "Step 2/2: Install udp-zivpn"
  download_and_run "$ZIVPN_INSTALL_URL" "udp-zivpn-zi"

  persist_iptables
  post_checks

  ok "Done. If everything connects, you're good."
  echo "Tip: If you run other UDP-based services, avoid UDP range ${ZIVPN_UDP_RANGE} (it is redirected to ${ZIVPN_UDP_INTERNAL_PORT})."
}

main "$@"
