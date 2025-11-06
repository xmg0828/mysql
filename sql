#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

show_menu() {
    clear
    echo -e "${BLUE}=====================================${NC}"
    echo -e "${BLUE}    MySQL备份恢复工具${NC}"
    echo -e "${BLUE}=====================================${NC}"
    echo ""
    echo "1. 安装自动备份"
    echo "2. 立即备份"
    echo "3. 恢复数据库"
    echo "4. 查看备份"
    echo "5. 查看定时任务"
    echo "0. 退出"
    echo ""
    echo -e "${BLUE}=====================================${NC}"
}

detect_mysql() {
    IS_DOCKER=false
    MYSQL_CONTAINER=""
    
    if command -v docker &> /dev/null; then
        MYSQL_CONTAINER=$(docker ps --format "{{.Names}}" | grep -i mysql | head -1)
        if [ -n "$MYSQL_CONTAINER" ]; then
            IS_DOCKER=true
            echo -e "${GREEN}检测到Docker MySQL容器: $MYSQL_CONTAINER${NC}"
            return 0
        fi
    fi
    
    if command -v mysql &> /dev/null; then
        echo -e "${GREEN}检测到本地MySQL${NC}"
        return 0
    fi
    
    echo -e "${RED}错误: 未检测到MySQL${NC}"
    return 1
}

install_backup() {
    echo -e "${YELLOW}开始安装自动备份...${NC}\n"
    
    if ! detect_mysql; then
        exit 1
    fi
    
    read -p "MySQL用户名 [root]: " USER
    USER=${USER:-root}
    read -sp "MySQL密码: " PASS
    echo ""
    read -p "保留天数 [7]: " DAYS
    DAYS=${DAYS:-7}
    read -p "每天几点备份(0-23) [2]: " HOUR
    HOUR=${HOUR:-2}
    
    if [ "$IS_DOCKER" = true ]; then
        cat > /usr/local/bin/mysql-backup << EOFSCRIPT
#!/bin/bash
USER="$USER"
PASS="$PASS"
DIR="/var/backups/mysql"
DAYS=$DAYS
CONTAINER="$MYSQL_CONTAINER"

mkdir -p "\$DIR"
FILE="\$DIR/backup_\$(date +%Y%m%d_%H%M%S).sql"

docker exec \$CONTAINER mysqldump -u "\$USER" -p"\$PASS" --all-databases > "\$FILE" 2>/dev/null

if [ \$? -eq 0 ] && [ -s "\$FILE" ]; then
    gzip "\$FILE"
    SIZE=\$(du -h "\${FILE}.gz" | cut -f1)
    echo "备份成功: \${FILE}.gz (\$SIZE)"
    find "\$DIR" -name "*.sql.gz" -mtime +\$DAYS -delete
else
    echo "备份失败"
    rm -f "\$FILE"
    exit 1
fi
EOFSCRIPT
    else
        cat > /usr/local/bin/mysql-backup << EOFSCRIPT
#!/bin/bash
USER="$USER"
PASS="$PASS"
DIR="/var/backups/mysql"
DAYS=$DAYS

mkdir -p "\$DIR"
FILE="\$DIR/backup_\$(date +%Y%m%d_%H%M%S).sql"

if [ -z "\$PASS" ]; then
    mysqldump -u "\$USER" --all-databases > "\$FILE" 2>/dev/null
else
    mysqldump -u "\$USER" -p"\$PASS" --all-databases > "\$FILE" 2>/dev/null
fi

if [ \$? -eq 0 ] && [ -s "\$FILE" ]; then
    gzip "\$FILE"
    SIZE=\$(du -h "\${FILE}.gz" | cut -f1)
    echo "备份成功: \${FILE}.gz (\$SIZE)"
    find "\$DIR" -name "*.sql.gz" -mtime +\$DAYS -delete
else
    echo "备份失败"
    rm -f "\$FILE"
    exit 1
fi
EOFSCRIPT
    fi
    
    chmod 755 /usr/local/bin/mysql-backup
    chown root:root /usr/local/bin/mysql-backup
    
    if [ ! -x /usr/local/bin/mysql-backup ]; then
        echo -e "${RED}权限设置失败，正在修复...${NC}"
        chmod 755 /usr/local/bin/mysql-backup
    fi
    
    (crontab -l 2>/dev/null | grep -v mysql-backup; echo "0 $HOUR * * * /usr/local/bin/mysql-backup >> /var/log/mysql-backup.log 2>&1") | crontab -
    
    echo -e "\n${GREEN}✓ 安装完成${NC}"
    echo -e "${YELLOW}每天 ${HOUR}:00 自动备份${NC}"
    echo -e "${YELLOW}备份目录: /var/backups/mysql${NC}"
    echo -e "${YELLOW}保留天数: ${DAYS}天${NC}\n"
    
    read -p "立即测试备份? [Y/n]: " TEST
    if [[ ! "$TEST" =~ ^[Nn]$ ]]; then
        echo -e "${YELLOW}正在测试备份...${NC}\n"
        /usr/local/bin/mysql-backup
    fi
}

backup_now() {
    echo -e "${YELLOW}正在备份...${NC}\n"
    
    if [ -f /usr/local/bin/mysql-backup ]; then
        /usr/local/bin/mysql-backup
    else
        echo -e "${RED}错误: 请先安装自动备份(选项1)${NC}"
    fi
}

restore_db() {
    DIR="/var/backups/mysql"
    
    if [ ! -d "$DIR" ] || [ -z "$(ls -A $DIR/*.sql.gz 2>/dev/null)" ]; then
        echo -e "${RED}错误: 没有找到备份文件${NC}"
        return
    fi
    
    if ! detect_mysql; then
        return
    fi
    
    echo -e "${YELLOW}可用的备份文件:${NC}\n"
    files=($DIR/backup_*.sql.gz)
    for i in "${!files[@]}"; do
        name=$(basename "${files[$i]}")
        size=$(du -h "${files[$i]}" | cut -f1)
        time=$(stat -c %y "${files[$i]}" | cut -d. -f1)
        echo "$((i+1)). $name ($size) - $time"
    done
    
    echo ""
    read -p "选择要恢复的备份 (输入编号): " choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#files[@]}" ]; then
        file="${files[$((choice-1))]}"
        
        echo -e "\n${RED}警告: 恢复将覆盖当前所有数据库！${NC}"
        read -p "确认恢复? 输入YES继续: " confirm
        
        if [ "$confirm" = "YES" ]; then
            read -sp "MySQL密码: " PASS
            echo ""
            echo -e "${YELLOW}正在恢复数据库...${NC}"
            
            if [ "$IS_DOCKER" = true ]; then
                gunzip < "$file" | docker exec -i $MYSQL_CONTAINER mysql -u root -p"$PASS" 2>/dev/null
            else
                if [ -z "$PASS" ]; then
                    gunzip < "$file" | mysql
                else
                    gunzip < "$file" | mysql -p"$PASS"
                fi
            fi
            
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✓ 恢复成功！${NC}"
            else
                echo -e "${RED}✗ 恢复失败${NC}"
            fi
        else
            echo -e "${YELLOW}已取消恢复${NC}"
        fi
    else
        echo -e "${RED}无效的选择${NC}"
    fi
}

list_backups() {
    DIR="/var/backups/mysql"
    
    if [ ! -d "$DIR" ]; then
        echo -e "${RED}备份目录不存在${NC}"
        return
    fi
    
    echo -e "${YELLOW}备份文件列表:${NC}\n"
    
    files=($DIR/backup_*.sql.gz)
    
    if [ ${#files[@]} -eq 0 ] || [ ! -e "${files[0]}" ]; then
        echo -e "${RED}没有备份文件${NC}"
        return
    fi
    
    total=0
    for file in "${files[@]}"; do
        name=$(basename "$file")
        size=$(du -h "$file" | cut -f1)
        bytes=$(du -b "$file" | cut -f1)
        time=$(stat -c %y "$file" | cut -d. -f1)
        echo "📦 $name"
        echo "   大小: $size | 时间: $time"
        echo ""
        total=$((total + bytes))
    done
    
    total_mb=$(echo $total | awk '{printf "%.2f MB", $1/1024/1024}')
    echo -e "${YELLOW}总计: ${#files[@]} 个备份文件, 共 $total_mb${NC}"
}

check_cron() {
    echo -e "${YELLOW}定时任务状态:${NC}\n"
    
    if crontab -l 2>/dev/null | grep -q mysql-backup; then
        echo -e "${GREEN}✓ 定时任务已启用${NC}\n"
        echo "当前配置:"
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
        echo "请先运行选项1进行安装"
    fi
}

main() {
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}错误: 需要root权限${NC}"
        echo "请使用: sudo $0"
        exit 1
    fi
    
    while true; do
        show_menu
        read -p "请选择 [0-5]: " choice
        
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
            0)
                echo -e "${GREEN}再见！${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效的选择${NC}"
                sleep 1
                ;;
        esac
    done
}

main
