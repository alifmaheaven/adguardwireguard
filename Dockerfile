FROM alpine:latest

LABEL maintainer="Antigravity"
LABEL description="All-in-One WireGuard VPN + AdGuard Home Ad-Blocking DNS container"

ARG TARGETARCH

# Install WireGuard, networking tools, AdGuard Home dependencies, and utilities
RUN apk add --no-cache \
    bash \
    curl \
    tar \
    ca-certificates \
    tzdata \
    wireguard-tools \
    wireguard-go \
    iptables \
    ip6tables \
    iproute2 \
    openresolv \
    libqrencode-tools \
    apache2-utils

# Download and install official AdGuard Home binary based on architecture
RUN set -eux; \
    if [ -z "${TARGETARCH}" ]; then \
        ARCH="$(uname -m)"; \
        case "${ARCH}" in \
            x86_64) AGH_ARCH="amd64" ;; \
            aarch64|arm64) AGH_ARCH="arm64" ;; \
            armv7l) AGH_ARCH="armv7" ;; \
            *) echo "Unsupported architecture: ${ARCH}" && exit 1 ;; \
        esac; \
    else \
        case "${TARGETARCH}" in \
            amd64) AGH_ARCH="amd64" ;; \
            arm64) AGH_ARCH="arm64" ;; \
            arm/v7|armv7) AGH_ARCH="armv7" ;; \
            *) echo "Unsupported TARGETARCH: ${TARGETARCH}" && exit 1 ;; \
        esac; \
    fi; \
    echo "Downloading AdGuard Home for ${AGH_ARCH}..."; \
    mkdir -p /opt/adguardhome; \
    curl -sSL "https://github.com/AdguardTeam/AdGuardHome/releases/latest/download/AdGuardHome_linux_${AGH_ARCH}.tar.gz" \
        | tar -xz -C /tmp; \
    mv /tmp/AdGuardHome/AdGuardHome /opt/adguardhome/AdGuardHome; \
    rm -rf /tmp/AdGuardHome; \
    chmod +x /opt/adguardhome/AdGuardHome

# Prepare directories
RUN mkdir -p /data/wireguard/server \
             /data/wireguard/clients \
             /data/adguard/conf \
             /data/adguard/work \
             /etc/wireguard

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Environment defaults
ENV SERVERURL="auto" \
    SERVERPORT="51820" \
    PEERS="1" \
    INTERNAL_SUBNET="10.13.13.0/24" \
    ALLOWEDIPS="0.0.0.0/0, ::/0" \
    WEB_PORT="3000" \
    ADMIN_USER="admin" \
    FORCE_DNS_REDIRECT="true" \
    TZ="Asia/Jakarta"

# Wireguard UDP, AdGuard Web UI, AdGuard DNS (UDP/TCP)
EXPOSE 51820/udp 3000/tcp 53/tcp 53/udp

VOLUME ["/data"]

ENTRYPOINT ["/entrypoint.sh"]
