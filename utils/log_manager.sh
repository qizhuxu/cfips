#!/bin/bash
export LANG=en_US.UTF-8

# ====== 日志管理器 ======
# 该脚本用于集中管理Cloudflare IP优选工具的所有日志

# 设置颜色
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
BLUE="\033[0;34m"
CYAN="\033[0;36m"
GRAY="\033[0;37m"
NC="\033[0m" # 恢复默认颜色

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UTILS_DIR="${SCRIPT_DIR}/utils"
cd "${UTILS_DIR}" || exit 1

# 默认配置
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/cfips.log"
MAX_LOG_SIZE=1048576 # 1MB
MAX_LOG_FILES=5      # 保留5个轮转日志
LOG_LEVEL="INFO"     # 默认日志级别
LOG_TO_CONSOLE=true  # 是否同时输出到控制台
CONSOLE_VERBOSE=false # 控制台输出是否详细

# 日志级别定义
declare -A LOG_LEVELS
LOG_LEVELS=([DEBUG]=0 [INFO]=1 [WARN]=2 [ERROR]=3 [FATAL]=4)

# 导入配置加载器
if [ -f "${UTILS_DIR}/config_loader.sh" ]; then
  source "${UTILS_DIR}/config_loader.sh"
  
  # 从配置文件加载日志设置
  LOG_DIR=$(get_config "log.directory" "$LOG_DIR")
  LOG_FILE=$(get_config "log.file" "$LOG_FILE")
  MAX_LOG_SIZE=$(get_config "log.max_size" "$MAX_LOG_SIZE")
  MAX_LOG_FILES=$(get_config "log.max_files" "$MAX_LOG_FILES")
  LOG_LEVEL=$(get_config "log.level" "$LOG_LEVEL")
  LOG_TO_CONSOLE=$(get_config "log.console_output" "$LOG_TO_CONSOLE")
  CONSOLE_VERBOSE=$(get_config "log.console_verbose" "$CONSOLE_VERBOSE")
fi

# 确保日志目录存在
mkdir -p "$LOG_DIR"

# 打印带颜色的消息到控制台
print_msg() {
  local color=$1
  local msg=$2
  local file_only=$3
  
  # 总是记录到日志文件
  local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
  echo "[$timestamp] $msg" >> "$LOG_FILE"
  
  # 如果不是仅文件日志，且配置为输出到控制台，则输出到控制台
  if [ "$file_only" != "true" ] && [ "$LOG_TO_CONSOLE" = true ]; then
    echo -e "${color}${msg}${NC}"
  fi
}

# 检查日志文件大小并轮转
check_log_size() {
  if [ ! -f "$LOG_FILE" ]; then
    return
  fi
  
  local size=$(stat -c %s "$LOG_FILE" 2>/dev/null || stat -f %z "$LOG_FILE" 2>/dev/null)
  
  if [ "$size" -gt "$MAX_LOG_SIZE" ]; then
    rotate_logs
  fi
}

# 轮转日志文件
rotate_logs() {
  # 删除最老的日志文件
  if [ -f "${LOG_FILE}.${MAX_LOG_FILES}" ]; then
    rm "${LOG_FILE}.${MAX_LOG_FILES}"
  fi
  
  # 轮转现有日志文件
  for i in $(seq $((MAX_LOG_FILES - 1)) -1 1); do
    if [ -f "${LOG_FILE}.$i" ]; then
      mv "${LOG_FILE}.$i" "${LOG_FILE}.$((i + 1))"
    fi
  done
  
  # 重命名当前日志文件
  if [ -f "$LOG_FILE" ]; then
    mv "$LOG_FILE" "${LOG_FILE}.1"
  fi
  
  # 创建新的日志文件
  touch "$LOG_FILE"
  log_internal "INFO" "日志文件已轮转，旧日志移至 ${LOG_FILE}.1"
}

# 清理过期日志文件
clean_logs() {
  local days=$1
  if [ -z "$days" ]; then
    days=30 # 默认清理30天前的日志
  fi
  
  find "$LOG_DIR" -name "*.log.*" -type f -mtime +$days -delete
  log_internal "INFO" "已清理${days}天前的日志文件"
}

# 内部日志记录函数
log_internal() {
  local level=$1
  local message=$2
  local file_only=$3
  local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
  local log_entry="[$timestamp] [$level] $message"
  
  # 追加到日志文件
  echo "$log_entry" >> "$LOG_FILE"
  
  # 根据日志级别显示颜色，如果不是仅文件日志
  if [ "$file_only" != "true" ] && [ "$LOG_TO_CONSOLE" = true ]; then
    case $level in
      DEBUG)
        echo -e "$GRAY$log_entry$NC"
        ;;
      INFO)
        echo -e "$BLUE$log_entry$NC"
        ;;
      WARN)
        echo -e "$YELLOW$log_entry$NC"
        ;;
      ERROR)
        echo -e "$RED$log_entry$NC"
        ;;
      FATAL)
        echo -e "$RED$log_entry$NC"
        ;;
      *)
        echo -e "$log_entry"
        ;;
    esac
  fi
}

# 记录调试日志
log_debug() {
  if [ "${LOG_LEVELS[$LOG_LEVEL]}" -le "${LOG_LEVELS[DEBUG]}" ]; then
    local caller_info="$(caller)"
    local line_number=$(echo "$caller_info" | awk '{print $1}')
    local function_name=$(echo "$caller_info" | awk '{print $2}')
    local file_name=$(basename "$(echo "$caller_info" | awk '{print $3}')")
    
    # 如果控制台不是详细模式，则只记录到文件
    if [ "$CONSOLE_VERBOSE" = false ]; then
      log_internal "DEBUG" "[$file_name:$line_number] $1" true
    else
      log_internal "DEBUG" "[$file_name:$line_number] $1"
    fi
  fi
}

# 记录信息日志
log_info() {
  if [ "${LOG_LEVELS[$LOG_LEVEL]}" -le "${LOG_LEVELS[INFO]}" ]; then
    local file_only=$2
    
    # 如果控制台不是详细模式，并且文件标志为true，则只记录到文件
    if [ "$CONSOLE_VERBOSE" = false ] && [ "$file_only" = "true" ]; then
      log_internal "INFO" "$1" true
    else
      log_internal "INFO" "$1"
    fi
  fi
}

# 记录警告日志
log_warn() {
  if [ "${LOG_LEVELS[$LOG_LEVEL]}" -le "${LOG_LEVELS[WARN]}" ]; then
    local file_only=$2
    
    # 控制台始终显示警告，除非明确指定仅文件
    if [ "$file_only" = "true" ]; then
      log_internal "WARN" "$1" true
    else
      log_internal "WARN" "$1"
    fi
  fi
}

# 记录错误日志
log_error() {
  if [ "${LOG_LEVELS[$LOG_LEVEL]}" -le "${LOG_LEVELS[ERROR]}" ]; then
    # 错误始终在控制台显示
    log_internal "ERROR" "$1"
  fi
}

# 记录致命错误日志
log_fatal() {
  if [ "${LOG_LEVELS[$LOG_LEVEL]}" -le "${LOG_LEVELS[FATAL]}" ]; then
    # 致命错误始终在控制台显示
    log_internal "FATAL" "$1"
  fi
}

# 带有组件名称的日志记录
log_component() {
  local component=$1
  local level=$2
  local message=$3
  local file_only=$4
  
  case $level in
    DEBUG)
      log_debug "[$component] $message" $file_only
      ;;
    INFO)
      log_info "[$component] $message" $file_only
      ;;
    WARN)
      log_warn "[$component] $message" $file_only
      ;;
    ERROR)
      log_error "[$component] $message"
      ;;
    FATAL)
      log_fatal "[$component] $message"
      ;;
    *)
      log_info "[$component] $message" $file_only
      ;;
  esac
}

# 设置日志级别
set_log_level() {
  local level=$1
  case $level in
    DEBUG|INFO|WARN|ERROR|FATAL)
      LOG_LEVEL=$level
      log_info "日志级别已设置为 $LOG_LEVEL"
      ;;
    *)
      log_warn "无效的日志级别: $level，保持当前级别 $LOG_LEVEL"
      ;;
  esac
}

# 设置控制台输出冗长程度
set_console_verbose() {
  local verbose=$1
  case $verbose in
    true|false)
      CONSOLE_VERBOSE=$verbose
      log_info "控制台输出详细模式: $CONSOLE_VERBOSE"
      ;;
    *)
      log_warn "无效的控制台详细模式值: $verbose，应为true或false"
      ;;
  esac
}

# 查看日志
view_log() {
  local lines=$1
  if [ -z "$lines" ]; then
    lines=20 # 默认显示最后20行
  fi
  
  if [ -f "$LOG_FILE" ]; then
    echo -e "${CYAN}======== 最近的 $lines 行日志 ========${NC}"
    tail -n $lines "$LOG_FILE" | while read -r line; do
      # 根据日志级别着色
      if [[ $line == *"[DEBUG]"* ]]; then
        echo -e "${GRAY}$line${NC}"
      elif [[ $line == *"[INFO]"* ]]; then
        echo -e "${BLUE}$line${NC}"
      elif [[ $line == *"[WARN]"* ]]; then
        echo -e "${YELLOW}$line${NC}"
      elif [[ $line == *"[ERROR]"* ]]; then
        echo -e "${RED}$line${NC}"
      elif [[ $line == *"[FATAL]"* ]]; then
        echo -e "${RED}$line${NC}"
      else
        echo -e "$line"
      fi
    done
    echo -e "${CYAN}================================${NC}"
  else
    echo -e "${YELLOW}日志文件不存在: $LOG_FILE${NC}"
  fi
}

# 查看特定类型日志
view_log_by_level() {
  local level=$1
  local lines=$2
  
  if [ -z "$lines" ]; then
    lines=20 # 默认显示最后20行
  fi
  
  if [ -f "$LOG_FILE" ]; then
    echo -e "${CYAN}======== 最近的 $lines 行 $level 日志 ========${NC}"
    grep "\\[$level\\]" "$LOG_FILE" | tail -n $lines | while read -r line; do
      case $level in
        DEBUG)
          echo -e "${GRAY}$line${NC}"
          ;;
        INFO)
          echo -e "${BLUE}$line${NC}"
          ;;
        WARN)
          echo -e "${YELLOW}$line${NC}"
          ;;
        ERROR|FATAL)
          echo -e "${RED}$line${NC}"
          ;;
        *)
          echo -e "$line"
          ;;
      esac
    done
    echo -e "${CYAN}============================================${NC}"
  else
    echo -e "${YELLOW}日志文件不存在: $LOG_FILE${NC}"
  fi
}

# 搜索日志
search_log() {
  local pattern=$1
  if [ -z "$pattern" ]; then
    echo -e "${YELLOW}请提供搜索模式${NC}"
    return 1
  fi
  
  if [ -f "$LOG_FILE" ]; then
    echo -e "${CYAN}======== 搜索结果: '$pattern' ========${NC}"
    grep -i "$pattern" "$LOG_FILE" | while read -r line; do
      # 根据日志级别着色
      if [[ $line == *"[DEBUG]"* ]]; then
        echo -e "${GRAY}$line${NC}"
      elif [[ $line == *"[INFO]"* ]]; then
        echo -e "${BLUE}$line${NC}"
      elif [[ $line == *"[WARN]"* ]]; then
        echo -e "${YELLOW}$line${NC}"
      elif [[ $line == *"[ERROR]"* ]]; then
        echo -e "${RED}$line${NC}"
      elif [[ $line == *"[FATAL]"* ]]; then
        echo -e "${RED}$line${NC}"
      else
        echo -e "$line"
      fi
    done
    echo -e "${CYAN}================================${NC}"
  else
    echo -e "${YELLOW}日志文件不存在: $LOG_FILE${NC}"
  fi
}

# 显示日志统计信息
log_stats() {
  if [ -f "$LOG_FILE" ]; then
    local total_lines=$(wc -l < "$LOG_FILE")
    local error_lines=$(grep -c "\[ERROR\]" "$LOG_FILE")
    local warn_lines=$(grep -c "\[WARN\]" "$LOG_FILE")
    local info_lines=$(grep -c "\[INFO\]" "$LOG_FILE")
    local debug_lines=$(grep -c "\[DEBUG\]" "$LOG_FILE")
    local fatal_lines=$(grep -c "\[FATAL\]" "$LOG_FILE")
    local other_lines=$((total_lines - error_lines - warn_lines - info_lines - debug_lines - fatal_lines))
    
    echo -e "${CYAN}======== 日志统计 ========${NC}"
    echo -e "总行数: $total_lines"
    echo -e "${RED}错误 (ERROR): $error_lines${NC}"
    echo -e "${RED}致命 (FATAL): $fatal_lines${NC}"
    echo -e "${YELLOW}警告 (WARN): $warn_lines${NC}"
    echo -e "${BLUE}信息 (INFO): $info_lines${NC}"
    echo -e "${GRAY}调试 (DEBUG): $debug_lines${NC}"
    echo -e "其他: $other_lines"
    
    local size=$(stat -c %s "$LOG_FILE" 2>/dev/null || stat -f %z "$LOG_FILE" 2>/dev/null)
    local size_kb=$((size / 1024))
    echo -e "文件大小: ${size_kb}KB"
    echo -e "${CYAN}=========================${NC}"
  else
    echo -e "${YELLOW}日志文件不存在: $LOG_FILE${NC}"
  fi
}

# 检查是否作为shell函数库被source引入
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  # 脚本被source引入，不执行命令行解析，仅导出函数
  check_log_size
  
  # 导出函数，使其可在其他脚本中使用
  export -f log_debug log_info log_warn log_error log_fatal log_component
  export -f set_log_level set_console_verbose view_log view_log_by_level search_log log_stats
  export LOG_DIR LOG_FILE LOG_LEVEL
else
  # 脚本被直接执行，处理命令行参数
  
  # 帮助函数
  show_help() {
    echo -e "${CYAN}Cloudflare IP优选工具 - 日志管理器${NC}"
    echo "用法: $0 [命令] [选项]"
    echo ""
    echo "命令:"
    echo "  view [n]         查看最后n行日志"
    echo "  search <pattern> 搜索匹配模式的日志"
    echo "  rotate           强制轮转日志"
    echo "  clean [days]     清理指定天数前的日志"
    echo "  stats            显示日志统计信息"
    echo "  level <level>    设置日志级别 (DEBUG|INFO|WARN|ERROR|FATAL)"
    echo "  console <true|false> 设置控制台输出详细模式"
    echo ""
    echo "示例:"
    echo "  $0 view 50       # 查看最后50行日志"
    echo "  $0 search error  # 搜索包含'error'的日志"
    echo "  $0 clean 7       # 清理7天前的日志"
    echo "  $0 level DEBUG   # 设置日志级别为DEBUG"
    echo "  $0 console true  # 设置控制台输出详细模式为true"
  }
  
  # 如果没有参数，显示帮助
  if [ $# -eq 0 ]; then
    show_help
    exit 0
  fi
  
  # 解析命令
  command=$1
  shift
  
  case $command in
    view)
      lines=$1
      if [ -z "$lines" ]; then
        lines=20
      fi
      view_log $lines
      ;;
    search)
      pattern=$1
      if [ -z "$pattern" ]; then
        echo -e "${YELLOW}错误: 缺少搜索模式${NC}"
        echo "用法: $0 search <pattern>"
        exit 1
      fi
      search_log "$pattern"
      ;;
    rotate)
      rotate_logs
      echo -e "${GREEN}日志轮转完成${NC}"
      ;;
    clean)
      days=$1
      if [ -z "$days" ]; then
        days=30
      fi
      clean_logs $days
      echo -e "${GREEN}日志清理完成${NC}"
      ;;
    stats)
      log_stats
      ;;
    level)
      level=$1
      if [ -z "$level" ]; then
        echo -e "${YELLOW}错误: 缺少日志级别${NC}"
        echo "用法: $0 level <DEBUG|INFO|WARN|ERROR|FATAL>"
        exit 1
      fi
      set_log_level "$level"
      echo -e "${GREEN}日志级别已设置为 $level${NC}"
      ;;
    console)
      verbose=$1
      if [ -z "$verbose" ]; then
        echo -e "${YELLOW}错误: 缺少控制台详细模式${NC}"
        echo "用法: $0 console <true|false>"
        exit 1
      fi
      set_console_verbose "$verbose"
      echo -e "${GREEN}控制台输出详细模式已设置为 $verbose${NC}"
      ;;
    *)
      echo -e "${YELLOW}错误: 未知命令 '$command'${NC}"
      show_help
      exit 1
      ;;
  esac
fi

# 初始化日志
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  log_info "日志管理器启动"
fi 