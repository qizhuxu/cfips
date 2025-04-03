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
  
  # 总是写入日志文件（如果日志目录存在）
  if [ -d "${SCRIPT_DIR}/logs" ]; then
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[${timestamp}] ${msg}" >> "${SCRIPT_DIR}/logs/upload.log"
  fi
  
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

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/config"
DATA_DIR="${SCRIPT_DIR}/data"
RESULTS_DIR="${SCRIPT_DIR}/results"
EXEC_DIR="${SCRIPT_DIR}/exec"
UTILS_DIR="${SCRIPT_DIR}/utils"

# 确保日志目录存在
mkdir -p "${SCRIPT_DIR}/logs"

print_info "开始上传文件..."

# 导入日志管理器
if [ -f "${UTILS_DIR}/log_manager.sh" ]; then
  source "${UTILS_DIR}/log_manager.sh"
fi

# 导入配置加载器
if [ -f "${UTILS_DIR}/config_loader.sh" ]; then
  source "${UTILS_DIR}/config_loader.sh"
else
  print_error "无法找到配置加载器，程序无法继续"
  exit 1
fi

# 从配置文件加载上传设置
CF_KV_ENABLED=$(get_config "upload.cloudflare.enabled")
CF_KV_DOMAIN=$(get_config "upload.cloudflare.domain")
CF_KV_TOKEN=$(get_config "upload.cloudflare.token")
GITHUB_ENABLED=$(get_config "upload.github.enabled")
GITHUB_TOKEN=$(get_config "upload.github.token")
GITHUB_GIST_ID=$(get_config "upload.github.gist_id")
GITHUB_DESC=$(get_config "upload.github.description")
UPLOAD_FILES=$(get_config "upload.files.default" | tr -d '[]" ' | tr ',' ' ')

if [ -z "$CF_KV_ENABLED" ] || [ -z "$GITHUB_ENABLED" ]; then
  print_error "配置文件加载失败或缺少必要配置，请检查配置文件"
  exit 1
fi

print_info "已从配置文件加载上传设置"

# Cloudflare KV配置
CF_DOMAIN=""
CF_TOKEN=""

# GitHub Gist配置
# 如需上传到GitHub Gist，请在此设置你的GitHub令牌
# 你可以在 https://github.com/settings/tokens 创建令牌，需要勾选gist权限
GITHUB_TOKEN=""
GIST_ID=""  # 已有的Gist ID，留空则创建新的Gist
GIST_DESC="Cloudflare IP优选测速结果"

# 默认上传文件
DEFAULT_FILES=("cfips.txt" "result_ip.txt")

# 解析命令行参数
UPLOAD_TO_CF=true
UPLOAD_TO_GIST=false  # 默认关闭Gist上传，除非显式提供token
CUSTOM_FILES=()

# 解析命令行参数
while [[ $# -gt 0 ]]; do
  case $1 in
    --no-cf)
      UPLOAD_TO_CF=false
      shift
      ;;
    --no-gist)
      UPLOAD_TO_GIST=false
      shift
      ;;
    --token)
      GITHUB_TOKEN="$2"
      shift 2
      ;;
    --gist-id)
      GIST_ID="$2"
      shift 2
      ;;
    -f|--file)
      CUSTOM_FILES+=("$2")
      shift 2
      ;;
    -h|--help)
      print_info "用法: $0 [选项] [文件...]"
      print_info "选项:"
      print_info "  --no-cf         不上传到Cloudflare KV"
      print_info "  --no-gist       不上传到GitHub Gist"
      print_info "  --token TOKEN   设置GitHub令牌"
      print_info "  --gist-id ID    设置GitHub Gist ID(更新已有Gist)"
      print_info "  -f, --file FILE 指定要上传的文件"
      print_info "  -h, --help      显示此帮助信息"
      exit 0
      ;;
    *)
      CUSTOM_FILES+=("$1")
      shift
      ;;
  esac
done

# 使用自定义文件列表（如果提供），否则使用默认列表
if [ ${#CUSTOM_FILES[@]} -gt 0 ]; then
  FILES=("${CUSTOM_FILES[@]}")
else
  FILES=("${DEFAULT_FILES[@]}")
fi

print_info "开始上传文件..."

# 检查是否启用了任何上传方式
if [ "$UPLOAD_TO_CF" != "true" ] && [ "$UPLOAD_TO_GIST" != "true" ]; then
  print_info "所有上传方式都已禁用，未执行任何上传操作"
  exit 2
fi

# 初始化文件路径数组
FILES_FULLPATH=()

# 检查文件存在
for file in "${FILES[@]}"; do
  # 首先检查results目录
  if [ -f "${RESULTS_DIR}/$file" ]; then
    # 更新文件路径为完整路径
    FILES_FULLPATH+=("${RESULTS_DIR}/$file")
  elif [ -f "$file" ]; then
    # 如果在当前目录找到，使用当前路径
    FILES_FULLPATH+=("$file")
  else
    print_warn "文件不存在: $file (在results目录和当前目录均未找到)"
  fi
done

# 检查是否有有效文件要上传
if [ ${#FILES_FULLPATH[@]} -eq 0 ]; then
  print_warn "没有找到可上传的文件"
  print_warn "已启用上传功能但未找到任何文件，请检查results目录"
  # 返回非0退出码表示错误
  exit 1
fi

# 上传到Cloudflare KV
upload_to_cloudflare() {
  local filepath=$1
  local filename=$(basename "$filepath")
  print_info "正在上传 $filename 到Cloudflare KV..."
  
  # 对文件内容进行base64编码（限制前65行）
  BASE64_TEXT=$(head -n 65 "$filepath" | base64 -w 0)
  
  # 上传到Cloudflare KV
  local http_code
  RESPONSE=$(curl -s -k -w "\n%{http_code}" "https://${CF_DOMAIN}/${filename}?token=${CF_TOKEN}&b64=${BASE64_TEXT}")
  
  # 提取HTTP状态码和响应体
  http_code=$(echo "$RESPONSE" | tail -n1)
  RESPONSE=$(echo "$RESPONSE" | sed '$d')
  
  # 判断上传是否成功 - HTTP 2xx 表示成功
  if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
    print_success "成功上传 $filename 到Cloudflare KV"
    return 0
  # 如果HTTP码提示成功但响应中含有error或failed
  elif [[ "$http_code" =~ ^2[0-9][0-9]$ ]] && [[ "$RESPONSE" == *"success"* ]]; then
    print_success "成功上传 $filename 到Cloudflare KV"
    return 0
  else
    # 如果返回的是文本而且包含IP地址格式，那么实际上是成功的
    if [[ "$RESPONSE" =~ ([0-9]{1,3}\.){3}[0-9]{1,3}|([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4} ]]; then
      print_success "成功上传 $filename 到Cloudflare KV (返回了文件内容)"
      return 0
    fi
    
    # 真正的错误情况
    local error_msg="未知错误"
    if [[ "$RESPONSE" == *"error"* ]]; then
      # 尝试提取错误信息
      error_msg=$(echo "$RESPONSE" | grep -o '"error":"[^"]*"' | cut -d'"' -f4 || echo "服务器返回错误")
    elif [[ "$RESPONSE" == *"failed"* ]]; then
      error_msg="上传失败"
    elif [[ -z "$RESPONSE" ]]; then
      error_msg="无响应"
    else
      # 如果响应不是标准JSON或不包含预期的错误字段，只显示前30个字符
      error_msg="HTTP $http_code: ${RESPONSE:0:30}..."
    fi
    
    print_error "上传 $filename 到Cloudflare KV失败: $error_msg"
    return 1
  fi
}

# 上传到GitHub Gist
upload_to_gist() {
  if [ -z "$GITHUB_TOKEN" ]; then
    print_info "未设置GitHub令牌，跳过Gist上传"
    return
  fi
  
  print_info "正在上传文件到GitHub Gist..."
  
  # 准备JSON数据
  local json_content='{"description":"'"$GIST_DESC"'","public":false,"files":{'
  
  # 添加每个文件的内容
  local first=true
  for filepath in "${FILES_FULLPATH[@]}"; do
    local filename=$(basename "$filepath")
    # 处理JSON格式的逗号
    if [ "$first" = true ]; then
      first=false
    else
      json_content+=','
    fi
    
    # 读取文件内容并转义特殊字符
    local file_content=$(cat "$filepath" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed 's/\n/\\n/g' | tr -d '\r')
    
    # 添加到JSON
    json_content+='"'"$filename"'":{"content":"'"$file_content"'"}'
  done
  
  # 完成JSON
  json_content+='}}'
  
  # 发送到GitHub API
  local url="https://api.github.com/gists"
  local method="POST"
  
  # 如果提供了Gist ID，则更新现有Gist
  if [ -n "$GIST_ID" ]; then
    url="https://api.github.com/gists/$GIST_ID"
    method="PATCH"
    print_info "将更新现有Gist: $GIST_ID"
  fi
  
  # 发送到GitHub API
  local response=$(curl -s -X $method \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$json_content" \
    "$url")
  
  # 检查响应
  if [ "$(echo "$response" | grep -c '"html_url"')" -gt 0 ]; then
    local gist_url=$(echo "$response" | grep -o '"html_url":"[^"]*"' | head -1 | cut -d'"' -f4)
    local gist_id=$(echo "$response" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    print_success "成功上传到GitHub Gist: $gist_url"
    print_info "Gist ID: $gist_id (可添加到配置文件以便后续更新)"
    return 0
  else
    print_error "上传到GitHub Gist失败: $response"
    return 1
  fi
}

# 执行上传
UPLOAD_SUCCESS=false  # 默认设为false，只有真正上传成功才设为true
UPLOAD_ATTEMPTED=false  # 是否尝试过上传操作

if [ "$UPLOAD_TO_CF" = true ]; then
  UPLOAD_ATTEMPTED=true
  CF_SUCCESS=true
  for filepath in "${FILES_FULLPATH[@]}"; do
    upload_to_cloudflare "$filepath"
    # 如果任何一个文件上传失败，标记整体上传失败
    if [ $? -ne 0 ]; then
      CF_SUCCESS=false
    else
      UPLOAD_SUCCESS=true  # 至少有一个文件上传成功
    fi
  done
  
  if [ "$CF_SUCCESS" = true ]; then
    print_success "Cloudflare KV上传全部成功"
  else
    print_warn "Cloudflare KV存在上传失败的文件"
  fi
else
  print_info "已跳过Cloudflare KV上传"
fi

if [ "$UPLOAD_TO_GIST" = true ]; then
  UPLOAD_ATTEMPTED=true
  upload_to_gist
  # 检查Gist上传结果
  if [ $? -eq 0 ]; then
    UPLOAD_SUCCESS=true
  fi
else
  print_info "已跳过GitHub Gist上传"
fi

# 根据上传情况输出结果
if [ "$UPLOAD_ATTEMPTED" = false ]; then
  print_info "所有上传方式都已禁用，未执行任何上传操作"
  exit 0
elif [ "$UPLOAD_SUCCESS" = true ]; then
  print_success "结果上传完成"
else
  print_warn "上传完成，但存在失败项目"
  exit 3
fi

# 标记上传状态，用于通知脚本
export_upload_status() {
  if [ -n "$1" ]; then
    local status_file="${RESULTS_DIR}/upload_status.txt"
    echo "$1" > "$status_file"
    
    # 如果设置了强制通知，执行通知脚本
    if [ "$FORCE_NOTIFY" = "true" ] && [ -f "${BIN_DIR}/notify_results.sh" ]; then
      bash "${BIN_DIR}/notify_results.sh" --upload-status "$1"
    fi
  fi
}

# 发送通知 - 只有当run_all未单独调用通知时才执行
# 检查是否需要执行推送通知(避免重复推送)
# 为避免与start.sh中的run_all重复调用notify_results.sh，我们在此设置一个标记
PARENT_SCRIPT=$(ps -o comm= $PPID 2>/dev/null || echo "unknown")

# 当从start.sh的all命令调用时，跳过通知（让start.sh处理）
if [[ "$PARENT_SCRIPT" == *"start.sh"* ]] && [[ -z "$FORCE_NOTIFY" ]]; then
  print_info "检测到从start.sh调用，跳过通知步骤"
else
  # 只有直接调用或明确要求时才发送通知
  if [ -f "notify_results.sh" ]; then
    if [ "$UPLOAD_ATTEMPTED" = false ]; then
      export_upload_status "跳过"
    elif [ "$UPLOAD_SUCCESS" = true ]; then
      export_upload_status "成功"
    else
      export_upload_status "部分失败"
    fi
  fi
fi 