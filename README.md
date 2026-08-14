# 🚀 Frappe Packaging & Automated Deployment Scripts

Bộ công cụ tự động hóa quá trình đóng gói **Frappe / ERPNext Custom Apps** và triển khai hệ thống lên môi trường VPS Ubuntu/Debian bằng **Docker Compose**, **Traefik (SSL Let's Encrypt)** và **MariaDB Shared Database**.

---

## 📁 Cấu Trúc Repository

```text
frappe-packaging-scripts/
├── setup.sh                 # Script Bash tự động thực thi 12 bước cài đặt & deploy
├── example.env              # File cấu hình mẫu chứa các biến môi trường cho dự án
├── .gitignore               # Cấu hình loại bỏ file nhạy cảm (.env, .env.local)
└── docs/
    ├── workflow.md          # Tài liệu mô tả quy trình thực thi 12 bước chi tiết
    └── research/
        └── frappe_docker_deployment.md  # Tài liệu phân tích kiến trúc Frappe Docker
```

---

## ⚙️ Yêu Cầu Tiền Đề (Prerequisites)

- **Hệ điều hành**: VPS chạy Ubuntu (20.04/22.04 LTS) hoặc Debian.
- **Quyền hạn**: Quyền `root` hoặc `sudo`.
- **Tên miền (Domain)**: Tên miền đã được trỏ (DNS A Record) về IP của VPS.

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

### Bước 3: Chỉnh Sửa Thông Số Trong `.env`
Mở file `.env` và cập nhật thông tin tên miền, danh sách custom apps và mật khẩu bảo mật:
```bash
nano .env
```

### Bước 4: Cấp Quyền Thực Thi & Chạy Script Setup
```bash
chmod +x setup.sh
./setup.sh
```

---

## 🛠️ Cấu Hình Chi Tiết File `.env`

File `.env` quản lý toàn bộ tham số hoạt động của script tự động:

| Biến Môi Trường | Mô Tả | Ví Dụ |
| :--- | :--- | :--- |
| `APPS_JSON` | Mảng JSON khai báo danh sách repo Custom App cần đóng gói | `'[{"url":"https://github.com/user/app1.git","branch":"main"}]'` |
| `CUSTOM_APP_NAMES` | Danh sách tên app (cách nhau bởi khoảng trắng) dùng cho `bench install-app` | `"custom_app_1 custom_app_2"` |
| `FRAPPE_BRANCH` | Phiên bản branch của Frappe/ERPNext | `"version-15"` |
| `CUSTOM_IMAGE_TAG` | Tag tên cho Docker Image sẽ tự động build | `"smrs-custom-image:latest"` |
| `SITE_DOMAIN` | Tên miền chính truy cập hệ thống | `"erp.yourdomain.com"` |
| `PROJECT_NAME` | Tên dự án cô lập môi trường Docker Compose | `"smrs-project"` |
| `LETSENCRYPT_EMAIL` | Email đăng ký gia hạn SSL với Let's Encrypt | `"admin@yourdomain.com"` |
| `DB_ROOT_PASSWORD` | Mật khẩu root cơ sở dữ liệu MariaDB | `"Password_Bao_Mat_DB_123!"` |
| `FRAPPE_ADMIN_PASSWORD` | Mật khẩu tài khoản `Administrator` của Frappe | `"Password_Bao_Mat_Admin_123!"` |
| `USE_CLOUDFLARE_TUNNEL` | Đặt `"true"` nếu chạy qua Cloudflare Tunnel, `"false"` nếu chạy trực tiếp Traefik SSL | `"false"` |
| `CLOUDFLARE_TUNNEL_TOKEN` | Token từ Cloudflare Zero Trust Dashboard (bắt buộc khi `USE_CLOUDFLARE_TUNNEL="true"`) | `"eyJhSW9p..."` |

---

## 📊 Quy Trình Thực Thi 12 Bước Của `setup.sh`

Script `setup.sh` sẽ tự động thực hiện tuần tự các bước sau mà không cần can thiệp thủ công:

1. **[Bước 1] Kiểm tra quyền Root/Sudo**: Xác thực quyền hạn và thiết lập các biến môi trường người dùng.
2. **[Bước 2] Đọc & Validation `.env`**: Nạp và kiểm tra sự tồn tại của file cấu hình `.env`.
3. **[Bước 3] Cập nhật APT**: Tự động chạy `apt-get update` & `upgrade` ở chế độ non-interactive.
4. **[Bước 4] Cài đặt Prerequisites**: Kiểm tra và cài đặt Git, Docker Engine (v23.0+) và Docker Compose v2.
5. **[Bước 5] Tạo thư mục làm việc**: Khởi tạo `~/frappe-packaging` và `~/gitops`.
6. **[Bước 6] Clone `frappe_docker`**: Tải repository chính thức từ `frappe/frappe_docker`.
7. **[Bước 7] Tạo `apps.json`**: Xuất mảng `$APPS_JSON` thành file secret cho Docker build.
8. **[Bước 8] Build Custom Image**: Gọi `docker build` đóng gói Frappe cùng các custom apps.
9. **[Bước 9] Khởi chạy Traefik SSL**: Dựng Reverse Proxy tự động xin & gia hạn SSL Let's Encrypt trên port 80/443.
10. **[Bước 10] Khởi chạy MariaDB Shared**: Dựng instance MariaDB dùng chung an toàn.
11. **[Bước 11] Deploy Project Stack**: Sinh file Compose tổng hợp và khởi chạy stack backend, frontend, redis, socketio.
12. **[Bước 12] Tạo Site & Install Apps**: Chạy `bench new-site` trực tiếp với domain và tự động cài đặt tất cả custom app.

---

## 🏗️ Kiến Trúc Hệ Thống (Architecture)

```text
                   [ Web Browser ]
                         │
                  Port 80 / 443 (HTTPS)
                         ▼
             ┌───────────────────────┐
             │ Traefik Reverse Proxy │ (Auto Let's Encrypt SSL)
             └───────────┬───────────┘
                         │
                         ▼
             ┌───────────────────────┐
             │  Frappe Frontend/NGINX│
             └───────────┬───────────┘
                         │
            ┌────────────┴────────────┐
            ▼                         ▼
   ┌─────────────────┐       ┌─────────────────┐
   │ Frappe Backend  │       │ Redis (Cache &  │
   │   (Python/Gunicorn)     │  Queue Workers) │
   └────────┬────────┘       └─────────────────┘
            │
            ▼
   ┌─────────────────┐
   │ MariaDB Shared  │ (Database Engine)
   └─────────────────┘
```

---

## 📌 Các Lệnh Thao Tác Thường Dùng (Operations Guide)

### Xem Logs Của Stack Project
```bash
docker compose -p smrs-project logs -f
```

### Xem Trạng Thái Các Container
```bash
docker compose -p smrs-project ps
```

### Khởi Động Lại Hệ Thống
```bash
docker compose -p smrs-project restart
```

### Chạy Lệnh Bench Trong Container Backend
```bash
docker compose -p smrs-project exec backend bench migrate
```
