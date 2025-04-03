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
  echo -e "${color}${msg}${NC}"
}

print_info() {
  print_msg "${BLUE}" "[信息] $1"
}

print_success() {
  print_msg "${GREEN}" "[成功] $1"
}

print_warn() {
  print_msg "${YELLOW}" "[警告] $1"
}

print_error() {
  print_msg "${RED}" "[错误] $1"
}

# 推送配置
# Telegram 机器人配置 (替换为你的机器人token和聊天ID)
TG_BOT_TOKEN=""
TG_CHAT_ID=""

# 微信企业机器人配置 (替换为你的微信企业机器人key)
WX_KEY=""

# 上传状态文件
UPLOAD_STATUS_FILE="${RESULTS_DIR}/upload_status.txt"

# 导入配置加载器
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
RESULTS_DIR="${PARENT_DIR}/results"
UTILS_DIR="${PARENT_DIR}/utils"

if [ -f "${UTILS_DIR}/config_loader.sh" ]; then
  source "${UTILS_DIR}/config_loader.sh"
  
  # 从配置文件加载通知设置
  TG_ENABLED=$(get_config "notification.telegram.enabled" "false")
  TG_BOT_TOKEN=$(get_config "notification.telegram.bot_token" "$TG_BOT_TOKEN")
  TG_CHAT_ID=$(get_config "notification.telegram.chat_id" "$TG_CHAT_ID")
  
  WX_ENABLED=$(get_config "notification.wechat.enabled" "false")
  WX_KEY=$(get_config "notification.wechat.key" "$WX_KEY")
  
  print_info "已从配置文件加载通知设置"
else
  TG_ENABLED=false
  WX_ENABLED=false
  
  # 如果有token或key则启用相应通知
  [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_CHAT_ID" ] && TG_ENABLED=true
  [ -n "$WX_KEY" ] && WX_ENABLED=true
  
  print_warn "未找到配置加载器，使用脚本内置设置"
fi

# 获取IP数量信息
get_ip_stats() {
  # 获取优选的IP总数 (cfips.txt)
  if [ -f "${RESULTS_DIR}/cfips.txt" ]; then
    TOTAL_IPS=$(wc -l < "${RESULTS_DIR}/cfips.txt")
  elif [ -f "${RESULTS_DIR}/cfips.csv" ]; then
    TOTAL_IPS=$(wc -l < "${RESULTS_DIR}/cfips.csv")
  else
    TOTAL_IPS="未知"
  fi

  # 获取测速后的IP数量 (result_ip.txt)
  if [ -f "${RESULTS_DIR}/result_ip.txt" ]; then
    TESTED_IPS=$(wc -l < "${RESULTS_DIR}/result_ip.txt")
  else
    TESTED_IPS="未知"
  fi

  # 检查上传状态
  if [ -f "$UPLOAD_STATUS_FILE" ]; then
    UPLOAD_STATUS=$(cat "$UPLOAD_STATUS_FILE")
  else
    # 如果没有状态文件，检查文件是否存在作为简单判断
    if [ -f "${RESULTS_DIR}/cfips.txt" ] && [ -f "${RESULTS_DIR}/result_ip.txt" ]; then
      UPLOAD_STATUS="可能成功"
    else
      UPLOAD_STATUS="可能失败"
    fi
  fi
}

# 构建通知消息
build_message() {
  local host_name=$(hostname)
  local date_time=$(date "+%Y-%m-%d %H:%M:%S")
  local total_ips=0
  local tested_ips=0
  local upload_status="${1:-未上传}"

  # 获取IP信息
  if [ -f "${RESULTS_DIR}/cfips.csv" ]; then
    total_ips=$(wc -l < "${RESULTS_DIR}/cfips.csv")
  fi

  if [ -f "${RESULTS_DIR}/result_ip.txt" ]; then
    tested_ips=$(wc -l < "${RESULTS_DIR}/result_ip.txt")
  fi

  # 构建消息
  MSG_TITLE="📊 Cloudflare IP优选结果通知"
  MSG_CONTENT="🖥️ 主机名: ${host_name}\n"
  MSG_CONTENT+="⏰ 时间: ${date_time}\n"
  MSG_CONTENT+="📊 总IP数: ${total_ips}\n"
  MSG_CONTENT+="🚀 测速后IP数: ${tested_ips}\n"
  MSG_CONTENT+="📤 上传状态: ${upload_status}\n\n"

  # 添加结果预览
  if [ -f "${RESULTS_DIR}/result_ip.txt" ]; then
    MSG_CONTENT+="🔸 速度测试结果预览 (前5条):\n"
    
    # 检查是否包含端口信息
    if grep -q ":" "${RESULTS_DIR}/result_ip.txt"; then
      # 结果包含端口
      MSG_CONTENT+="$(head -n 5 "${RESULTS_DIR}/result_ip.txt" | sed 's/^/  /')\n\n"
    else
      # 结果不包含端口，尝试读取端口配置
      local port_enabled=$(grep "port_config:" -A 3 "${CONFIG_DIR}/config.yml" | grep "enabled:" | awk '{print $2}')
      local default_port=$(grep "port_config:" -A 3 "${CONFIG_DIR}/config.yml" | grep "default_port:" | awk '{print $2}')
      
      if [ "$port_enabled" = "true" ] && [ -n "$default_port" ]; then
        MSG_CONTENT+="$(head -n 5 "${RESULTS_DIR}/result_ip.txt" | sed "s/#/:${default_port}#/" | sed 's/^/  /')\n\n"
      else
        MSG_CONTENT+="$(head -n 5 "${RESULTS_DIR}/result_ip.txt" | sed 's/^/  /')\n\n"
      fi
    fi
  else
    MSG_CONTENT+="❗ 没有找到测速结果\n\n"
  fi

  # 添加帮助信息
  MSG_CONTENT+="💡 如需详细结果，请查看 results 目录下的 cfips.csv 和 result_ip.txt 文件。"

  # 导出消息变量供其他函数使用
  export MSG_TITLE
  export MSG_CONTENT
}

# 通过Telegram发送消息
send_telegram_message() {
  print_info "发送通知消息到Telegram..."
  
  local telegram_url="https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage"
  
  # 发送消息
  local response=$(curl -s -X POST "$telegram_url" \
    -d "chat_id=${TG_CHAT_ID}" \
    -d "text=${MSG_CONTENT}" \
    -d "parse_mode=Markdown" \
    --connect-timeout 10 \
    --max-time 30)
  
  # 检查发送结果
  if echo "$response" | grep -q '"ok":true'; then
    print_success "Telegram通知发送成功"
    return 0
  else
    error_msg=$(echo "$response" | grep -o '"description":"[^"]*"' | sed 's/"description":"//g' | sed 's/"//g')
    print_error "Telegram通知发送失败: $error_msg"
    return 1
  fi
}

# 通过企业微信机器人发送消息
send_wechat_message() {
  print_info "发送通知消息到企业微信..."
  
  local wechat_url="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=${WX_KEY}"
  
  # 构建JSON数据
  local json_data="{\"msgtype\":\"markdown\",\"markdown\":{\"content\":\"### ${MSG_TITLE}\n${MSG_CONTENT}\"}}"
  
  # 发送消息
  local response=$(curl -s -X POST "$wechat_url" \
    -H "Content-Type: application/json" \
    -d "$json_data" \
    --connect-timeout 10 \
    --max-time 30)
  
  # 检查发送结果
  if echo "$response" | grep -q '"errcode":0'; then
    print_success "企业微信通知发送成功"
    return 0
  else
    error_msg=$(echo "$response" | grep -o '"errmsg":"[^"]*"' | sed 's/"errmsg":"//g' | sed 's/"//g')
    print_error "企业微信通知发送失败: $error_msg"
    return 1
  fi
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
  case $1 in
    --tg-token)
      TG_BOT_TOKEN="$2"
      shift 2
      ;;
    --tg-chat)
      TG_CHAT_ID="$2"
      shift 2
      ;;
    --wx-key)
      WX_KEY="$2"
      shift 2
      ;;
    --upload-status)
      UPLOAD_STATUS="$2"
      echo "$UPLOAD_STATUS" > "$UPLOAD_STATUS_FILE"
      shift 2
      ;;
    -h|--help)
      print_info "用法: $0 [选项]"
      print_info "选项:"
      print_info "  --tg-token TOKEN    设置Telegram机器人token"
      print_info "  --tg-chat ID        设置Telegram聊天ID"
      print_info "  --wx-key KEY        设置微信企业机器人key"
      print_info "  --upload-status STATUS 设置上传状态(成功/失败)"
      print_info "  -h, --help          显示此帮助信息"
      exit 0
      ;;
    *)
      shift
      ;;
  esac
done

# 主要执行流程
print_info "开始收集测速结果信息..."

# 获取IP统计数据
get_ip_stats

# 构建通知消息
MESSAGE=$(build_message "$UPLOAD_STATUS")
print_info "已生成通知消息:"
echo "$MESSAGE"

# 发送通知
# 根据TG_ENABLED和WX_ENABLED变量决定是否发送相应通知
if [ "$TG_ENABLED" = "true" ] && [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_CHAT_ID" ]; then
  send_telegram_message
else
  print_info "未配置或未启用Telegram机器人，跳过Telegram通知"
fi

if [ "$WX_ENABLED" = "true" ] && [ -n "$WX_KEY" ]; then
  send_wechat_message
else
  print_info "未配置或未启用微信企业机器人，跳过微信通知"
fi

# 清理
if [ -f "$UPLOAD_STATUS_FILE" ]; then
  rm -f "$UPLOAD_STATUS_FILE"
fi

print_success "通知推送完成" 