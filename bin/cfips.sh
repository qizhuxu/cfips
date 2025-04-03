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
    echo "[${timestamp}] ${msg}" >> "${SCRIPT_DIR}/logs/cfips.log"
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

print_info "初始化 Cloudflare IP 优选工具..."

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

# 从配置文件加载参数
CANDIDATE_NUM=$(get_config "ip_select.candidate_num")
FINAL_NUM=$(get_config "ip_select.final_num")
PORT=$(get_config "ip_select.port")
ALLOW_EXTERNAL=$(get_config "ip_select.allow_external")
CUSTOM_IPS_ENABLED=$(get_config "ip_select.custom_ips.enabled")

if [ -z "$CANDIDATE_NUM" ] || [ -z "$FINAL_NUM" ] || [ -z "$PORT" ] || [ -z "$ALLOW_EXTERNAL" ] || [ -z "$CUSTOM_IPS_ENABLED" ]; then
  print_error "配置文件加载失败或缺少必要配置，请检查配置文件"
  exit 1
fi

print_info "已从配置文件加载优选设置"
print_info "候选IP数量: $CANDIDATE_NUM"
print_info "最终选择数量: $FINAL_NUM"
print_info "监听端口: $PORT"
print_info "允许外部连接: $ALLOW_EXTERNAL"
print_info "自定义IP库启用: $CUSTOM_IPS_ENABLED"

# 检查cf执行文件是否存在
if [ -e "${DATA_DIR}/cf" ]; then
  CF_CMD="${DATA_DIR}/cf"
  print_info "已找到cf执行文件"
  # 确保有执行权限
  [ -x "${CF_CMD}" ] || chmod +x "${CF_CMD}"
  if [ $? -ne 0 ]; then
    print_error "无法给cf添加执行权限，请检查文件权限"
    exit 1
  fi
else
  print_error "未找到cf执行文件，请确保该文件位于data目录"
  exit 1
fi

# 检查其他必要文件
for file in "locations.json" "ips-v4.txt" "ips-v6.txt"; do
  if [ ! -e "${DATA_DIR}/$file" ]; then
    print_warn "未找到 ${DATA_DIR}/$file 文件，这可能导致测试结果不准确"
  fi
done

# 定义地区代码
declare -A REGION_CODES=(
  ["US"]="BGI|YCC|YVR|YWG|YHZ|YOW|YYZ|YUL|YXE|STI|SDQ|GUA|KIN|GDL|MEX|QRO|SJU|MGM|ANC|PHX|LAX|SMF|SAN|SFO|SJC|DEN|JAX|MIA|TLH|TPA|ATL|HNL|ORD|IND|BGR|BOS|DTW|MSP|MCI|STL|OMA|LAS|EWR|ABQ|BUF|CLT|RDU|CLE|CMH|OKC|PDX|PHL|PIT|FSD|MEM|BNA|AUS|DFW|IAH|MFE|SAT|SLC|IAD|ORF|RIC|SEA"
  ["AS"]="CGP|DAC|JSR|PBH|BWN|PNH|GUM|HKG|AMD|BLR|BBI|IXC|MAA|HYD|CNN|KNU|COK|CCU|BOM|NAG|DEL|PAT|DPS|CGK|JOG|FUK|OKA|KIX|NRT|ALA|NQZ|ICN|VTE|MFM|JHB|KUL|KCH|MLE|ULN|MDL|RGN|KTM|ISB|KHI|LHE|CGY|CEB|MNL|CRK|KJA|SVX|SIN|CMB|KHH|TPE|BKK|CNX|URT|TAS|DAD|HAN|SGN"
  ["EU"]="TIA|VIE|MSQ|BRU|SOF|ZAG|LCA|PRG|CPH|TLL|HEL|BOD|LYS|MRS|CDG|TBS|TXL|DUS|FRA|HAM|MUC|STR|ATH|SKG|BUD|KEF|ORK|DUB|MXP|PMO|FCO|RIX|VNO|LUX|KIV|AMS|SKP|OSL|WAW|LIS|OTP|DME|LED|KLD|BEG|BTS|BCN|MAD|GOT|ARN|GVA|ZRH|IST|ADB|KBP|EDI|LHR|MAN"
)

# 确保结果目录存在
mkdir -p "${RESULTS_DIR}" 2>/dev/null

# 初始化
print_info "正在清理旧文件..."
rm -rf "${RESULTS_DIR}"/{4,6}.csv "${RESULTS_DIR}"/cfips.csv "${RESULTS_DIR}"/*-*.csv 2>/dev/null
> "${RESULTS_DIR}/cfips.csv"

# 检测IPv6支持
print_info "正在检测网络IPv6支持情况..."
IPV6_SUPPORT=false

# 多重检查IPv6连通性:
# 1. 检查是否存在默认IPv6路由
if ip -6 route show default &>/dev/null; then
  # 2. 尝试连接到几个知名的IPv6服务器，确保实际连通性
  if ping -6 -c 1 -W 2 2606:4700:4700::1111 &>/dev/null || 
     ping -6 -c 1 -W 2 2606:4700:4700::1001 &>/dev/null || 
     ping -6 -c 1 -W 2 2620:0:ccc::2 &>/dev/null || 
     ping -6 -c 1 -W 2 2620:0:ccd::2 &>/dev/null || 
     ping -6 -c 1 -W 2 2001:4860:4860::8888 &>/dev/null || 
     ping -6 -c 1 -W 2 2001:4860:4860::8844 &>/dev/null; then
    IPV6_SUPPORT=true
    print_success "检测到当前网络支持IPv6，将同时测试IPv4和IPv6"
  else
    print_warn "检测到IPv6配置，但无法连接IPv6网络，将仅测试IPv4"
  fi
else
  print_warn "当前网络不支持IPv6，将仅测试IPv4"
  print_info "如需启用IPv6，请确保Docker配置了IPv6网络（已在docker-compose.yml中配置）"
fi

# 处理一个IP版本的优选
process_ip() {
  local ver=$1
  local ver_name="IPv$ver"
  
  print_info "开始处理${ver_name}优选..."
  
  # 运行测试，抑制输出
  print_info "正在执行${ver_name}连接性测试，请耐心等待..."
  $CF_CMD -ips $ver -outfile "${RESULTS_DIR}/$ver.csv" >/dev/null 2>&1
  
  if [ ! -e "${RESULTS_DIR}/$ver.csv" ] || [ ! -s "${RESULTS_DIR}/$ver.csv" ]; then
    print_error "${ver_name}测试失败，未生成有效数据"
    return 1
  fi
  
  print_success "${ver_name}测试完成，正在处理结果..."
  
  # 各地区优选
  for region in US AS EU; do
    case $region in
      "US") region_name="美国" ;;
      "AS") region_name="亚洲" ;;
      "EU") region_name="欧洲" ;;
    esac
    
    print_info "正在处理${region_name}地区的${ver_name}数据..."
    
    # 筛选该地区IP并排序
    awk -F ',' '$2 ~ /'${REGION_CODES[$region]}'/ {print $0}' "${RESULTS_DIR}/$ver.csv" | 
      sort -t ',' -k5,5n | 
      head -n $CANDIDATE_NUM > "${RESULTS_DIR}/$region-$ver-all.csv"
    
    if [ ! -s "${RESULTS_DIR}/$region-$ver-all.csv" ]; then
      print_warn "未找到${region_name}地区的${ver_name}数据"
      continue
    fi
    
    # 取最终结果并添加到结果文件
    sort -t ',' -k5,5n "${RESULTS_DIR}/$region-$ver-all.csv" | 
      head -n $FINAL_NUM >> "${RESULTS_DIR}/cfips.csv"
    
    # 显示结果摘要
    ip_count=$(wc -l < "${RESULTS_DIR}/$region-$ver-all.csv")
    final_count=$(sort -t ',' -k5,5n "${RESULTS_DIR}/$region-$ver-all.csv" | head -n $FINAL_NUM | wc -l)
    print_success "已找到${region_name}地区的${ip_count}个${ver_name}候选IP，优选出${final_count}个"
  done
  
  return 0
}

# 处理自定义IP库
process_custom_ips() {
  if [ "$CUSTOM_IPS_ENABLED" != "true" ]; then
    print_info "自定义IP库未启用，跳过加载"
    return 0
  fi
  
  print_info "开始加载自定义IP库..."
  local custom_ip_file="${RESULTS_DIR}/custom_ips.csv"
  > "$custom_ip_file"
  
  # 创建临时存放IP的文件
  local temp_ip_file="${DATA_DIR}/temp_custom_ips.txt"
  > "$temp_ip_file"
  
  # 检查自定义IP文件
  local ip_file="${CONFIG_DIR}/custom_ips.txt"
  if [ -f "$ip_file" ]; then
    print_info "从文件读取自定义IP: $ip_file"
    # 提取非注释且非空行
    grep -v "^#" "$ip_file" | grep -v "^$" >> "$temp_ip_file"
  else
    print_warn "未找到自定义IP文件: $ip_file"
    touch "$ip_file"  # 创建一个空文件以便未来使用
  fi
  
  # 去重
  sort -u "$temp_ip_file" > "${temp_ip_file}.sorted"
  mv "${temp_ip_file}.sorted" "$temp_ip_file"
  
  # 检查是否有自定义IP
  local ip_count=$(wc -l < "$temp_ip_file")
  if [ $ip_count -eq 0 ]; then
    print_warn "未找到任何自定义IP，跳过自定义IP测试"
    rm -f "$temp_ip_file"
    return 0
  fi
  
  print_success "找到 $ip_count 个自定义IP，开始测试"
  
  # 创建测试结果的临时文件
  local output_file="${DATA_DIR}/custom_test_output.csv"
  
  # 执行测试
  $CF_CMD -ip $temp_ip_file -outfile "$output_file" >/dev/null 2>&1
  
  if [ ! -e "$output_file" ] || [ ! -s "$output_file" ]; then
    print_error "自定义IP测试失败，未生成有效数据"
    rm -f "$temp_ip_file" "$output_file"
    return 1
  fi
  
  # 处理测试结果
  print_info "自定义IP测试完成，处理结果..."
  
  # 把测试结果按延迟排序，取前CANDIDATE_NUM个
  sort -t ',' -k5,5n "$output_file" | head -n $CANDIDATE_NUM > "$custom_ip_file"
  
  if [ ! -s "$custom_ip_file" ]; then
    print_warn "自定义IP测试未产生有效结果"
    rm -f "$temp_ip_file" "$output_file"
    return 1
  fi
  
  # 从结果中选取前FINAL_NUM个自定义IP添加到最终结果
  sort -t ',' -k5,5n "$custom_ip_file" | head -n $FINAL_NUM >> "${RESULTS_DIR}/cfips.csv"
  
  local final_count=$(sort -t ',' -k5,5n "$custom_ip_file" | head -n $FINAL_NUM | wc -l)
  print_success "成功添加 $final_count 个自定义IP到优选结果"
  
  # 清理临时文件
  rm -f "$temp_ip_file" "$output_file"
  return 0
}

# 执行优选
print_info "开始执行IP优选工作..."

# 处理IPv4
process_ip 4
ipv4_success=$?

# 处理IPv6
if $IPV6_SUPPORT; then
  process_ip 6
  ipv6_success=$?
else
  ipv6_success=1
fi

# 处理自定义IP库
process_custom_ips

# 检查结果
if [ ! -s "${RESULTS_DIR}/cfips.csv" ]; then
  print_error "优选失败，未生成有效结果"
  exit 1
fi

# 显示结果
total_ips=$(wc -l < "${RESULTS_DIR}/cfips.csv")
print_success "优选完成！共找到${total_ips}个优质IP"

# 清理临时文件
print_info "正在清理临时文件..."
rm -rf "${RESULTS_DIR}/"{4,6}.csv "${RESULTS_DIR}/"*-*-all.csv "${RESULTS_DIR}/"*-{4,6}.csv 2>/dev/null

# 结果保存位置
print_success "所有优选结果已保存到 ${RESULTS_DIR}/cfips.csv 文件中"

# 转换cfips.csv为cfips.txt (IP:端口#城市格式)
print_info "正在转换IP格式为cfips.txt..."

# 加载端口配置 - 不再检查是否启用，默认所有IP都有端口
DEFAULT_PORT=$(get_config "ip_select.port_config.default_port" "443")
RANDOM_PORT=$(get_config "ip_select.port_config.random_port" "false")

# 确保RANDOM_PORT是true或false
if [ "$RANDOM_PORT" != "true" ]; then
  RANDOM_PORT="false"
fi

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

# 所有IP都添加端口，不再检查PORT_ENABLED
if [ "$RANDOM_PORT" = "true" ]; then
  print_info "使用随机端口模式，从可用端口中随机选择"
  # 使用随机端口生成cfips.txt
  awk -F ',' '
  BEGIN {
    srand();
    ports[0] = "443";
    ports[1] = "8443";
    ports[2] = "2053";
    ports[3] = "2083";
    ports[4] = "2087";
    ports[5] = "2086";
  }
  {
    port_index = int(rand() * 6);
    random_port = ports[port_index];
    print $1":"random_port"#"$4
  }' "${RESULTS_DIR}/cfips.csv" > "${RESULTS_DIR}/cfips.txt"
else
  print_info "使用固定端口: $DEFAULT_PORT"
  # 使用指定端口生成cfips.txt
  awk -F ',' -v port="$DEFAULT_PORT" '{print $1":"port"#"$4}' "${RESULTS_DIR}/cfips.csv" > "${RESULTS_DIR}/cfips.txt"
fi

if [ -s "${RESULTS_DIR}/cfips.txt" ]; then
  print_success "已将IP信息转换为cfips.txt，格式为IP:端口#城市"
  print_info "生成的cfips.txt预览 (前5条):"
  head -n 5 "${RESULTS_DIR}/cfips.txt"
else
  print_warn "生成cfips.txt失败或文件为空"
fi

# 如果用户需要查看结果
if [ $total_ips -gt 0 ]; then
  print_info "结果预览 (前5条):"
  head -n 5 "${RESULTS_DIR}/cfips.csv"
  print_info "使用 'cat ${RESULTS_DIR}/cfips.csv' 命令查看完整结果"
  print_info "使用 'cat ${RESULTS_DIR}/cfips.txt' 命令查看IP:端口#城市格式结果"
fi

# 备份cfips.csv以便于问题排查
print_info "备份cfips.csv到${RESULTS_DIR}/cfips.csv.backup..."
cp "${RESULTS_DIR}/cfips.csv" "${RESULTS_DIR}/cfips.csv.backup"

# 创建带端口信息的cfips_port.csv
print_info "创建带有端口信息的cfips_port.csv文件..."
if [ "$RANDOM_PORT" = "true" ]; then
  # 使用随机端口
  awk -F ',' 'BEGIN {
    srand();
    ports[0] = "443";
    ports[1] = "8443";
    ports[2] = "2053";
    ports[3] = "2083";
    ports[4] = "2087";
    ports[5] = "2086";
  }
  {
    port_index = int(rand() * 6);
    port = ports[port_index];
    printf("%s:%s,%s,%s,%s,%s\n", $1, port, $2, $3, $4, $5);
  }' "${RESULTS_DIR}/cfips.csv" > "${RESULTS_DIR}/cfips_port.csv"
else
  # 使用固定端口
  awk -F ',' -v port="$DEFAULT_PORT" '{printf("%s:%s,%s,%s,%s,%s\n", $1, port, $2, $3, $4, $5);}' "${RESULTS_DIR}/cfips.csv" > "${RESULTS_DIR}/cfips_port.csv"
fi

print_info "IP优选过程已完成，所有文件已保存"
