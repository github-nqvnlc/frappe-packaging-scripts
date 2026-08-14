# Workflow Cài Đặt SMRS Pack (Tự Động Với Biến Môi Trường .env)

Tài liệu này định nghĩa thứ tự các bước thực thi cho script tự động hóa trong `/home/baucan/scripts`, tự động đọc các tham số cấu hình từ file `.env` (mẫu tại `example.env`).

---

### Các biến môi trường sẽ sử dụng (từ file `.env`)

| Tên biến | Mô tả | Ví dụ trong `example.env` |
| :--- | :--- | :--- |
| `APPS_JSON` | Danh sách custom app dạng JSON truyền vào Docker build secret | `'[{"url":"...","branch":"main"}]'` |
| `CUSTOM_APP_NAMES` | Danh sách tên app (cách nhau bởi khoảng trắng) cài vào site | `"custom_app_1 custom_app_2"` |
| `FRAPPE_BRANCH` | Branch phiên bản Frappe | `"version-15"` |
| `CUSTOM_IMAGE_TAG` | Tag tên Docker Image sẽ build | `"smrs-custom-image:latest"` |
| `LETSENCRYPT_EMAIL` | Email đăng ký gia hạn SSL Let's Encrypt | `"admin@yourdomain.com"` |
| `SITE_DOMAIN` | Tên miền chính cho site | `"yourdomain.com"` |
| `PROJECT_NAME` | Tên project Docker Compose | `"smrs-project"` |
| `DB_ROOT_PASSWORD` | Mật khẩu root MariaDB | `"ChangeMe_Secure_DB_Password_123!"` |
| `FRAPPE_ADMIN_PASSWORD` | Mật khẩu Administrator Frappe | `"ChangeMe_Secure_Admin_Password_123!"` |

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
Tạo thư mục `~/smrs-pack` và di chuyển vào thư mục này:
```bash
mkdir -p ~/smrs-pack && cd ~/smrs-pack
```

#### 5. Clone Repository `frappe_docker`
Clone repository chính thức của `frappe_docker` nếu chưa tồn tại:
```bash
git clone https://github.com/frappe/frappe_docker
cd ~/smrs-pack/frappe_docker
```

#### 6. Đọc file `.env` và tạo file `apps.json`
Kiểm tra sự tồn tại của file `.env`. Nếu không tìm thấy, thông báo lỗi và dừng script. Nếu có, đọc các biến môi trường và tạo file `apps.json` từ biến `$APPS_JSON`:
```bash
# Đường dẫn tới file .env (ví dụ trong thư mục script hoặc thư mục làm việc)
ENV_FILE="/path/to/.env"

# 1. Kiểm tra file .env có tồn tại hay không
if [ ! -f "$ENV_FILE" ]; then
    echo "[!] Lỗi: Không tìm thấy file cấu hình $ENV_FILE"
    echo "[*] Vui lòng sao chép từ example.env và điền đầy đủ cấu hình trước khi chạy script."
    exit 1
fi

# 2. Load biến môi trường từ .env
set -o allexport
source "$ENV_FILE"
set +o allexport

# 3. Tạo file apps.json chứa cấu hình custom apps
echo "$APPS_JSON" > apps.json
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

#### 8. Thiết lập Traefik (Load Balancer & SSL)
- Tạo thư mục lưu cấu hình GitOps (ví dụ: `~/gitops`).
- Tạo file `~/gitops/traefik.env`:
  ```env
  UPSTREAM_LOG_LEVEL=info
  LETSENCRYPT_EMAIL=$LETSENCRYPT_EMAIL
  ```
- Khởi chạy Traefik với docker compose (`overrides/compose.traefik.yaml` và `compose.traefik-ssl.yaml`).

#### 9. Thiết lập MariaDB Shared
- Tạo file `~/gitops/mariadb.env`:
  ```env
  DB_PASSWORD=$DB_ROOT_PASSWORD
  ```
- Khởi chạy MariaDB shared với `overrides/compose.mariadb-shared.yaml`.

#### 10. Cấu hình Project Stack (Bench)
- Tạo file `~/gitops/${PROJECT_NAME}.env` chứa các biến:
  ```env
  BACKEND_IMAGE=$CUSTOM_IMAGE_TAG
  FRONTEND_IMAGE=$CUSTOM_IMAGE_TAG
  ROUTER=${PROJECT_NAME}-router
  SITES_RULE=Host(`$SITE_DOMAIN`)
  ```

#### 11. Deploy Project Stack
- Sinh file cấu hình tổng hợp `${PROJECT_NAME}.yaml` bằng `docker compose config` kèm các overrides (`redis`, `multi-bench`, `multi-bench-ssl`).
- Khởi chạy stack:
  ```bash
  docker compose -p "$PROJECT_NAME" -f ~/gitops/${PROJECT_NAME}.yaml up -d
  ```

#### 12. Tạo Site và Cài đặt các Custom Apps
Dựng động các cờ `--install-app` cho từng custom app có trong `$CUSTOM_APP_NAMES` và thực thi `bench new-site`:
```bash
# Dựng danh sách cờ --install-app
INSTALL_APP_FLAGS=""
for app in $CUSTOM_APP_NAMES; do
  INSTALL_APP_FLAGS="$INSTALL_APP_FLAGS --install-app $app"
done

# Tạo site mới và cài đặt tất cả custom app
docker compose --project-name "$PROJECT_NAME" exec backend \
  bench new-site "$SITE_DOMAIN" \
  --mariadb-user-host-login-scope=% \
  --db-root-password "$DB_ROOT_PASSWORD" \
  --admin-password "$FRAPPE_ADMIN_PASSWORD" \
  $INSTALL_APP_FLAGS
```
