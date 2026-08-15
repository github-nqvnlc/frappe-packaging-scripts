# Workflow Cài Đặt Frappe Packaging (Hỗ Trợ Direct Domain & Cloudflare Tunnel)

Tài liệu này định nghĩa quy trình thực thi tự động hóa cho script cài đặt, tự động đọc cấu hình từ file `.env` (mẫu tại `example.env`). Quy trình hỗ trợ cả 2 chế độ: **Triển khai Domain trực tiếp (Traefik SSL)** và **Triển khai qua Cloudflare Tunnel (Không mở port 80/443 public)**.

---

### Bảng Biến Môi Trường Cấu Hình (Từ file `.env`)

| Tên biến | Bắt buộc | Mô tả | Ví dụ trong `example.env` |
| :--- | :---: | :--- | :--- |
| `APPS_JSON` | **Có** | Mảng JSON khai báo danh sách custom app cần clone & build | `'[{"url":"...","branch":"main"}]'` |
| `CUSTOM_APP_NAMES` | **Có** | Danh sách tên app (cách nhau bởi khoảng trắng) cài vào site | `"custom_app_1 custom_app_2"` |
| `FRAPPE_BRANCH` | **Có** | Phiên bản branch của Frappe/ERPNext | `"version-15"` |
| `CUSTOM_IMAGE_TAG` | **Có** | Tag tên Docker Image sẽ build | `"frappe-custom-image:latest"` |
| `SITE_DOMAIN` | **Có** | Tên miền chính cho site | `"yourdomain.com"` |
| `PROJECT_NAME` | **Có** | Tên project Docker Compose cô lập | `"frappe-packaging"` |
| `DB_ROOT_PASSWORD` | **Có** | Mật khẩu root MariaDB | `"admin@123"` |
| `FRAPPE_ADMIN_PASSWORD` | **Có** | Mật khẩu Administrator Frappe | `"admin"` |
| `LETSENCRYPT_EMAIL` | Tùy chọn | Email gia hạn SSL Let's Encrypt (Khi không dùng Tunnel) | `"admin@yourdomain.com"` |
| `USE_CLOUDFLARE_TUNNEL` | **Có** | Đặt `"true"` để dùng Cloudflare Tunnel, `"false"` để chạy trực tiếp | `"false"` |
| `CLOUDFLARE_TUNNEL_TOKEN` | Khi Tunnel | Token từ Cloudflare Zero Trust (Yêu cầu nếu `USE_CLOUDFLARE_TUNNEL="true"`) | `"eyJhSW9p..."` |

---

### Tuần Tự Các Bước Thực Thi (Workflow)

#### 1. Yêu cầu quyền sudo / root
Kiểm tra xem script có đang được chạy với quyền root/sudo hay không. Nếu không phải root, tự động chuyển đổi qua `sudo` hoặc thông báo lỗi và dừng lại.

#### 2. Cập nhật APT trên VPS
Chạy cập nhật hệ thống tự động, bỏ qua các hộp thoại tương tác:
```bash
export DEBIAN_FRONTEND=noninteractive
apt-get update -y && apt-get upgrade -y
```

#### 3. Cài đặt các yêu cầu (Prerequisites)
Kiểm tra và cài đặt nếu chưa có:
- **Git**
- **Docker Engine v23.0+** (kèm `buildx` plugin)
- **Docker Compose v2** (`docker compose` plugin)

#### 4. Tạo thư mục làm việc
Tạo thư mục `~/frappe-packaging` và `~/gitops`:
```bash
mkdir -p ~/frappe-packaging ~/gitops
```

#### 5. Clone Repository `frappe_docker`
Clone repository chính thức của `frappe_docker` nếu chưa tồn tại:
```bash
git clone https://github.com/frappe/frappe_docker ~/frappe-packaging/frappe_docker
cd ~/frappe-packaging/frappe_docker
```

#### 6. Đọc & Kiểm tra file `.env`
- Kiểm tra file `.env` tồn tại. Báo lỗi và dừng nếu thiếu `.env`.
- Load biến môi trường và kiểm tra nếu `USE_CLOUDFLARE_TUNNEL="true"` thì biến `CLOUDFLARE_TUNNEL_TOKEN` không được để trống.
- Đọc biến `$APPS_JSON` và xuất ra file `apps.json`:
```bash
echo "$APPS_JSON" > ~/frappe-packaging/frappe_docker/apps.json
```

#### 7. Build Custom Docker Image
Sử dụng `docker build` với tham số `$FRAPPE_BRANCH`, `$CUSTOM_IMAGE_TAG` và secret `apps.json`:
```bash
docker build \
  --build-arg=FRAPPE_PATH=https://github.com/frappe/frappe \
  --build-arg=FRAPPE_BRANCH="$FRAPPE_BRANCH" \
  --build-arg=CACHE_BUST="$(date +%s)" \
  --secret=id=apps_json,src=apps.json \
  --tag="$CUSTOM_IMAGE_TAG" \
  --file=images/layered/Containerfile .
```

#### 8. Thiết lập Proxy & Cloudflare Tunnel (Phân nhánh chế độ)

##### 🟢 Chế độ A: Người dùng chạy qua Cloudflare Tunnel (`USE_CLOUDFLARE_TUNNEL="true"`)
1. **Khởi chạy Traefik HTTP** (Tự động sinh `~/gitops/traefik.yaml` khởi chạy Traefik Reverse Proxy trên cổng 80 và tạo mạng Docker `traefik-public`):
   ```bash
   docker compose --project-name traefik \
     -f ~/gitops/traefik.yaml up -d
   ```
2. **Tạo & Khởi chạy Container `cloudflared`**:
   - Tạo file `~/gitops/cloudflared.yaml`:
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
           - traefik-public

     networks:
       traefik-public:
         external: true
     ```
   - Khởi chạy container:
     ```bash
     docker compose --project-name tunnel -f ~/gitops/cloudflared.yaml up -d
     ```

##### 🔵 Chế độ B: Trực tiếp qua Public IP/Domain (`USE_CLOUDFLARE_TUNNEL="false"`)
- Tự động sinh `~/gitops/traefik.yaml` với cấu hình Traefik HTTP + HTTPS Let's Encrypt SSL và tự động redirect HTTP -> HTTPS.
- Khởi chạy Traefik Reverse Proxy:
  ```bash
  docker compose --project-name traefik \
    -f ~/gitops/traefik.yaml up -d
  ```

#### 9. Thiết lập MariaDB Shared
- Tạo file `~/gitops/mariadb.env`:
  ```env
  DB_PASSWORD=$DB_ROOT_PASSWORD
  ```
- Khởi chạy MariaDB shared:
  ```bash
  docker compose --project-name mariadb \
    --env-file ~/gitops/mariadb.env \
    -f overrides/compose.mariadb-shared.yaml up -d
  ```

#### 10. Cấu hình Project Stack (Bench)
- Tạo file `~/gitops/${PROJECT_NAME}.env`:
  ```env
  CUSTOM_IMAGE=frappe-custom-image
  CUSTOM_TAG=latest
  ROUTER=${PROJECT_NAME}-router
  SITES_RULE=Host(`$SITE_DOMAIN`)
  ```

#### 11. Deploy Project Stack
- Sinh file cấu hình tổng hợp `${PROJECT_NAME}.yaml`:
  - **Nếu `USE_CLOUDFLARE_TUNNEL="true"`**:
    ```bash
    docker compose --project-name "$PROJECT_NAME" \
      --env-file ~/gitops/${PROJECT_NAME}.env \
      -f compose.yaml \
      -f overrides/compose.redis.yaml \
      -f overrides/compose.multi-bench.yaml config > ~/gitops/${PROJECT_NAME}.yaml
    ```
  - **Nếu `USE_CLOUDFLARE_TUNNEL="false"`**:
    ```bash
    docker compose --project-name "$PROJECT_NAME" \
      --env-file ~/gitops/${PROJECT_NAME}.env \
      -f compose.yaml \
      -f overrides/compose.redis.yaml \
      -f overrides/compose.multi-bench.yaml \
      -f overrides/compose.multi-bench-ssl.yaml config > ~/gitops/${PROJECT_NAME}.yaml
    ```
- Khởi chạy stack:
  ```bash
  docker compose -p "$PROJECT_NAME" -f ~/gitops/${PROJECT_NAME}.yaml up -d
  ```

#### 12. Tạo Site và Cài đặt các Custom Apps
Dựng động các cờ `--install-app` cho từng custom app trong `$CUSTOM_APP_NAMES` và thực thi `bench new-site`:
```bash
INSTALL_APP_FLAGS=""
for app in $CUSTOM_APP_NAMES; do
  INSTALL_APP_FLAGS="$INSTALL_APP_FLAGS --install-app $app"
done

docker compose --project-name "$PROJECT_NAME" exec backend \
  bench new-site "$SITE_DOMAIN" \
  --mariadb-user-host-login-scope=% \
  --db-root-password "$DB_ROOT_PASSWORD" \
  --admin-password "$FRAPPE_ADMIN_PASSWORD" \
  $INSTALL_APP_FLAGS
```
