#!/bin/bash
set -e

# Cấu hình tự động hoàn toàn (bỏ qua tất cả các hộp thoại tương tác như debconf / dpkg)
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
APT_CMD="apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

# ==============================================================================
# Script setup SMRS Pack & Prerequisites
# Đường dẫn: /home/baucan/scripts/setup_smrs.sh
# ==============================================================================

# 1. Yêu cầu quyền sudo / root
if [ "$EUID" -ne 0 ]; then
    echo "[!] Script này yêu cầu quyền root/sudo."
    echo "[*] Đang tự động chạy lại script với sudo..."
    exec sudo bash "$0" "$@"
fi

# Xác định user thực tế (nếu chạy qua sudo) và thư mục home tương ứng
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")
SMRS_DIR="$REAL_HOME/smrs-pack"

echo "=========================================="
echo " Bắt đầu chạy workflow cài đặt SMRS Pack (Chế độ tự động)"
echo " Target User: $REAL_USER"
echo " Home Directory: $REAL_HOME"
echo "=========================================="

# 2. Cập nhật apt tất cả trên VPS
echo ""
echo "[Bước 2/5] Cập nhật apt tất cả trên VPS (tự động bỏ qua hộp thoại tương tác)..."

# Tự động giải quyết lỗi khóa (lock) apt/dpkg thường gặp trên VPS mới
echo "[*] Tự động kiểm tra và giải phóng khóa apt..."
killall -9 apt apt-get 2>/dev/null || true
rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock
dpkg --configure -a || true

apt-get update -y && $APT_CMD upgrade

# 3. Cài đặt các yêu cầu: Prerequisites (git, docker Engine v23.0+ với buildx, docker compose v2)
echo ""
echo "[Bước 3/5] Kiểm tra và cài đặt các Prerequisites (git, docker, docker compose)..."

# Cài đặt git
if ! command -v git &> /dev/null; then
    echo "[*] Tiến hành cài đặt Git..."
    $APT_CMD install git
else
    echo "[✓] Git đã được cài đặt: $(git --version)"
fi

# Kiểm tra Docker Engine / Podman & Compose v2
HAS_DOCKER=false
HAS_PODMAN=false

if command -v docker &> /dev/null; then
    DOCKER_VER=$(docker --version 2>/dev/null || true)
    echo "[*] Đã phát hiện Docker: $DOCKER_VER"
    if docker compose version &> /dev/null; then
        echo "[✓] Docker Compose v2 đã sẵn sàng: $(docker compose version)"
        HAS_DOCKER=true
    fi
fi

if command -v podman &> /dev/null; then
    PODMAN_VER=$(podman --version 2>/dev/null || true)
    echo "[*] Đã phát hiện Podman: $PODMAN_VER"
    if podman compose version &> /dev/null || command -v podman-compose &> /dev/null; then
        echo "[✓] Podman Compose đã sẵn sàng."
        HAS_PODMAN=true
    fi
fi

if [ "$HAS_DOCKER" = false ] && [ "$HAS_PODMAN" = false ]; then
    echo "[*] Tiến hành cài đặt Docker Engine v23.0+ & Docker Compose v2 từ apt repository chính thức..."
    
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
        echo "[*] Đã thêm user '$REAL_USER' vào group 'docker'."
    fi

    echo "[✓] Đã cài đặt xong Docker Engine v23.0+ và Docker Compose v2."
fi

# 4. Tạo thư mục mới: ~/smrs-pack -> cd ~/smrs-pack
echo ""
echo "[Bước 4/5] Tạo thư mục $SMRS_DIR..."
mkdir -p "$SMRS_DIR"
cd "$SMRS_DIR"
echo "[✓] Đã chuyển đến thư mục: $(pwd)"

# 5. Clone git clone https://github.com/frappe/frappe_docker
echo ""
echo "[Bước 5/5] Clone repository frappe_docker..."
if [ -d "$SMRS_DIR/frappe_docker" ]; then
    echo "[!] Thư mục 'frappe_docker' đã tồn tại tại $SMRS_DIR/frappe_docker"
else
    git clone https://github.com/frappe/frappe_docker "$SMRS_DIR/frappe_docker"
    echo "[✓] Clone repository thành công!"
fi

# Phân quyền lại thư mục cho REAL_USER nếu script chạy dưới sudo
if [ -n "$REAL_USER" ] && [ "$REAL_USER" != "root" ]; then
    chown -R "$REAL_USER:$REAL_USER" "$SMRS_DIR"
fi

echo ""
echo "=========================================="
echo " Hoàn tất workflow thành công!"
echo " Thư mục kết quả: $SMRS_DIR/frappe_docker"
echo "=========================================="
