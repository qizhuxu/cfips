#!/bin/bash
set -e

# 设置颜色
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
BLUE="\033[0;34m"
NC="\033[0m" # 恢复默认颜色

# 确保日志目录存在
mkdir -p /app/logs

# 打印带颜色的消息
print_msg() {
  local color=$1
  local msg=$2
  local log_only=$3
  
  # 构建带时间戳的日志消息
  local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
  local log_msg="[${timestamp}] ${msg}"
  
  # 写入日志文件
  echo -e "${log_msg}" >> "/app/logs/entrypoint.log"
  
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

# 创建健康检查文件
touch /tmp/healthy

# 确保配置目录存在
if [ ! -d "/app/config" ]; then
  mkdir -p /app/config
  print_info "已创建配置目录: /app/config" "true"
fi

# 确保结果目录存在
if [ ! -d "/app/results" ]; then
  mkdir -p /app/results
  print_info "已创建结果目录: /app/results" "true"
fi

# 确保数据目录存在
if [ ! -d "/app/data" ]; then
  mkdir -p /app/data
  print_info "已创建数据目录: /app/data" "true"
fi

# 确保自定义IP库文件存在
if [ ! -f "/app/config/custom_ips.txt" ]; then
  print_info "创建默认自定义IP库文件" "true"
  cat > /app/config/custom_ips.txt << EOF
# 自定义Cloudflare IP列表
# 每行一个IP地址，支持IPv4和IPv6
# 以#开头的行为注释，会被忽略
EOF
  print_success "已创建自定义IP库文件: /app/config/custom_ips.txt" "true"
fi

# 检查配置文件是否存在，不存在则创建默认配置
if [ ! -f "/app/config/config.yml" ]; then
  print_warn "配置文件不存在，将创建默认配置文件"
  cp /app/config/config.yml.template /app/config/config.yml 2>/dev/null || {
    # 如果模板不存在，则复制当前配置
    cp /app/config.yml /app/config/config.yml 2>/dev/null || {
      print_error "无法创建默认配置文件"
      exit 1
    }
  }
  print_success "已创建默认配置文件" "true"
fi

# 解析命令行参数
CMD=${1:-schedule}  # 默认执行定时任务
shift || true

print_info "启动Cloudflare IP优选工具 (命令: $CMD)"

# 执行启动脚本
exec /app/start.sh "$CMD" "$@"