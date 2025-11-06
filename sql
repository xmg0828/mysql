#!/bin/bash

# ============================================
# MySQL一键备份恢复工具 - 超简单版
# 功能：备份、恢复、定时任务全包含
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 显示菜单
show_menu() {
    clear
    echo -e "${BLUE}======================================${NC}"
    echo -e "${BLUE}    MySQL备份恢复工具 - 一键版${NC}"
    echo -e "${BLUE}======================================${NC}"
    echo ""
    echo "1. 安装自动备份（首次使用）"
    echo "2. 立即备份数据库"
    echo "3. 恢复数据库"
    echo "4. 查看备份列表"
    echo "5. 查看定时任务状态"
    echo "6. 卸载"
    echo "0. 退出"
    echo ""
    echo -e "${BLUE}======================================${NC}"
}

# 安装自动备份
install_backup() {
    echo -e "${YELLOW}开始安装MySQL自动备份...${NC}\n"
    
    # 检查MySQL
    if ! command -v mysql &> /dev/null; then
        echo -e "${RED}错误: 未检测到MySQL/MariaDB${NC}"
        exit 1
    fi
    
    # 收集配置
    read -p "MySQL用户名 [root]: " MYSQL_USER
    MYSQL_USER=${MYSQL_USER:-root}
    
    read -sp "MySQL密码: " MYSQL_PASSWORD
    echo ""
    
    read -p "备份保留天数 [7]: " KEEP_DAYS
    KEEP_DAYS=${KEEP_DAYS:-7}
    
    read -p "每天几点备份(0-23) [2]: " BACKUP_HOUR
    BACKUP_HOUR=${BACKUP_HOUR:-2}
    
    # 创建备份脚本
    cat > /usr/local/bin/mysql-backup << 'EOFBACKUP'
#!/bin/bash
MYSQL_USER="PLACEHOLDER_USER"
MYSQL_PASSWORD="PLACEHOLDER_PASS"
BACKUP_DIR="/var/backups/mysql"
KEEP_DAYS=PLACEHOLDER_DAYS

mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="$BACKUP_DIR/backup_${TIMESTAMP}.sql"

if [ -z "$MYSQL_PASSWORD" ]; then
    mysqldump -u "$MYSQL_USER" --all-databases --single-transaction --quick --lock-tables=false > "$BACKUP_FILE" 2>/dev/null
else
    mysqldump -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" --all-databases --single-transaction --quick --lock-tables=false > "$BACKUP_FILE" 2>/dev/null
fi

if [ $? -eq 0 ] && [ -s "$BACKUP_FILE" ]; then
    gzip "$BACKUP_FILE"
    SIZE=$(du -h "${BACKUP_FILE}.gz" | cut -f1)
    echo "✓ 备份成功: $(basename ${BACKUP_FILE}.gz) ($SIZE)"
    find "$BACKUP_DIR" -name "backup_*.sql.gz" -mtime +$KEEP_DAYS -delete
else
    echo "✗ 备份失败"
    rm -f "$BACKUP_FILE"
    exit 1
fi
EOFBACKUP

    # 替换配置
    sed -i "s/PLACEHOLDER_USER/$MYSQL_USER/g" /usr/local/bin/mysql-backup
    sed -i "s/PLACEHOLDER_PASS/$MYSQL_PASSWORD/g" /usr/local/bin/mysql-backup
    sed -i "s/PLACEHOLDER_DAYS/$KEEP_DAYS/g" /usr/local/bin/mysql-backup
    
    chmod +x /usr/local/bin/mysql-backup
    chmod 600 /usr/local/bin/mysql-backup
    
    # 创建定时任务
    (crontab -l 2>/dev/null | grep -v mysql-backup; echo "0 $BACKUP_HOUR * * * /usr/local/bin/mysql-backup >> /var/log/mysql-backup.log 2>&1") | crontab -
    
    echo -e "\n${GREEN}✓ 安装完成！${NC}"
    echo -e "${YELLOW}每天 ${BACKUP_HOUR}:00 自动备份${NC}"
    echo -e "${YELLOW}备份目录: /var/backups/mysql${NC}"
    echo -e "${YELLOW}保留天数: ${KEEP_DAYS}天${NC}\n"
    
    read -p "是否立即执行一次备份测试? [Y/n]: " TEST
    if [[ ! "$TEST" =~ ^[Nn]$ ]]; then
        /usr/local/bin/mysql-backup
    fi
}

# 立即备份
backup_now() {
    echo -e "${YELLOW}正在备份...${NC}\n"
    if [ -f /usr/local/bin/mysql-backup ]; then
        /usr/local/bin/mysql-backup
    else
        echo -e "${RED}错误: 请先安装(选项1)${NC}"
    fi
}

# 恢复数据库
restore_db() {
    BACKUP_DIR="/var/backups/mysql"
    
    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A $BACKUP_DIR/*.sql.gz 2>/dev/null)" ]; then
        echo -e "${RED}错误: 没有找到备份文件${NC}"
        return
    fi
    
    echo -e "${YELLOW}可用的备份文件:${NC}\n"
    
    # 列出备份文件
    files=($BACKUP_DIR/backup_*.sql.gz)
    for i in "${!files[@]}"; do
        filename=$(basename "${files[$i]}")
        filesize=$(du -h "${files[$i]}" | cut -f1)
        filetime=$(echo "$filename" | sed 's/backup_\(.*\)\.sql\.gz/\1/' | sed 's/_/ /')
        echo "$((i+1)). $filename ($filesize) - $filetime"
    done
    
    echo ""
    read -p "选择要恢复的备份 (输入编号): " choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#files[@]}" ]; then
        selected_file="${files[$((choice-1))]}"
        
        echo -e "\n${RED}警告: 恢复将覆盖当前所有数据库！${NC}"
        read -p "确认恢复? 输入 YES 继续: " confirm
        
        if [ "$confirm" = "YES" ]; then
            read -sp "MySQL密码: " MYSQL_PASSWORD
            echo ""
            
            echo -e "${YELLOW}正在恢复数据库...${NC}"
            
            if [ -z "$MYSQL_PASSWORD" ]; then
                gunzip < "$selected_file" | mysql
            else
                gunzip < "$selected_file" | mysql -p"$MYSQL_PASSWORD"
            fi
            
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✓ 恢复成功！${NC}"
            else
                echo -e "${RED}✗ 恢复失败${NC}"
            fi
        else
            echo -e "${YELLOW}已取消${NC}"
        fi
    else
        echo -e "${RED}无效选择${NC}"
    fi
}

# 查看备份列表
list_backups() {
    BACKUP_DIR="/var/backups/mysql"
    
    if [ ! -d "$BACKUP_DIR" ]; then
        echo -e "${RED}备份目录不存在${NC}"
        return
    fi
    
    echo -e "${YELLOW}备份文件列表:${NC}\n"
    
    files=($BACKUP_DIR/backup_*.sql.gz)
    
    if [ ${#files[@]} -eq 0 ] || [ ! -e "${files[0]}" ]; then
        echo -e "${RED}没有备份文件${NC}"
        return
    fi
    
    total_size=0
    for file in "${files[@]}"; do
        filename=$(basename "$file")
        filesize=$(du -h "$file" | cut -f1)
        filesize_bytes=$(du -b "$file" | cut -f1)
        filetime=$(stat -c %y "$file" | cut -d'.' -f1)
        echo "📦 $filename"
        echo "   大小: $filesize | 时间: $filetime"
        echo ""
        total_size=$((total_size + filesize_bytes))
    done
    
    total_size_human=$(echo $total_size | awk '{printf "%.2f MB", $1/1024/1024}')
    echo -e "${YELLOW}总计: ${#files[@]} 个备份文件, 共 $total_size_human${NC}"
}

# 查看定时任务
check_cron() {
    echo -e "${YELLOW}定时任务状态:${NC}\n"
    
    if crontab -l 2>/dev/null | grep -q mysql-backup; then
        echo -e "${GREEN}✓ 定时任务已启用${NC}\n"
        echo "当前设置:"
        crontab -l | grep mysql-backup
        echo ""
        echo -e "${YELLOW}最近的备份日志:${NC}"
        if [ -f /var/log/mysql-backup.log ]; then
            tail -n 10 /var/log/mysql-backup.log
        else
            echo "暂无日志"
        fi
    else
        echo -e "${RED}✗ 定时任务未设置${NC}"
    fi
}

# 卸载
uninstall() {
    echo -e "${RED}确认卸载? 备份文件将保留 [y/N]:${NC} "
    read confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        # 删除定时任务
        crontab -l 2>/dev/null | grep -v mysql-backup | crontab -
        
        # 删除脚本
        rm -f /usr/local/bin/mysql-backup
        
        echo -e "${GREEN}✓ 卸载完成${NC}"
        echo -e "${YELLOW}备份文件保留在: /var/backups/mysql${NC}"
    else
        echo -e "${YELLOW}已取消${NC}"
    fi
}

# 主程序
main() {
    # 检查root权限
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}请使用root权限运行: sudo $0${NC}"
        exit 1
    fi
    
    while true; do
        show_menu
        read -p "请选择 [0-6]: " choice
        
        case $choice in
            1)
                install_backup
                read -p "按回车继续..."
                ;;
            2)
                backup_now
                read -p "按回车继续..."
                ;;
            3)
                restore_db
                read -p "按回车继续..."
                ;;
            4)
                list_backups
                read -p "按回车继续..."
                ;;
            5)
                check_cron
                read -p "按回车继续..."
                ;;
            6)
                uninstall
                read -p "按回车继续..."
                ;;
            0)
                echo -e "${GREEN}再见！${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选择${NC}"
                sleep 1
                ;;
        esac
    done
}

# 运行主程序
main
