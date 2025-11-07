#!/bin/bash

##############################################

# VPS 完整系统备份和恢复脚本

# 功能: 系统快照、配置备份、远程上传、自动恢复

##############################################

set -e

# 颜色定义

RED=’\033[0;31m’
GREEN=’\033[0;32m’
YELLOW=’\033[1;33m’
NC=’\033[0m’ # No Color

# 配置文件路径

CONFIG_FILE=”/etc/vps-backup.conf”

# 日志函数

log_info() {
echo -e “${GREEN}[INFO]${NC} $(date ‘+%Y-%m-%d %H:%M:%S’) - $1”
}

log_warn() {
echo -e “${YELLOW}[WARN]${NC} $(date ‘+%Y-%m-%d %H:%M:%S’) - $1”
}

log_error() {
echo -e “${RED}[ERROR]${NC} $(date ‘+%Y-%m-%d %H:%M:%S’) - $1”
}

# 显示帮助信息

show_help() {
cat << EOF
VPS 完整系统备份和恢复工具

使用方法:
$0 [选项]

选项:
quickstart      一键快速配置（推荐新手）
setup           手动配置备份参数
backup          执行完整备份
restore         从备份恢复系统
list            列出所有备份
upload          手动上传备份到远程
schedule        设置自动备份计划
help            显示此帮助信息

示例:
$0 quickstart   # 一键配置并立即备份
$0 backup       # 执行备份
$0 restore      # 恢复系统

EOF
}

# 一键快速配置

quickstart_config() {
log_info “开始一键配置备份系统…”

```
# 自动检测MySQL
local MYSQL_INSTALLED="n"
local MYSQL_ROOT_PASS=""
if command -v mysql &> /dev/null || command -v mysqld &> /dev/null; then
    MYSQL_INSTALLED="y"
    log_info "检测到MySQL/MariaDB"
    echo ""
    read -sp "请输入MySQL root密码（直接回车跳过数据库备份）: " MYSQL_ROOT_PASS
    echo ""
    if [[ -z "$MYSQL_ROOT_PASS" ]]; then
        MYSQL_INSTALLED="n"
        log_warn "跳过MySQL备份"
    fi
fi

# 自动检测PostgreSQL
local POSTGRES_INSTALLED="n"
if command -v psql &> /dev/null || command -v postgres &> /dev/null; then
    POSTGRES_INSTALLED="y"
    log_info "检测到PostgreSQL"
fi

# 自动检测Web目录
local EXTRA_DIRS=""
if [[ -d "/var/www" ]]; then
    EXTRA_DIRS="/var/www"
    log_info "检测到网站目录: /var/www"
fi
if [[ -d "/opt" ]]; then
    if [[ -n "$EXTRA_DIRS" ]]; then
        EXTRA_DIRS="$EXTRA_DIRS,/opt"
    else
        EXTRA_DIRS="/opt"
    fi
    log_info "检测到应用目录: /opt"
fi

# 生成默认配置
cat > "$CONFIG_FILE" << EOF
```

# VPS 备份系统配置文件（一键配置生成）

# 生成时间: $(date)

# 本地备份配置

BACKUP_DIR=”/backup”
RETENTION_DAYS=7

# 远程备份配置（默认关闭，可稍后手动配置）

REMOTE_ENABLED=false
REMOTE_METHOD=””

# 备份目录配置

EXTRA_DIRS=”$EXTRA_DIRS”
EXCLUDE_DIRS=”/tmp,/var/cache,/var/log”

# 数据库配置

BACKUP_MYSQL=”$MYSQL_INSTALLED”
MYSQL_ROOT_PASS=”$MYSQL_ROOT_PASS”
BACKUP_POSTGRES=”$POSTGRES_INSTALLED”

EOF

```
chmod 600 "$CONFIG_FILE"

# 创建备份目录
mkdir -p /backup

log_info "配置文件已创建: $CONFIG_FILE"
echo ""
echo -e "${GREEN}配置摘要:${NC}"
echo "  备份目录: /backup"
echo "  保留天数: 7天"
echo "  额外目录: ${EXTRA_DIRS:-无}"
echo "  MySQL备份: $MYSQL_INSTALLED"
echo "  PostgreSQL备份: $POSTGRES_INSTALLED"
echo "  远程备份: 关闭（可后续配置）"
echo ""

# 安装依赖
install_dependencies

log_info "一键配置完成！"
echo ""
read -p "是否立即执行第一次备份？(y/n): " do_backup
if [[ "$do_backup" == "y" ]]; then
    echo ""
    do_backup
else
    log_info "稍后可运行: vps-backup backup"
fi
```

}

# 首次配置

setup_config() {
log_info “开始配置备份系统…”

```
echo ""
echo "=== VPS 备份系统配置 ==="
echo ""

# 本地备份目录
read -p "本地备份保存目录 [默认: /backup]: " BACKUP_DIR
BACKUP_DIR=${BACKUP_DIR:-/backup}

# 备份保留天数
read -p "本地备份保留天数 [默认: 7]: " RETENTION_DAYS
RETENTION_DAYS=${RETENTION_DAYS:-7}

# 远程备份配置
echo ""
echo "远程备份方式:"
echo "1) SFTP/SCP (SSH远程服务器)"
echo "2) S3兼容对象存储 (AWS S3/阿里云OSS/腾讯云COS等)"
echo "3) WebDAV"
echo "4) 不使用远程备份"
read -p "选择远程备份方式 [1-4]: " REMOTE_TYPE

REMOTE_ENABLED="false"

case $REMOTE_TYPE in
    1)
        REMOTE_METHOD="sftp"
        REMOTE_ENABLED="true"
        read -p "远程服务器地址: " REMOTE_HOST
        read -p "远程服务器端口 [默认: 22]: " REMOTE_PORT
        REMOTE_PORT=${REMOTE_PORT:-22}
        read -p "远程服务器用户名: " REMOTE_USER
        read -p "远程服务器路径: " REMOTE_PATH
        read -p "SSH密钥路径 [默认: ~/.ssh/id_rsa]: " SSH_KEY
        SSH_KEY=${SSH_KEY:-~/.ssh/id_rsa}
        ;;
    2)
        REMOTE_METHOD="s3"
        REMOTE_ENABLED="true"
        read -p "S3 Endpoint (如: s3.amazonaws.com): " S3_ENDPOINT
        read -p "S3 Bucket 名称: " S3_BUCKET
        read -p "S3 Access Key: " S3_ACCESS_KEY
        read -sp "S3 Secret Key: " S3_SECRET_KEY
        echo ""
        read -p "S3 Region [默认: us-east-1]: " S3_REGION
        S3_REGION=${S3_REGION:-us-east-1}
        ;;
    3)
        REMOTE_METHOD="webdav"
        REMOTE_ENABLED="true"
        read -p "WebDAV URL: " WEBDAV_URL
        read -p "WebDAV 用户名: " WEBDAV_USER
        read -sp "WebDAV 密码: " WEBDAV_PASS
        echo ""
        ;;
    4)
        REMOTE_ENABLED="false"
        log_info "跳过远程备份配置"
        ;;
esac

# 要备份的额外目录
echo ""
read -p "需要备份的额外目录 (逗号分隔，如: /var/www,/opt/app): " EXTRA_DIRS

# 要排除的目录
read -p "需要排除的目录 (逗号分隔，如: /tmp,/var/cache): " EXCLUDE_DIRS

# 是否备份数据库
echo ""
read -p "是否备份MySQL/MariaDB数据库? (y/n): " BACKUP_MYSQL
if [[ "$BACKUP_MYSQL" == "y" ]]; then
    read -p "MySQL root密码: " MYSQL_ROOT_PASS
fi

read -p "是否备份PostgreSQL数据库? (y/n): " BACKUP_POSTGRES

# 生成配置文件
cat > "$CONFIG_FILE" << EOF_CONFIG
```

# VPS 备份系统配置文件

# 生成时间: $(date)

# 本地备份配置

BACKUP_DIR=”$BACKUP_DIR”
RETENTION_DAYS=$RETENTION_DAYS

# 远程备份配置

REMOTE_ENABLED=$REMOTE_ENABLED
REMOTE_METHOD=”$REMOTE_METHOD”

EOF_CONFIG

```
if [[ "$REMOTE_ENABLED" == "true" ]]; then
    case $REMOTE_METHOD in
        sftp)
            cat >> "$CONFIG_FILE" << EOF_CONFIG
```

# SFTP配置

REMOTE_HOST=”$REMOTE_HOST”
REMOTE_PORT=$REMOTE_PORT
REMOTE_USER=”$REMOTE_USER”
REMOTE_PATH=”$REMOTE_PATH”
SSH_KEY=”$SSH_KEY”

EOF_CONFIG
;;
s3)
cat >> “$CONFIG_FILE” << EOF_CONFIG

# S3配置

S3_ENDPOINT=”$S3_ENDPOINT”
S3_BUCKET=”$S3_BUCKET”
S3_ACCESS_KEY=”$S3_ACCESS_KEY”
S3_SECRET_KEY=”$S3_SECRET_KEY”
S3_REGION=”$S3_REGION”

EOF_CONFIG
;;
webdav)
cat >> “$CONFIG_FILE” << EOF_CONFIG

# WebDAV配置

WEBDAV_URL=”$WEBDAV_URL”
WEBDAV_USER=”$WEBDAV_USER”
WEBDAV_PASS=”$WEBDAV_PASS”

EOF_CONFIG
;;
esac
fi

```
cat >> "$CONFIG_FILE" << EOF_CONFIG
```

# 备份目录配置

EXTRA_DIRS=”$EXTRA_DIRS”
EXCLUDE_DIRS=”$EXCLUDE_DIRS”

# 数据库配置

BACKUP_MYSQL=”$BACKUP_MYSQL”
MYSQL_ROOT_PASS=”$MYSQL_ROOT_PASS”
BACKUP_POSTGRES=”$BACKUP_POSTGRES”

EOF_CONFIG

```
chmod 600 "$CONFIG_FILE"

# 创建备份目录
mkdir -p "$BACKUP_DIR"

log_info "配置已保存到 $CONFIG_FILE"
log_info "备份目录: $BACKUP_DIR"

# 安装必要的工具
install_dependencies

log_info "配置完成！现在可以运行: $0 backup"
```

}

# 安装依赖

install_dependencies() {
log_info “检查并安装必要的工具…”

```
if command -v apt-get &> /dev/null; then
    apt-get update -qq
    apt-get install -y rsync tar gzip pigz pv curl &> /dev/null || true
    
    if [[ "$REMOTE_METHOD" == "s3" ]]; then
        apt-get install -y awscli &> /dev/null || {
            log_warn "无法通过apt安装awscli，尝试使用pip..."
            apt-get install -y python3-pip &> /dev/null
            pip3 install awscli &> /dev/null || log_error "AWS CLI安装失败"
        }
    fi
    
    if [[ "$REMOTE_METHOD" == "webdav" ]]; then
        apt-get install -y cadaver &> /dev/null || log_warn "WebDAV客户端安装失败"
    fi
    
elif command -v yum &> /dev/null; then
    yum install -y rsync tar gzip pigz pv curl &> /dev/null || true
    
    if [[ "$REMOTE_METHOD" == "s3" ]]; then
        yum install -y awscli &> /dev/null || {
            yum install -y python3-pip &> /dev/null
            pip3 install awscli &> /dev/null || log_error "AWS CLI安装失败"
        }
    fi
fi

log_info "依赖安装完成"
```

}

# 加载配置

load_config() {
if [[ ! -f “$CONFIG_FILE” ]]; then
log_error “配置文件不存在，请先运行: $0 setup”
exit 1
fi

```
source "$CONFIG_FILE"
```

}

# 执行备份

do_backup() {
load_config

```
local TIMESTAMP=$(date +%Y%m%d_%H%M%S)
local BACKUP_NAME="vps_backup_${TIMESTAMP}"
local BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"

log_info "开始备份: $BACKUP_NAME"

mkdir -p "$BACKUP_PATH"

# 1. 备份系统信息
log_info "收集系统信息..."
mkdir -p "${BACKUP_PATH}/system_info"

uname -a > "${BACKUP_PATH}/system_info/uname.txt"
cat /etc/os-release > "${BACKUP_PATH}/system_info/os-release.txt" 2>/dev/null || true
df -h > "${BACKUP_PATH}/system_info/disk_usage.txt"
free -h > "${BACKUP_PATH}/system_info/memory.txt"
ip addr > "${BACKUP_PATH}/system_info/network.txt"
dpkg -l > "${BACKUP_PATH}/system_info/packages.txt" 2>/dev/null || rpm -qa > "${BACKUP_PATH}/system_info/packages.txt" 2>/dev/null || true
systemctl list-units > "${BACKUP_PATH}/system_info/services.txt" 2>/dev/null || true

# 2. 备份关键配置文件
log_info "备份系统配置..."
mkdir -p "${BACKUP_PATH}/etc"

rsync -a --exclude='shadow*' --exclude='gshadow*' \
    /etc/ "${BACKUP_PATH}/etc/" 2>/dev/null || true

# 3. 备份用户数据
log_info "备份用户数据..."

if [[ -d /home ]]; then
    rsync -a /home/ "${BACKUP_PATH}/home/" 2>/dev/null || true
fi

if [[ -d /root ]]; then
    rsync -a /root/ "${BACKUP_PATH}/root/" 2>/dev/null || true
fi

# 4. 备份额外目录
if [[ -n "$EXTRA_DIRS" ]]; then
    log_info "备份额外目录..."
    IFS=',' read -ra DIRS <<< "$EXTRA_DIRS"
    for dir in "${DIRS[@]}"; do
        dir=$(echo "$dir" | xargs) # 去除空格
        if [[ -d "$dir" ]]; then
            log_info "备份: $dir"
            local target_dir="${BACKUP_PATH}/extra$(dirname "$dir")"
            mkdir -p "$target_dir"
            rsync -a "$dir" "$target_dir/" 2>/dev/null || true
        fi
    done
fi

# 5. 备份数据库
if [[ "$BACKUP_MYSQL" == "y" ]]; then
    log_info "备份MySQL数据库..."
    mkdir -p "${BACKUP_PATH}/databases/mysql"
    
    if command -v mysqldump &> /dev/null; then
        databases=$(mysql -u root -p"$MYSQL_ROOT_PASS" -e "SHOW DATABASES;" 2>/dev/null | grep -Ev "(Database|information_schema|performance_schema|mysql|sys)")
        
        for db in $databases; do
            log_info "备份数据库: $db"
            mysqldump -u root -p"$MYSQL_ROOT_PASS" --single-transaction --routines --triggers "$db" 2>/dev/null | \
                pigz > "${BACKUP_PATH}/databases/mysql/${db}.sql.gz" || true
        done
    fi
fi

if [[ "$BACKUP_POSTGRES" == "y" ]]; then
    log_info "备份PostgreSQL数据库..."
    mkdir -p "${BACKUP_PATH}/databases/postgresql"
    
    if command -v pg_dumpall &> /dev/null; then
        sudo -u postgres pg_dumpall 2>/dev/null | \
            pigz > "${BACKUP_PATH}/databases/postgresql/all_databases.sql.gz" || true
    fi
fi

# 6. 备份crontab
log_info "备份计划任务..."
mkdir -p "${BACKUP_PATH}/crontabs"
crontab -l > "${BACKUP_PATH}/crontabs/root_crontab.txt" 2>/dev/null || true
cp -r /etc/cron.* "${BACKUP_PATH}/crontabs/" 2>/dev/null || true

# 7. 创建恢复脚本
log_info "创建恢复脚本..."
cat > "${BACKUP_PATH}/RESTORE.sh" << 'EOF_RESTORE'
```

#!/bin/bash

# VPS 系统恢复脚本

# 自动生成

set -e

echo “=== VPS 系统恢复 ===”
echo “警告: 此操作将恢复系统配置，可能覆盖当前文件”
read -p “确定要继续吗? (yes/no): “ confirm

if [[ “$confirm” != “yes” ]]; then
echo “取消恢复”
exit 0
fi

BACKUP_DIR=$(dirname “$(readlink -f “$0”)”)

echo “[1/5] 恢复系统配置…”
rsync -a “${BACKUP_DIR}/etc/” /etc/ 2>/dev/null || true

echo “[2/5] 恢复用户数据…”
rsync -a “${BACKUP_DIR}/home/” /home/ 2>/dev/null || true
rsync -a “${BACKUP_DIR}/root/” /root/ 2>/dev/null || true

echo “[3/5] 恢复额外目录…”
if [[ -d “${BACKUP_DIR}/extra” ]]; then
rsync -a “${BACKUP_DIR}/extra/” / 2>/dev/null || true
fi

echo “[4/5] 恢复数据库…”
if [[ -d “${BACKUP_DIR}/databases/mysql” ]]; then
read -sp “MySQL root密码: “ mysql_pass
echo “”
for sql_file in “${BACKUP_DIR}/databases/mysql”/*.sql.gz; do
if [[ -f “$sql_file” ]]; then
db_name=$(basename “$sql_file” .sql.gz)
echo “恢复数据库: $db_name”
mysql -u root -p”$mysql_pass” -e “CREATE DATABASE IF NOT EXISTS $db_name;” 2>/dev/null
gunzip < “$sql_file” | mysql -u root -p”$mysql_pass” “$db_name” 2>/dev/null || true
fi
done
fi

if [[ -f “${BACKUP_DIR}/databases/postgresql/all_databases.sql.gz” ]]; then
echo “恢复PostgreSQL数据库…”
gunzip < “${BACKUP_DIR}/databases/postgresql/all_databases.sql.gz” | sudo -u postgres psql 2>/dev/null || true
fi

echo “[5/5] 恢复计划任务…”
if [[ -f “${BACKUP_DIR}/crontabs/root_crontab.txt” ]]; then
crontab “${BACKUP_DIR}/crontabs/root_crontab.txt” 2>/dev/null || true
fi

echo “”
echo “恢复完成！”
echo “建议重启系统以确保所有更改生效: reboot”
EOF_RESTORE

```
chmod +x "${BACKUP_PATH}/RESTORE.sh"

# 8. 创建备份信息文件
cat > "${BACKUP_PATH}/BACKUP_INFO.txt" << EOF
```

# 备份信息

备份时间: $(date)
主机名: $(hostname)
操作系统: $(cat /etc/os-release | grep PRETTY_NAME | cut -d’”’ -f2)
备份大小: 计算中…

备份内容:

- 系统配置 (/etc)
- 用户数据 (/home, /root)
- 额外目录: $EXTRA_DIRS
- MySQL数据库: $BACKUP_MYSQL
- PostgreSQL数据库: $BACKUP_POSTGRES

恢复方法:

1. 解压此备份文件
1. 运行: bash RESTORE.sh
   ========================================
   EOF
   
   # 9. 压缩备份
   
   log_info “压缩备份文件…”
   local ARCHIVE_NAME=”${BACKUP_NAME}.tar.gz”
   
   cd “$BACKUP_DIR”
   tar czf “$ARCHIVE_NAME” “$BACKUP_NAME” 2>/dev/null ||   
   tar cf - “$BACKUP_NAME” | pigz > “$ARCHIVE_NAME”
   
   local BACKUP_SIZE=$(du -h “${ARCHIVE_NAME}” | cut -f1)
   log_info “备份完成: ${ARCHIVE_NAME} (${BACKUP_SIZE})”
   
   # 更新备份信息
   
   sed -i “s/备份大小: 计算中…/备份大小: ${BACKUP_SIZE}/” “${BACKUP_PATH}/BACKUP_INFO.txt”
   
   # 10. 上传到远程
   
   if [[ “$REMOTE_ENABLED” == “true” ]]; then
   upload_backup “$ARCHIVE_NAME”
   fi
   
   # 11. 清理旧备份
   
   log_info “清理旧备份…”
   find “$BACKUP_DIR” -name “vps_backup_*.tar.gz” -mtime +$RETENTION_DAYS -delete 2>/dev/null || true
   find “$BACKUP_DIR” -name “vps_backup_*” -type d -mtime +$RETENTION_DAYS -exec rm -rf {} + 2>/dev/null || true
   
   # 删除临时目录
   
   rm -rf “$BACKUP_PATH”
   
   log_info “备份流程完成！”
   echo “”
   echo “备份文件: ${BACKUP_DIR}/${ARCHIVE_NAME}”
   echo “备份大小: ${BACKUP_SIZE}”
   }

# 上传备份到远程

upload_backup() {
local ARCHIVE_NAME=”$1”
local ARCHIVE_PATH=”${BACKUP_DIR}/${ARCHIVE_NAME}”

```
log_info "开始上传备份到远程..."

case $REMOTE_METHOD in
    sftp)
        log_info "使用SFTP上传..."
        scp -P "$REMOTE_PORT" -i "$SSH_KEY" "$ARCHIVE_PATH" \
            "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/" && \
            log_info "上传成功！" || log_error "上传失败"
        ;;
    s3)
        log_info "使用S3上传..."
        export AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY"
        export AWS_SECRET_ACCESS_KEY="$S3_SECRET_KEY"
        
        aws s3 cp "$ARCHIVE_PATH" \
            "s3://${S3_BUCKET}/${ARCHIVE_NAME}" \
            --endpoint-url "https://${S3_ENDPOINT}" \
            --region "$S3_REGION" && \
            log_info "上传成功！" || log_error "上传失败"
        ;;
    webdav)
        log_info "使用WebDAV上传..."
        curl -u "${WEBDAV_USER}:${WEBDAV_PASS}" \
            -T "$ARCHIVE_PATH" \
            "${WEBDAV_URL}/${ARCHIVE_NAME}" && \
            log_info "上传成功！" || log_error "上传失败"
        ;;
esac
```

}

# 列出所有备份

list_backups() {
load_config

```
log_info "本地备份列表:"
echo ""

if [[ -d "$BACKUP_DIR" ]]; then
    ls -lh "${BACKUP_DIR}"/vps_backup_*.tar.gz 2>/dev/null | \
        awk '{print $9, "(" $5 ")", $6, $7, $8}' || \
        log_warn "没有找到本地备份"
fi

echo ""

if [[ "$REMOTE_ENABLED" == "true" ]]; then
    log_info "远程备份列表:"
    echo ""
    
    case $REMOTE_METHOD in
        sftp)
            ssh -p "$REMOTE_PORT" -i "$SSH_KEY" \
                "${REMOTE_USER}@${REMOTE_HOST}" \
                "ls -lh ${REMOTE_PATH}/vps_backup_*.tar.gz" 2>/dev/null || \
                log_warn "无法列出远程备份"
            ;;
        s3)
            export AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY"
            export AWS_SECRET_ACCESS_KEY="$S3_SECRET_KEY"
            
            aws s3 ls "s3://${S3_BUCKET}/" \
                --endpoint-url "https://${S3_ENDPOINT}" \
                --region "$S3_REGION" | grep "vps_backup_" || \
                log_warn "无法列出远程备份"
            ;;
    esac
fi
```

}

# 设置自动备份

schedule_backup() {
log_info “设置自动备份计划…”

```
echo ""
echo "选择备份频率:"
echo "1) 每天凌晨2点"
echo "2) 每周日凌晨2点"
echo "3) 每月1号凌晨2点"
echo "4) 自定义"
read -p "选择 [1-4]: " schedule_choice

case $schedule_choice in
    1)
        CRON_SCHEDULE="0 2 * * *"
        ;;
    2)
        CRON_SCHEDULE="0 2 * * 0"
        ;;
    3)
        CRON_SCHEDULE="0 2 1 * *"
        ;;
    4)
        read -p "输入cron表达式 (如: 0 2 * * *): " CRON_SCHEDULE
        ;;
    *)
        log_error "无效选择"
        exit 1
        ;;
esac

local SCRIPT_PATH=$(readlink -f "$0")
local CRON_CMD="$CRON_SCHEDULE $SCRIPT_PATH backup >> /var/log/vps-backup.log 2>&1"

# 移除旧的备份任务
crontab -l 2>/dev/null | grep -v "vps-backup" | crontab - 2>/dev/null || true

# 添加新任务
(crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -

log_info "自动备份已设置: $CRON_SCHEDULE"
log_info "日志文件: /var/log/vps-backup.log"
```

}

# 恢复系统

do_restore() {
load_config

```
log_info "可用的备份文件:"
echo ""

local backups=($(ls -t "${BACKUP_DIR}"/vps_backup_*.tar.gz 2>/dev/null))

if [[ ${#backups[@]} -eq 0 ]]; then
    log_error "没有找到备份文件"
    exit 1
fi

for i in "${!backups[@]}"; do
    local size=$(du -h "${backups[$i]}" | cut -f1)
    echo "$((i+1))) $(basename ${backups[$i]}) - $size"
done

echo ""
read -p "选择要恢复的备份 [1-${#backups[@]}]: " choice

if [[ $choice -lt 1 || $choice -gt ${#backups[@]} ]]; then
    log_error "无效选择"
    exit 1
fi

local selected_backup="${backups[$((choice-1))]}"

echo ""
log_warn "警告: 恢复操作将覆盖当前系统配置！"
read -p "确定要继续吗? (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
    log_info "取消恢复"
    exit 0
fi

log_info "开始恢复: $(basename $selected_backup)"

local RESTORE_DIR="/tmp/vps_restore_$$"
mkdir -p "$RESTORE_DIR"

log_info "解压备份..."
tar xzf "$selected_backup" -C "$RESTORE_DIR"

local BACKUP_FOLDER=$(ls "$RESTORE_DIR")

if [[ -f "${RESTORE_DIR}/${BACKUP_FOLDER}/RESTORE.sh" ]]; then
    log_info "执行恢复脚本..."
    bash "${RESTORE_DIR}/${BACKUP_FOLDER}/RESTORE.sh"
else
    log_error "未找到恢复脚本"
    rm -rf "$RESTORE_DIR"
    exit 1
fi

rm -rf "$RESTORE_DIR"

log_info "恢复完成！建议重启系统。"
```

}

# 主函数

main() {
# 检查root权限
if [[ $EUID -ne 0 ]]; then
log_error “此脚本需要root权限运行”
exit 1
fi

```
case "${1:-help}" in
    quickstart)
        quickstart_config
        ;;
    setup)
        setup_config
        ;;
    backup)
        do_backup
        ;;
    restore)
        do_restore
        ;;
    list)
        list_backups
        ;;
    upload)
        load_config
        read -p "输入要上传的备份文件名: " filename
        if [[ -f "${BACKUP_DIR}/${filename}" ]]; then
            upload_backup "$filename"
        else
            log_error "文件不存在"
        fi
        ;;
    schedule)
        schedule_backup
        ;;
    help|*)
        show_help
        ;;
esac
```

}

main “$@”
