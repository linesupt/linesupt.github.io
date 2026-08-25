#!/usr/bin/env bash
# ============================================================
# 02-issue-cert.sh
# 使用 acme.sh + 腾讯云 DNS API 签发 Let's Encrypt 证书，
# 并将证书安装到 Nginx 证书目录，随后重载 Nginx。
#
# 用法：
#   ./02-issue-cert.sh
# ============================================================
set -euo pipefail

# ====== 用户需在此确认 ======
DOMAINS="${DOMAINS:-lineying.cn www.lineying.cn}"

# Nginx 证书存放目录（会自动创建）
CERT_DIR="/etc/nginx/ssl"
# Nginx reload 命令（Debian/Ubuntu 用 systemctl reload nginx）
RELOAD_CMD="systemctl reload nginx"
# ===========================

ACME_BIN="$HOME/.acme.sh/acme.sh"
PRIMARY_DOMAIN="${DOMAINS%% *}"   # 取第一个域名为主域名

# 将空格分隔的域名列表转换为 acme.sh 的多个 -d 参数
# 例：DOMAINS="a.com b.com" -> -d a.com -d b.com
build_domain_args() {
    local args=""
    for d in $DOMAINS; do
        args="$args -d $d"
    done
    echo "$args"
}

echo "================ 01. 校验凭证 ================"
# 检查腾讯云 DNS 凭证是否已配置
if grep -qE "DP_Id=|DP_Key=" "$HOME/.acme.sh/account.conf" 2>/dev/null \
   && ! grep -qE "DP_Id=\"?\"?$|DP_Key=\"?\"?$" "$HOME/.acme.sh/account.conf" 2>/dev/null; then
    echo "  [OK] 检测到腾讯云 DNS 凭证"
else
    echo "  [ERROR] 未找到腾讯云 DNS 凭证，请先执行 01-setup-acme.sh"
    exit 1
fi

echo ""
echo "================ 02. 签发证书 ================"
echo "  域名: $DOMAINS"
echo "  （DNS-01 验证：通过腾讯云 DNS API 自动添加 TXT 记录）"

DOMAIN_ARGS=$(build_domain_args)

# 签发或更新证书；若已存在且仍有效则自动跳过
if "$ACME_BIN" --issue --dns dns_myapi $DOMAIN_ARGS --server letsencrypt 2>/dev/null; then
    echo "  [OK] 证书签发/更新完成"
else
    echo "  [WARN] 首次签发失败，尝试以注册/重签方式处理 ..."
    "$ACME_BIN" --issue --dns dns_myapi $DOMAIN_ARGS --server letsencrypt --force
fi

echo ""
echo "================ 03. 安装到 Nginx ================"
mkdir -p "$CERT_DIR"

# 使用 acme.sh 的 install-cert 将证书复制到指定目录并绑定 reload 命令
"$ACME_BIN" --install-cert -d "$PRIMARY_DOMAIN" \
    --key-file "$CERT_DIR/$PRIMARY_DOMAIN.key" \
    --fullchain-file "$CERT_DIR/$PRIMARY_DOMAIN.pem" \
    --reloadcmd "$RELOAD_CMD"

echo "  [OK] 证书已安装:"
echo "      证书: $CERT_DIR/$PRIMARY_DOMAIN.pem"
echo "      密钥: $CERT_DIR/$PRIMARY_DOMAIN.key"

echo ""
echo "================ 04. 校验 ================"
if [ -f "$CERT_DIR/$PRIMARY_DOMAIN.pem" ]; then
    echo "  证书文件信息："
    openssl x509 -in "$CERT_DIR/$PRIMARY_DOMAIN.pem" -noout -subject -issuer -dates 2>/dev/null || true
    echo ""
    echo "  证书剩余有效期："
    openssl x509 -in "$CERT_DIR/$PRIMARY_DOMAIN.pem" -noout -enddate 2>/dev/null || true
else
    echo "  [WARN] 未找到证书文件，请检查上方输出"
fi

echo ""
echo "================ 完成 ================"
echo "请确认 Nginx 配置文件已指向上述证书路径（参考 nginx-ssl.conf.example）"
echo "部署后使用 https://$PRIMARY_DOMAIN 访问验证。"
