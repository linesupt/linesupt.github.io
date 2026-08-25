#!/usr/bin/env bash
# ============================================================
# 03-auto-renew.sh
# 自动续期核心脚本：每日检查证书剩余有效期，
# 当剩余天数 < RENEW_THRESHOLD（默认 7 天）时，自动续期并部署 Nginx。
#
# 该脚本应通过 cron 每日执行（见 04-cron-setup.sh）。
# 也可手动运行：./03-auto-renew.sh
# ============================================================
set -euo pipefail

# ====== 可调参数 ======
DOMAINS="${DOMAINS:-lineying.cn www.lineying.cn}"
PRIMARY_DOMAIN="${DOMAINS%% *}"
CERT_DIR="/etc/nginx/ssl"
# 续期阈值：证书剩余有效期小于该天数（天）时触发续期
RENEW_THRESHOLD="${RENEW_THRESHOLD:-7}"
ACME_BIN="$HOME/.acme.sh/acme.sh"
LOG_FILE="${LOG_FILE:-/var/log/acme-autorenew.log}"
RELOAD_CMD="systemctl reload nginx"
# ======================

# 将空格分隔的域名列表转换为 acme.sh 的多个 -d 参数
# 例：DOMAINS="a.com b.com" -> -d a.com -d b.com
build_domain_args() {
    local args=""
    for d in $DOMAINS; do
        args="$args -d $d"
    done
    echo "$args"
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# 计算证书剩余有效期（天）
cert_remaining_days() {
    local cert="$1"
    if [ ! -f "$cert" ]; then
        echo "9999"   # 证书不存在时返回一个大数，走首次签发流程
        return 0
    fi

    # 提取 notAfter= 之后的日期字符串，如 "Aug 29 17:16:58 2026 GMT"
    local end_str
    end_str=$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null | cut -d= -f2- | xargs)
    if [ -z "$end_str" ]; then
        echo "9999"
        return 0
    fi

    # 解析为时间戳：优先 GNU date(-d)，兼容 BSD date(-jf)
    local end_epoch=""
    end_epoch=$(date -d "$end_str" +%s 2>/dev/null || true)
    if [ -z "$end_epoch" ] || ! echo "$end_epoch" | grep -qE '^[0-9]+$'; then
        end_epoch=$(date -jf "%b %d %T %Y %Z" "$end_str" +%s 2>/dev/null || echo "")
    fi
    if [ -z "$end_epoch" ] || ! echo "$end_epoch" | grep -qE '^[0-9]+$'; then
        echo "9999"
        return 0
    fi

    local now_epoch diff_days
    now_epoch=$(date +%s)
    diff_days=$(( (end_epoch - now_epoch) / 86400 ))
    echo "$diff_days"
}

# 主流程
main() {
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"

    local cert_file="$CERT_DIR/$PRIMARY_DOMAIN.pem"
    local remaining
    local domain_args
    remaining=$(cert_remaining_days "$cert_file")
    domain_args=$(build_domain_args)

    if [ -z "$remaining" ] || [ "$remaining" -gt 9000 ]; then
        # 证书不存在，执行首次签发
        log "证书不存在，执行首次签发"
        "$ACME_BIN" --issue --dns dns_myapi $domain_args --server letsencrypt --force > /dev/null 2>&1
        "$ACME_BIN" --install-cert -d "$PRIMARY_DOMAIN" \
            --key-file "$CERT_DIR/$PRIMARY_DOMAIN.key" \
            --fullchain-file "$cert_file" \
            --reloadcmd "$RELOAD_CMD" > /dev/null 2>&1
        log "首次签发并部署完成"
        exit 0
    fi

    if [ "$remaining" -le "$RENEW_THRESHOLD" ]; then
        log "证书剩余 $remaining 天（阈值 ${RENEW_THRESHOLD} 天），触发自动续期"
        "$ACME_BIN" --renew --dns dns_myapi $domain_args --server letsencrypt > /dev/null 2>&1 \
            && "$ACME_BIN" --install-cert -d "$PRIMARY_DOMAIN" \
                --key-file "$CERT_DIR/$PRIMARY_DOMAIN.key" \
                --fullchain-file "$cert_file" \
                --reloadcmd "$RELOAD_CMD" > /dev/null 2>&1
        log "自动续期完成，证书剩余有效期：$(cert_remaining_days "$cert_file") 天"
    else
        log "证书剩余 $remaining 天，无需续期（阈值 ${RENEW_THRESHOLD} 天）"
    fi
}

main
