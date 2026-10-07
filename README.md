# 🛡️ WireGuard VPN + AdGuard Home (All-in-One Docker Container)

Solusi **1 Docker Image / Container** yang menggabungkan **WireGuard VPN** dan **AdGuard Home (DNS Ad-Blocker)** siap pakai (*out-of-the-box*). 

Begitu Anda terhubung ke VPN WireGuard, seluruh lalu lintas internet dan DNS dari perangkat Anda otomatis disaring oleh AdGuard Home: **iklan, tracker, phising, dan malware otomatis diblokir!**

---

## 🌟 Fitur Utama

- **1 Container, Zero Ribet:** Tidak perlu membuat 2 container terpisah atau setup docker network yang rumit. Cukup 1 container langsung jalan.
- **Auto Ad-Blocking Aktif Langsung:** AdGuard Home sudah dikonfigurasi awal dengan filter AdGuard DNS Filter & AdAway. Tidak perlu melewati setup wizard yang panjang.
- **DNS Hijack Prevention:** Semua query DNS (port 53) di dalam tunnel VPN dipaksa dialihkan ke AdGuard Home menggunakan iptables redirect. Aplikasi atau perangkat yang mencoba bypass DNS (seperti hardcoded DNS 8.8.8.8) tetap akan disaring.
- **Auto Generate Klien & QR Code:** Otomatis membuat profil client WireGuard lengkap dengan file `.conf`, gambar `.png`, dan tampilan QR code ANSI langsung di layar terminal / log.
- **Multi-Arsitektur:** Mendukung `amd64` (Intel/AMD x86_64 VPS) dan `arm64` (Raspberry Pi, Apple Silicon, AWS Graviton).
- **Dual WireGuard Support:** Menggunakan performa tinggi in-kernel WireGuard jika didukung host, serta fallback otomatis ke `wireguard-go` jika dijalankan di environment tanpa modul kernel.
- **Web Dashboard AdGuard:** Tetap bisa mengakses Web UI AdGuard Home di port `3000` untuk memantau log statistik DNS dan menambah blocklist kustom.

---

## 🏗️ Cara Kerja Sistem

```text
[ Perangkat Klien (HP / Laptop) ]
               │
               ▼  (Terkoneksi via WireGuard Tunnel: 10.13.13.X)
[ Container: WireGuard Server (10.13.13.1) ]
         │                        │
         │ (DNS Query Port 53)    │ (Traffic Web/App Lainnya)
         ▼                        ▼
[ AdGuard Home (Port 53) ]   [ iptables NAT Masquerade ]
   ├─ Domain Iklan? ──> BLOCKED!          │
   └─ Domain Aman?  ──> Upstream DNS      ▼
                                    [ INTERNET ]
```

---

## 🚀 Panduan Memulai Cepat (Quick Start)

### 1. Prasyarat
Pastikan server/komputer Anda telah terinstall **Docker** dan **Docker Compose**.

### 2. Konfigurasi Lingkungan (`.env`)
Salin file template `.env.example` ke `.env`:

```bash
cp .env.example .env
```

Buka file `.env` dan sesuaikan nilainya jika diperlukan:
- `SERVERURL`: Isi dengan IP Publik VPS Anda (misal `103.150.90.10`) atau domain DDNS Anda. Jika dibiarkan `auto`, kontainer akan mendeteksi IP publik secara otomatis.
- `PEERS`: Daftar nama client yang ingin dibuat, dipisah koma (misal `phone,laptop,pc`) atau berupa angka (misal `2`).
- `ADMIN_PASSWORD`: Password login untuk Dashboard AdGuard Home (default: `admin123`).
- `WEB_PORT_HOST`: Port dashboard di host (default: `3000`).

### 3. Jalankan Kontainer
Cukup jalankan satu perintah berikut:

```bash
docker compose up -d
```

---

## 📱 Cara Konek ke VPN

### Melalui HP / Tablet (Android & iOS):
1. Install aplikasi resmi **WireGuard** dari Google Play Store atau Apple App Store.
2. Tampilkan QR Code di terminal dengan menjalankan:
   ```bash
   ./scripts/show-qr.sh phone
   ```
   *(atau ganti `phone` dengan nama client Anda, misal `client1`)*.
3. Di aplikasi WireGuard HP, pilih tombol **+** -> **Scan from QR code**, lalu arahkan kamera ke terminal Anda.
4. Aktifkan VPN, dan iklan di HP Anda otomatis terblokir!

> **Tips:** File gambar QR Code juga tersimpan rapi di folder `./data/wireguard/clients/<nama>.png`.

### Melalui Laptop / PC (Windows / macOS / Linux):
1. Install aplikasi **WireGuard**.
2. Ambil file konfigurasi yang sudah di-generate di folder:
   `./data/wireguard/clients/<nama>.conf`
3. Import file `.conf` tersebut ke dalam aplikasi WireGuard dan klik **Activate**.

---

## 📊 Mengakses Dashboard AdGuard Home

Buka browser dan akses:
- **URL:** `http://<IP-SERVER-ANDA>:3000`
- **Username:** `admin` *(atau sesuai `ADMIN_USER` di `.env`)*
- **Password:** `admin123` *(atau sesuai `ADMIN_PASSWORD` di `.env`)*

Di dalam dashboard ini, Anda dapat:
- Melihat grafik query DNS yang diblokir secara realtime.
- Melihat perangkat/klien mana saja yang sedang melakukan query.
- Menambahkan filter/blocklist tambahan (misal filter khusus Indonesia, judi online, pornografi, dll).

---

## ➕ Menambahkan Client Baru (Tanpa Restart)

Ingin menambahkan perangkat baru tanpa mengganggu koneksi VPN perangkat yang sedang aktif? Gunakan script helper:

```bash
./scripts/add-client.sh tablet
```

Script akan:
1. Membuat kunci enkripsi baru untuk `tablet`.
2. Mengalokasikan IP baru secara otomatis.
3. Menambahkan peer langsung ke WireGuard tanpa memutus koneksi perangkat lain.
4. Menampilkan QR code di layar dan menyimpan `./data/wireguard/clients/tablet.conf`.

---

## 📁 Struktur Direktori Proyek

```text
.
├── Dockerfile              # Definisi multi-arch build container
├── docker-compose.yml      # Konfigurasi orkestrasi Docker
├── entrypoint.sh           # Script otomatisasi WireGuard, IP forward, AdGuard Home
├── .env.example            # Template variabel konfigurasi
├── .env                    # File konfigurasi aktif Anda
├── scripts/
│   ├── show-qr.sh          # Script pembaca QR Code client di terminal
│   └── add-client.sh       # Script penambah client baru secara live
└── data/                   # (Dibuat otomatis) Data persisten
    ├── wireguard/
    │   ├── server/         # Kunci privat & publik server
    │   └── clients/        # File .conf dan QR Code (.png) tiap client
    └── adguard/
        ├── conf/           # AdGuardHome.yaml
        └── work/           # Database statistik, cache DNS, dan filter list
```

---

## ⚙️ Variabel Konfigurasi Lengkap

| Variabel | Default | Keterangan |
| :--- | :--- | :--- |
| `SERVERURL` | `auto` | IP publik atau domain VPS Anda. `auto` mendeteksi otomatis. |
| `SERVERPORT` | `51820` | Port UDP yang digunakan oleh WireGuard. |
| `PEERS` | `phone,laptop` | Jumlah atau daftar nama client yang dibuat saat pertama kali jalan. |
| `INTERNAL_SUBNET`| `10.13.13.0/24` | Rentang IP subnet internal VPN (Server = `.1`, Klien = `.2`, `.3`, dst). |
| `ALLOWEDIPS` | `0.0.0.0/0, ::/0` | Rute IP klien (`0.0.0.0/0` untuk full tunnel VPN). |
| `WEB_PORT` | `3000` | Port AdGuard Home web dashboard di dalam kontainer. |
| `WEB_PORT_HOST` | `3000` | Port AdGuard Home web dashboard yang dibuka di host. |
| `ADMIN_USER` | `admin` | Username login dashboard AdGuard Home. |
| `ADMIN_PASSWORD` | `admin123` | Password login dashboard AdGuard Home. |
| `FORCE_DNS_REDIRECT`| `true` | Paksa alihkan semua query port 53 di VPN ke AdGuard Home. |
| `TZ` | `Asia/Jakarta` | Zona waktu sistem. |

---

## ❓ FAQ & Troubleshooting

### 1. Apakah data dan akun AdGuard Home hilang jika kontainer di-restart?
**Tidak.** Semua konfigurasi WireGuard dan AdGuard Home disimpan di folder `./data` pada host Anda. Saat kontainer di-restart atau di-update, semua statistik, setting, dan user tetap aman.

### 2. Bagaimana jika port 3000 sudah dipakai aplikasi lain di VPS?
Cukup ubah `WEB_PORT_HOST` di file `.env`, misalnya:
```env
WEB_PORT_HOST=3001
```
Lalu jalankan `docker compose up -d`. Anda bisa mengakses AdGuard Home di port `3001`.

### 3. Di VPS Linux, apakah perlu membuka firewall?
Ya, pastikan port WireGuard (UDP) dan Dashboard (TCP) diizinkan di firewall VPS (misal UFW atau security group cloud):
```bash
sudo ufw allow 51820/udp
sudo ufw allow 3000/tcp
```
