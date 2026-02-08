#!/usr/bin/env bash
set -Eeuo pipefail

ZIVPN_UDP_INTERNAL_PORT="${ZIVPN_UDP_INTERNAL_PORT:-5667}"

echo "== OS =="
cat /etc/os-release | sed -n '1,6p' || true
echo

echo "== UFW =="
if command -v ufw >/dev/null 2>&1; then
  ufw status verbose || true
else
  echo "ufw not installed"
fi
echo

echo "== Listening ports (80/443/5667) =="
ss -tulpn | egrep ":(80|443|${ZIVPN_UDP_INTERNAL_PORT})\b" || true
echo

echo "== NAT PREROUTING (first 120 lines) =="
iptables -t nat -S | sed -n '1,120p' || true
echo

echo "== sysctl forwarding flags =="
sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding 2>/dev/null || true
