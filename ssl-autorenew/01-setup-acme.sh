#!/usr/bin/env bash
# ============================================================
# 01-setup-acme.sh
# 安装 acme.sh 并配置腾讯云 DNS API 凭证（用于自动验证域名）
#
# 用法：
#   ./01-setup-acme.sh
#   （执行前请先编辑下方的 腾讯云凭证 变量）
# ============================================================
set -euo pipefail

# ================================================================
# ★★★ 请在这里填写你的腾讯云 API 密钥 ★★★
#
# 获取方式：登录腾讯云控制台 -> 访问管理 CAM -> 访问密钥 -> API密钥管理
#   DP_ID  = SecretId    （以 AKID 开头，约32位大写字母+数字）
#   DP_KEY = SecretKey   （字母和数字组成的随机串）
#
# 填写示例：
#   DP_ID="AKIDLf9xxxxxabcdefghijklmnopqrstu"
#   DP_KEY="wJalrXUtnFEMIxxxxxYQzW5xZgGxxxxxxxxx"
#
# 注意：
#   1. 引号内的值直接替换为你自己的密钥，不要留空格
#   2. SecretId 和 SecretKey 必须成对填写，缺一不可
#   3. 若使用子账号密钥，需确保子账号有 DNS 解析（DNSPod）权限
# ================================================================
DP_ID=""
DP_KEY=""

# 接收证书到期提醒的邮箱（可留空，建议填写，如 admin@example.com）
ACME_EMAIL=""

# 域名（多域名用空格分隔，需全部在腾讯云 DNS 解析管理下）
# 默认即为 lineying.cn 和 www.lineying.cn，一般无需修改
DOMAINS="lineying.cn www.lineying.cn"
# ================================================================

echo "================ 01. 检查必要命令 ================"
for cmd in curl crontab openssl; do
    if command -v "$cmd" >/dev/null 2>&1; then
        echo "  [OK] $cmd"
    else
        echo "  [ERROR] 缺少命令: $cmd"
        exit 1
    fi
done

echo ""
echo "================ 02. 安装 acme.sh ================"
if [ ! -f "$HOME/.acme.sh/acme.sh" ]; then
    echo "  正在安装 acme.sh ..."
    if [ -n "$ACME_EMAIL" ]; then
        curl https://get.acme.sh | sh -s email="$ACME_EMAIL"
    else
        curl https://get.acme.sh | sh
    fi
    echo "  acme.sh 安装完成"
else
    echo "  acme.sh 已存在，跳过安装"
fi

ACME_BIN="$HOME/.acme.sh/acme.sh"
echo "  acme.sh 路径: $ACME_BIN"

echo ""
echo "================ 03. 配置腾讯云 DNS API 凭证 ================"
if [ -n "$DP_ID" ] && [ -n "$DP_KEY" ]; then
    "$ACME_BIN" --set-env "DP_Id=$DP_ID"
    "$ACME_BIN" --set-env "DP_Key=$DP_KEY"
    echo "  [OK] 已写入腾讯云 DNS 凭证 (DP_Id / DP_Key)"
else
    echo "  [WARN] 未检测到 DP_ID/DP_KEY，请手动设置环境变量后重试，或编辑本脚本头部。"
    echo "  凭证将写入 acme.sh 账户配置 (~/.acme.sh/account.conf)，不会提交到 git。"
fi

echo ""
echo "================ 04. 配置自动升级 ================"
# acme.sh 默认已自动配置定时任务用于自动升级
crontab -l 2>/dev/null | grep acme.sh >/dev/null && echo "  [OK] acme.sh 定时任务已存在" || echo "  [WARN] 未发现 acme.sh 定时任务（稍后通过 03-cron-setup.sh 配置）"

echo ""
echo "================ 完成 ================"
echo "下一步：执行 ./02-issue-cert.sh 签发并安装证书"
echo "（脚本需可执行：chmod +x *.sh）"
