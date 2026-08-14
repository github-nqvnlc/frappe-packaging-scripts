# 🚀 Frappe Packaging & Automated Deployment Scripts

Bộ công cụ tự động hóa quá trình đóng gói **Frappe / ERPNext Custom Apps** và triển khai hệ thống lên môi trường VPS Ubuntu/Debian bằng **Docker Compose** với **2 Luồng Triển Khai Tên Miền (Routing Workflows)** linh hoạt: **Direct Public Domain (Traefik Auto SSL)** và **Cloudflare Tunnel (Zero Trust - No Open Ports)**.

---

## 🌟 2 Luồng Workflow Triển Khai Tên Miền (Domain Workflows)

Dự án hỗ trợ 2 luồng triển khai tên miền độc lập, dễ dàng chuyển đổi thông qua cấu hình trong file `.env`:

```text
 ┌─────────────────────────────────────────────────────────────────────────────────┐
 │                                CHỌN LUỒNG TRIỂN KHAI                            │
 └────────────────────────┬────────────────────────────────┬───────────────────────┘
                          │                                │
                          ▼                                ▼
       ┌──────────────────────────────────────┐ ┌──────────────────────────────────────┐
       │   LUỒNG 1: DIRECT PUBLIC DOMAIN      │ │     LUỒNG 2: CLOUDFLARE TUNNEL       │
       │ (Cần mở Port 80/443 & IP Public)     │ │ (Không cần mở Port & Ẩn IP VPS)      │
       └──────────────────┬───────────────────┘ └──────────────────┬───────────────────┘
                          │                                        │
                          ▼                                        ▼
             [ Traefik HTTP/HTTPS Proxy ]              [ Cloudflare Tunnel Container ]
                          │                                        │
                          ▼                                        ▼
             [ Auto Let's Encrypt SSL ]                [ Cloudflare Edge SSL & WAF ]
```

### 🔹 Luồng 1: Direct Public Domain (Dùng Traefik SSL Trực Tiếp)
- **Cơ chế**: Domain (`SITE_DOMAIN`) trỏ thẳng DNS A Record về IP Public của VPS.
- **Cổng giao tiếp**: Yêu cầu mở cổng **80** (HTTP) và **443** (HTTPS) ra Internet.
- **Quản lý SSL**: Traefik tự động gửi yêu cầu xác thực ACME HTTP-01 và cấp/gia hạn chứng chỉ SSL Let's Encrypt.
- **Phù hợp cho**: VPS trên Cloud (AWS, DigitalOcean, Linode, Hetzner...) có IP Tĩnh Public và mở cổng đầy đủ.

### 🔹 Luồng 2: Cloudflare Tunnel (Dùng Cloudflare Zero Trust)
- **Cơ chế**: Daemon `cloudflared` tạo kết nối mã hóa outbound từ VPS đến mạng Cloudflare Edge.
- **Cổng giao tiếp**: **Không cần mở bất kỳ cổng Inbound 80 hay 443 nào** trên Firewall/Router.
- **Quản lý SSL**: Do Cloudflare Edge quản lý và cấp chứng chỉ HTTPS hoàn toàn tự động.
- **Phù hợp cho**: Server nội bộ (On-Premise, Homelab), VPS nằm đằng sau NAT/CGNAT, IP Động, hoặc cần bảo mật ẩn IP gốc của máy chủ chống tấn công DDoS.

---

## 📁 Cấu Trúc Repository

```text
frappe-packaging-scripts/
├── setup.sh                 # Script Bash tự động thực thi 12 bước cài đặt & deploy
├── example.env              # File cấu hình mẫu chứa các biến môi trường cho cả 2 luồng
├── .gitignore               # Cấu hình loại bỏ các file nhạy cảm (.env, .env.local)
├── README.md                # Tài liệu hướng dẫn sử dụng chi tiết
└── docs/
    ├── workflow.md          # Tài liệu mô tả 12 bước workflow chi tiết
    └── research/
        ├── cloudflare_tunnel_deployment.md # Tài liệu nghiên cứu & cấu hình Cloudflare Tunnel
        └── frappe_docker_deployment.md     # Tài liệu phân tích kiến trúc Frappe Docker
```

---

## ⚙️ Yêu Cầu Tiền Đề (Prerequisites)

- **Hệ điều hành**: VPS / Máy chủ chạy Ubuntu (20.04/22.04 LTS) hoặc Debian.
- **Quyền hạn**: Quyền `root` hoặc `sudo`.
- **Tên miền (Domain)**:
  - **Luồng 1 (Direct)**: Tên miền trỏ DNS A Record về IP VPS.
  - **Luồng 2 (Cloudflare Tunnel)**: Tên miền được thêm vào tài khoản Cloudflare và đã tạo Tunnel trên [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/).

---

## 🚀 Hướng Dẫn Sử Dụng Nhanh (Quick Start)

### Bước 1: Clone Repository về VPS
```bash
git clone https://github.com/your-username/frappe-packaging-scripts.git
cd frappe-packaging-scripts
```

### Bước 2: Tạo File Cấu Hình `.env` Từ File Mẫu
```bash
cp example.env .env
```

### Bước 3: Chỉnh Sửa File `.env` Theo Luồng Triển Khai
Mở file `.env` bằng trình biên soạn văn bản:
```bash
nano .env
```

#### 💡 Nếu chọn Luồng 1 (Direct Domain + Traefik SSL):
```env
USE_CLOUDFLARE_TUNNEL="false"
LETSENCRYPT_EMAIL="admin@yourdomain.com"
SITE_DOMAIN="yourdomain.com"
```

#### 💡 Nếu chọn Luồng 2 (Cloudflare Tunnel Zero Trust):
```env
USE_CLOUDFLARE_TUNNEL="true"
CLOUDFLARE_TUNNEL_TOKEN="eyJhSW9p..."  # Lấy Token từ Cloudflare Dashboard (xem hướng dẫn bên dưới)
SITE_DOMAIN="yourdomain.com"
```

##### 🔑 Hướng Dẫn 5 Bước Lấy `CLOUDFLARE_TUNNEL_TOKEN`:
1. Truy cập [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/) ➔ Chọn **Networks** ➔ Chọn **Tunnels**.
2. Nhấn **Create a tunnel** ➔ Chọn loại **Cloudflared** ➔ Đặt tên Tunnel (ví dụ: `frappe-tunnel`) ➔ Nhấn **Save tunnel**.
3. Tại bước **Install and run a connector**: Chọn môi trường **Docker**, bạn sẽ thấy câu lệnh mẫu chứa đoạn token:
   `docker run cloudflare/cloudflared:latest tunnel --no-autoupdate run --token eyJhSW9p...`
   ➔ **Copy chuỗi mã hóa sau `--token`** (bắt đầu bằng `eyJh...`). Đây chính là `CLOUDFLARE_TUNNEL_TOKEN` cần dán vào file `.env`.
4. Nhấn **Next** chuyển sang trang **Public Hostname Page**:
   - **Subdomain**: Nhập subdomain (vd: `erp` nếu là `erp.yourdomain.com`) hoặc để trống nếu dùng domain gốc (`yourdomain.com`).
   - **Domain**: Chọn tên miền của bạn đã trỏ về Cloudflare.
   - **Service Type**: Chọn `HTTP`.
   - **URL**: Nhập `traefik:80` (vì container `cloudflared` chạy chung Docker Network với Traefik).
5. Nhấn **Save tunnel** để hoàn tất.

### Bước 4: Cấp Quyền Thực Thi & Chạy Script Setup
```bash
chmod +x setup.sh

# Chạy menu tương tác (Menu hiển thị trực quan các bước và kiểm tra tiền đề)
./setup.sh

# Hoặc chạy trực tiếp toàn bộ 12 bước không qua menu
./setup.sh --all

# Hoặc kiểm tra trạng thái tất cả các bước (Health Check)
./setup.sh --check

# Hoặc chạy riêng một bước cụ thể (ví dụ Bước 8)
./setup.sh --step 8
```

---

## 🛠️ Bảng Cấu Hình Chi Tiết File `.env`

| Biến Môi Trường | Bắt buộc | Mô Tả | Ví Dụ Mẫu |
| :--- | :---: | :--- | :--- |
| **`APPS_JSON`** | **Có** | Mảng JSON danh sách repo Custom App cần đóng gói | `'[{"url":"https://github.com/user/app1.git","branch":"main"}]'` |
| **`CUSTOM_APP_NAMES`** | **Có** | Danh sách tên app (cách nhau bởi khoảng trắng) cài vào site | `"custom_app_1 custom_app_2"` |
| **`FRAPPE_BRANCH`** | **Có** | Phiên bản branch Frappe/ERPNext | `"version-15"` |
| **`CUSTOM_IMAGE_TAG`** | **Có** | Tag tên cho Docker Image tự động build | `"frappe-custom-image:latest"` |
| **`SITE_DOMAIN`** | **Có** | Tên miền chính truy cập hệ thống | `"erp.yourdomain.com"` |
| **`PROJECT_NAME`** | **Có** | Tên dự án cô lập môi trường Docker Compose | `"frappe-packaging"` |
| **`DB_ROOT_PASSWORD`** | **Có** | Mật khẩu root cơ sở dữ liệu MariaDB | `"Password_DB_Secure_123!"` |
| **`FRAPPE_ADMIN_PASSWORD`** | **Có** | Mật khẩu tài khoản `Administrator` Frappe | `"Password_Admin_Secure_123!"` |
| `LETSENCRYPT_EMAIL` | **Luồng 1** | Email nhận gia hạn SSL Let's Encrypt (Khi `USE_CLOUDFLARE_TUNNEL="false"`) | `"admin@yourdomain.com"` |
| **`USE_CLOUDFLARE_TUNNEL`** | **Có** | Đặt `"true"` nếu chạy qua Tunnel, `"false"` nếu chạy Direct SSL | `"false"` |
| `CLOUDFLARE_TUNNEL_TOKEN` | **Luồng 2** | Token cấp từ Cloudflare Zero Trust (Yêu cầu khi `USE_CLOUDFLARE_TUNNEL="true"`) | `"eyJhSW9p..."` |

---

## 📊 Quy Trình Thực Thi 12 Bước Của `setup.sh`

Script `setup.sh` tự động phân nhánh và thực thi 12 bước cài đặt:

1. **[Bước 1] Kiểm tra quyền Root/Sudo**: Xác thực môi trường và quyền người dùng.
2. **[Bước 2] Đọc & Kiểm tra file `.env`**: Validation các biến bắt buộc và token nếu chạy Cloudflare Tunnel.
3. **[Bước 3] Cập nhật APT**: Tự động nâng cấp hệ thống `apt-get update & upgrade` (Non-interactive).
4. **[Bước 4] Cài đặt Prerequisites**: Kiểm tra/Cài đặt Git, Docker Engine (v23.0+) và Docker Compose v2.
5. **[Bước 5] Tạo thư mục làm việc**: Khởi tạo `~/frappe-packaging` và `~/gitops`.
6. **[Bước 6] Clone `frappe_docker`**: Tải repository `frappe/frappe_docker`.
7. **[Bước 7] Tạo `apps.json`**: Xuất mảng `$APPS_JSON` thành file secret để build image.
8. **[Bước 8] Build Custom Image**: Gọi `docker build` đóng gói Frappe cùng các custom app có trong secret.
9. **[Bước 9] Khởi chạy Proxy / Tunnel**:
   - **Luồng 1**: Khởi chạy Traefik HTTP + HTTPS Let's Encrypt SSL (`overrides/compose.proxy.yaml` & `overrides/compose.https.yaml`).
   - **Luồng 2**: Khởi chạy Traefik HTTP nội bộ (`overrides/compose.proxy.yaml`) và container `cloudflared` với `$CLOUDFLARE_TUNNEL_TOKEN`.
10. **[Bước 10] Khởi chạy MariaDB Shared**: Khởi động database MariaDB dùng chung.
11. **[Bước 11] Deploy Project Stack**: Sinh file Compose tổng hợp `${PROJECT_NAME}.yaml` tương ứng với từng luồng và khởi chạy container stack.
12. **[Bước 12] Tạo Site & Install Custom Apps**: Thực thi `bench new-site` trực tiếp với domain và cài đặt toàn bộ custom app.

---

## 🏗️ Sơ Đồ Kiến Trúc Hệ Thống (System Architecture)

### 🔴 Mô hình Luồng 1: Direct Public Domain (Traefik Auto SSL)
```text
                   [ Web Browser ]
                         │
             HTTPS (Port 443) / HTTP (Port 80)
                         ▼
             ┌───────────────────────┐
             │ Traefik Reverse Proxy │ ◄── Auto Let's Encrypt SSL
             └───────────┬───────────┘
                         │
                         ▼
             ┌───────────────────────┐
             │ Frappe Frontend (Nginx)│
             └───────────┬───────────┘
                         │
            ┌────────────┴────────────┐
            ▼                         ▼
   ┌─────────────────┐       ┌─────────────────┐
   │ Frappe Backend  │       │ Redis (Cache &  │
   │ (Python/Gunicorn)       │  Queue Workers) │
   └────────┬────────┘       └─────────────────┘
            │
            ▼
   ┌─────────────────┐
   │ MariaDB Shared  │ (Database Engine)
   └─────────────────┘
```

### 🟢 Mô hình Luồng 2: Cloudflare Tunnel (Zero Trust - No Open Ports)
```text
                   [ Web Browser ]
                         │ https://erp.yourdomain.com
                         ▼
           ┌───────────────────────────┐
           │   Cloudflare Edge Network │ (Managed SSL Certificate & WAF/DDoS)
           └─────────────┬─────────────┘
                         │
             Outbound Encrypted Tunnel (No open ports)
                         ▼
             ┌───────────────────────────┐
             │ Container `cloudflared`   │
             └───────────┬───────────────┘
                         │ Internal Traffic
                         ▼
             ┌───────────────────────────┐
             │ Traefik Proxy (HTTP Only) │
             └───────────┬───────────────┘
                         │
                         ▼
             ┌───────────────────────────┐
             │ Frappe Frontend & Backend │
             └───────────┬───────────────┘
                         │
                         ▼
             ┌───────────────────────────┐
             │ MariaDB Shared Database   │
             └───────────────────────────┘
```

---

## 📌 Hướng Dẫn Vận Hành & Các Lệnh Thường Dùng

### Xem Logs Của Stack Project
```bash
docker compose -p frappe-packaging logs -f
```

### Xem Log Của Container Cloudflare Tunnel (Nếu dùng Luồng 2)
```bash
docker compose -p tunnel logs -f
```

### Kiểm Tra Trạng Thái Container
```bash
docker compose -p frappe-packaging ps
```

### Khởi Động Lại Hệ Thống
```bash
docker compose -p frappe-packaging restart
```

### Thực Thi Lệnh Bench Migration Trong Backend
```bash
docker compose -p frappe-packaging exec backend bench migrate
```

---

## 📚 Tài Liệu Tham Khảo Thêm

- [Quy trình thực thi 12 bước chi tiết (`docs/workflow.md`)](file:///Users/vanloc/Documents/Windify/frappe-packaging-scripts/docs/workflow.md)
- [Nghiên cứu & Triển khai Cloudflare Tunnel (`docs/research/cloudflare_tunnel_deployment.md`)](file:///Users/vanloc/Documents/Windify/frappe-packaging-scripts/docs/research/cloudflare_tunnel_deployment.md)
- [Phân tích kiến trúc Frappe Docker (`docs/research/frappe_docker_deployment.md`)](file:///Users/vanloc/Documents/Windify/frappe-packaging-scripts/docs/research/frappe_docker_deployment.md)
