# 1clickxray-x-zivpn (Debian 11)

Wrapper installer untuk menjalankan **dua script di 1 VPS**:

- **1clickxray** (`install2.sh`) → stack Xray (umumnya TCP **80/443**)
- **udp-zivpn** (`zi.sh`) → redirect UDP **6000–19999 → 5667** (default)

> Repo ini **download & mengeksekusi script upstream** dari GitHub. Selalu review upstream script sebelum eksekusi dan gunakan dengan risiko sendiri.

---

## Install cepat (Debian 11)

```bash
sudo -i
git clone https://github.com/AhollL/1clickxray-x-zivpn.git
cd 1clickxray-x-zivpn
bash install.sh
```

### Yang dilakukan `install.sh`
- Install prerequisites: `wget`, `curl`, `ufw`, `iptables-persistent`, `netfilter-persistent`, dll.
- Aktifkan **IP forwarding**
- Set UFW:
  - SSH (auto-detect dari `sshd_config`, fallback 22)
  - TCP 80 & 443
  - UDP 5667
  - UDP 6000:19999
- Jalankan installer upstream (1clickxray lalu udp-zivpn)
- Save iptables rules via `netfilter-persistent`

---

## Update (re-run installer upstream)
```bash
sudo bash update.sh
```

---

## Health check
```bash
sudo bash healthcheck.sh
```

---

## Uninstall

Jalankan menu uninstaller:

```bash
sudo bash uninstall.sh
```

Pilihan:
1) Uninstall **Xray stack** saja  
2) Uninstall **ZiVPN** saja  
3) Uninstall **keduanya**

### Opsi tambahan (env flags)
Secara default, uninstaller **tidak menghapus rules UFW** (biar nggak bikin lockout) dan **tidak purge paket** (nginx/fail2ban/vnstat) supaya tidak merusak service lain.

Kalau kamu mau coba hapus rules UFW yang “umum dipakai”:

```bash
REMOVE_UFW_RULES=1 sudo bash uninstall.sh
```

Kalau kamu benar-benar ingin purge beberapa paket umum (hati-hati, bisa ngaruh ke service lain):

```bash
PURGE_PACKAGES=1 sudo bash uninstall.sh
```

---

## Catatan penting

### 1) Konflik UDP range
`udp-zivpn` biasanya melakukan redirect **UDP 6000:19999 → 5667**.  
Kalau kamu mau menjalankan UDP lain (Hysteria/QUIC/game), **hindari** range UDP itu.

### 2) Hindari lockout SSH
Script ini meng-allow SSH dulu sebelum enable UFW, tapi tetap disarankan pakai `screen`/`tmux`.

---

## Konfigurasi (opsional)
Kamu bisa override variabel:

```bash
XRAY_INSTALL_URL="https://raw.githubusercontent.com/dugong-lewat/1clickxray/main/install2.sh" \
ZIVPN_INSTALL_URL="https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/zi.sh" \
RELAX_RPFILTER=1 \
bash install.sh
```

---

## License
MIT
