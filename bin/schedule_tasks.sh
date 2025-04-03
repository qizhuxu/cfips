#!/bin/bash
export LANG=en_US.UTF-8

# 设置颜色
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
BLUE="\033[0;34m"
NC="\033[0m" # 恢复默认颜色

# 打印带颜色的消息
print_msg() {
  local color=$1
  local msg=$2
  local log_only=$3
  
  # 构建带时间戳的日志消息
  local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
  local log_msg="[${timestamp}] ${color}${msg}${NC}"
  
  # 写入日志文件
  echo -e "${log_msg}" >> "${SCRIPT_DIR}/logs/schedule.log"
  
  # 如果不是仅日志，则输出到控制台
  if [ "$log_only" != "true" ]; then
    echo -e "${color}${msg}${NC}"
  fi
}

print_info() {
  print_msg "${BLUE}" "[信息] $1" "$2"
}

print_success() {
  print_msg "${GREEN}" "[成功] $1" "$2"
}

print_warn() {
  print_msg "${YELLOW}" "[警告] $1" "$2"
}

print_error() {
  print_msg "${RED}" "[错误] $1" "$2"
}

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/config"
DATA_DIR="${SCRIPT_DIR}/data"
RESULTS_DIR="${SCRIPT_DIR}/results"
EXEC_DIR="${SCRIPT_DIR}/exec"
UTILS_DIR="${SCRIPT_DIR}/utils"

# 确保日志目录存在
mkdir -p "${SCRIPT_DIR}/logs"

# 导入日志管理器
if [ -f "${UTILS_DIR}/log_manager.sh" ]; then
  source "${UTILS_DIR}/log_manager.sh"
fi

# 导入配置加载器
if [ -f "${UTILS_DIR}/config_loader.sh" ]; then
  source "${UTILS_DIR}/config_loader.sh"
fi

# 默认配置
MAIN_SCRIPT="${BIN_DIR}/run_all.sh"  # 将创建此脚本来执行所有任务

# 从配置文件加载定时任务设置
INTERVAL=$(get_config "schedule.interval")

if [ -z "$INTERVAL" ]; then
  print_error "配置文件加载失败或缺少必要配置，请检查配置文件"
  exit 1
fi

print_info "已从配置文件加载设置"
print_info "定时执行间隔: ${INTERVAL}分钟"

# 创建执行所有任务的脚本
create_main_script() {
  print_info "正在创建主执行脚本: ${MAIN_SCRIPT}" "true"
  
  cat > "${MAIN_SCRIPT}" << 'EOF'
#!/bin/bash
export LANG=en_US.UTF-8

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# 记录开始时间
echo "===== 开始执行自动任务 $(date) =====" >> "${SCRIPT_DIR}/../logs/task_log.txt"

# 执行IP优选
echo "正在执行IP优选..." >> "${SCRIPT_DIR}/../logs/task_log.txt"
bash cfips.sh >> "${SCRIPT_DIR}/../logs/task_log.txt" 2>&1
if [ $? -ne 0 ]; then
  echo "IP优选执行失败" >> "${SCRIPT_DIR}/../logs/task_log.txt"
  exit 1
fi

# 执行测速
echo "正在执行测速..." >> "${SCRIPT_DIR}/../logs/task_log.txt"
bash speed_test.sh >> "${SCRIPT_DIR}/../logs/task_log.txt" 2>&1
if [ $? -ne 0 ]; then
  echo "测速执行失败" >> "${SCRIPT_DIR}/../logs/task_log.txt"
  exit 1
fi

# 执行上传
echo "正在执行上传..." >> "${SCRIPT_DIR}/../logs/task_log.txt"
bash upload_results.sh >> "${SCRIPT_DIR}/../logs/task_log.txt" 2>&1

# 执行通知
echo "正在发送通知..." >> "${SCRIPT_DIR}/../logs/task_log.txt"
bash notify_results.sh >> "${SCRIPT_DIR}/../logs/task_log.txt" 2>&1

# 任务完成
echo "===== 任务执行完成 $(date) =====" >> "${SCRIPT_DIR}/../logs/task_log.txt"
EOF
  
  # 设置执行权限
  chmod +x "${MAIN_SCRIPT}"
  
  print_success "主执行脚本创建完成" "true"
}

# 格式化时间为可读形式
format_time() {
  local timestamp=$1
  date -d "@$timestamp" "+%Y-%m-%d %H:%M:%S"
}

# 使用循环实现定时任务
run_scheduler() {
  print_info "开始定时任务循环，间隔时间: ${INTERVAL}分钟"
  print_info "任务将首先执行一次，然后按设定的间隔重复执行"
  print_info "按 Ctrl+C 可以终止任务循环" "true"
  
  # 循环执行任务
  while true; do
    # 更新健康检查文件
    touch /tmp/healthy 2>/dev/null || true
    
    # 当前时间
    current_time=$(date "+%Y-%m-%d %H:%M:%S")
    current_timestamp=$(date +%s)
    next_timestamp=$((current_timestamp + INTERVAL * 60))
    next_time=$(format_time $next_timestamp)
    
    print_info "开始执行定时任务... (${current_time})"
    print_info "开始执行CloudflareIP优选和测速任务" "true"
    
    # 执行主脚本
    ${MAIN_SCRIPT}
    
    # 计算各种时区的下次执行时间
    print_success "任务执行完成"
    print_info "下次执行时间: ${next_time} (北京时间)"
    
    # 记录详细日志到文件
    print_info "任务执行完成，详细日志请查看logs目录" "true"
    
    # 添加明显的分隔符，区分不同执行周期
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}=== 等待 ${INTERVAL} 分钟后执行下一周期 ===${NC}"
    echo -e "${BLUE}=========================================${NC}"
    
    # 每小时更新一次健康检查文件
    for ((i=0; i<${INTERVAL}; i+=10)); do
      sleep 600  # 睡眠10分钟
      touch /tmp/healthy 2>/dev/null || true
      
      # 每小时输出一次状态日志，避免日志太多
      if [ $((i % 60)) -eq 0 ] && [ $i -ne 0 ]; then
        hours_left=$(( (${INTERVAL} - i) / 60 ))
        mins_left=$(( (${INTERVAL} - i) % 60 ))
        remaining_timestamp=$((next_timestamp - $(date +%s)))
        if [ $remaining_timestamp -lt 0 ]; then
          remaining_timestamp=0
        fi
        remaining_hours=$(( remaining_timestamp / 3600 ))
        remaining_mins=$(( (remaining_timestamp % 3600) / 60 ))
        
        # 日志中记录详细信息
        print_info "定时任务正在等待，距离下次执行还有${remaining_hours}小时${remaining_mins}分钟" "true"
        # 控制台简洁提示
        if [ $remaining_hours -gt 0 ]; then
          print_info "等待中: ${remaining_hours}小时${remaining_mins}分钟后执行 (${next_time})"
        else
          print_info "等待中: ${remaining_mins}分钟后执行 (${next_time})"
        fi
      fi
    done
    
    # 处理余数
    remainder=$((${INTERVAL} % 10))
    if [ $remainder -gt 0 ]; then
      sleep $((remainder * 60))
    fi
  done
}

# 解析命令行参数
parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -i|--interval)
        INTERVAL="$2"
        shift 2
        ;;
      -r|--run-once)
        # 仅运行一次任务然后退出
        create_main_script
        print_info "执行单次任务..."
        ${MAIN_SCRIPT}
        print_success "单次任务执行完成"
        exit 0
        ;;
      -h|--help)
        print_info "用法: $0 [选项]"
        print_info "选项:"
        print_info "  -i, --interval MINUTES  设置定时执行的间隔(分钟)"
        print_info "                          默认为360分钟(6小时)"
        print_info "  -r, --run-once         仅运行一次任务然后退出"
        print_info "  -h, --help             显示此帮助信息"
        exit 0
        ;;
      *)
        print_warn "未知参数: $1"
        shift
        ;;
    esac
  done
}

# 主函数
main() {
  print_info "开始设置Cloudflare IP测速定时任务..."
  
  # 创建执行所有任务的主脚本
  create_main_script
  
  # 开始定时任务循环
  run_scheduler
  
  print_success "设置完成"
}

# 解析命令行参数
parse_args "$@"

# 执行主函数
main