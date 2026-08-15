# Phân Tích & Hướng Dẫn Chỉnh Sửa `site_config.json` Trong Frappe Docker

Tài liệu này tổng hợp và phân tích các phương pháp chỉnh sửa cấu hình `site_config.json` và `common_site_config.json` dựa trên tài liệu chính thức `frappe-docker` tại [`docs/docs-frappe-docker`](file:///Users/vanloc/Documents/Windify/frappe-packaging-scripts/docs/docs-frappe-docker) và áp dụng thực tế cho dự án `frappe-packaging-scripts`.

---

## 1. Giới Thiệu & Bản Chất Cấu Hình Trong Frappe Bench

Trong kiến trúc Frappe Framework và môi trường Container Docker, hệ thống phân chia các thông số cấu hình thành 2 loại chính nằm trong thư mục `sites`:

1. **`site_config.json`** (`sites/<site-name>/site_config.json`):
   - Chứa cấu hình **riêng biệt cho từng Site** (tương ứng từng tên miền hoặc tenant).
   - *Các tham số thường gặp*: `db_name`, `db_password`, `encryption_key`, `developer_mode`, `maintenance_mode`, `pause_scheduler`, `admin_password`, các API keys, custom app settings...

2. **`common_site_config.json`** (`sites/common_site_config.json`):
   - Chứa cấu hình **dùng chung cho toàn bộ Bench** (tất cả các sites trong cùng container).
   - *Các tham số thường gặp*: `db_host`, `db_port`, `redis_cache`, `redis_queue`, `redis_socketio`, `gunicorn_workers`, `webserver_port`...

---

## 2. Đặc Thù Của Frappe Docker & Lưu Ý Về File Permissions

Khi triển khai trên Docker (đặc biệt là theo các stack Docker Compose trong dự án `frappe-packaging-scripts`), thư mục `sites` được lưu trữ trong một **Docker Volume** (ví dụ: `<project_name>_sites` hoặc `frappe_sites`).

- **Mối nguy rủi ro**: Việc dùng các công cụ trực tiếp trên host can thiệp vào volume docker không đúng cách có thể gây lỗi **File Permission** (User `frappe` UID/GID 1000 trong container không thể đọc/ghi vào file) hoặc làm hỏng định dạng JSON.
- **Giải pháp**: Luôn ưu tiên dùng lệnh `bench set-config` hoặc dùng container làm môi trường trung gian để sửa file.

---

## 3. Chi Tiết Các Phương Pháp Chỉnh Sửa

### 🟢 Phương Pháp 1: Sử Dụng Lệnh `bench set-config` (Khuyên Dùng & An Toàn Nhất)

Đây là phương pháp **an toàn nhất và được khuyến nghị mặc định** từ Frappe Framework. Nó thực thi mã Python bên trong container để cập nhật file JSON mà không làm mất cấu trúc hay thay đổi quyền sở hữu (file permissions) của file.

#### A. Cú pháp cơ bản
```bash
# Thay đổi cấu hình của 1 site cụ thể (site_config.json)
docker compose -p <PROJECT_NAME> exec backend bench --site <SITE_NAME> set-config <KEY> <VALUE>

# Thay đổi cấu hình chung toàn bench (common_site_config.json)
docker compose -p <PROJECT_NAME> exec backend bench set-config -g <KEY> <VALUE>
```

#### B. Các ví dụ thường dùng trong thực tế:
1. **Bật chế độ Nhà phát triển (`developer_mode`):**
   ```bash
   docker compose -p frappe-packaging exec backend bench --site yourdomain.com set-config developer_mode 1
   ```
2. **Bật / Tắt chế độ bảo trì (`maintenance_mode`):**
   ```bash
   # Bật chế độ bảo trì
   docker compose -p frappe-packaging exec backend bench --site yourdomain.com set-config maintenance_mode 1
   # Tắt chế độ bảo trì
   docker compose -p frappe-packaging exec backend bench --site yourdomain.com set-config maintenance_mode 0
   ```
3. **Tạm dừng Scheduler (`pause_scheduler`):**
   ```bash
   docker compose -p frappe-packaging exec backend bench --site yourdomain.com set-config pause_scheduler 1
   ```
4. **Cấu hình tham số dạng chuỗi (String) hoặc JSON Object:**
   ```bash
   docker compose -p frappe-packaging exec backend bench --site yourdomain.com set-config encryption_key '"your_secret_key"'
   ```

---

### 🟡 Phương Pháp 2: Sử Dụng Container Tạm Thời Mount Volume (Theo Chuẩn Frappe-Docker Docs)

> 📖 *Tham khảo tài liệu chính thức*: [`01-site-operations.md`](file:///Users/vanloc/Documents/Windify/frappe-packaging-scripts/docs/docs-frappe-docker/04-operations/01-site-operations.md#L46-L53)

Nếu bạn cần sửa nhiều dòng thủ công, chỉnh sửa thông tin Database bên ngoài (như Amazon RDS, GCP Cloud SQL) hoặc cấu hình không hỗ trợ trực tiếp qua `bench CLI`, hãy sử dụng một container Alpine tạm thời mount volume `sites`:

#### A. Sửa `site_config.json` bằng trình chỉnh sửa `vi`:
```bash
docker run --rm -it \
  -v <project-name>_sites:/sites \
  alpine vi /sites/<site-name>/site_config.json
```

#### B. Sửa bằng trình chỉnh sửa `nano`:
```bash
docker run --rm -it \
  -v <project-name>_sites:/sites \
  alpine sh -c "apk add --no-cache nano && nano /sites/<site-name>/site_config.json"
```

#### C. Sửa `common_site_config.json`:
```bash
docker run --rm -it \
  -v <project-name>_sites:/sites \
  alpine vi /sites/common_site_config.json
```

*(Lưu ý: Thay `<project-name>` bằng tên project Docker Compose của bạn, ví dụ `frappe-packaging` hay `frappe_docker`).*

---

### 🔵 Phương Pháp 3: Tương Tác Trực Tiếp Trong Container `backend`

Bạn có thể mở một phiên làm việc (bash shell) tương tác bên trong container `backend`:

```bash
# 1. Truy cập vào container backend
docker compose -p frappe-packaging exec -it backend bash

# 2. Di chuyển đến thư mục site
cd sites/yourdomain.com/

# 3. Kiểm tra nội dung site_config.json
cat site_config.json

# 4. Sử dụng bench set-config hoặc python script để chỉnh sửa
bench --site yourdomain.com set-config developer_mode 1
```

---

### 🟣 Phương Pháp 4: Sử Dụng Bind Mount / Override File (Môi Trường Phát Triển hoặc Custom Setup)

> 📖 *Tham khảo tài liệu chính thức*: [`02-docker-bind-mounts.md`](file:///Users/vanloc/Documents/Windify/frappe-packaging-scripts/docs/docs-frappe-docker/09-concepts/02-docker-bind-mounts.md)

Nếu trong file `docker-compose.yml` (hoặc `compose.override.yaml`), bạn gắn ổ đĩa trực tiếp từ máy host (Bind Mount) thay vì dùng Docker Named Volume:

```yaml
services:
  backend:
    volumes:
      - ./sites:/home/frappe/frappe-bench/sites
```

Khi đó, bạn có thể chỉnh sửa trực tiếp file bằng trình soạn thảo trên VPS / Máy thật tại đường dẫn `./sites/<site-name>/site_config.json` bằng `nano`, `vim` hoặc VS Code.

Ngoài ra, nếu muốn nạp một file cấu hình chung cố định dưới dạng chỉ đọc (Read-Only), bạn có thể dùng cấu hình override:
```yaml
services:
  backend:
    volumes:
      - ./custom-config.json:/home/frappe/frappe-bench/sites/common_site_config.json:ro
```

---

## 4. Các Bước Cần Thực Hiện Sau Khi Edit Cấu Hình

Sau khi tiến hành chỉnh sửa thành công file `site_config.json` hoặc `common_site_config.json`, hãy thực hiện các bước sau để đảm bảo thay đổi có hiệu lực:

1. **Xóa Cache của Site (Clear Cache):**
   ```bash
   docker compose -p <project_name> exec backend bench --site <site_name> clear-cache
   ```

2. **Chạy Database Migration (nếu cài lại / cập nhật app hoặc thay đổi DB schema):**
   ```bash
   docker compose -p <project_name> exec backend bench --site <site_name> migrate
   ```

3. **Restart lại dịch vụ backend & workers (nếu sửa cấu hình kết nối DB/Redis/System):**
   ```bash
   docker compose -p <project_name> restart backend worker-default worker-short worker-long
   ```

---

## 5. Tóm Tắt Bảng Hướng Dẫn Nhanh

| Nhu cầu chỉnh sửa | Phương pháp tối ưu nhất | Câu lệnh khuyến nghị |
| :--- | :--- | :--- |
| **Bật/Tắt Dev Mode, Maintenance, Scheduler** | Lệnh `bench set-config` | `docker compose -p $PROJECT_NAME exec backend bench --site $SITE_DOMAIN set-config <key> <val>` |
| **Thay đổi thông tin kết nối MariaDB / Redis** | Container Alpine tạm thời | `docker run --rm -it -v ${PROJECT_NAME}_sites:/sites alpine vi /sites/common_site_config.json` |
| **Sửa nhiều key phức tạp / JSON lồng nhau** | Exec vào backend container | `docker compose -p $PROJECT_NAME exec -it backend bash` |
