# SSL 证书自动续期方案（acme.sh + 腾讯云 DNS）

本方案用于在 **腾讯云 CVM + Nginx** 服务器上，实现 **Let's Encrypt 免费证书**的自动申请与续期，并在证书过期前（默认 **提前 7 天**）自动部署到 Nginx，全程无需人工干预。

## 原理

```
每日 cron 定时任务
      │
      ▼
03-auto-renew.sh ── 检查证书剩余有效期
      │
      ├── 剩余天数 > 7 天 ──▶ 无需操作，直接结束
      │
      └── 剩余天数 ≤ 7 天（或证书不存在）
            │
            ▼
      acme.sh --renew ──▶ 通过腾讯云 DNS API 自动添加 TXT 验证记录
            │
            ▼
      acme.sh --install-cert ──▶ 安装新证书到 /etc/nginx/ssl/
            │
            ▼
      systemctl reload nginx ──▶ HTTPS 自动生效
```

- **证书来源**：Let's Encrypt（有效期 90 天，免费）
- **域名验证**：DNS-01（通过腾讯云 DNS API 自动添加 TXT 记录，支持泛域名/多域名）
- **自动部署**：证书更新后自动重载 Nginx

## 文件说明

| 文件 | 作用 |
|------|------|
| `01-setup-acme.sh` | 安装 acme.sh，配置腾讯云 DNS API 凭证 |
| `02-issue-cert.sh` | 首次签发证书并安装到 Nginx |
| `03-auto-renew.sh` | 自动续期核心脚本（每日检查，临期续期） |
| `04-cron-setup.sh` | 配置 cron 每日定时任务 |
| `nginx-ssl.conf.example` | Nginx HTTPS 配置示例 |

---

## 一、前置准备

### 1. 获取腾讯云 API 密钥
1. 登录 [腾讯云控制台](https://console.cloud.tencent.com/)
2. 进入 **访问管理 CAM → API 密钥管理**
3. 创建/复制 **SecretId** 和 **SecretKey**
   - 密钥有较高权限，建议使用**子账号**并仅授予 `QcloudDNSAPIFullAccess`（DNS 解析）权限，以降低风险

### 2. 确认域名已在腾讯云 DNS 解析
- 域名 `lineying.cn`、`www.lineying.cn` 的解析记录需托管在腾讯云 DNS 解析（DNSPod）下
- 若当前域名解析在阿里云等其他平台，需先迁移到腾讯云，或改用其他 DNS 插件

### 3. 上传脚本到服务器
将 `ssl-autorenew/` 整个目录上传到服务器，例如 `/opt/ssl-autorenew/`：

```bash
scp -r ssl-autorenew root@你的服务器IP:/opt/
```

---

## 二、部署步骤

### 第 1 步：安装 acme.sh 并配置腾讯云凭证

```bash
cd /opt/ssl-autorenew
chmod +x *.sh

# 编辑 01-setup-acme.sh，填写以下变量：
#   DP_ID     = 腾讯云 SecretId
#   DP_KEY    = 腾讯云 SecretKey
#   ACME_EMAIL= 接收到期提醒的邮箱（可选）
#   DOMAINS   = "lineying.cn www.lineying.cn"

./01-setup-acme.sh
```

### 第 2 步：首次签发证书

```bash
./02-issue-cert.sh
```

成功后会生成证书：
- `/etc/nginx/ssl/lineying.cn.pem`
- `/etc/nginx/ssl/lineying.cn.key`

### 第 3 步：配置 Nginx

参考 `nginx-ssl.conf.example`，在 Nginx 站点配置中启用 HTTPS：

```bash
# 将 nginx-ssl.conf.example 内容复制到你的 server 配置
# 注意修改 root 路径为你的网站实际目录
cp nginx-ssl.conf.example /etc/nginx/conf.d/lineying-ssl.conf
vi /etc/nginx/conf.d/lineying-ssl.conf   # 修改 root 路径

# 校验配置并重载
nginx -t && systemctl reload nginx
```

### 第 4 步：配置自动续期定时任务

```bash
./04-cron-setup.sh
```

该脚本会添加 cron 任务：**每日凌晨 2:30** 运行 `03-auto-renew.sh`。

---

## 三、验证

### 1. 验证 HTTPS 正常访问
```bash
curl -v https://lineying.cn   # 应看到 SSL certificate verify ok
```

### 2. 查看证书有效期
```bash
openssl x509 -in /etc/nginx/ssl/lineying.cn.pem -noout -dates
```

### 3. 查看自动续期日志
```bash
tail -f /var/log/acme-autorenew.log
```

### 4. 手动触发一次续期检查
```bash
/opt/ssl-autorenew/03-auto-renew.sh
```

---

## 四、注意事项

1. **提前量可调**：修改 `03-auto-renew.sh` 中的 `RENEW_THRESHOLD=7`，可改为提前 30/60 天续期。
2. **证书默认有效期 90 天**，提前 7 天触发续期，实际有约 83 天的正常使用窗口，若续期失败仍有 7 天补救时间。
3. **安全建议**：腾讯云 API 密钥请使用**子账号**并最小权限授权（DNS 解析权限即可），并妥善保管。
4. **域名托管**：本方案要求域名解析托管在**腾讯云 DNS**（DNSPod）。若您的域名解析在其他平台，此方案需调整。
5. **备份**：`04-cron-setup.sh` 会备份原 crontab 到 `crontab.backup`。
6. **防火墙**：确保服务器安全组/防火墙放行 **443** 端口。

---

## 五、常见问题

### Q1：签发时报 "凭证无效"？
- 检查 `DP_ID`/`DP_KEY` 是否填写正确
- 确认子账号已授权 DNS 解析权限

### Q2：`dns_myapi` 插件不支持？
- acme.sh 通过 `DP_Id`/`DP_Key` 环境变量识别腾讯云，插件名固定为 `dns_myapi`
- 升级 acme.sh：`acme.sh --upgrade`

### Q3：续期后 HTTPS 没生效？
- 检查 `03-auto-renew.sh` 中 `RELOAD_CMD` 是否与服务器 Nginx 重载方式匹配
- 手动执行 `systemctl reload nginx` 验证

### Q4：域名解析不在腾讯云？
- 方案需使用 DNSPod API，若解析在其他平台，可改用对应平台的 DNS 插件（如阿里云 `dns_ali`）
- 或在 02/03 脚本中将 `--dns dns_myapi` 替换为对应插件
