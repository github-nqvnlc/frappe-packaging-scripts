# Hướng Dẫn Chi Tiết Menu Điều Khiển Script `setup.sh`

Tài liệu này giải thích chi tiết chức năng, cơ chế vận hành và cách hoạt động của từng bước (menu) trong script cài đặt tự động [`setup.sh`](file:///Users/vanloc/Documents/Windify/frappe-packaging-scripts/setup.sh), đối chiếu trực tiếp với quy trình trong [`workflow.md`](file:///Users/vanloc/Documents/Windify/frappe-packaging-scripts/docs/workflow.md).

---

## 🛠️ 1. Tổng Quan Về Script `setup.sh`

Script `setup.sh` được thiết kế để tự động hóa toàn bộ quy trình đóng gói và triển khai hệ thống Frappe/ERPNext với Custom Apps trên Docker.

### Key Features:
- **Tự động hóa hoàn toàn (Non-interactive APT)**: Thiết lập `DEBIAN_FRONTEND=noninteractive` để tránh mọi hộp thoại chờ bấm Enter của hệ thống.
- **Menu Tương Tác 12 Bước (Step-by-step Interactive Menu)**: Cho phép chạy từng bước đơn lẻ hoặc chạy toàn bộ quy trình từ 1 đến 12.
- **Cơ chế Kiểm tra Tiền đề (Prerequisite Engine)**: Ngăn ngừa việc người dùng chạy nhảy bước khi các bước phụ thuộc trước đó chưa hoàn thành.
- **Tự động nhận diện trạng thái (Health Check Status)**: Đánh dấu biểu tượng `[✓]` cho các bước đã hoàn thành dựa trên kiểm tra thực tế hệ thống.
- **Hỗ trợ CLI Flags**: Cho phép chạy trực tiếp từ dòng lệnh không cần qua menu tương tác.

---

## 🔒 2. Cơ Chế Kiểm Tra Tiền Đề (Prerequisite System)

Trước khi thực thi bất kỳ bước nào (từ Bước 2 đến Bước 12), hàm `validate_prerequisites_for_step` sẽ tự động quét lại toàn bộ các bước trước đó.

- **Cách hoạt động**: Nếu bạn chọn chạy **Bước 8 (Build Image)** nhưng **Bước 4 (Cài Docker)** hoặc **Bước 7 (Xuất apps.json)** chưa hoàn thành, script sẽ chặn lại, in cảnh báo đỏ và hướng dẫn bạn chạy lại bước còn thiếu.
- **Biểu tượng trạng thái**:
  - `[✓]` : Bước đã hoàn thành.
  - `[ ]` : Bước chưa được thực hiện hoặc chưa đủ điều kiện.

---

## 📋 3. Giải Thích Chi Tiết Mỗi Menu Trong Script

### 🚀 Menu `[ 0 ]`: Chạy TOÀN BỘ Workflow (Từ Bước 1 đến Bước 12)
- **Hàm tương ứng**: `run_all_steps()`
- **Chức năng**: Tự động thực thi tuần tự từ Bước 1 đến Bước 12 không dừng lại (nếu không gặp lỗi).
- **Kết quả**: Cuối quy trình, script sẽ xuất **Báo cáo kết quả triển khai** hiển thị thông tin domain, chế độ triển khai (Tunnel hay Traefik Direct), tài khoản & mật khẩu Administrator.

---

### 🔑 Menu `[ 1 ]`: Bước 1 - Kiểm tra quyền Root/Sudo & Môi trường
- **Hàm tương ứng**: `run_step_1()` -> `init_env_vars()`
- **Workflow tương ứng**: Bước 1 trong `workflow.md`.
- **Mô tả hoạt động**:
  1. Kiểm tra xem người dùng có chạy bằng quyền `root` hoặc `sudo` hay không. Nếu không, tự động gọi `sudo bash`.
  2. Xác định thư mục Home thực sự của user (`REAL_HOME`) và khởi tạo đường dẫn làm việc:
     - `SMRS_DIR`: `~/frappe-packaging`
     - `GITOPS_DIR`: `~/gitops`
  3. Tìm kiếm file cấu hình `.env` ở các đường dẫn khả thi (`.env` tại thư mục script, thư mục hiện tại, hoặc thư mục gốc).

---

### 📋 Menu `[ 2 ]`: Bước 2 - Kiểm tra & Đọc file cấu hình `.env`
- **Hàm tương ứng**: `run_step_2()`
- **Workflow tương ứng**: Bước 6 trong `workflow.md`.
- **Mô tả hoạt động**:
  1. Đọc và nạp các biến từ file `.env` vào môi trường shell (`set -o allexport`).
  2. Kiểm tra danh sách các biến bắt buộc: `APPS_JSON`, `CUSTOM_APP_NAMES`, `SITE_DOMAIN`, `PROJECT_NAME`, `DB_ROOT_PASSWORD`, `FRAPPE_ADMIN_PASSWORD`.
  3. Nếu `USE_CLOUDFLARE_TUNNEL="true"`, bắt buộc phải có `CLOUDFLARE_TUNNEL_TOKEN`.
  4. Nếu thiếu bất kỳ biến nào, script dừng lại và báo lỗi rõ ràng.

---

### 🔄 Menu `[ 3 ]`: Bước 3 - Cập nhật danh sách gói tin APT hệ thống
- **Hàm tương ứng**: `run_step_3()`
- **Workflow tương ứng**: Bước 2 trong `workflow.md`.
- **Mô tả hoạt động**:
  1. Mở khóa file lock của APT nếu có tiến trình ngầm đang giữ (`killall -9 apt apt-get`, xóa file `/var/lib/dpkg/lock-frontend`).
  2. Thực hiện `apt-get update -y` và `apt-get upgrade -y` hoàn toàn tự động.
  3. Tạo file đánh dấu thành công `~/gitops/.apt_updated`.

---

### 🛠️ Menu `[ 4 ]`: Bước 4 - Cài đặt công cụ cần thiết (Git, Docker Engine, Compose v2)
- **Hàm tương ứng**: `run_step_4()`
- **Workflow tương ứng**: Bước 3 trong `workflow.md`.
- **Mô tả hoạt động**:
  1. Kiểm tra `git`. Nếu chưa có, tự động cài `git`.
  2. Kiểm tra `docker` và `docker compose version` (yêu cầu Docker v23.0+ và Compose v2 plugin).
  3. Nếu chưa có Docker, tự động thêm GPG Key chính thức từ `download.docker.com`, cài đặt `docker-ce`, `docker-buildx-plugin`, `docker-compose-plugin`.
  4. Tự động thêm user hiện tại vào group `docker` (`usermod -aG docker`).

---

### 📁 Menu `[ 5 ]`: Bước 5 - Khởi tạo thư mục làm việc (`~/frappe-packaging`, `~/gitops`)
- **Hàm tương ứng**: `run_step_5()`
- **Workflow tương ứng**: Bước 4 trong `workflow.md`.
- **Mô tả hoạt động**:
  - Tạo 2 thư mục làm việc chính:
    - `~/frappe-packaging`: Nơi chứa nguồn `frappe_docker` và tài nguyên đóng gói.
    - `~/gitops`: Nơi chứa các file cấu hình triển khai tĩnh (`traefik.env`, `mariadb.env`, `cloudflared.yaml`, `${PROJECT_NAME}.yaml`).

---

### 📦 Menu `[ 6 ]`: Bước 6 - Clone / Kiểm tra repository `frappe_docker`
- **Hàm tương ứng**: `run_step_6()`
- **Workflow tương ứng**: Bước 5 trong `workflow.md`.
- **Mô tả hoạt động**:
  - Kiểm tra xem thư mục `~/frappe-packaging/frappe_docker/.git` đã tồn tại chưa.
  - Nếu chưa có: Thực hiện `git clone https://github.com/frappe/frappe_docker` vào thư mục làm việc.
  - Nếu đã có: Bỏ qua clone để tiết kiệm thời gian.

---

### 🔐 Menu `[ 7 ]`: Bước 7 - Khởi tạo file secret `apps.json`
- **Hàm tương ứng**: `run_step_7()`
- **Workflow tương ứng**: Bước 6 trong `workflow.md`.
- **Mô tả hoạt động**:
  - Trích xuất nội dung biến `$APPS_JSON` khai báo trong `.env` và ghi ra file `~/frappe-packaging/frappe_docker/apps.json`.
  - In nội dung `apps.json` lên màn hình để người dùng xác nhận lại danh sách custom app và branch Git.

---

### 🏗️ Menu `[ 8 ]`: Bước 8 - Build Custom Docker Image
- **Hàm tương ứng**: `run_step_8()`
- **Workflow tương ứng**: Bước 7 trong `workflow.md`.
- **Mô tả hoạt động**:
  - Thực thi câu lệnh `docker build` tạo Docker Image chứa custom app:
    - `--build-arg=FRAPPE_BRANCH`: Phiên bản Frappe (VD: `version-15`).
    - `--build-arg=CACHE_BUST`: Sử dụng timestamp để vô hiệu hóa cache khi build.
    - `--secret=id=apps_json,src=apps.json`: Truyền bí mật danh sách app an toàn vào quá trình build.
    - `--tag`: Gán tên image theo biến `$CUSTOM_IMAGE_TAG`.
    - `--file=images/layered/Containerfile`: Sử dụng cấu trúc Layered Containerfile chính thức.

---

### 🌐 Menu `[ 9 ]`: Bước 9 - Khởi chạy Traefik Proxy & Cloudflare Tunnel
- **Hàm tương ứng**: `run_step_9()`
- **Workflow tương ứng**: Bước 8 trong `workflow.md`.
- **Mô tả hoạt động (Phân nhánh theo biến `USE_CLOUDFLARE_TUNNEL`)**:
  - **Nếu `USE_CLOUDFLARE_TUNNEL="true"`**:
    1. Khởi chạy Traefik Reverse Proxy ở chế độ HTTP nội bộ (`overrides/compose.proxy.yaml`).
    2. Tạo file `~/gitops/cloudflared.yaml` với token `$CLOUDFLARE_TUNNEL_TOKEN` và khởi chạy container `cloudflared` kết nối vào mạng `traefik-public`.
  - **Nếu `USE_CLOUDFLARE_TUNNEL="false"`**:
    1. Tạo file `~/gitops/traefik.env` chứa email Let's Encrypt.
    2. Khởi chạy Traefik hỗ trợ HTTP & HTTPS tự động cấp phát SSL Let's Encrypt (`compose.proxy.yaml` + `compose.https.yaml`).

---

### 🗄️ Menu `[ 10 ]`: Bước 10 - Cấu hình & Khởi chạy MariaDB Shared Database
- **Hàm tương ứng**: `run_step_10()`
- **Workflow tương ứng**: Bước 9 trong `workflow.md`.
- **Mô tả hoạt động**:
  1. Sinh file cấu hình môi trường `~/gitops/mariadb.env` chứa `DB_PASSWORD=$DB_ROOT_PASSWORD`.
  2. Khởi chạy MariaDB container dùng chung (`overrides/compose.mariadb-shared.yaml`) dưới project name `mariadb`.

---

### 🚀 Menu `[ 11 ]`: Bước 11 - Tạo cấu hình & Deploy Project Stack
- **Hàm tương ứng**: `run_step_11()`
- **Workflow tương ứng**: Bước 10 & 11 trong `workflow.md`.
- **Mô tả hoạt động**:
  1. Tạo file môi trường `~/gitops/${PROJECT_NAME}.env` định nghĩa các biến router Traefik, tên miền `SITES_RULE`, và tag docker image custom.
  2. Sử dụng `docker compose config` tổng hợp nhiều file override thành 1 file YAML duy nhất `~/gitops/${PROJECT_NAME}.yaml`.
  3. Khởi chạy toàn bộ stack dịch vụ (backend, frontend, websocket, redis) bằng `docker compose -p "$PROJECT_NAME" -f ... up -d`.

---

### ✨ Menu `[ 12 ]`: Bước 12 - Khởi tạo Frappe Site & Cài đặt các Custom Apps
- **Hàm tương ứng**: `run_step_12()`
- **Workflow tương ứng**: Bước 12 trong `workflow.md`.
- **Mô tả hoạt động**:
  1. Tạm dừng 10 giây chờ container `backend` khởi động hoàn tất.
  2. Tạo danh sách các cờ `--install-app` cho từng app khai báo trong `$CUSTOM_APP_NAMES`.
  3. Thực thi lệnh tạo site trong container `backend`:
     ```bash
     docker compose -p "$PROJECT_NAME" exec backend \
       bench new-site "$SITE_DOMAIN" \
       --mariadb-user-host-login-scope=% \
       --db-root-password "$DB_ROOT_PASSWORD" \
       --admin-password "$FRAPPE_ADMIN_PASSWORD" \
       $INSTALL_APP_FLAGS
     ```
  4. Phân lại quyền sở hữu thư mục (`chown`) cho user thường (nếu chạy qua `sudo`).

---

### 🔍 Menu `[ K ]`: Kiểm tra chi tiết trạng thái tất cả các bước (Health Check)
- **Hàm tương ứng**: `show_status_check()`
- **Mô tả hoạt động**:
  - Quét qua cả 12 bước từ 1 đến 12 và thực thi hàm kiểm tra `is_step_completed`.
  - In bảng tổng quan màu sắc hiển thị từng bước là `[✓ HOÀN THÀNH]` hay `[  CHƯA LÀM  ]`.

---

### 📝 Menu `[ E ]`: Chỉnh sửa `site_config.json` hoặc `common_site_config.json` (nano / vi)
- **Hàm tương ứng**: `edit_site_config()`
- **Mô tả hoạt động**:
  1. **Tự động tìm kiếm Docker Volume**: Tự động phát hiện Volume lưu trữ các sites (ví dụ `${PROJECT_NAME}_sites` hoặc `sites`).
  2. **Cho phép chọn file chỉnh sửa**:
     - `1`: `site_config.json` của site mặc định (`$SITE_DOMAIN`).
     - `2`: `common_site_config.json` (Cấu hình dùng chung toàn Bench: DB Host, Redis...).
     - `3`: Tùy chỉnh tên site khác trong hệ thống.
  3. **Tùy chọn trình soạn thảo**:
     - `1`: `nano` (Tự động tải & chạy container Alpine tích hợp nano).
     - `2`: `vi` / `vim`.
  4. **Tự động reload hệ thống**: Sau khi lưu file, script sẽ hỏi và tự động chạy `bench clear-cache` và khởi động lại container `backend` để áp dụng thay đổi ngay lập tức.

---

### 🗑️ Menu `[ D ]`: Xóa & Dừng TOÀN BỘ hệ thống Docker (Teardown & Clean up)
- **Hàm tương ứng**: `teardown_all_containers()`
- **Mô tả hoạt động**:
  1. **Cảnh báo an toàn**: Hiển thị bảng cảnh báo đỏ nguy hiểm và yêu cầu người dùng phải gõ xác nhận `YES`, `y` hoặc `Y` trước khi tiến hành xóa dữ liệu.
  2. **Dừng & Xóa Container + Volume**:
     - Thực thi `docker compose down -v --remove-orphans` cho từng stack (Project Stack `$PROJECT_NAME`, Cloudflare Tunnel `tunnel`, MariaDB Shared `mariadb`, Traefik Reverse Proxy `traefik`).
     - Cờ `-v` sẽ **xóa hoàn toàn các Docker Volume** (bao gồm dữ liệu MariaDB database và dữ liệu Frappe Sites).
  3. **Xóa toàn bộ thư mục làm việc & mã nguồn đã clone**:
     - Xóa hoàn toàn thư mục `~/frappe-packaging` (chứa mã nguồn `frappe_docker` và secret `apps.json`).
     - Xóa hoàn toàn thư mục `~/gitops` (chứa toàn bộ các file cấu hình `.yaml` và `.env` tạm).
  4. **Tài nguyên DUY NHẤT được GIỮ LẠI**:
     - **File `.env`**: File cấu hình gốc chứa biến môi trường triển khai của bạn hoàn toàn an toàn và được giữ nguyên.

---

### ❌ Menu `[ Q ]`: Thoát Menu
- **Mô tả**: Dừng script và thoát về terminal shell.

---

## 💻 4. Hướng Dẫn Chạy Script Qua CLI (Command Line Flags)

Ngoài việc sử dụng Menu Tương Tác, bạn có thể gọi trực tiếp `setup.sh` từ Terminal bằng các cờ lệnh sau:

| CLI Command | Tương đương trong Menu | Chức năng |
| :--- | :--- | :--- |
| `./setup.sh --all` hoặc `./setup.sh 0` | Option `[ 0 ]` | Chạy tự động toàn bộ 12 bước từ A-Z |
| `./setup.sh --step <N>` hoặc `./setup.sh <N>` | Option `[ 1-12 ]` | Chạy riêng lẻ Bước N (Ví dụ: `./setup.sh 8` để Re-build Image) |
| `./setup.sh --check` hoặc `./setup.sh k` | Option `[ K ]` | Hiển thị bảng Health Check trạng thái các bước |
| `./setup.sh --edit` hoặc `./setup.sh e` | Option `[ E ]` | Mở công cụ chỉnh sửa `site_config.json` hoặc `common_site_config.json` bằng nano/vi |
| `./setup.sh --down` hoặc `./setup.sh d` | Option `[ D ]` | Thực thi dừng & xóa sạch toàn bộ hệ thống Docker (yêu cầu xác nhận) |

---

## 📊 5. Bảng Đối Chiếu Menu Script và File Workflow

| Bước Menu | Tên Bước Trong Script | Mục Tương Ứng Trong `workflow.md` |
| :---: | :--- | :--- |
| **Bước 1** | Kiểm tra quyền Root/Sudo & Môi trường | Mục 1: Yêu cầu quyền sudo / root |
| **Bước 2** | Kiểm tra & Đọc file cấu hình `.env` | Mục 6: Đọc & Kiểm tra file `.env` |
| **Bước 3** | Cập nhật hệ thống APT | Mục 2: Cập nhật APT trên VPS |
| **Bước 4** | Cài đặt Git, Docker Engine, Compose v2 | Mục 3: Cài đặt các yêu cầu (Prerequisites) |
| **Bước 5** | Khởi tạo thư mục (`~/frappe-packaging`, `~/gitops`) | Mục 4: Tạo thư mục làm việc |
| **Bước 6** | Clone repository `frappe_docker` | Mục 5: Clone Repository `frappe_docker` |
| **Bước 7** | Khởi tạo file secret `apps.json` | Mục 6: Đọc & Kiểm tra file `.env` |
| **Bước 8** | Build Custom Docker Image | Mục 7: Build Custom Docker Image |
| **Bước 9** | Khởi chạy Traefik & Cloudflare Tunnel | Mục 8: Thiết lập Proxy & Cloudflare Tunnel |
| **Bước 10** | Khởi chạy MariaDB Shared Database | Mục 9: Thiết lập MariaDB Shared |
| **Bước 11** | Deploy Project Stack | Mục 10 & 11: Cấu hình & Deploy Project Stack |
| **Bước 12** | Tạo Site & Cài đặt Custom Apps | Mục 12: Tạo Site và Cài đặt các Custom Apps |
| **Option E** | Chỉnh sửa `site_config.json` / `common_site_config.json` | Quản trị và cấu hình runtime nâng cao cho Frappe Site |
| **Option D** | Dừng & Xóa sạch toàn bộ hệ thống Docker | Thao tác Teardown / Dọn dẹp môi trường thử nghiệm |


