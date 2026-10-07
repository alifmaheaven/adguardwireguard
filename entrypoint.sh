#!/bin/bash
set -e

echo "================================================================="
echo "   WireGuard + AdGuard Home All-in-One Container Initializing    "
echo "================================================================="

# Environment variable defaults
SERVERURL="${SERVERURL:-auto}"
SERVERPORT="${SERVERPORT:-51820}"
PEERS="${PEERS:-1}"
INTERNAL_SUBNET="${INTERNAL_SUBNET:-10.13.13.0/24}"
ALLOWEDIPS="${ALLOWEDIPS:-0.0.0.0/0, ::/0}"
WEB_PORT="${WEB_PORT:-3000}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin123}"
FORCE_DNS_REDIRECT="${FORCE_DNS_REDIRECT:-true}"
TZ="${TZ:-Asia/Jakarta}"

# 1. Ensure /dev/net/tun exists (for userspace WireGuard fallback if needed)
if [ ! -c /dev/net/tun ]; then
    echo "[*] Creating /dev/net/tun..."
    mkdir -p /dev/net
    mknod /dev/net/tun c 10 200 2>/dev/null || true
    chmod 600 /dev/net/tun 2>/dev/null || true
fi

# 2. Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null 2>&1 || true

# 3. Detect outbound network interface
DEFAULT_IFACE=$(ip route show default 2>/dev/null | awk '{print $5}' | head -n1)
DEFAULT_IFACE=${DEFAULT_IFACE:-eth0}
echo "[*] Outbound network interface detected: ${DEFAULT_IFACE}"

# 4. Resolve Server Public IP/URL
if [ -z "${SERVERURL}" ] || [ "${SERVERURL}" = "auto" ]; then
    echo "[*] Detecting server public IP address..."
    DETECTED_IP=$(curl -s4 --max-time 5 https://ifconfig.co 2>/dev/null || \
                  curl -s4 --max-time 5 https://api.ipify.org 2>/dev/null || \
                  ip route get 1.1.1.1 2>/dev/null | awk '{print $7}' | head -n1)
    if [ -n "${DETECTED_IP}" ]; then
        SERVERURL="${DETECTED_IP}"
        echo "[+] Public IP detected: ${SERVERURL}"
    else
        SERVERURL="127.0.0.1"
        echo "[!] Warning: Could not detect public IP. Falling back to 127.0.0.1"
    fi
else
    echo "[*] Using configured SERVERURL: ${SERVERURL}"
fi

# 5. Network Subnet Parsing
# Default INTERNAL_SUBNET="10.13.13.0/24"
SUBNET_BASE=$(echo "${INTERNAL_SUBNET}" | cut -d'/' -f1 | awk -F'.' '{print $1"."$2"."$3}')
SUBNET_CIDR=$(echo "${INTERNAL_SUBNET}" | cut -d'/' -f2)
SERVER_IP="${SUBNET_BASE}.1"
WG_DNS_SERVER="${SERVER_IP}"

mkdir -p /data/wireguard/server /data/wireguard/clients /data/adguard/conf /data/adguard/work /etc/wireguard

# 6. WireGuard Server Key Generation
if [ ! -f /data/wireguard/server/server_private.key ]; then
    echo "[*] Generating WireGuard server keys..."
    wg genkey | tee /data/wireguard/server/server_private.key | wg pubkey > /data/wireguard/server/server_public.key
    chmod 600 /data/wireguard/server/server_private.key
fi
SERVER_PRIVKEY=$(cat /data/wireguard/server/server_private.key)
SERVER_PUBKEY=$(cat /data/wireguard/server/server_public.key)

# 7. Parse Peer List
PEER_LIST=()
if [[ "${PEERS}" =~ ^[0-9]+$ ]]; then
    for ((i=1; i<=PEERS; i++)); do
        PEER_LIST+=("client${i}")
    done
else
    IFS=',' read -ra ADDR <<< "${PEERS}"
    for p in "${ADDR[@]}"; do
        clean_p=$(echo "$p" | tr -d '[:space:]')
        if [ -n "$clean_p" ]; then
            PEER_LIST+=("$clean_p")
        fi
    done
fi

if [ ${#PEER_LIST[@]} -eq 0 ]; then
    PEER_LIST=("client1")
fi

echo "[*] Configured peers: ${PEER_LIST[*]}"

# 8. Setup Clients & Allocate IPs
# Map existing IPs or allocate sequentially starting from .2
CLIENT_INDEX=2
PEER_CONFIGS=""

for peer in "${PEER_LIST[@]}"; do
    PEER_DIR="/data/wireguard/clients/${peer}"
    mkdir -p "${PEER_DIR}"
    
    CLIENT_KEY_FILE="${PEER_DIR}/${peer}.key"
    CLIENT_PUB_FILE="${PEER_DIR}/${peer}.pub"
    CLIENT_CONF_FILE="${PEER_DIR}/${peer}.conf"
    CLIENT_PNG_FILE="${PEER_DIR}/${peer}.png"
    
    if [ ! -f "${CLIENT_KEY_FILE}" ]; then
        echo "[*] Generating keys for peer: ${peer}..."
        wg genkey | tee "${CLIENT_KEY_FILE}" | wg pubkey > "${CLIENT_PUB_FILE}"
        chmod 600 "${CLIENT_KEY_FILE}"
    fi
    
    CLIENT_PRIVKEY=$(cat "${CLIENT_KEY_FILE}")
    CLIENT_PUBKEY=$(cat "${CLIENT_PUB_FILE}")
    
    # Check if conf exists and extract IP, otherwise assign sequential IP
    if [ -f "${CLIENT_CONF_FILE}" ]; then
        CLIENT_IP=$(grep -E "^Address" "${CLIENT_CONF_FILE}" | awk -F'=' '{print $2}' | tr -d '[:space:]' | cut -d'/' -f1)
    else
        CLIENT_IP="${SUBNET_BASE}.${CLIENT_INDEX}"
    fi
    
    # Create / Update Client Config
    cat <<EOF > "${CLIENT_CONF_FILE}"
[Interface]
PrivateKey = ${CLIENT_PRIVKEY}
Address = ${CLIENT_IP}/${SUBNET_CIDR}
DNS = ${WG_DNS_SERVER}

[Peer]
PublicKey = ${SERVER_PUBKEY}
Endpoint = ${SERVERURL}:${SERVERPORT}
AllowedIPs = ${ALLOWEDIPS}
PersistentKeepalive = 25
EOF

    # Generate QR Code PNG
    qrencode -t png -o "${CLIENT_PNG_FILE}" < "${CLIENT_CONF_FILE}" 2>/dev/null || true
    
    # Also symlink / copy to /data/wireguard/clients for easy access
    cp -f "${CLIENT_CONF_FILE}" "/data/wireguard/clients/${peer}.conf"
    cp -f "${CLIENT_PNG_FILE}" "/data/wireguard/clients/${peer}.png" 2>/dev/null || true

    # Append peer block to server configuration
    PEER_CONFIGS+="$(cat <<EOF

[Peer]
# Name: ${peer}
PublicKey = ${CLIENT_PUBKEY}
AllowedIPs = ${CLIENT_IP}/32
EOF
)"
    CLIENT_INDEX=$((CLIENT_INDEX + 1))
done

# 9. Build Server wg0.conf
# Build PostUp / PostDown rules:
POST_UP_RULES="iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ${DEFAULT_IFACE} -j MASQUERADE"
POST_DOWN_RULES="iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o ${DEFAULT_IFACE} -j MASQUERADE"

if [ "${FORCE_DNS_REDIRECT}" = "true" ]; then
    # Force redirect all DNS packets arriving on wg0 to AdGuard Home (port 53)
    # This prevents any client device/app from bypassing AdGuard Home with hardcoded DNS!
    POST_UP_RULES="${POST_UP_RULES}; iptables -t nat -A PREROUTING -i wg0 -p udp --dport 53 -j REDIRECT --to-ports 53; iptables -t nat -A PREROUTING -i wg0 -p tcp --dport 53 -j REDIRECT --to-ports 53"
    POST_DOWN_RULES="${POST_DOWN_RULES}; iptables -t nat -D PREROUTING -i wg0 -p udp --dport 53 -j REDIRECT --to-ports 53; iptables -t nat -D PREROUTING -i wg0 -p tcp --dport 53 -j REDIRECT --to-ports 53"
fi

cat <<EOF > /etc/wireguard/wg0.conf
[Interface]
Address = ${SERVER_IP}/${SUBNET_CIDR}
ListenPort = ${SERVERPORT}
PrivateKey = ${SERVER_PRIVKEY}
PostUp = ${POST_UP_RULES}
PostDown = ${POST_DOWN_RULES}
${PEER_CONFIGS}
EOF
chmod 600 /etc/wireguard/wg0.conf

# 10. Configure AdGuard Home if not already configured
AGH_CONF="/data/adguard/conf/AdGuardHome.yaml"
if [ ! -f "${AGH_CONF}" ]; then
    echo "[*] Initializing AdGuard Home configuration with auto ad-blocking..."
    
    # Generate bcrypt password hash
    ADMIN_HASH=$(htpasswd -bnBC 10 "" "${ADMIN_PASSWORD}" | tr -d ':\n')
    
    cat <<EOF > "${AGH_CONF}"
http:
  pprof:
    port: 6060
    enabled: false
  address: 0.0.0.0:${WEB_PORT}
  session_ttl: 30d
users:
  - name: ${ADMIN_USER}
    password: ${ADMIN_HASH}
auth_attempts: 5
block_auth_min: 15
http_proxy: ""
language: ""
theme: auto
dns:
  bind_hosts:
    - 0.0.0.0
  port: 53
  anonymize_client_ip: false
  ratelimit: 0
  refuse_any: true
  upstream_dns:
    - https://dns10.quad9.net/dns-query
    - 1.1.1.1
    - 8.8.8.8
  bootstrap_dns:
    - 9.9.9.10
    - 149.112.112.10
    - 1.1.1.1
    - 8.8.8.8
  fallback_dns: []
  upstream_mode: load_balance
  fastest_timeout: 1s
  allowed_clients: []
  disallowed_clients: []
  cache_enabled: true
  cache_size: 4194304
  cache_ttl_min: 0
  cache_ttl_max: 0
  cache_optimistic: true
  cache_optimistic_answer_ttl: 30s
  cache_optimistic_max_age: 12h
  enable_dnssec: true
  max_goroutines: 300
  handle_ddr: true
  upstream_timeout: 10s
  serve_plain_dns: true
  hostsfile_enabled: true
  pending_requests:
    enabled: true
tls:
  enabled: false
querylog:
  enabled: true
  file_enabled: true
  interval: 90d
  size_memory: 1000
statistics:
  enabled: true
  interval: 1d
filters:
  - enabled: true
    url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt
    name: AdGuard DNS filter
    id: 1
  - enabled: true
    url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_2.txt
    name: AdAway Default Blocklist
    id: 2
whitelist_filters: []
user_rules: []
dhcp:
  enabled: false
filtering:
  blocking_mode: default
  parental_block_host: family-block.dns.adguard.com
  safebrowsing_block_host: standard-block.dns.adguard.com
  rewrites: []
  cache_time: 30
  filters_update_interval: 24
  blocked_response_ttl: 10
  filtering_enabled: true
  rewrites_enabled: true
  parental_enabled: false
  safebrowsing_enabled: false
  protection_enabled: true
clients:
  runtime_sources:
    whois: true
    arp: true
    rdns: true
    dhcp: true
    hosts: true
  persistent: []
log:
  enabled: true
  file: ""
  max_backups: 0
  max_size: 100
  max_age: 3
  compress: false
  local_time: false
  verbose: false
schema_version: 34
EOF
    echo "[+] AdGuard Home pre-configured with default ad-blocking lists!"
else
    echo "[*] Existing AdGuard Home configuration found. Preserving user settings."
fi

# 11. Start WireGuard
echo "[*] Bringing up WireGuard interface (wg0)..."
wg-quick up wg0

# 12. Display Status & QR Codes
echo ""
echo "================================================================="
echo "   WIREGUARD + ADGUARD HOME ALL-IN-ONE IS READY!                 "
echo "================================================================="
echo " -> WireGuard Endpoint : ${SERVERURL}:${SERVERPORT}"
echo " -> AdGuard Web UI     : http://${SERVERURL}:${WEB_PORT}"
echo " -> AdGuard Admin User : ${ADMIN_USER}"
echo " -> AdGuard Admin Pass : ${ADMIN_PASSWORD}"
echo " -> DNS Server         : ${WG_DNS_SERVER} (AdGuard Home)"
echo " -> Configs Directory  : /data/wireguard/clients/"
echo "================================================================="
echo ""

for peer in "${PEER_LIST[@]}"; do
    CONF_FILE="/data/wireguard/clients/${peer}/${peer}.conf"
    if [ -f "${CONF_FILE}" ]; then
        echo "-----------------------------------------------------------------"
        echo " QR CODE FOR PEER: ${peer}"
        echo " Scan this in your WireGuard app (iOS / Android / Desktop):"
        echo "-----------------------------------------------------------------"
        qrencode -t ansiutf8 < "${CONF_FILE}"
        echo ""
        echo "Config file path: /data/wireguard/clients/${peer}.conf"
        echo "QR image path   : /data/wireguard/clients/${peer}.png"
        echo "-----------------------------------------------------------------"
    fi
done

# 13. Graceful shutdown handler
cleanup() {
    echo ""
    echo "[*] Caught stop signal. Shutting down gracefully..."
    if [ -n "$AGH_PID" ]; then
        kill -TERM "$AGH_PID" 2>/dev/null || true
        wait "$AGH_PID" 2>/dev/null || true
    fi
    echo "[*] Stopping WireGuard interface..."
    wg-quick down wg0 2>/dev/null || true
    echo "[+] Done. Container stopped."
    exit 0
}
trap cleanup SIGTERM SIGINT

# 14. Start AdGuard Home in foreground
echo "[*] Starting AdGuard Home daemon..."
/opt/adguardhome/AdGuardHome -c /data/adguard/conf/AdGuardHome.yaml -w /data/adguard/work &
AGH_PID=$!

# Wait on AdGuard Home process
wait $AGH_PID
