#!/usr/bin/env bash
# Updates by re-running upstream installers (may overwrite components)
set -Eeuo pipefail

XRAY_INSTALL_URL="${XRAY_INSTALL_URL:-https://raw.githubusercontent.com/dugong-lewat/1clickxray/main/install2.sh}"
ZIVPN_INSTALL_URL="${ZIVPN_INSTALL_URL:-https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/zi.sh}"

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "[x] Run as root: sudo bash $0" >&2
  exit 1
fi

tmp1="/tmp/1clickxray-install2.$$.sh"
tmp2="/tmp/udp-zivpn-zi.$$.sh"

echo "[i] Updating 1clickxray from: $XRAY_INSTALL_URL"
curl -fsSL "$XRAY_INSTALL_URL" -o "$tmp1"
chmod +x "$tmp1"
bash "$tmp1"
rm -f "$tmp1"

echo "[i] Updating udp-zivpn from: $ZIVPN_INSTALL_URL"
curl -fsSL "$ZIVPN_INSTALL_URL" -o "$tmp2"
chmod +x "$tmp2"
bash "$tmp2"
rm -f "$tmp2"

if command -v netfilter-persistent >/dev/null 2>&1; then
  netfilter-persistent save || true
  systemctl enable netfilter-persistent >/dev/null 2>&1 || true
fi

echo "[+] Update finished."
