#!/bin/bash
# Script untuk menampilkan QR Code Wireguard peer di terminal

CONTAINER_NAME="wireguard-adguard"
DATA_DIR="./data/wireguard/clients"

PEER_NAME="$1"

if [ -z "$PEER_NAME" ]; then
    echo "=================================================="
    echo "          WireGuard Client QR Code Viewer         "
    echo "=================================================="
    echo "Daftar client yang tersedia:"
    if [ -d "$DATA_DIR" ]; then
        ls -1 "$DATA_DIR"/*.conf 2>/dev/null | sed -e 's/.*\///' -e 's/\.conf$//' | while read -r name; do
            echo " - $name"
        done
    else
        echo " (Belum ada konfigurasi client di $DATA_DIR)"
    fi
    echo ""
    read -rp "Masukkan nama client yang ingin dilihat QR code-nya: " PEER_NAME
fi

if [ -z "$PEER_NAME" ]; then
    echo "[!] Nama client tidak boleh kosong."
    exit 1
fi

CONF_FILE="${DATA_DIR}/${PEER_NAME}.conf"

if [ ! -f "$CONF_FILE" ]; then
    echo "[!] File konfigurasi tidak ditemukan: ${CONF_FILE}"
    echo "Pastikan kontainer sudah berjalan minimal sekali."
    exit 1
fi

echo ""
echo "=================================================="
echo " QR Code untuk Peer: ${PEER_NAME}"
echo " Scan menggunakan aplikasi WireGuard (HP/Tablet/PC)"
echo "=================================================="
echo ""

# Periksa apakah qrencode terinstall di host, jika tidak jalankan via docker exec
if command -v qrencode >/dev/null 2>&1; then
    qrencode -t ansiutf8 < "$CONF_FILE"
elif docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    docker exec -i "$CONTAINER_NAME" qrencode -t ansiutf8 < "$CONF_FILE"
else
    cat "$CONF_FILE"
    echo ""
    echo "[i] Tip: Install 'qrencode' di komputer Anda untuk melihat QR Code langsung,"
    echo "    atau lihat gambar QR di: ${DATA_DIR}/${PEER_NAME}.png"
fi

echo ""
echo "Isi file konfigurasi (${CONF_FILE}):"
cat "$CONF_FILE"
echo ""
