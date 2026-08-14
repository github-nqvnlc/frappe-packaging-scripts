Giúp tôi viết script trong folder /home/baucan/scripts với nội dung sẽ chạy theo tuần tự workflow như sau:

1. **Yêu cầu có quyền sudo**: Kiểm tra xem script có đang được chạy với quyền root/sudo hay không, nếu không thì báo lỗi và dừng lại.
2. **Cập nhật apt**: Chạy `apt update` và `apt upgrade -y` trên VPS.
3. **Cài đặt các yêu cầu (Prerequisites)**:
    - Cài đặt `git`.
    - Cài đặt `docker` (Engine v23.0+ với buildx).
    - Cài đặt `docker compose v2`.
4. **Tạo thư mục mới**: Tạo thư mục `~/smrs-pack` và di chuyển vào đó (`cd ~/smrs-pack`).
5. **Clone Repository**: Chạy lệnh `git clone https://github.com/frappe/frappe_docker`.
6. **Di chuyển vào thư mục dự án**: `cd ~/smrs-pack/frappe_docker`.
7. **Tạo file `apps.json`**: Tạo file `apps.json` chứa thông tin về custom app cần đóng gói, ví dụ:
    ```json
    [
      {
        "url": "https://github.com/your-username/your_custom_app.git",
        "branch": "main"
      }
    ]
    ```
8. **Build Custom Docker Image**: Sử dụng `docker build` để đóng gói image với custom app:
    ```bash
    docker build \
      --build-arg=FRAPPE_PATH=https://github.com/frappe/frappe \
      --build-arg=FRAPPE_BRANCH=version-15 \
      --build-arg=CACHE_BUST="$(date +%s)" \
      --secret=id=apps_json,src=apps.json \
      --tag=smrs-custom-image:latest \
      --file=images/layered/Containerfile .
    ```
9. **Thiết lập Traefik (Load Balancer & SSL)**:
    - Tạo thư mục lưu cấu hình (vd: `~/gitops`).
    - Tạo file `~/gitops/traefik.env` chứa cấu hình domain và email nhận thông báo Let's Encrypt.
    - Khởi chạy Traefik với docker compose (`overrides/compose.traefik.yaml` và `compose.traefik-ssl.yaml`).
10. **Thiết lập MariaDB**:
    - Tạo file `~/gitops/mariadb.env` định nghĩa `DB_PASSWORD`.
    - Khởi chạy MariaDB shared với `overrides/compose.mariadb-shared.yaml`.
11. **Cấu hình Project (Bench)**:
    - Tạo file `~/gitops/my-project.env`.
    - Định nghĩa các biến môi trường quan trọng: trỏ `BACKEND_IMAGE` và `FRONTEND_IMAGE` tới `smrs-custom-image:latest`, thiết lập `ROUTER` và `SITES_RULE=Host('yourdomain.com')`.
12. **Deploy Project Stack**:
    - Dùng lệnh `docker compose config` với các overrides (`redis`, `multi-bench`, `multi-bench-ssl`) để sinh ra file cấu hình `~/gitops/my-project.yaml`.
    - Khởi chạy project stack: `docker compose -p my-project -f ~/gitops/my-project.yaml up -d`.
13. **Tạo Site và Cài đặt Custom App (Trực tiếp với Domain)**:
    - Thực thi lệnh `bench new-site` vào bên trong container `backend` vừa được dựng.
    - Truyền tên miền (yourdomain.com), mật khẩu DB gốc, mật khẩu admin, và cờ `--install-app your_custom_app` để tạo site với domain thực tế ngay từ đầu.
    ```bash
    docker compose --project-name my-project exec backend \
      bench new-site yourdomain.com \
      --mariadb-user-host-login-scope=% \
      --db-root-password YOUR_DB_ROOT_PASSWORD \
      --admin-password YOUR_ADMIN_PASSWORD \
      --install-app your_custom_app
    ```
