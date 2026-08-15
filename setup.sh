#!/bin/bash
set -e

# Cấu hình tự động hoàn toàn (bỏ qua tất cả các hộp thoại tương tác như debconf / dpkg)
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
APT_CMD="apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

# ==============================================================================
# Frappe Packaging & Deployment Automation Script (Interactive Step Menu)
# ==============================================================================

# Lưu đường dẫn gốc của thư mục chứa script ngay khi bắt đầu (trước mọi lệnh cd)
INITIAL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Khai báo các tên bước
STEP_NAMES=(
    "" # Step 0 index unused
    "Kiểm tra quyền Root/Sudo & Môi trường"
    "Kiểm tra & Đọc file cấu hình .env"
    "Cập nhật danh sách gói tin APT hệ thống"
    "Cài đặt công cụ cần thiết (Git, Docker, Compose v2)"
    "Khởi tạo thư mục làm việc (~/frappe-packaging, ~/gitops)"
    "Clone / Kiểm tra repository frappe_docker"
    "Khởi tạo file secret apps.json"
    "Build Custom Docker Image"
    "Khởi chạy Traefik Proxy & Cloudflare Tunnel"
    "Khởi chạy MariaDB Shared Database"
    "Deploy Project Stack"
    "Khởi tạo Site & Cài đặt các Custom Apps"
)

# ------------------------------------------------------------------------------
# 1. HÀM NẠP / KIỂM TRA MÔI TRƯỜNG BAN ĐẦU
# ------------------------------------------------------------------------------
init_env_vars() {
    if [ "$EUID" -ne 0 ]; then
        echo "[!] Script này yêu cầu quyền root/sudo."
        echo "[*] Đang tự động chuyển đổi sang quyền sudo..."
        exec sudo bash "$0" "$@"
    fi

    REAL_USER="${SUDO_USER:-$USER}"
    REAL_HOME=$(eval echo "~$REAL_USER")
    SMRS_DIR="$REAL_HOME/frappe-packaging"
    GITOPS_DIR="$REAL_HOME/gitops"

    # Tìm file .env nếu chưa được lưu hoặc đường dẫn không khả dụng
    if [ -z "$ENV_FILE" ] || [ ! -f "$ENV_FILE" ]; then
        POSSIBLE_ENV_PATHS=(
            "$INITIAL_SCRIPT_DIR/.env"
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
    fi

    if [ -n "$ENV_FILE" ] && [ -f "$ENV_FILE" ]; then
        set -o allexport
        source "$ENV_FILE" 2>/dev/null || true
        set +o allexport
    fi

    USE_CLOUDFLARE_TUNNEL="${USE_CLOUDFLARE_TUNNEL:-false}"
    FRAPPE_BRANCH="${FRAPPE_BRANCH:-version-15}"
    CUSTOM_IMAGE_TAG="${CUSTOM_IMAGE_TAG:-frappe-custom-image:latest}"
    LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-admin@$SITE_DOMAIN}"
}

# ------------------------------------------------------------------------------
# 2. HÀM KIỂM TRA TRẠNG THÁI HOÀN THÀNH CỦA TỪNG BƯỚC (CONDITION CHECKERS)
# ------------------------------------------------------------------------------
is_step_completed() {
    local step_num="$1"
    case "$step_num" in
        1)
            [ "$EUID" -eq 0 ] && [ -n "$REAL_USER" ]
            ;;
        2)
            [ -n "$ENV_FILE" ] && [ -f "$ENV_FILE" ] && [ -n "$PROJECT_NAME" ] && [ -n "$SITE_DOMAIN" ] && [ -n "$APPS_JSON" ]
            ;;
        3)
            [ -f "$GITOPS_DIR/.apt_updated" ] || command -v git &>/dev/null
            ;;
        4)
            command -v git &>/dev/null && command -v docker &>/dev/null && docker compose version &>/dev/null
            ;;
        5)
            [ -d "$SMRS_DIR" ] && [ -d "$GITOPS_DIR" ]
            ;;
        6)
            [ -d "$SMRS_DIR/frappe_docker/.git" ]
            ;;
        7)
            [ -f "$SMRS_DIR/frappe_docker/apps.json" ]
            ;;
        8)
            [ -n "$CUSTOM_IMAGE_TAG" ] && docker image inspect "$CUSTOM_IMAGE_TAG" &>/dev/null
            ;;
        9)
            if [ "$USE_CLOUDFLARE_TUNNEL" = "true" ]; then
                docker compose -p traefik ps --services 2>/dev/null | grep -q traefik && docker compose -p tunnel ps --services 2>/dev/null | grep -q cloudflared
            else
                docker compose -p traefik ps --services 2>/dev/null | grep -q traefik
            fi
            ;;
        10)
            docker compose -p mariadb ps --services 2>/dev/null | grep -q mariadb
            ;;
        11)
            [ -f "$GITOPS_DIR/${PROJECT_NAME}.yaml" ] && docker compose -p "$PROJECT_NAME" ps --services 2>/dev/null | grep -q backend
            ;;
        12)
            [ -n "$PROJECT_NAME" ] && [ -n "$SITE_DOMAIN" ] && docker compose -p "$PROJECT_NAME" exec -T backend bench list-sites 2>/dev/null | grep -q "$SITE_DOMAIN"
            ;;
        *)
            return 1
            ;;
    esac
}

# ------------------------------------------------------------------------------
# 3. HÀM KIỂM TRA ĐIỀU KIỆN TIỀN ĐỀ TRƯỚC KHÍ CHẠY MỘT BƯỚC (PREREQUISITE CHECK)
# ------------------------------------------------------------------------------
validate_prerequisites_for_step() {
    local target_step="$1"
    
    # Bước 1 không có tiền đề
    if [ "$target_step" -le 1 ]; then
        return 0
    fi

    # Kiểm tra tất cả các bước trước đó từ 1 đến (target_step - 1)
    for (( i=1; i<target_step; i++ )); do
        if ! is_step_completed "$i"; then
            echo ""
            echo "================================================================================"
            echo "[!] LỖI TIỀN ĐỀ: KHÔNG THỂ THỰC HIỆN BƯỚC $target_step!"
            echo "================================================================================"
            echo " -> Bước $target_step (${STEP_NAMES[$target_step]}) yêu cầu Bước $i phải hoàn thành trước."
            echo " -> Chưa hoàn thành Bước $i: ${STEP_NAMES[$i]}"
            echo "--------------------------------------------------------------------------------"
            echo "[*] GỢI Ý: Vui lòng chọn và chạy BƯỚC $i từ menu trước khi chạy Bước $target_step."
            echo "================================================================================"
            echo ""
            return 1
        fi
    done
    return 0
}

# ------------------------------------------------------------------------------
# 4. ĐỊNH NGHĨA CÁC HÀM THỰC THI CHO TỪNG BƯỚC (STEP FUNCTIONS)
# ------------------------------------------------------------------------------

run_step_1() {
    echo ""
    echo "[BƯỚC 1/12] Kiểm tra quyền Root/Sudo & Khai báo môi trường..."
    init_env_vars
    echo "  -> Target User     : $REAL_USER"
    echo "  -> Home Directory  : $REAL_HOME"
    echo "  -> Work Directory  : $SMRS_DIR"
    echo "  -> GitOps Directory: $GITOPS_DIR"
    echo "[✓] Bước 1 hoàn tất."
}

run_step_2() {
    echo ""
    echo "[BƯỚC 2/12] Kiểm tra & Đọc file cấu hình .env..."
    if [ -z "$ENV_FILE" ]; then
        echo "[!] LỖI BÁO ĐỘNG: Không tìm thấy file cấu hình .env!"
        echo "[*] Vui lòng sao chép file example.env thành .env và khai báo thông số trước khi chạy."
        return 1
    fi

    set -o allexport
    source "$ENV_FILE"
    set +o allexport

    REQUIRED_VARS=("APPS_JSON" "CUSTOM_APP_NAMES" "SITE_DOMAIN" "PROJECT_NAME" "DB_ROOT_PASSWORD" "FRAPPE_ADMIN_PASSWORD")
    for var in "${REQUIRED_VARS[@]}"; do
        if [ -z "${!var}" ]; then
            echo "[!] LỖI: Biến bắt buộc '$var' chưa được định nghĩa trong .env!"
            return 1
        fi
    done

    USE_CLOUDFLARE_TUNNEL="${USE_CLOUDFLARE_TUNNEL:-false}"
    if [ "$USE_CLOUDFLARE_TUNNEL" = "true" ] && [ -z "$CLOUDFLARE_TUNNEL_TOKEN" ]; then
        echo "[!] LỖI: Chế độ Cloudflare Tunnel đang bật nhưng 'CLOUDFLARE_TUNNEL_TOKEN' chưa được khai báo!"
        return 1
    fi

    echo "  -> File .env        : $ENV_FILE"
    echo "  -> Project Name     : $PROJECT_NAME"
    echo "  -> Site Domain      : $SITE_DOMAIN"
    echo "  -> Custom Apps      : $CUSTOM_APP_NAMES"
    echo "  -> Mode Tunnel      : $USE_CLOUDFLARE_TUNNEL"
    echo "[✓] Bước 2 hoàn tất."
}

run_step_3() {
    echo ""
    echo "[BƯỚC 3/12] Cập nhật danh sách gói tin & nâng cấp hệ thống (APT Update & Upgrade)..."
    killall -9 apt apt-get 2>/dev/null || true
    rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock
    dpkg --configure -a || true

    apt-get update -y && $APT_CMD upgrade
    mkdir -p "$GITOPS_DIR"
    touch "$GITOPS_DIR/.apt_updated"
    echo "[✓] Bước 3 hoàn tất."
}

run_step_4() {
    echo ""
    echo "[BƯỚC 4/12] Kiểm tra và cài đặt công cụ cần thiết (Git, Docker Engine v23.0+, Docker Compose v2)..."
    if ! command -v git &> /dev/null; then
        echo "  -> Đang cài đặt Git..."
        $APT_CMD install git
    else
        echo "  -> Git đã sẵn sàng: $(git --version)"
    fi

    HAS_DOCKER=false
    if command -v docker &> /dev/null && docker compose version &> /dev/null; then
        echo "  -> Docker & Docker Compose v2 đã sẵn sàng: $(docker compose version)"
        HAS_DOCKER=true
    fi

    if [ "$HAS_DOCKER" = false ]; then
        echo "  -> Đang cài đặt Docker Engine & Docker Compose v2 từ repository chính thức..."
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
    echo "[✓] Bước 4 hoàn tất."
}

run_step_5() {
    echo ""
    echo "[BƯỚC 5/12] Khởi tạo các thư mục lưu trữ dự án ($SMRS_DIR & $GITOPS_DIR)..."
    mkdir -p "$SMRS_DIR"
    mkdir -p "$GITOPS_DIR"
    echo "  -> Đã khởi tạo thư mục: $SMRS_DIR"
    echo "  -> Đã khởi tạo thư mục: $GITOPS_DIR"
    echo "[✓] Bước 5 hoàn tất."
}

run_step_6() {
    echo ""
    echo "[BƯỚC 6/12] Chuẩn bị repository frappe_docker..."
    if [ -d "$SMRS_DIR/frappe_docker/.git" ]; then
        echo "  -> Thư mục frappe_docker đã tồn tại. Bỏ qua bước clone."
    else
        echo "  -> Đang clone repository https://github.com/frappe/frappe_docker..."
        git clone https://github.com/frappe/frappe_docker "$SMRS_DIR/frappe_docker"
    fi
    cd "$SMRS_DIR/frappe_docker"
    echo "[✓] Bước 6 hoàn tất."
}

run_step_7() {
    echo ""
    echo "[BƯỚC 7/12] Khởi tạo file cấu hình secret apps.json..."
    cd "$SMRS_DIR/frappe_docker"
    echo "$APPS_JSON" > "$SMRS_DIR/frappe_docker/apps.json"
    echo "  -> Nội dung apps.json:"
    cat "$SMRS_DIR/frappe_docker/apps.json" | sed 's/^/     /'
    echo "[✓] Bước 7 hoàn tất."
}

run_step_8() {
    echo ""
    echo "[BƯỚC 8/12] Build Custom Docker Image ($CUSTOM_IMAGE_TAG)..."
    cd "$SMRS_DIR/frappe_docker"
    echo "  -> Quá trình build image bắt đầu (Frappe branch: $FRAPPE_BRANCH)..."
    docker build \
      --build-arg=FRAPPE_PATH=https://github.com/frappe/frappe \
      --build-arg=FRAPPE_BRANCH="$FRAPPE_BRANCH" \
      --build-arg=CACHE_BUST="$(date +%s)" \
      --secret=id=apps_json,src=apps.json \
      --tag="$CUSTOM_IMAGE_TAG" \
      --file=images/layered/Containerfile .
    echo "[✓] Bước 8 hoàn tất."
}

run_step_9() {
    echo ""
    echo "[BƯỚC 9/12] Cấu hình Proxy và Tunnel (Mode Cloudflare Tunnel: $USE_CLOUDFLARE_TUNNEL)..."
    cd "$SMRS_DIR/frappe_docker"
    if [ "$USE_CLOUDFLARE_TUNNEL" = "true" ]; then
        echo "  -> Khởi chạy Traefik ở chế độ HTTP nội bộ..."
        cat <<EOF > "$GITOPS_DIR/traefik.yaml"
version: "3.8"
services:
  traefik:
    image: traefik:v3.6
    container_name: traefik
    restart: unless-stopped
    command:
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --entrypoints.http.address=:80
      - --accesslog
      - --log
    ports:
      - ${HTTP_PUBLISH_PORT:-80}:80
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - traefik-public

networks:
  traefik-public:
    name: traefik-public
    external: false
EOF
        docker compose --project-name traefik -f "$GITOPS_DIR/traefik.yaml" up -d

        echo "  -> Khởi tạo Cloudflare Tunnel container (cloudflared)..."
        cat <<EOF > "$GITOPS_DIR/cloudflared.yaml"
version: "3.8"
services:
  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflared
    restart: unless-stopped
    command: tunnel --no-autoupdate run
    environment:
      - TUNNEL_TOKEN=$CLOUDFLARE_TUNNEL_TOKEN
    networks:
      - traefik-public

networks:
  traefik-public:
    external: true
EOF
        docker compose --project-name tunnel -f "$GITOPS_DIR/cloudflared.yaml" up -d
        echo "[✓] Traefik HTTP và Cloudflare Tunnel đã chạy."
    else
        echo "  -> Khởi chạy Traefik với SSL Let's Encrypt..."
        cat <<EOF > "$GITOPS_DIR/traefik.yaml"
version: "3.8"
services:
  traefik:
    image: traefik:v3.6
    container_name: traefik
    restart: unless-stopped
    command:
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --entrypoints.http.address=:80
      - --entrypoints.http.http.redirections.entrypoint.to=https
      - --entrypoints.http.http.redirections.entrypoint.scheme=https
      - --entrypoints.https.address=:443
      - --certificatesresolvers.le.acme.email=$LETSENCRYPT_EMAIL
      - --certificatesresolvers.le.acme.storage=/certificates/acme.json
      - --certificatesresolvers.le.acme.httpchallenge=true
      - --certificatesresolvers.le.acme.httpchallenge.entrypoint=http
      - --accesslog
      - --log
    ports:
      - ${HTTP_PUBLISH_PORT:-80}:80
      - ${HTTPS_PUBLISH_PORT:-443}:443
    volumes:
      - cert-data:/certificates
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - traefik-public

volumes:
  cert-data:

networks:
  traefik-public:
    name: traefik-public
    external: false
EOF
        docker compose --project-name traefik -f "$GITOPS_DIR/traefik.yaml" up -d
        echo "[✓] Traefik Reverse Proxy & SSL đã chạy."
    fi
    echo "[✓] Bước 9 hoàn tất."
}

run_step_10() {
    echo ""
    echo "[BƯỚC 10/12] Cấu hình và khởi chạy MariaDB Database dùng chung..."
    cd "$SMRS_DIR/frappe_docker"
    cat <<EOF > "$GITOPS_DIR/mariadb.env"
DB_PASSWORD=$DB_ROOT_PASSWORD
EOF
    docker compose --project-name mariadb \
      --env-file "$GITOPS_DIR/mariadb.env" \
      -f overrides/compose.mariadb-shared.yaml up -d
    echo "[✓] Bước 10 hoàn tất."
}

run_step_11() {
    echo ""
    echo "[BƯỚC 11/12] Tạo cấu hình & Deploy Project Stack ($PROJECT_NAME)..."
    cd "$SMRS_DIR/frappe_docker"

    cat <<EOF > "$GITOPS_DIR/${PROJECT_NAME}.env"
BACKEND_IMAGE=$CUSTOM_IMAGE_TAG
FRONTEND_IMAGE=$CUSTOM_IMAGE_TAG
ROUTER=${PROJECT_NAME}-router
SITES_RULE=Host(\`$SITE_DOMAIN\`)
EOF

    echo "  -> Đang sinh file cấu hình tổng hợp $GITOPS_DIR/${PROJECT_NAME}.yaml..."
    if [ "$USE_CLOUDFLARE_TUNNEL" = "true" ]; then
        docker compose --project-name "$PROJECT_NAME" \
          --env-file "$GITOPS_DIR/${PROJECT_NAME}.env" \
          -f compose.yaml \
          -f overrides/compose.redis.yaml \
          -f overrides/compose.multi-bench.yaml config > "$GITOPS_DIR/${PROJECT_NAME}.yaml"
    else
        docker compose --project-name "$PROJECT_NAME" \
          --env-file "$GITOPS_DIR/${PROJECT_NAME}.env" \
          -f compose.yaml \
          -f overrides/compose.redis.yaml \
          -f overrides/compose.multi-bench.yaml \
          -f overrides/compose.multi-bench-ssl.yaml config > "$GITOPS_DIR/${PROJECT_NAME}.yaml"
    fi

    docker compose -p "$PROJECT_NAME" -f "$GITOPS_DIR/${PROJECT_NAME}.yaml" up -d
    echo "[✓] Bước 11 hoàn tất."
}

run_step_12() {
    echo ""
    echo "[BƯỚC 12/12] Khởi tạo Frappe Site ($SITE_DOMAIN) & Cài đặt các Custom Apps..."
    echo "  -> Chờ backend container sẵn sàng (10s)..."
    sleep 10

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

    if [ -n "$REAL_USER" ] && [ "$REAL_USER" != "root" ]; then
        chown -R "$REAL_USER:$REAL_USER" "$SMRS_DIR" "$GITOPS_DIR" 2>/dev/null || true
    fi
    echo "[✓] Bước 12 hoàn tất."
}

# ------------------------------------------------------------------------------
# 5. HÀM THỰC THI MỘT BƯỚC ĐƯỢC CHỌN (KÈM CHECK TIỀN ĐỀ)
# ------------------------------------------------------------------------------
execute_single_step() {
    local step_num="$1"
    
    if [ "$step_num" -lt 1 ] || [ "$step_num" -gt 12 ]; then
        echo "[!] Lỗi: Số bước không hợp lệ ($step_num)."
        return 1
    fi

    # Đảm bảo nạp môi trường
    init_env_vars

    # Kiểm tra xem các bước trước đã làm xong chưa
    if ! validate_prerequisites_for_step "$step_num"; then
        return 1
    fi

    # Thực thi bước được chọn
    "run_step_$step_num"
}

# ------------------------------------------------------------------------------
# 6. HÀM THỰC THI TOÀN BỘ WORKFLOW (TỪ BƯỚC 1 ĐẾN 12)
# ------------------------------------------------------------------------------
run_all_steps() {
    echo ""
    echo "================================================================================"
    echo "         BẮT ĐẦU CHẠY TOÀN BỘ WORKFLOW (BƯỚC 1 ĐẾN BƯỚC 12)                    "
    echo "================================================================================"
    
    init_env_vars
    for i in {1..12}; do
        "run_step_$i"
    done

    echo ""
    echo "================================================================================"
    echo "               BÁO CÁO KẾT QUẢ TRIỂN KHAI FRAPPE PACKAGING                      "
    echo "================================================================================"
    echo " [✓] BƯỚC 1 : Xác thực quyền Root & Môi trường ($REAL_USER)"
    echo " [✓] BƯỚC 2 : Load file cấu hình .env ($ENV_FILE)"
    echo " [✓] BƯỚC 3 : Cập nhật hệ thống APT thành công"
    echo " [✓] BƯỚC 4 : Kiểm tra & cài đặt Prerequisites (Git, Docker, Compose v2)"
    echo " [✓] BƯỚC 5 : Khởi tạo thư mục $SMRS_DIR và $GITOPS_DIR"
    echo " [✓] BƯỚC 6 : Đã chuẩn bị repository frappe_docker"
    echo " [✓] BƯỚC 7 : Đã xuất file apps.json với các custom app"
    echo " [✓] BƯỚC 8 : Build thành công Docker Image: $CUSTOM_IMAGE_TAG"
    echo " [✓] BƯỚC 9 : Khởi chạy Proxy / Cloudflare Tunnel thành công"
    echo " [✓] BƯỚC 10: MariaDB Shared Database đã khởi chạy"
    echo " [✓] BƯỚC 11: Project Stack '$PROJECT_NAME' đã được deploy"
    echo " [✓] BƯỚC 12: Đã tạo Site '$SITE_DOMAIN' & Cài đặt xong app ($CUSTOM_APP_NAMES)"
    echo "================================================================================"
    echo " THÔNG TIN TRUY CẬP HỆ THỐNG:"
    echo "  - Trang web chính  : https://$SITE_DOMAIN"
    echo "  - Chế độ triển khai: $([ "$USE_CLOUDFLARE_TUNNEL" = "true" ] && echo "Cloudflare Tunnel" || echo "Direct Domain Traefik SSL")"
    echo "  - Tài khoản Admin  : Administrator"
    echo "  - Mật khẩu Admin   : $FRAPPE_ADMIN_PASSWORD"
    echo "================================================================================"
}

# ------------------------------------------------------------------------------
# 7. HÀM HIỂN THỊ TRẠNG THÁI TỔNG QUAN (HEALTH CHECK STATUS)
# ------------------------------------------------------------------------------
show_status_check() {
    init_env_vars
    echo ""
    echo "================================================================================"
    echo "              BẢNG KIỂM TRA TRẠNG THÁI CÁC BƯỚC (HEALTH CHECK)                  "
    echo "================================================================================"
    for i in {1..12}; do
        if is_step_completed "$i"; then
            echo -e "  Bước $(printf "%2d" $i): [✓ HOÀN THÀNH] - ${STEP_NAMES[$i]}"
        else
            echo -e "  Bước $(printf "%2d" $i): [  CHƯA LÀM  ] - ${STEP_NAMES[$i]}"
        fi
    done
    echo "================================================================================"
    echo ""
}

# ------------------------------------------------------------------------------
# 8. HÀM DỪNG & XÓA TOÀN BỘ HỆ THỐNG DOCKER (TEARDOWN & CLEANUP)
# ------------------------------------------------------------------------------
teardown_all_containers() {
    init_env_vars
    echo ""
    echo "================================================================================"
    echo "⚠️  CẢNH BÁO NGUY HIỂM: XOÁ & DỪNG TOÀN BỘ HỆ THỐNG (TEARDOWN / CLEANUP)"
    echo "================================================================================"
    echo " Hành động này sẽ thực hiện:"
    echo "  1. Dừng & XÓA tất cả Container Docker ($PROJECT_NAME, mariadb, traefik, cloudflared)"
    echo "  2. XÓA các Docker Volume chứa dữ liệu (Bao gồm Database MariaDB và Frappe Sites)"
    echo "  3. XÓA các Docker Network khởi tạo bởi các stack dự án"
    echo "  4. Dọn dẹp các file cấu hình triển khai trong thư mục $GITOPS_DIR"
    echo "  5. XÓA HOÀN TOÀN thư mục làm việc $SMRS_DIR (chứa repo frappe_docker đã clone) và thư mục $GITOPS_DIR"
    echo "--------------------------------------------------------------------------------"
    echo " ℹ️  GIỮ LẠI (Không bị xóa):"
    echo "  - File cấu hình gốc .env của bạn"
    echo "--------------------------------------------------------------------------------"
    echo " ❗ LƯU Ý: DỮ LIỆU SITE, DATABASE VÀ TOÀN BỘ THƯ MỤC CẤU HÌNH SẼ BỊ XÓA VĨNH VIỄN!"
    echo "================================================================================"
    read -p "Bạn có CHẮC CHẮN muốn tiếp tục xóa không? (Gõ 'YES' hoặc 'y' để đồng ý): " confirm

    if [ "$confirm" = "YES" ] || [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        echo ""
        echo "[*] Đang tiến hành dọn dẹp và dừng hệ thống Docker..."

        # Dừng & Xóa Project Stack ($PROJECT_NAME)
        if [ -n "$PROJECT_NAME" ] && [ -f "$GITOPS_DIR/${PROJECT_NAME}.yaml" ]; then
            echo "  -> Đang dừng & xóa Project Stack ($PROJECT_NAME)..."
            docker compose -p "$PROJECT_NAME" -f "$GITOPS_DIR/${PROJECT_NAME}.yaml" down -v --remove-orphans 2>/dev/null || true
        fi

        # Dừng & Xóa Cloudflare Tunnel (nếu có)
        if [ -f "$GITOPS_DIR/cloudflared.yaml" ]; then
            echo "  -> Đang dừng & xóa Cloudflare Tunnel container..."
            docker compose -p tunnel -f "$GITOPS_DIR/cloudflared.yaml" down -v --remove-orphans 2>/dev/null || true
        fi

        # Dừng & Xóa MariaDB Shared
        echo "  -> Đang dừng & xóa MariaDB Shared Database..."
        if [ -d "$SMRS_DIR/frappe_docker" ]; then
            cd "$SMRS_DIR/frappe_docker" 2>/dev/null || true
        fi
        if [ -f "$GITOPS_DIR/mariadb.env" ]; then
            docker compose --project-name mariadb --env-file "$GITOPS_DIR/mariadb.env" -f overrides/compose.mariadb-shared.yaml down -v --remove-orphans 2>/dev/null || true
        fi

        # Dừng & Xóa Traefik Proxy
        echo "  -> Đang dừng & xóa Traefik Proxy..."
        if [ -f "$GITOPS_DIR/traefik.yaml" ]; then
            docker compose --project-name traefik -f "$GITOPS_DIR/traefik.yaml" down -v --remove-orphans 2>/dev/null || true
        elif [ -f "$GITOPS_DIR/traefik.env" ]; then
            docker compose --project-name traefik --env-file "$GITOPS_DIR/traefik.env" -f overrides/compose.proxy.yaml -f overrides/compose.https.yaml down -v --remove-orphans 2>/dev/null || true
        else
            docker compose --project-name traefik -f overrides/compose.proxy.yaml down -v --remove-orphans 2>/dev/null || true
        fi

        # Xóa toàn bộ thư mục làm việc $SMRS_DIR và $GITOPS_DIR
        echo "  -> Đang xóa thư mục làm việc $SMRS_DIR (chứa repo frappe_docker)..."
        if [ -n "$SMRS_DIR" ] && [ "$SMRS_DIR" != "/" ] && [ "$SMRS_DIR" != "$REAL_HOME" ]; then
            rm -rf "$SMRS_DIR" 2>/dev/null || true
        fi

        echo "  -> Đang xóa thư mục cấu hình $GITOPS_DIR..."
        if [ -n "$GITOPS_DIR" ] && [ "$GITOPS_DIR" != "/" ] && [ "$GITOPS_DIR" != "$REAL_HOME" ]; then
            rm -rf "$GITOPS_DIR" 2>/dev/null || true
        fi

        echo "[✓] Đã dọn dẹp và xóa sạch toàn bộ hệ thống Docker cùng thư mục làm việc!"
    else
        echo "[*] Đã hủy thao tác xóa. Không có dữ liệu nào bị thay đổi."
    fi
}

# ------------------------------------------------------------------------------
# 9. HÀM CHỈNH SỬA SITE_CONFIG.JSON HOẶC COMMON_SITE_CONFIG.JSON (EDIT CONFIG)
# ------------------------------------------------------------------------------
edit_site_config() {
    init_env_vars
    echo ""
    echo "================================================================================"
    echo "       🛠️  CHỈNH SỬA CẤU HÌNH SITE_CONFIG.JSON / COMMON_SITE_CONFIG.JSON        "
    echo "================================================================================"

    # Tìm Docker Volume thích hợp
    VOLUME_NAME="${PROJECT_NAME}_sites"
    if ! docker volume inspect "$VOLUME_NAME" &>/dev/null; then
        if docker volume inspect "sites" &>/dev/null; then
            VOLUME_NAME="sites"
        elif docker volume inspect "${PROJECT_NAME}-sites" &>/dev/null; then
            VOLUME_NAME="${PROJECT_NAME}-sites"
        fi
    fi

    if ! docker volume inspect "$VOLUME_NAME" &>/dev/null; then
        echo "[!] LỖI: Không tìm thấy Docker Volume lưu trữ sites ('$VOLUME_NAME')."
        echo "[*] Gợi ý: Vui lòng chạy Bước 11 (Deploy Project Stack) trước khi chỉnh sửa cấu hình."
        return 1
    fi

    echo " Chọn file cấu hình cần chỉnh sửa:"
    echo "  [ 1 ] site_config.json (Cấu hình riêng của site: ${SITE_DOMAIN:-N/A})"
    echo "  [ 2 ] common_site_config.json (Cấu hình chung toàn Bench: DB Host, Redis...)"
    echo "  [ 3 ] Nhập tên site khác"
    read -p "Nhập lựa chọn của bạn [1/2/3]: " file_choice

    local target_path=""
    local target_site=""
    case "$file_choice" in
        1)
            if [ -z "$SITE_DOMAIN" ]; then
                echo "[!] Lỗi: Biến SITE_DOMAIN chưa được khai báo."
                return 1
            fi
            target_site="$SITE_DOMAIN"
            target_path="${SITE_DOMAIN}/site_config.json"
            ;;
        2)
            target_site="$SITE_DOMAIN"
            target_path="common_site_config.json"
            ;;
        3)
            read -p "Nhập tên site (ví dụ: erp.domain.com): " custom_site
            if [ -z "$custom_site" ]; then
                echo "[!] Tên site không được để trống."
                return 1
            fi
            target_site="$custom_site"
            target_path="${custom_site}/site_config.json"
            ;;
        *)
            echo "[!] Lựa chọn không hợp lệ."
            return 1
            ;;
    esac

    echo ""
    echo " Chọn trình soạn thảo văn bản:"
    echo "  [ 1 ] nano (Khuyên dùng - dễ thao tác & lưu file)"
    echo "  [ 2 ] vi / vim"
    read -p "Nhập lựa chọn của bạn [1/2]: " editor_choice

    echo ""
    echo "[*] Đang mở file /sites/$target_path trong Docker Volume '$VOLUME_NAME'..."
    if [ "$editor_choice" = "2" ]; then
        docker run --rm -it \
          -v "$VOLUME_NAME:/sites" \
          alpine vi "/sites/$target_path"
    else
        docker run --rm -it \
          -v "$VOLUME_NAME:/sites" \
          alpine sh -c "apk add --no-cache nano && nano /sites/$target_path"
    fi

    echo "[✓] Đã kết thúc phiên chỉnh sửa file cấu hình."

    echo ""
    read -p "Bạn có muốn xóa cache (clear-cache) và restart backend container để áp dụng thay đổi không? [Y/n]: " reload_choice
    if [ "$reload_choice" != "n" ] && [ "$reload_choice" != "N" ]; then
        echo "  -> Đang xóa cache..."
        if [ -n "$target_site" ]; then
            docker compose -p "$PROJECT_NAME" exec backend bench --site "$target_site" clear-cache 2>/dev/null || true
        fi
        echo "  -> Đang restart backend container..."
        docker compose -p "$PROJECT_NAME" restart backend 2>/dev/null || true
        echo "[✓] Đã xóa cache và khởi động lại backend thành công!"
    fi
}

# ------------------------------------------------------------------------------
# 10. MENU TƯƠNG TÁC CHÍNH (INTERACTIVE MENU)
# ------------------------------------------------------------------------------
show_menu() {
    init_env_vars
    while true; do
        echo ""
        echo "================================================================================"
        echo "           MENU ĐIỀU KHIỂN & KIỂM TRA QUY TRÌNH FRAPPE PACKAGING                "
        echo "================================================================================"
        echo " Môi trường hiện tại:"
        echo "  - User: ${REAL_USER:-N/A} | Project: ${PROJECT_NAME:-N/A} | Domain: ${SITE_DOMAIN:-N/A}"
        echo "--------------------------------------------------------------------------------"
        echo "  [ 0 ] 🚀 Chạy TOÀN BỘ Workflow (Từ Bước 1 đến Bước 12)"
        echo "--------------------------------------------------------------------------------"
        for i in {1..12}; do
            local status_symbol=" "
            if is_step_completed "$i"; then
                status_symbol="✓"
            fi
            printf "  [%2d ] [%s] Bước %2d: %s\n" "$i" "$status_symbol" "$i" "${STEP_NAMES[$i]}"
        done
        echo "--------------------------------------------------------------------------------"
        echo "  [ K  ] 🔍 Kiểm tra chi tiết trạng thái tất cả các bước (Health Check)"
        echo "  [ E  ] 📝 Chỉnh sửa site_config.json / common_site_config.json (nano / vi)"
        echo "  [ D  ] 🗑️  Xóa & Dừng TOÀN BỘ hệ thống Docker (Teardown & Clean up)"
        echo "  [ Q  ] ❌ Thoát menu"
        echo "================================================================================"
        read -p "Nhập lựa chọn của bạn [0-12 / K / E / D / Q]: " choice

        case "$choice" in
            0)
                run_all_steps
                ;;
            1|2|3|4|5|6|7|8|9|10|11|12)
                execute_single_step "$choice" || true
                ;;
            k|K)
                show_status_check
                ;;
            e|E)
                edit_site_config
                ;;
            d|D)
                teardown_all_containers
                ;;
            q|Q)
                echo "Thoát chương trình. Tạm biệt!"
                exit 0
                ;;
            *)
                echo "[!] Lựa chọn không hợp lệ. Vui lòng nhập từ 0 đến 12, K, E, D hoặc Q."
                ;;
        esac
        
        echo ""
        read -p "Nhấn [Enter] để tiếp tục..." dummy
    done
}

# ------------------------------------------------------------------------------
# MAIN ENTRY POINT
# ------------------------------------------------------------------------------
init_env_vars

# Hỗ trợ truyền tham số qua dòng lệnh (CLI flags)
if [ "$1" = "--all" ] || [ "$1" = "all" ] || [ "$1" = "0" ]; then
    run_all_steps
elif [ "$1" = "--step" ] && [ -n "$2" ]; then
    execute_single_step "$2"
elif [[ "$1" =~ ^[1-9]$|^1[0-2]$ ]]; then
    execute_single_step "$1"
elif [ "$1" = "--check" ] || [ "$1" = "check" ] || [ "$1" = "k" ]; then
    show_status_check
elif [ "$1" = "--edit" ] || [ "$1" = "edit" ] || [ "$1" = "e" ]; then
    edit_site_config
elif [ "$1" = "--down" ] || [ "$1" = "down" ] || [ "$1" = "d" ]; then
    teardown_all_containers
else
    # Không truyền tham số -> Mở Menu tương tác
    show_menu
fi

