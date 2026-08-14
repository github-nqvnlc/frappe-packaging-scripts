# Nghiên Cứu & Triển Khai Frappe Docker Qua Cloudflare Tunnel (Không Dùng Domain/Port Direct)

Tài liệu này nghiên cứu giải pháp triển khai **Frappe / ERPNext Docker** thông qua **Cloudflare Tunnel (`cloudflared`)** qua một port nội bộ, dành cho trường hợp server/VPS không mở trực tiếp cổng `80/443` ra Internet, nằm sau NAT/CGNAT, hoặc muốn tăng cường bảo mật ẩn IP gốc.

---

## 1. Đặt Vấn Đề & Phân Tích Kiến Trúc

### A. Vấn đề của mô hình truyền thống (Public Port 80/443)
Mô hình tiêu chuẩn của `frappe_docker` yêu cầu:
1. VPS phải có **Public IP** tĩnh.
2. Firewall / Router phải mở cổng `80` (HTTP) và `443` (HTTPS).
3. Traefik hoặc NGINX Proxy Manager tự lắng nghe trên port 80/443 để xác thực SSL Let's Encrypt (ACME HTTP-01 challenge).

### B. Giải pháp khi dùng Cloudflare Tunnel (Zero Trust)
**Cloudflare Tunnel** tạo một kết nối mã hóa outbound từ VPS tới mạng Edge của Cloudflare thông qua daemon `cloudflared`.

```text
 Client (Browser)
      │ https://erp.yourdomain.com
      ▼
 Cloudflare Edge (SSL/TLS Certificate, WAF, DDoS Protection)
      │
      │ Secure Tunnel (Outbound - No Open Inbound Ports)
      ▼
 [cloudflared container / daemon trên VPS]
      │
      │ Internal Network / Localhost Port (vd: http://frontend:8080 hoặc http://traefik:80)
      ▼
 Frappe Container (Frontend / Traefik Proxy)
```

#### Ưu điểm:
- **Không cần mở Inbound Port**: Không cần mở port 80 hay 443 trên Firewall VPS/Router.
- **Hoạt động tốt đằng sau NAT/CGNAT/IP Động**: Phù hợp cho máy chủ nội bộ (On-Premise, Homelab, VPS cá nhân).
- **SSL Tự Động**: SSL do Cloudflare Edge quản lý, không lo Let's Encrypt bị lỗi challenge.
- **Bảo mật**: Hide IP thật của VPS, phòng chống DDoS và quét port tự động.
- **Hỗ trợ đầy đủ WebSockets**: SocketIO trong Frappe Desk (thông báo real-time) chạy hoàn toàn tương thích trên Cloudflare WebSockets.

---

## 2. Các Mô Hình Triển Khai Với Frappe Docker

Có 2 mô hình phổ biến khi kết hợp `frappe_docker` và `cloudflared`:

### Mô hình 1: Cloudflare Tunnel -> Traefik HTTP (Khuyên dùng cho Multi-site / Multi-bench)
- **Kiến trúc**: Traefik chỉ lắng nghe cổng HTTP nội bộ (Port `80`). `cloudflared` chuyển tiếp traffic từ Cloudflare Edge đến Traefik.
- **Ưu điểm**: Giữ nguyên khả năng định tuyến nhiều Site/Bench của Traefik dựa theo `Host` header.
- **Cấu hình SSL**: SSL được xử lý ở Cloudflare Edge, không cần nạp `compose.traefik-ssl.yaml` hay Let's Encrypt trên VPS.

### Mô hình 2: Cloudflare Tunnel -> Direct Published Port (Single Site / Đơn giản)
- **Kiến trúc**: Không sử dụng Traefik. Expose cổng `8080` của service `frontend` (`compose.noproxy.yaml` hoặc map port `8080:8080`). `cloudflared` trỏ trực tiếp tới `http://frontend:8080` hoặc `http://127.0.0.1:8080`.
- **Ưu điểm**: Đơn giản, nhẹ, bớt 1 layer proxy (Traefik).

---

## 3. Hướng Dẫn Triển Khai Chi Tiết (Step-by-step)

Dưới đây là chi tiết các bước triển khai theo **Mô hình 1 (Cloudflare Tunnel -> Traefik / Local Port)**.

### Bước 1: Tạo Tunnel trên Cloudflare Zero Trust Dashboard
1. Truy cập [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/).
2. Vào **Networks** -> **Tunnels** -> Chọn **Create a tunnel**.
3. Chọn loại tunnel **Cloudflared**.
4. Đặt tên Tunnel (ví dụ: `frappe-vps-tunnel`) và nhấn **Save tunnel**.
5. Copy đoạn **Tunnel Token** được cấp (chuỗi mã hóa dạng `eyJhIjoi...`).
6. Trong mục **Public Hostname Page**:
   - **Subdomain / Domain**: Điền `erp.yourdomain.com`.
   - **Service Type**: Chọn `HTTP`.
   - **URL**: Điền `traefik:80` (nếu chạy `cloudflared` chung Docker Network với Traefik) hoặc `127.0.0.1:8080` / `localhost:80`.
   - Trong **Additional application settings** -> **HTTP Settings**:
     - Bật **HTTP2 Origin** (tùy chọn).
     - Giữ nguyên `Host Header` (để Cloudflare tự truyền `Host: erp.yourdomain.com` vào Frappe).

---

### Bước 2: Thêm Cloudflared Service vào Docker Compose

Bạn có thể tích hợp `cloudflared` chạy trực tiếp dưới dạng một Docker Container trong stack hoặc chạy daemon độc lập trên OS.

#### Cách 1: Tích hợp vào Docker Compose (`overrides/compose.cloudflared.yaml`)
Tạo file override cho docker compose:

```yaml
version: "3.8"

services:
  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflared
    restart: unless-stopped
    command: tunnel --no-autoupdate run
    environment:
      - TUNNEL_TOKEN=${CLOUDFLARE_TUNNEL_TOKEN}
    networks:
      - traefik-public # Kết nối chung network với Traefik hoặc Frontend

networks:
  traefik-public:
    external: true
```

#### Cách 2: Chạy `cloudflared` dưới dạng Service trên VPS Host
Nếu cài trực tiếp lên hệ điều hành Linux:
```bash
# Cài đặt cloudflared
curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared.deb

# Khởi chạy service với Token
sudo cloudflared service install <YOUR_CLOUDFLARE_TUNNEL_TOKEN>
```

---

### Bước 3: Cấu Hình File `.env` Cho Cloudflare Tunnel

Cập nhật các biến trong `.env` tương ứng:

```env
# 1. CLOUDFLARE TUNNEL TOKEN
CLOUDFLARE_TUNNEL_TOKEN="eyJhIjoi..."

# 2. THÔNG TIN SITE & DOMAIN
SITE_DOMAIN="erp.yourdomain.com"
PROJECT_NAME="smrs-project"

# 3. THÔNG TIN DOCKER IMAGE & APPS
CUSTOM_IMAGE_TAG="smrs-custom-image:latest"
CUSTOM_APP_NAMES="custom_app_1"
APPS_JSON='[{"url":"https://github.com/user/app.git","branch":"main"}]'

# 4. MẬT KHẨU
DB_ROOT_PASSWORD="ChangeMe_DB_123!"
FRAPPE_ADMIN_PASSWORD="ChangeMe_Admin_123!"
```

---

### Bước 4: Lệnh Khởi Chạy Hệ Thống Qua Tunnel

Khi triển khai với Cloudflare Tunnel, ta **không dùng** `compose.traefik-ssl.yaml` hay `compose.multi-bench-ssl.yaml` vì Cloudflare đã cấp SSL ở Edge.

#### 1. Khởi chạy Traefik (HTTP Only):
```bash
docker compose --project-name traefik \
  -f overrides/compose.proxy.yaml up -d
```

#### 2. Khởi chạy Cloudflare Tunnel Container:
```bash
docker compose --project-name tunnel \
  --env-file .env \
  -f overrides/compose.cloudflared.yaml up -d
```

#### 3. Deploy Project Stack (Frappe Bench):
```bash
cat <<EOF > ~/gitops/${PROJECT_NAME}.env
BACKEND_IMAGE=$CUSTOM_IMAGE_TAG
FRONTEND_IMAGE=$CUSTOM_IMAGE_TAG
ROUTER=${PROJECT_NAME}-router
SITES_RULE=Host(\`$SITE_DOMAIN\`)
EOF

# Sinh file yaml tổng hợp (HTTP - không dùng SSL override nội bộ)
docker compose --project-name "$PROJECT_NAME" \
  --env-file ~/gitops/${PROJECT_NAME}.env \
  -f compose.yaml \
  -f overrides/compose.redis.yaml \
  -f overrides/compose.multi-bench.yaml config > ~/gitops/${PROJECT_NAME}.yaml

docker compose -p "$PROJECT_NAME" -f ~/gitops/${PROJECT_NAME}.yaml up -d
```

#### 4. Khởi tạo Site:
```bash
docker compose --project-name "$PROJECT_NAME" exec backend \
  bench new-site "$SITE_DOMAIN" \
  --mariadb-user-host-login-scope=% \
  --db-root-password "$DB_ROOT_PASSWORD" \
  --admin-password "$FRAPPE_ADMIN_PASSWORD" \
  --install-app custom_app_1
```

---

## 4. Những Lưu Ý Quan Trọng Khi Dùng Cloudflare Tunnel Với Frappe

### 1. Host Header Matching (Bắt buộc)
Frappe định vị site thông qua `Host` header. Trên Cloudflare Tunnel Ingress configuration, đảm bảo **HTTP Host Header** không bị ghi đè thành `localhost` hoặc `127.0.0.1`.
- Giữ mặc định hoặc set **HTTP Host Header**: `erp.yourdomain.com`.

### 2. Bật WebSockets trên Cloudflare
Frappe Desk sử dụng **SocketIO** cho thông báo real-time.
- Vào Cloudflare Dashboard -> **Network** -> Kiểm tra tùy chọn **WebSockets** đã bật (Enabled).

### 3. Giới Hạn File Upload (Upload Limit)
- Tài khoản Cloudflare Free giới hạn dung lượng HTTP request body tối đa **100MB**.
- Nếu bạn cần upload file đính kèm lớn hơn 100MB trong ERPNext, bạn cần:
  - Cấu hình Chunk Upload hoặc
  - Nâng cấp Cloudflare plan / Sử dụng S3-compatible Object Storage (MinIO, AWS S3) cho file đính kèm.

### 4. Cấu hình SSL Mode Trên Cloudflare Dashboard
Vào **SSL/TLS** -> chọn chế độ **Flexible** hoặc **Full**:
- **Flexible**: Encryption giữa Browser <-> Cloudflare Edge (HTTPS), Cloudflare Edge <-> VPS (HTTP). *(Phổ biến & Đơn giản nhất khi ngắt SSL tại Tunnel)*.
- **Full**: Nếu phía VPS có SSL tự ký hoặc SSL nội bộ.

---

## 5. Kết Luận

Giải pháp **Cloudflare Tunnel + Frappe Docker** là sự lựa chọn tối ưu khi:
- VPS không có IP Tĩnh Public hoặc bị nhà mạng chặn port `80/443`.
- Muốn bảo vệ hệ thống ERP khỏi các cuộc tấn công dò quét IP công cộng.
- Không muốn phức tạp hóa quá trình xin và quản lý chứng chỉ SSL trên máy chủ.
