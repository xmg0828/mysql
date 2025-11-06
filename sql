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

install_backup() {
    echo -e "${YELLOW}开始安装...${NC}"
    
    if ! command -v mysql &> /dev/null; then
        echo -e "${RED}错误: 未检测到MySQL${NC}"
        exit 1
    fi
    
    read -p "MySQL用户名 [root]: " USER
    USER=${USER:-root}
    read -sp "MySQL密码: " PASS
    echo ""
    read -p "保留天数 [7]: " DAYS
    DAYS=${DAYS:-7}
    read -p "每天几点备份 [2]: " HOUR
    HOUR=${HOUR:-2}
    
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
    echo "备份成功: \${FILE}.gz"
    find "\$DIR" -name "*.sql.gz" -mtime +\$DAYS -delete
else
    echo "备份失败"
    rm -f "\$FILE"
    exit 1
fi
EOFSCRIPT

    chmod +x /usr/local/bin/mysql-backup
    chmod 600 /usr/local/bin/mysql-backup
    
    (crontab -l 2>/dev/null | grep -v mysql-backup; echo "0 $HOUR * * * /usr/local/bin/mysql-backup >> /var/log/mysql-backup.log 2>&1") | crontab -
    
    echo -e "${GREEN}✓ 安装完成${NC}"
    echo "每天 ${HOUR}:00 自动备份"
    
    read -p "立即测试? [Y/n]: " TEST
    if [[ ! "$TEST" =~ ^[Nn]$ ]]; then
        /usr/local/bin/mysql-backup
    fi
}

backup_now() {
    echo -e "${YELLOW}正在备份...${NC}"
    if [ -f /usr/local/bin/mysql-backup ]; then
        /usr/local/bin/mysql-backup
    else
        echo -e "${RED}请先安装${NC}"
    fi
}

restore_db() {
    DIR="/var/backups/mysql"
    
    if [ ! -d "$DIR" ] || [ -z "$(ls -A $DIR/*.sql.gz 2>/dev/null)" ]; then
        echo -e "${RED}没有备份文件${NC}"
        return
    fi
    
    echo -e "${YELLOW}可用备份:${NC}"
    files=($DIR/backup_*.sql.gz)
    for i in "${!files[@]}"; do
        name=$(basename "${files[$i]}")
        size=$(du -h "${files[$i]}" | cut -f1)
        echo "$((i+1)). $name ($size)"
    done
    
    echo ""
    read -p "选择编号: " choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#files[@]}" ]; then
        file="${files[$((choice-1))]}"
        
        echo -e "${RED}警告: 将覆盖所有数据${NC}"
        read -p "输入YES确认: " confirm
        
        if [ "$confirm" = "YES" ]; then
            read -sp "MySQL密码: " PASS
            echo ""
            echo "恢复中..."
            
            if [ -z "$PASS" ]; then
                gunzip < "$file" | mysql
            else
                gunzip < "$file" | mysql -p"$PASS"
            fi
            
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✓ 恢复成功${NC}"
            else
                echo -e "${RED}✗ 恢复失败${NC}"
            fi
        else
            echo "已取消"
        fi
    else
        echo -e "${RED}无效选择${NC}"
    fi
}

list_backups() {
    DIR="/var/backups/mysql"
    echo -e "${YELLOW}备份列表:${NC}"
    ls -lh $DIR/*.sql.gz 2>/dev/null || echo "无备份"
}

check_cron() {
    echo -e "${YELLOW}定时任务:${NC}"
    if crontab -l 2>/dev/null | grep -q mysql-backup; then
        echo -e "${GREEN}✓ 已启用${NC}"
        crontab -l | grep mysql-backup
    else
        echo -e "${RED}✗ 未设置${NC}"
    fi
}

main() {
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}需要root权限: sudo $0${NC}"
        exit 1
    fi
    
    while true; do
        show_menu
        read -p "选择 [0-5]: " choice
        
        case $choice in
            1) install_backup; read -p "回车继续..." ;;
            2) backup_now; read -p "回车继续..." ;;
            3) restore_db; read -p "回车继续..." ;;
            4) list_backups; read -p "回车继续..." ;;
            5) check_cron; read -p "回车继续..." ;;
            0) echo "再见"; exit 0 ;;
            *) echo -e "${RED}无效${NC}"; sleep 1 ;;
        esac
    done
}

main
