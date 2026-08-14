#!/bin/bash
set -e

# Cấu hình tự động hoàn toàn (bỏ qua tất cả các hộp thoại tương tác như debconf / dpkg)
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
APT_CMD="apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

# ==============================================================================
# SMRS Pack & Deployment Automation Script
# ==============================================================================

echo "================================================================================"
echo "           BẮT ĐẦU WORKFLOW TỰ ĐỘNG CÀI ĐẶT VÀ DEPLOY SMRS PACK                 "
echo "================================================================================"

# ------------------------------------------------------------------------------
# Bước 1: Yêu cầu quyền sudo / root & Xác định môi trường
# ------------------------------------------------------------------------------
echo ""
echo "[BƯỚC 1/12] Kiểm tra quyền Root/Sudo & Khai báo môi trường..."

if [ "$EUID" -ne 0 ]; then
    echo "[!] Script này yêu cầu quyền root/sudo."
    echo "[*] Đang tự động chuyển đổi sang quyền sudo..."
    exec sudo bash "$0" "$@"
fi

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")
SMRS_DIR="$REAL_HOME/smrs-pack"
GITOPS_DIR="$REAL_HOME/gitops"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

echo "  -> Target User     : $REAL_USER"
echo "  -> Home Directory  : $REAL_HOME"
echo "  -> SMRS Directory  : $SMRS_DIR"
echo "  -> GitOps Directory: $GITOPS_DIR"
echo "[✓] Kiểm tra quyền root & môi trường hoàn tất."

# ------------------------------------------------------------------------------
# Bước 2: Kiểm tra & Đọc file cấu hình .env
# ------------------------------------------------------------------------------
echo ""
echo "[BƯỚC 2/12] Kiểm tra & Đọc file cấu hình .env..."

ENV_FILE=""
POSSIBLE_ENV_PATHS=(
    "$SCRIPT_DIR/.env"
    "$(pwd)/.env"
    "$SMRS_DIR/.env"
    "$REAL_HOME/.env"
)

for path in "${POSSIBLE_ENV_PATHS[@]}"; do
    if [ -f "$path" ]; then
        ENV_FILE="$path"
        break
    fi
done

if [ -z "$ENV_FILE" ]; then
    echo "[!] LỖI BÁO ĐỘNG: Không tìm thấy file cấu hình .env!"
    echo "[*] Vui lòng sao chép file example.env thành .env và khai báo thông số trước khi chạy script."
    exit 1
fi

echo "  -> File cấu hình được sử dụng: $ENV_FILE"
set -o allexport
source "$ENV_FILE"
set +o allexport

# Kiểm tra các biến bắt buộc
REQUIRED_VARS=("APPS_JSON" "CUSTOM_APP_NAMES" "SITE_DOMAIN" "PROJECT_NAME" "DB_ROOT_PASSWORD" "FRAPPE_ADMIN_PASSWORD")
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        echo "[!] LỖI: Biến bắt buộc '$var' chưa được định nghĩa trong .env!"
        exit 1
    fi
done

FRAPPE_BRANCH="${FRAPPE_BRANCH:-version-15}"
CUSTOM_IMAGE_TAG="${CUSTOM_IMAGE_TAG:-smrs-custom-image:latest}"
LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-admin@$SITE_DOMAIN}"

echo "  -> Project Name   : $PROJECT_NAME"
echo "  -> Site Domain    : $SITE_DOMAIN"
echo "  -> Custom Apps    : $CUSTOM_APP_NAMES"
echo "  -> Frappe Branch  : $FRAPPE_BRANCH"
echo "  -> Image Tag      : $CUSTOM_IMAGE_TAG"
echo "[✓] Đọc và kiểm tra cấu hình .env hoàn tất."

# ------------------------------------------------------------------------------
# Bước 3: Cập nhật apt trên VPS
# ------------------------------------------------------------------------------
echo ""
echo "[BƯỚC 3/12] Cập nhật danh sách gói tin & nâng cấp hệ thống (APT Update & Upgrade)..."

echo "  -> Giải phóng các khóa (lock) apt/dpkg nếu có..."
killall -9 apt apt-get 2>/dev/null || true
rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock
dpkg --configure -a || true

echo "  -> Đang thực thi apt-get update & upgrade..."
apt-get update -y && $APT_CMD upgrade
echo "[✓] Cập nhật APT thành công."

# ------------------------------------------------------------------------------
# Bước 4: Cài đặt Prerequisites (git, docker engine v23.0+, docker compose v2)
# ------------------------------------------------------------------------------
echo ""
echo "[BƯỚC 4/12] Kiểm tra và cài đặt công cụ cần thiết (Git, Docker Engine v23.0+, Docker Compose v2)..."

if ! command -v git &> /dev/null; then
    echo "  -> Git chưa được cài đặt. Tiến hành cài đặt Git..."
    $APT_CMD install git
else
    echo "  -> Git đã được cài đặt: $(git --version)"
fi

HAS_DOCKER=false
if command -v docker &> /dev/null; then
    if docker compose version &> /dev/null; then
        echo "  -> Docker & Docker Compose v2 đã có sẵn: $(docker compose version)"
        HAS_DOCKER=true
    fi
fi

if [ "$HAS_DOCKER" = false ]; then
    echo "  -> Đang cài đặt Docker Engine v23.0+ và Docker Compose v2 từ repository chính thức..."
    $APT_CMD install ca-certificates curl gnupg lsb-release

    install -m 0755 -d /etc/apt/keyrings
    if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
    fi

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$UBUNTU_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -y
    $APT_CMD install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    if [ -n "$REAL_USER" ] && [ "$REAL_USER" != "root" ]; then
        usermod -aG docker "$REAL_USER" || true
    fi
fi
echo "[✓] Đã đảm bảo tất cả Prerequisites sẵn sàng."

# ------------------------------------------------------------------------------
# Bước 5: Tạo thư mục làm việc
# ------------------------------------------------------------------------------
echo ""
echo "[BƯỚC 5/12] Khởi tạo các thư mục lưu trữ dự án ($SMRS_DIR & $GITOPS_DIR)..."
mkdir -p "$SMRS_DIR"
mkdir -p "$GITOPS_DIR"
echo "  -> Đã tạo/kiểm tra thư mục: $SMRS_DIR"
echo "  -> Đã tạo/kiểm tra thư mục: $GITOPS_DIR"
echo "[✓] Khởi tạo thư mục hoàn tất."

# ------------------------------------------------------------------------------
# Bước 6: Clone Repository frappe_docker
# ------------------------------------------------------------------------------
echo ""
echo "[BƯỚC 6/12] Chuẩn bị repository frappe_docker..."
if [ -d "$SMRS_DIR/frappe_docker" ]; then
    echo "  -> Thư mục frappe_docker đã tồn tại tại $SMRS_DIR/frappe_docker. Bỏ qua bước clone."
else
    echo "  -> Đang clone repository https://github.com/frappe/frappe_docker..."
    git clone https://github.com/frappe/frappe_docker "$SMRS_DIR/frappe_docker"
fi
cd "$SMRS_DIR/frappe_docker"
echo "[✓] Chuẩn bị repository frappe_docker hoàn tất."

# ------------------------------------------------------------------------------
# Bước 7: Tạo file apps.json từ biến APPS_JSON
# ------------------------------------------------------------------------------
echo ""
echo "[BƯỚC 7/12] Khởi tạo file cấu hình secret apps.json..."
echo "$APPS_JSON" > "$SMRS_DIR/frappe_docker/apps.json"
echo "  -> Nội dung apps.json:"
cat "$SMRS_DIR/frappe_docker/apps.json" | sed 's/^/     /'
echo "[✓] Tạo file apps.json thành công."

# ------------------------------------------------------------------------------
# Bước 8: Build Custom Docker Image
# ------------------------------------------------------------------------------
echo ""
echo "[BƯỚC 8/12] Build Custom Docker Image ($CUSTOM_IMAGE_TAG)..."
echo "  -> Quá trình build image bắt đầu (Frappe branch: $FRAPPE_BRANCH)..."
docker build \
  --build-arg=FRAPPE_PATH=https://github.com/frappe/frappe \
  --build-arg=FRAPPE_BRANCH="$FRAPPE_BRANCH" \
  --build-arg=CACHE_BUST="$(date +%s)" \
  --secret=id=apps_json,src=apps.json \
  --tag="$CUSTOM_IMAGE_TAG" \
  --file=images/layered/Containerfile .
echo "[✓] Build Custom Docker Image $CUSTOM_IMAGE_TAG thành công!"

# ------------------------------------------------------------------------------
# Bước 9: Thiết lập Traefik (Load Balancer & SSL)
# ------------------------------------------------------------------------------
echo ""
echo "[BƯỚC 9/12] Cấu hình và khởi chạy Traefik Reverse Proxy & Let's Encrypt..."
cat <<EOF > "$GITOPS_DIR/traefik.env"
UPSTREAM_LOG_LEVEL=info
LETSENCRYPT_EMAIL=$LETSENCRYPT_EMAIL
EOF

echo "  -> Đang khởi chạy Traefik container..."
docker compose --project-name traefik \
  --env-file "$GITOPS_DIR/traefik.env" \
  -f overrides/compose.traefik.yaml \
  -f overrides/compose.traefik-ssl.yaml up -d
echo "[✓] Traefik đã được khởi chạy thành công."

# ------------------------------------------------------------------------------
# Bước 10: Thiết lập MariaDB Shared
# ------------------------------------------------------------------------------
echo ""
echo "[BƯỚC 10/12] Cấu hình và khởi chạy MariaDB Database dùng chung..."
cat <<EOF > "$GITOPS_DIR/mariadb.env"
DB_PASSWORD=$DB_ROOT_PASSWORD
EOF

echo "  -> Đang khởi chạy MariaDB container..."
docker compose --project-name mariadb \
  --env-file "$GITOPS_DIR/mariadb.env" \
  -f overrides/compose.mariadb-shared.yaml up -d
echo "[✓] MariaDB Database đã khởi chạy thành công."

# ------------------------------------------------------------------------------
# Bước 11: Cấu hình & Deploy Project Stack (Bench)
# ------------------------------------------------------------------------------
echo ""
echo "[BƯỚC 11/12] Tạo cấu hình & Deploy Project Stack ($PROJECT_NAME)..."

cat <<EOF > "$GITOPS_DIR/${PROJECT_NAME}.env"
BACKEND_IMAGE=$CUSTOM_IMAGE_TAG
FRONTEND_IMAGE=$CUSTOM_IMAGE_TAG
ROUTER=${PROJECT_NAME}-router
SITES_RULE=Host(\`$SITE_DOMAIN\`)
EOF

echo "  -> Đang sinh file cấu hình tổng hợp $GITOPS_DIR/${PROJECT_NAME}.yaml..."
docker compose --project-name "$PROJECT_NAME" \
  --env-file "$GITOPS_DIR/${PROJECT_NAME}.env" \
  -f compose.yaml \
  -f overrides/compose.redis.yaml \
  -f overrides/compose.multi-bench.yaml \
  -f overrides/compose.multi-bench-ssl.yaml config > "$GITOPS_DIR/${PROJECT_NAME}.yaml"

echo "  -> Đang khởi chạy Stack $PROJECT_NAME..."
docker compose -p "$PROJECT_NAME" -f "$GITOPS_DIR/${PROJECT_NAME}.yaml" up -d
echo "[✓] Deploy Stack $PROJECT_NAME thành công."

# ------------------------------------------------------------------------------
# Bước 12: Tạo Site và Cài đặt các Custom Apps
# ------------------------------------------------------------------------------
echo ""
echo "[BƯỚC 12/12] Khởi tạo Frappe Site ($SITE_DOMAIN) & Cài đặt các Custom Apps..."

echo "  -> Đang chờ Backend Container ổn định (10s)..."
sleep 10

INSTALL_APP_FLAGS=""
for app in $CUSTOM_APP_NAMES; do
  INSTALL_APP_FLAGS="$INSTALL_APP_FLAGS --install-app $app"
done

echo "  -> Thực thi lệnh bench new-site với các app: $CUSTOM_APP_NAMES..."
docker compose --project-name "$PROJECT_NAME" exec backend \
  bench new-site "$SITE_DOMAIN" \
  --mariadb-user-host-login-scope=% \
  --db-root-password "$DB_ROOT_PASSWORD" \
  --admin-password "$FRAPPE_ADMIN_PASSWORD" \
  $INSTALL_APP_FLAGS

# Phân quyền lại thư mục cho REAL_USER nếu script chạy dưới sudo
if [ -n "$REAL_USER" ] && [ "$REAL_USER" != "root" ]; then
    chown -R "$REAL_USER:$REAL_USER" "$SMRS_DIR" "$GITOPS_DIR" 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# BÁO CÁO TỔNG HỢP KẾT QUẢ THỰC THI
# ------------------------------------------------------------------------------
echo ""
echo "================================================================================"
echo "                  BÁO CÁO KẾT QUẢ TRIỂN KHAI SMRS PACK                          "
echo "================================================================================"
echo " [✓] BƯỚC 1 : Xác thực quyền Root & Môi trường ($REAL_USER)"
echo " [✓] BƯỚC 2 : Load file cấu hình .env ($ENV_FILE)"
echo " [✓] BƯỚC 3 : Cập nhật hệ thống APT thành công"
echo " [✓] BƯỚC 4 : Kiểm tra & cài đặt Prerequisites (Git, Docker, Compose v2)"
echo " [✓] BƯỚC 5 : Khởi tạo thư mục $SMRS_DIR và $GITOPS_DIR"
echo " [✓] BƯỚC 6 : Đã chuẩn bị repository frappe_docker"
echo " [✓] BƯỚC 7 : Đã xuất file apps.json với các custom app"
echo " [✓] BƯỚC 8 : Build thành công Docker Image: $CUSTOM_IMAGE_TAG"
echo " [✓] BƯỚC 9 : Traefik Reverse Proxy SSL đã hoạt động (Email: $LETSENCRYPT_EMAIL)"
echo " [✓] BƯỚC 10: MariaDB Shared Database đã khởi chạy"
echo " [✓] BƯỚC 11: Project Stack '$PROJECT_NAME' đã được deploy"
echo " [✓] BƯỚC 12: Đã tạo Site '$SITE_DOMAIN' & Cài đặt xong app ($CUSTOM_APP_NAMES)"
echo "================================================================================"
echo " THÔNG TIN TRUY CẬP HỆ THỐNG:"
echo "  - Trang web chính  : https://$SITE_DOMAIN"
echo "  - Tài khoản Admin  : Administrator"
echo "  - Mật khẩu Admin   : $FRAPPE_ADMIN_PASSWORD"
echo "================================================================================"
