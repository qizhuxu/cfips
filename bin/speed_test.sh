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
    echo "[${timestamp}] ${msg}" >> "${SCRIPT_DIR}/logs/speed_test.log"
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

# 导入配置加载器
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${SCRIPT_DIR}/data"
RESULTS_DIR="${SCRIPT_DIR}/results"
EXEC_DIR="${SCRIPT_DIR}/exec"
UTILS_DIR="${SCRIPT_DIR}/utils"
TEMP_DIR="${SCRIPT_DIR}/temp"  # 定义临时目录

# 确保临时目录和日志目录存在
mkdir -p "${SCRIPT_DIR}/logs" "${TEMP_DIR}"

if [ -f "${UTILS_DIR}/config_loader.sh" ]; then
  source "${UTILS_DIR}/config_loader.sh"
  print_info "已加载配置文件"
else
  print_error "无法找到配置加载器，程序无法继续"
  exit 1
fi

# 从配置文件加载参数
SPEED_LIMIT=$(get_config "speed_test.speed_limit")
LATENCY_LIMIT=$(get_config "speed_test.latency_limit")
TEST_COUNT=$(get_config "speed_test.test_count")
THREAD_NUM=$(get_config "speed_test.thread_num")
TEST_URL=$(get_config "speed_test.test_url")
PORT=$(get_config "speed_test.port")
ALLOW_EXTERNAL=$(get_config "speed_test.allow_external")

# 检查关键参数，设置默认值
if [ -z "$SPEED_LIMIT" ]; then
  SPEED_LIMIT=0
fi

if [ -z "$LATENCY_LIMIT" ]; then
  LATENCY_LIMIT=500
fi

if [ -z "$TEST_COUNT" ]; then
  TEST_COUNT=0
fi

if [ -z "$THREAD_NUM" ]; then
  THREAD_NUM=4
fi

if [ -z "$PORT" ]; then
  PORT=15001
fi

if [ -z "$ALLOW_EXTERNAL" ]; then
  ALLOW_EXTERNAL=true
fi

print_info "已从配置文件加载测速设置"
print_info "速度限制: $SPEED_LIMIT MB/s"
print_info "延迟限制: $LATENCY_LIMIT ms"
print_info "测试IP数量: $TEST_COUNT"
print_info "测速线程数: $THREAD_NUM"
print_info "测速URL: $TEST_URL"
print_info "测速功能端口: $PORT"
print_info "允许外部连接: $ALLOW_EXTERNAL"

# 检查CloudflareST可执行文件是否存在
CLOUDFLAREST_PATH="${EXEC_DIR}/CloudflareST"
if [ -f "$CLOUDFLAREST_PATH" ]; then
  if [ ! -x "$CLOUDFLAREST_PATH" ]; then
    chmod +x "$CLOUDFLAREST_PATH"
    if [ $? -ne 0 ]; then
      print_error "无法给CloudflareST添加执行权限，请检查文件权限"
      exit 1
    fi
  fi
  CLOUDFLAREST_CMD="$CLOUDFLAREST_PATH"
  print_info "已找到CloudflareST执行文件"
else
  print_error "未找到CloudflareST执行文件，请确保该文件位于exec目录"
  exit 1
fi

# 确保随机端口功能正确工作
ensure_random_port

# 检查cfips.csv是否存在
if [ ! -f "${RESULTS_DIR}/cfips.csv" ]; then
  print_error "未找到cfips.csv文件，请先运行cfips.sh生成IP列表"
  exit 1
fi

# 检查CloudflareST执行文件
if [ ! -x "${DATA_DIR}/CloudflareST" ]; then
  print_info "设置CloudflareST执行权限..."
  chmod +x ${DATA_DIR}/CloudflareST
  if [ $? -ne 0 ]; then
    print_error "无法设置CloudflareST执行权限，请检查文件是否存在"
    exit 1
  fi
fi

CLOUDFLAREST_CMD="${DATA_DIR}/CloudflareST"
print_success "已准备好CloudflareST执行文件"

# 提取IP地址到IP.txt
print_info "正在从cfips.csv提取IP地址..."
awk -F ',' '{print $1}' "${RESULTS_DIR}/cfips.csv" > "${RESULTS_DIR}/ip.txt"
ip_count=$(wc -l < "${RESULTS_DIR}/ip.txt")

if [ $ip_count -eq 0 ]; then
  print_error "从cfips.csv中未找到任何IP地址"
  exit 1
fi

print_success "已提取${ip_count}个IP地址"

# 定义测速函数
perform_speed_test() {
  local ip_file="$1"
  local output_file="${RESULTS_DIR}/result.csv"
  
  print_info "准备开始测速..."
  
  # 组装测速命令参数
  CMD_ARGS="-tp $PORT"
  
  if [ -n "$SPEED_LIMIT" ]; then
    CMD_ARGS="$CMD_ARGS -sl $SPEED_LIMIT"
  fi
  
  if [ -n "$LATENCY_LIMIT" ]; then
    CMD_ARGS="$CMD_ARGS -tl $LATENCY_LIMIT"
  fi
  
  if [ -n "$THREAD_NUM" ]; then
    CMD_ARGS="$CMD_ARGS -t $THREAD_NUM"
  fi
  
  if [ -n "$TEST_COUNT" ] && [ "$TEST_COUNT" -gt 0 ]; then
    CMD_ARGS="$CMD_ARGS -n $TEST_COUNT"
  fi
  
  if [ -n "$TEST_URL" ]; then
    CMD_ARGS="$CMD_ARGS -url $TEST_URL"
  fi
  
  if [ "$ALLOW_EXTERNAL" = "true" ]; then
    CMD_ARGS="$CMD_ARGS -httping"
  fi
  
  # 使用指定的IP文件
  CMD_ARGS="$CMD_ARGS -f $ip_file"
  
  # 指定输出文件
  CMD_ARGS="$CMD_ARGS -o $output_file"
  
  # 执行命令，不记录日志
  print_info "开始执行测速，这可能需要一段时间..."
  print_info "执行命令: ${CLOUDFLAREST_CMD} $CMD_ARGS"
  ${CLOUDFLAREST_CMD} $CMD_ARGS >/dev/null 2>&1
  
  # 检查结果文件
  if [ -f "$output_file" ]; then
    print_success "IP测速完成！"
    # 复制一份到临时目录以便后续处理
    cp "$output_file" "${TEMP_DIR}/result.csv"
    return 0
  else
    print_error "测速失败，未生成结果文件"
    return 1
  fi
}

# 执行测速
print_info "开始进行速度测试，测试线程数: ${THREAD_NUM}..."

# 构建命令参数
CMD_ARGS="-f ${RESULTS_DIR}/ip.txt -sl ${SPEED_LIMIT} -tl ${LATENCY_LIMIT} -t ${THREAD_NUM} -dn ${TEST_COUNT} -o ${RESULTS_DIR}/result.csv"

# 添加自定义测速地址（如果指定）
if [ -n "$TEST_URL" ]; then
  CMD_ARGS="$CMD_ARGS -url ${TEST_URL}"
  print_info "使用自定义测速地址: ${TEST_URL}"
else
  print_info "使用默认测速地址"
fi

# 添加监听端口（如果指定）
CMD_ARGS="$CMD_ARGS -p ${PORT}"
print_info "使用监听端口: $PORT"

# 添加允许外部连接（如果指定）
if [ "$ALLOW_EXTERNAL" == "true" ]; then
  CMD_ARGS="$CMD_ARGS -e"
  print_info "允许外部连接"
fi

# 执行命令，不记录日志
print_info "开始执行测速，这可能需要一段时间..."
${CLOUDFLAREST_CMD} $CMD_ARGS >/dev/null 2>&1

# 检查结果文件
if [ -f "${RESULTS_DIR}/result.csv" ]; then
  print_success "IP测速完成！"
  # 复制一份到临时目录以便后续处理
  cp "${RESULTS_DIR}/result.csv" "${TEMP_DIR}/result.csv"
else
  print_error "测速失败，未生成结果文件"
  exit 1
fi

# 显示结果
result_count=$(wc -l < "${RESULTS_DIR}/result.csv")
if [ $result_count -gt 1 ]; then
  # 排除标题行
  actual_count=$((result_count - 1))
  print_success "共有${actual_count}个IP通过测速条件"
  
  # 显示结果摘要
  print_info "测速结果预览 (前10条):"
  head -n 11 "${RESULTS_DIR}/result.csv"
  
  print_info "结果已保存到${RESULTS_DIR}/result.csv文件"
  print_info "使用'cat ${RESULTS_DIR}/result.csv'命令查看完整结果"
else
  print_warn "没有IP通过测速条件，请尝试调低速度限制或延迟限制"
fi

# 清理临时文件
rm -f "${RESULTS_DIR}/ip.txt" 2>/dev/null

# 处理测速结果 - 解决临时目录变量问题
print_info "正在处理测速结果文件..."

RESULT_CSV="${TEMP_DIR}/result.csv"
if [ -e "$RESULT_CSV" ] && [ -s "$RESULT_CSV" ]; then  
  # 如果测速IP文件不存在，则尝试全部IP再次测速
  if [ ! -e "${RESULTS_DIR}/result_ip.txt" ] || [ ! -s "${RESULTS_DIR}/result_ip.txt" ]; then
    print_warn "未找到有效的测速结果，尝试使用所有优选IP进行测速..."
    
    # 如果cfips.txt存在且不为空，则使用它进行测速
    if [ -e "${RESULTS_DIR}/cfips.txt" ] && [ -s "${RESULTS_DIR}/cfips.txt" ]; then
      print_info "使用cfips.txt中的IP进行测速..."
      # 创建只有IP的文件供测速使用
      awk -F '[:#]' '{print $1}' "${RESULTS_DIR}/cfips.txt" > "${TEMP_DIR}/ip.txt"
      
      # 确保生成的IP文件不为空
      if [ -s "${TEMP_DIR}/ip.txt" ]; then
        print_info "已生成IP文件，包含$(wc -l < "${TEMP_DIR}/ip.txt")个IP"
        
        # 调用测速函数
        perform_speed_test "${TEMP_DIR}/ip.txt"
      else
        print_error "无法从cfips.txt提取IP信息"
      fi
    else
      print_warn "未找到有效的cfips.txt文件"
    fi
  fi

  # 生成最终IP结果文件
  print_info "正在生成最终IP结果文件..."

  # 确保结果目录存在
  mkdir -p "${RESULTS_DIR}"

  # 加载端口配置 - 不再检查是否启用，默认所有IP都有端口
  DEFAULT_PORT=$(get_config "ip_select.port_config.default_port" "443")
  RANDOM_PORT=$(get_config "ip_select.port_config.random_port" "false")

  # 确保RANDOM_PORT是true或false
  if [ "$RANDOM_PORT" != "true" ]; then
    RANDOM_PORT="false"
  fi

  # 输出端口配置
  print_info "端口配置: 默认端口=${DEFAULT_PORT}, 随机端口=${RANDOM_PORT}"

  # 定义可用的端口
  AVAILABLE_PORTS=("443" "8443" "2053" "2083" "2087" "2086")

  # 检查端口是否有效，如果无效则使用默认443
  port_valid=false
  for port in "${AVAILABLE_PORTS[@]}"; do
    if [ "$port" = "$DEFAULT_PORT" ]; then
      port_valid=true
      break
    fi
  done

  if [ "$port_valid" = false ]; then
    print_warn "配置的端口 $DEFAULT_PORT 无效，使用默认端口443"
    DEFAULT_PORT="443"
  fi

  # 检查是否已生成带格式的result_ip.txt文件
  if [ -f "${RESULTS_DIR}/result_ip.txt" ] && [ -s "${RESULTS_DIR}/result_ip.txt" ]; then
    result_count=$(wc -l < "${RESULTS_DIR}/result_ip.txt")
    print_success "已找到带格式的result_ip.txt文件，共${result_count}条记录"
    print_info "结果预览 (前5条):"
    head -n 5 "${RESULTS_DIR}/result_ip.txt"
    exit 0
  fi

  # 备用方法：如果result_ip.txt不存在，直接从result.csv生成
  if [ -f "${RESULTS_DIR}/result.csv" ] && [ -s "${RESULTS_DIR}/result.csv" ]; then
    print_info "正在从result.csv生成result_ip.txt..."
    
    # 根据随机端口设置决定使用哪种方式生成
    if [ "$RANDOM_PORT" = "true" ]; then
      print_info "使用随机端口模式生成结果文件..."
      
      # 使用随机端口生成result_ip.txt
      awk -F ',' 'NR>1 {
        # 随机选择端口
        srand();
        port_index = int(rand() * 6);
        ports[0] = "443";
        ports[1] = "8443";
        ports[2] = "2053";
        ports[3] = "2083";
        ports[4] = "2087";
        ports[5] = "2086";
        random_port = ports[port_index];
        
        # 提取IP和速度
        ip = $1;
        speed = $5;
        location = $6;
        
        # 格式化速度
        if (speed == "") speed = "未知";
        else speed = speed " Mb/s";
        gsub(/ Mbps/, "Mb/s", speed);
        
        # 如果缺少位置信息，使用Unknown
        if (location == "") location = "Unknown";
        
        # 输出格式：IP:端口#城市 | 速度
        print ip":"random_port"#"location" | "speed
      }' "${RESULTS_DIR}/result.csv" > "${RESULTS_DIR}/result_ip.txt"
    else
      print_info "使用固定端口${DEFAULT_PORT}生成结果文件..."
      
      # 使用固定端口生成result_ip.txt
      awk -F ',' -v port="$DEFAULT_PORT" 'NR>1 {
        # 提取IP和速度
        ip = $1;
        speed = $5;
        location = $6;
        
        # 格式化速度
        if (speed == "") speed = "未知";
        else speed = speed " Mb/s";
        gsub(/ Mbps/, "Mb/s", speed);
        
        # 如果缺少位置信息，使用Unknown
        if (location == "") location = "Unknown";
        
        # 输出格式：IP:端口#城市 | 速度
        print ip":"port"#"location" | "speed
      }' "${RESULTS_DIR}/result.csv" > "${RESULTS_DIR}/result_ip.txt"
    fi
    
    # 检查结果
    if [ -s "${RESULTS_DIR}/result_ip.txt" ]; then
      result_count=$(wc -l < "${RESULTS_DIR}/result_ip.txt")
      print_success "成功生成result_ip.txt，共${result_count}条记录"
      print_info "结果预览 (前5条):"
      head -n 5 "${RESULTS_DIR}/result_ip.txt"
    else
      print_error "生成result_ip.txt失败或文件为空"
    fi
  else
    print_error "找不到result.csv文件，无法生成result_ip.txt"
  fi
else
  print_warn "未找到有效的测速结果文件result.csv"
fi

# 检查结果
if [ -f "${RESULTS_DIR}/result_ip.txt" ] && [ -s "${RESULTS_DIR}/result_ip.txt" ]; then
  result_count=$(wc -l < "${RESULTS_DIR}/result_ip.txt")
  print_success "已生成包含IP、端口、城市和速度信息的最终结果文件: ${RESULTS_DIR}/result_ip.txt"
  print_info "最终结果预览 (前5条):"
  head -n 5 "${RESULTS_DIR}/result_ip.txt"
else
  print_warn "未能生成有效的result_ip.txt文件"
fi

# 清理临时文件
print_info "清理临时文件..."
rm -f "${TEMP_DIR}/ip_speed.txt" "${TEMP_DIR}/ip.txt" 2>/dev/null

print_success "CloudflareST速度测试脚本执行完成" 