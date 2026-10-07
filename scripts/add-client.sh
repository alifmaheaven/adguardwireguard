#!/bin/bash
# Script untuk menambahkan client/peer baru tanpa perlu restart kontainer
set -e

CONTAINER_NAME="wireguard-adguard"
NEW_PEER="$1"

if [ -z "$NEW_PEER" ]; then
    read -rp "Masukkan nama client baru (misal: macbook, tablet, ayah): " NEW_PEER
fi

if [ -z "$NEW_PEER" ]; then
    echo "[!] Nama client tidak boleh kosong."
    exit 1
fi

# Sanitize nama peer
NEW_PEER=$(echo "$NEW_PEER" | tr -d '[:space:]')

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "[!] Kontainer '${CONTAINER_NAME}' tidak sedang berjalan."
    echo "    Silakan jalankan kontainer terlebih dahulu dengan: docker compose up -d"
    exit 1
fi

echo "[*] Menambahkan client '${NEW_PEER}' ke dalam kontainer..."

docker exec -i "${CONTAINER_NAME}" bash <<EOF
set -e
SUBNET_BASE=\$(grep "Address" /etc/wireguard/wg0.conf | head -n1 | awk -F'=' '{print \$2}' | tr -d '[:space:]' | cut -d'/' -f1 | awk -F'.' '{print \$1"."\$2"."\$3}')
SERVER_PUBKEY=\$(cat /data/wireguard/server/server_public.key)
SERVER_ENDPOINT=\$(grep "Endpoint" /data/wireguard/clients/*/*.conf 2>/dev/null | head -n1 | awk -F'=' '{print \$2}' | tr -d '[:space:]')

PEER_DIR="/data/wireguard/clients/${NEW_PEER}"
mkdir -p "\${PEER_DIR}"

CLIENT_KEY_FILE="\${PEER_DIR}/${NEW_PEER}.key"
CLIENT_PUB_FILE="\${PEER_DIR}/${NEW_PEER}.pub"
CLIENT_CONF_FILE="\${PEER_DIR}/${NEW_PEER}.conf"
CLIENT_PNG_FILE="\${PEER_DIR}/${NEW_PEER}.png"

if [ -f "\${CLIENT_CONF_FILE}" ]; then
    echo "[!] Client '${NEW_PEER}' sudah ada!"
    exit 0
fi

# Cari IP berikutnya yang belum dipakai
USED_IPS=\$(grep -h "AllowedIPs" /etc/wireguard/wg0.conf | awk -F'=' '{print \$2}' | tr -d '[:space:]' | cut -d'/' -f1 | awk -F'.' '{print \$4}')
NEXT_OCTET=2
while echo "\${USED_IPS}" | grep -q "^\${NEXT_OCTET}\$"; do
    NEXT_OCTET=\$((NEXT_OCTET + 1))
done

NEW_IP="\${SUBNET_BASE}.\${NEXT_OCTET}"

# Generate key
wg genkey | tee "\${CLIENT_KEY_FILE}" | wg pubkey > "\${CLIENT_PUB_FILE}"
chmod 600 "\${CLIENT_KEY_FILE}"

CLIENT_PRIVKEY=\$(cat "\${CLIENT_KEY_FILE}")
CLIENT_PUBKEY=\$(cat "\${CLIENT_PUB_FILE}")

# Buat client config
cat <<CLIENT_CONF > "\${CLIENT_CONF_FILE}"
[Interface]
PrivateKey = \${CLIENT_PRIVKEY}
Address = \${NEW_IP}/24
DNS = \${SUBNET_BASE}.1

[Peer]
PublicKey = \${SERVER_PUBKEY}
Endpoint = \${SERVER_ENDPOINT}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
CLIENT_CONF

# QR Code
qrencode -t png -o "\${CLIENT_PNG_FILE}" < "\${CLIENT_CONF_FILE}" 2>/dev/null || true
cp -f "\${CLIENT_CONF_FILE}" "/data/wireguard/clients/${NEW_PEER}.conf"
cp -f "\${CLIENT_PNG_FILE}" "/data/wireguard/clients/${NEW_PEER}.png" 2>/dev/null || true

# Daftarkan langsung ke WireGuard interface (tanpa restart!)
wg set wg0 peer "\${CLIENT_PUBKEY}" allowed-ips "\${NEW_IP}/32"

# Simpan ke wg0.conf agar permanen saat restart
cat <<SERVER_PEER >> /etc/wireguard/wg0.conf

[Peer]
# Name: ${NEW_PEER}
PublicKey = \${CLIENT_PUBKEY}
AllowedIPs = \${NEW_IP}/32
SERVER_PEER

echo "[+] Client '${NEW_PEER}' berhasil ditambahkan dengan IP \${NEW_IP}!"
echo ""
echo "=================================================="
echo " QR Code untuk Peer: ${NEW_PEER}"
echo "=================================================="
qrencode -t ansiutf8 < "\${CLIENT_CONF_FILE}"
echo ""
echo "Config file path: /data/wireguard/clients/${NEW_PEER}.conf"
EOF

echo "[+] Selesai! File konfigurasi tersimpan di ./data/wireguard/clients/${NEW_PEER}.conf"
