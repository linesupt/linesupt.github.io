#!/usr/bin/env bash
# ============================================================
# 04-cron-setup.sh
# 配置 cron 定时任务：每日凌晨检查证书有效期，临期自动续期。
#
# 用法：
#   ./04-cron-setup.sh
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RENEW_SCRIPT="$SCRIPT_DIR/03-auto-renew.sh"
LOG_FILE="/var/log/acme-autorenew.log"

# ====== 可调参数 ======
# 每日检查时刻（cron 分 时）
CRON_MINUTE="${CRON_MINUTE:-30}"    # 分钟
CRON_HOUR="${CRON_HOUR:-2}"          # 小时（凌晨2:30）
# ======================

if [ ! -f "$RENEW_SCRIPT" ]; then
    echo "[ERROR] 未找到续期脚本: $RENEW_SCRIPT"
    exit 1
fi

chmod +x "$SCRIPT_DIR"/*.sh

# 构造 cron 行
CRON_LINE="$CRON_MINUTE $CRON_HOUR * * * $RENEW_SCRIPT >> $LOG_FILE 2>&1"

echo "================ 配置 cron 定时任务 ================"
echo "  任务: $CRON_LINE"

# 备份现有 crontab
crontab -l > "${SCRIPT_DIR}/crontab.backup" 2>/dev/null || true
echo "  已备份当前 crontab 到 ${SCRIPT_DIR}/crontab.backup"

# 移除已存在的旧条目（防止重复添加）
( crontab -l 2>/dev/null | grep -v "ssl-autorenew/03-auto-renew.sh" ; echo "$CRON_LINE" ) | crontab -

echo ""
echo "================ 当前 crontab ================"
crontab -l 2>/dev/null | grep -E "acme|renew|ssl" || echo "  （无相关任务）"

echo ""
echo "================ 完成 ================"
echo "定时任务已配置，每日 $CRON_HOUR:$CRON_MINUTE 检查证书有效期。"
echo "日志文件: $LOG_FILE"
echo "可手动测试: $RENEW_SCRIPT"
