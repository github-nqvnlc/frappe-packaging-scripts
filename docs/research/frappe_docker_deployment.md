# Phân Tích Quy Trình Đóng Gói và Triển Khai Frappe Docker Với Custom App

Dựa trên tài liệu chính thức từ repository `frappe_docker`, dưới đây là phân tích và hướng giải quyết tối ưu cho các yêu cầu của bạn.

---

## 1. Đóng Gói Site Với Custom App Có Sẵn

Để đóng gói một Frappe/ERPNext site cùng với một (hoặc nhiều) custom app, phương pháp chuẩn là tạo một **Custom Docker Image** thay vì sử dụng ảnh mặc định. Frappe Docker cung cấp các Dockerfile chuyên dụng cho việc này tại thư mục `images/custom/` hoặc `images/layered/`.

**Cách thực hiện:**

1. **Tạo file `apps.json`**:
   Bạn định nghĩa các custom apps cần cài đặt trong một file `apps.json`.
   Ví dụ:
   ```json
   [
     {
       "url": "https://github.com/your-username/your_custom_app.git",
       "branch": "main"
     }
   ]
   ```
2. **Build Image với Docker Buildx**:
   Dùng lệnh `docker build` kết hợp với tham số `--secret` để truyền file `apps.json` vào quá trình build một cách an toàn mà không bị lưu lại trong các layer của Docker.
   ```bash
   docker build \
     --build-arg=FRAPPE_PATH=https://github.com/frappe/frappe \
     --build-arg=FRAPPE_BRANCH=version-15 \
     --secret=id=apps_json,src=apps.json \
     --tag=my-registry/my-custom-image:v1 \
     --file=images/layered/Containerfile .
   ```
   *(Sử dụng `images/layered/Containerfile` sẽ giúp build nhanh hơn nhờ tận dụng các layer build sẵn của Frappe, trong khi `images/custom/Containerfile` cho phép kiểm soát sâu hơn vào phiên bản Python/Node).*

---

## 2. Quy Trình Đóng Gói Hợp Lý (CI/CD)

Nếu bạn muốn đóng gói và duy trì quy trình chuyên nghiệp, tự động hoá (Automated Builds), đây là workflow khuyên dùng:

1. **Tạo Repository Quản Lý Cấu Hình**:
   Không nên chỉnh sửa trực tiếp trên repo `frappe_docker`. Bạn hãy dùng một repo riêng (hoặc fork repo gốc) chứa file `apps.json` và các workflow CI/CD (như GitHub Actions, GitLab CI).

2. **Quản Lý Build Cache (Cực kỳ quan trọng)**:
   Do `apps.json` được truyền dưới dạng `secret`, Docker sẽ không tự động nhận diện thay đổi bên trong file này để build lại (Cache Invalidation).
   Để giải quyết, bạn cần sử dụng tham số `--build-arg=CACHE_BUST`. Một cách tối ưu là dùng **hash của `apps.json`**:
   ```yaml
   # Trong file workflow (ví dụ GitHub Actions)
   - name: Build Docker image
     shell: sh
     run: |
       docker build \
         --build-arg=FRAPPE_PATH=https://github.com/frappe/frappe \
         --build-arg=FRAPPE_BRANCH=version-15 \
         --build-arg=CACHE_BUST="$(sha256sum apps.json | awk '{print $1}')" \
         --secret=id=apps_json,src=apps.json \
         --tag=my-registry/my-custom-image:v1 \
         --file=images/layered/Containerfile .
   ```
   Điều này đảm bảo image chỉ build lại (install lại custom app) khi nội dung `apps.json` thay đổi.

3. **Database Migrations Tự Động**:
   Sau khi image mới được push và deploy, bạn **bắt buộc** phải chạy `bench migrate`. Thay vì chạy tay bằng exec vào container, bạn có thể thêm service `migrator` vào file cấu hình compose (ví dụ: `overrides/compose.migrator.yaml`) để hệ thống tự động chạy migrate khi khởi động stack.

---

## 3. Đưa Site Lên Trực Tiếp Với Domain (Single Server Setup)

Quy trình sử dụng Traefik làm Reverse Proxy & Tự động cấp phát SSL (Let's Encrypt) như sau:

### Bước 1: Khởi tạo Network và Traefik
Bạn sẽ sử dụng Traefik làm Load Balancer chung để xử lý cổng `80` và `443`.
Tạo cấu hình Traefik và chạy nó ở dạng background (tham khảo file `compose.traefik.yaml` và `compose.traefik-ssl.yaml`).

### Bước 2: Dựng Database (MariaDB Shared)
Khởi chạy một instance MariaDB dùng chung cho các bench thông qua file cấu hình (ví dụ: `compose.mariadb-shared.yaml`).

### Bước 3: Cấu hình và Deploy Project (Bench) của bạn
Tạo một file `.env` (ví dụ `my-project.env`) định nghĩa cấu hình hệ thống, bao gồm cả biến trỏ tới image custom mà bạn đã build ở trên.

Nội dung `.env` trọng tâm cần chú ý:
```env
# Sử dụng image đã build có chứa custom app
BACKEND_IMAGE=my-registry/my-custom-image:v1
FRONTEND_IMAGE=my-registry/my-custom-image:v1
# ... các config DB, Redis ...

# Quan trọng: Khai báo routing domain
ROUTER=my-project-router
SITES_RULE=Host(`yourdomain.com`)
```

Generate file yaml tổng hợp và chạy:
```bash
docker compose --project-name my-project \
  --env-file my-project.env \
  -f compose.yaml \
  -f overrides/compose.redis.yaml \
  -f overrides/compose.multi-bench.yaml \
  -f overrides/compose.multi-bench-ssl.yaml config > my-project.yaml

docker compose --project-name my-project -f my-project.yaml up -d
```

### Bước 4: Tạo Site Mới Gắn Với Domain Và Custom App
Bước cuối cùng, bạn vào trong `backend` container để tạo site mới trùng với tên miền của bạn và cài đặt custom app (ở đây đã có sẵn trong image).

```bash
docker compose --project-name my-project exec backend \
  bench new-site yourdomain.com \
  --mariadb-user-host-login-scope=% \
  --db-root-password YOUR_DB_ROOT_PASSWORD \
  --admin-password YOUR_ADMIN_PASSWORD \
  --install-app your_custom_app
```

Bằng cách sử dụng lệnh này, site `yourdomain.com` sẽ được tạo ra, cấu hình Nginx bên trong container Traefik sẽ tự động nhận diện routing qua nhãn (labels) cấu hình trong `compose.multi-bench.yaml` (hoặc `compose.https.yaml`), tự xin SSL Let's Encrypt và bạn có thể truy cập site trực tiếp từ domain `https://yourdomain.com`.
