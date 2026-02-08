#!/usr/bin/env bash
# 1clickxray x udp-zivpn - Uninstaller (Debian 11)
# - Uninstall Xray stack only
# - Uninstall ZiVPN only
# - Uninstall both
#
# Notes:
# - This is a best-effort remover because upstream scripts may change over time.
# - Default mode removes services + binaries + configs.
# - By default, it does NOT purge packages (nginx, fail2ban, etc.) to avoid breaking other workloads.
#
# Optional env flags:
#   REMOVE_UFW_RULES=1     # attempt to delete UFW rules we typically add
#   PURGE_PACKAGES=1       # attempt to purge some packages (use carefully)
#
set -Eeuo pipefail

# Upstream ZiVPN uninstall script
ZIVPN_UNINSTALL_URL="${ZIVPN_UNINSTALL_URL:-https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/uninstall.sh}"

# Ports/ranges used by ZiVPN typical setup
ZIVPN_UDP_RANGE="${ZIVPN_UDP_RANGE:-6000:19999}"
ZIVPN_UDP_INTERNAL_PORT="${ZIVPN_UDP_INTERNAL_PORT:-5667}"

REMOVE_UFW_RULES="${REMOVE_UFW_RULES:-0}"
PURGE_PACKAGES="${PURGE_PACKAGES:-0}"

_color() { printf "\033[%sm%s\033[0m" "$1" "$2"; }
info()  { echo -e "$(_color '1;34' '[i]') $*"; }
ok()    { echo -e "$(_color '1;32' '[+]') $*"; }
warn()  { echo -e "$(_color '1;33' '[!]' ) $*"; }
err()   { echo -e "$(_color '1;31' '[x]' ) $*"; }

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    err "Please run as root: sudo -i"
    exit 1
  fi
}

confirm() {
  local prompt="${1:-Are you sure?}"
  read -r -p "$prompt [y/N]: " ans || true
  [[ "${ans:-}" =~ ^[Yy]$ ]]
}

stop_disable() {
  local svc="$1"
  systemctl stop "$svc" >/dev/null 2>&1 || true
  systemctl disable "$svc" >/dev/null 2>&1 || true
}

rm_service_file() {
  local svc_file="$1"
  rm -f "/etc/systemd/system/${svc_file}" >/dev/null 2>&1 || true
  rm -f "/lib/systemd/system/${svc_file}" >/dev/null 2>&1 || true
}

daemon_reload() {
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl reset-failed >/dev/null 2>&1 || true
}

# Delete iptables rules by pattern from a given table/chain (safe best-effort)
iptables_delete_matching() {
  local table="$1"
  local chain="$2"
  local pattern="$3"

  if ! command -v iptables >/dev/null 2>&1; then
    warn "iptables not found, skipping rule cleanup."
    return 0
  fi

  local rules
  rules="$(iptables -t "$table" -S "$chain" 2>/dev/null || true)"
  [[ -z "$rules" ]] && return 0

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if echo "$line" | grep -Eqi "$pattern"; then
      # Convert "-A CHAIN ..." -> "-D CHAIN ..."
      local del="${line/-A /-D }"
      iptables -t "$table" $del >/dev/null 2>&1 || true
    fi
  done <<< "$rules"
}

save_netfilter() {
  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save >/dev/null 2>&1 || true
    systemctl enable netfilter-persistent >/dev/null 2>&1 || true
  fi
}

ufw_try_delete() {
  local rule="$1"
  if command -v ufw >/dev/null 2>&1; then
    # Exact delete may fail if rule doesn't exist; ignore errors.
    ufw delete allow $rule >/dev/null 2>&1 || true
  fi
}

remove_common_ufw_rules() {
  info "Attempting to remove common UFW rules (best-effort)…"
  ufw_try_delete "80/tcp"
  ufw_try_delete "443/tcp"
  ufw_try_delete "${ZIVPN_UDP_INTERNAL_PORT}/udp"
  ufw_try_delete "${ZIVPN_UDP_RANGE}/udp"
  ok "UFW rule removal attempted."
  ufw status verbose >/dev/null 2>&1 || true
}

uninstall_xray_stack() {
  info "Uninstalling Xray stack (1clickxray best-effort)…"

  # Services seen in upstream install2.sh (xray + wireproxy + nginx)
  stop_disable "xray.service"
  stop_disable "wireproxy.service"
  # nginx may exist from elsewhere; stop only (don't disable by default)
  systemctl stop nginx.service >/dev/null 2>&1 || true

  rm_service_file "xray.service"
  rm_service_file "wireproxy.service"
  daemon_reload

  # Remove binaries/configs/logs commonly created by the upstream script
  rm -f /usr/local/bin/xray >/dev/null 2>&1 || true
  rm -rf /usr/local/etc/xray >/dev/null 2>&1 || true
  rm -rf /var/log/xray >/dev/null 2>&1 || true

  rm -f /usr/local/bin/wireproxy >/dev/null 2>&1 || true
  rm -f /etc/wireproxy.conf >/dev/null 2>&1 || true

  # Remove sysctl snippets created by our wrapper (if present)
  rm -f /etc/sysctl.d/99-xray-zivpn-forward.conf >/dev/null 2>&1 || true
  rm -f /etc/sysctl.d/99-xray-zivpn-rpfilter.conf >/dev/null 2>&1 || true
  sysctl --system >/dev/null 2>&1 || true

  if [[ "$PURGE_PACKAGES" == "1" ]]; then
    warn "PURGE_PACKAGES=1: attempting package purge (use carefully)…"
    export DEBIAN_FRONTEND=noninteractive
    # Keep netfilter-persistent/iptables-persistent unless you know you don't need them
    apt-get purge -y nginx nginx-common fail2ban vnstat speedtest socat >/dev/null 2>&1 || true
    apt-get autoremove -y >/dev/null 2>&1 || true
  fi

  ok "Xray stack removal completed (best-effort)."
}

run_upstream_zivpn_uninstall() {
  local tmp="/tmp/zivpn_uninstall.$$.$RANDOM.sh"
  info "Downloading ZiVPN upstream uninstaller…"
  curl -fsSL "$ZIVPN_UNINSTALL_URL" -o "$tmp" || { err "Failed to download $ZIVPN_UNINSTALL_URL"; return 1; }
  chmod +x "$tmp"
  info "Running ZiVPN upstream uninstaller…"
  bash "$tmp" || true
  rm -f "$tmp" || true
}

uninstall_zivpn() {
  info "Uninstalling ZiVPN (udp-zivpn)…"

  # Run official upstream remover first (stops services & deletes files)
  run_upstream_zivpn_uninstall || true

  # Extra cleanup: remove typical DNAT/ACCEPT rules if they exist
  info "Cleaning up iptables rules (DNAT/ACCEPT) for UDP ${ZIVPN_UDP_RANGE} -> :${ZIVPN_UDP_INTERNAL_PORT}…"
  iptables_delete_matching "nat" "PREROUTING" "udp.*--dport[[:space:]]+${ZIVPN_UDP_RANGE}.*DNAT.*:${ZIVPN_UDP_INTERNAL_PORT}"
  iptables_delete_matching "filter" "INPUT" "udp.*--dport[[:space:]]+${ZIVPN_UDP_INTERNAL_PORT}.*ACCEPT"
  iptables_delete_matching "filter" "INPUT" "udp.*--dport[[:space:]]+${ZIVPN_UDP_RANGE}.*ACCEPT"
  save_netfilter

  ok "ZiVPN removal completed (best-effort)."
}

menu() {
  echo
  echo "============================================"
  echo "  1clickxray x udp-zivpn - Uninstaller"
  echo "============================================"
  echo "1) Uninstall Xray stack only"
  echo "2) Uninstall ZiVPN only"
  echo "3) Uninstall BOTH"
  echo "0) Exit"
  echo
  read -r -p "Select: " choice || true
  case "${choice:-}" in
    1)
      confirm "Uninstall Xray stack only?" && uninstall_xray_stack
      ;;
    2)
      confirm "Uninstall ZiVPN only?" && uninstall_zivpn
      ;;
    3)
      confirm "Uninstall BOTH Xray stack + ZiVPN?" && { uninstall_xray_stack; uninstall_zivpn; }
      ;;
    0) exit 0 ;;
    *) warn "Invalid selection." ;;
  esac

  if [[ "$REMOVE_UFW_RULES" == "1" ]]; then
    confirm "REMOVE_UFW_RULES=1 set. Remove common UFW rules now?" && remove_common_ufw_rules
  else
    echo
    warn "UFW rules were NOT removed by default."
    echo "    To attempt removal, rerun with: REMOVE_UFW_RULES=1 bash uninstall.sh"
  fi
}

main() {
  require_root
  while true; do
    menu
  done
}

main "$@"
