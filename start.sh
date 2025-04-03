#!/bin/bash
export LANG=en_US.UTF-8

# 设置颜色
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
BLUE="\033[0;34m"
CYAN="\033[0;36m"
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

# 检查命令是否存在
check_cmd() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    if [ "${DEBUG}" = "true" ]; then
      echo "DEBUG: 找到命令: $cmd - $(command -v "$cmd")"
    fi
    return 0
  else
    if [ "${DEBUG}" = "true" ]; then
      echo "DEBUG: 未找到命令: $cmd"
    fi
    return 1
  fi
}

# 保存原始目录
ORIGINAL_DIR="$(pwd)"

# 获取脚本目录路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}" || exit 1

# 在任何其他操作前引入路径库
source "${SCRIPT_DIR}/utils/paths.sh"

# 调试输出
print_info "脚本初始化, 项目根目录: ${PROJECT_ROOT}"

# 引入日志管理器
if [ -f "${UTILS_DIR}/log_manager.sh" ]; then
  source "${UTILS_DIR}/log_manager.sh"
  log_info "启动脚本初始化"
fi

# 引入配置加载器
if [ -f "${UTILS_DIR}/config_loader.sh" ]; then
  source "${UTILS_DIR}/config_loader.sh"
  log_info "已加载配置文件"
else
  log_warn "未找到配置加载器，将使用默认配置"
fi

# 再次确认项目根目录未被修改
print_info "配置加载完成, 确认项目根目录: ${PROJECT_ROOT}"

# 显示版本信息
show_version() {
  echo "================================"
  echo "  Cloudflare IP优选工具 v1.0.0"
  echo "================================"
  echo "支持功能:"
  echo "  - 自动优选Cloudflare IP"
  echo "  - IP测速与筛选"
  echo "  - 结果上传(CF KV/GitHub Gist)"
  echo "  - 消息推送(Telegram/微信)"
  echo "  - 定时任务调度"
  echo "================================"
}

# 检查基本依赖
check_basic_deps() {
  local missing_deps=()
  local deps=("curl" "awk" "sed" "grep")
  
  for cmd in "${deps[@]}"; do
    if ! check_cmd "$cmd"; then
      missing_deps+=("$cmd")
    fi
  done
  
  if [ ${#missing_deps[@]} -gt 0 ]; then
    print_error "缺少基本组件: ${missing_deps[*]}"
    print_info "请使用包管理器安装缺少的组件，例如:"
    print_info "  apt install ${missing_deps[*]}      (Debian/Ubuntu)"
    print_info "  opkg install ${missing_deps[*]}     (OpenWrt/iStoreOS)"
    print_info "  yum install ${missing_deps[*]}      (CentOS/RHEL)"
    return 1
  fi
  
  return 0
}

# 检查上传依赖
check_upload_deps() {
  if ! check_cmd "base64"; then
    print_error "缺少上传所需的base64命令"
    print_info "请安装base64命令，例如:"
    print_info "  apt install coreutils           (Debian/Ubuntu)"
    print_info "  opkg install coreutils-base64   (OpenWrt/iStoreOS)"
    print_info "  yum install coreutils          (CentOS/RHEL)"
    
    # 尝试查找busybox base64
    if check_cmd "busybox" && busybox base64 --help >/dev/null 2>&1; then
      print_warn "发现busybox base64，将创建临时base64命令"
      create_base64_wrapper
      return 0
    fi
    
    return 1
  fi
  
  return 0
}

# 创建base64包装器
create_base64_wrapper() {
  cat > "${PROJECT_ROOT}/base64" << 'EOF'
#!/bin/sh
# 简单的base64实现，使用busybox
busybox base64 "$@"
exit $?
EOF
  chmod +x "${PROJECT_ROOT}/base64"
  print_success "已创建临时base64命令"
  
  # 修改PATH以包含当前目录
  export PATH="${PROJECT_ROOT}:$PATH"
}

# 检查必要目录是否存在
check_dirs() {
  local result=0
  
  # 检查并创建必要目录
  for dir_name in "bin" "config" "data" "logs" "results"; do
    local dir_path="${PROJECT_ROOT}/${dir_name}"
    if [ ! -d "$dir_path" ]; then
      if mkdir -p "$dir_path" 2>/dev/null; then
        print_info "已创建${dir_name}目录: $dir_path"
      else
        print_error "无法创建${dir_name}目录: $dir_path"
        result=1
      fi
    fi
  done
  
  # 创建bin/exec目录（如果不存在）
  if [ ! -d "${BIN_DIR}/exec" ]; then
    print_warn "执行文件目录不存在，正在创建..."
    mkdir -p "${BIN_DIR}/exec"
    if [ $? -eq 0 ]; then
      print_success "已创建执行文件目录"
    else
      print_error "无法创建执行文件目录"
      result=1
    fi
  fi
  
  if [ $result -eq 0 ]; then
    print_success "所有目录检查完成"
  else
    print_warn "以下目录无法创建: ${missing_dirs[*]}"
    print_info "请检查文件权限，或手动创建这些目录"
  fi
  
  return $result
}

# 检查主要脚本
check_scripts() {
  # 检查必要目录是否存在
  check_dirs
  
  # 检查必要脚本
  if [ ! -f "${BIN_DIR}/cfips.sh" ]; then
    print_error "未找到必要文件: bin/cfips.sh"
    print_info "尝试查找cfips.sh:"
    find "${PROJECT_ROOT}" -name "cfips.sh" -type f || print_error "未找到cfips.sh文件"
    return 1
  fi
  
  # 设置执行权限
  chmod +x "${BIN_DIR}/cfips.sh" 2>/dev/null || true
  
  # 检查可选脚本并设置执行权限
  for script in "speed_test.sh" "upload_results.sh" "notify_results.sh" "schedule_tasks.sh"; do
    if [ -f "${BIN_DIR}/$script" ] && [ ! -x "${BIN_DIR}/$script" ]; then
      chmod +x "${BIN_DIR}/$script" 2>/dev/null || true
    fi
  done
  
  return 0
}

# 执行IP优选
run_ip_select() {
  print_info "正在执行IP优选..."
  
  # 检查依赖
  if ! check_basic_deps; then
    return 1
  fi
  
  # 检查脚本
  if ! check_scripts; then
    return 1
  fi
  
  # 执行优选
  if [ -f "${BIN_DIR}/cfips.sh" ]; then
    bash "${BIN_DIR}/cfips.sh" "$@"
    local status=$?
    if [ $status -eq 0 ]; then
      print_success "IP优选完成"
      return 0
    else
      print_error "IP优选失败，退出码: $status"
      return 1
    fi
  else
    print_error "未找到cfips.sh脚本"
    return 1
  fi
}

# 执行IP测速
run_speed_test() {
  print_info "正在执行IP测速..."
  
  # 检查依赖
  if ! check_basic_deps; then
    return 1
  fi
  
  # 检查脚本
  if ! check_scripts; then
    return 1
  fi
  
  # 执行测速
  if [ -f "${BIN_DIR}/speed_test.sh" ]; then
    bash "${BIN_DIR}/speed_test.sh" "$@"
    local status=$?
    if [ $status -eq 0 ]; then
      print_success "IP测速完成"
      return 0
    else
      print_error "IP测速失败，退出码: $status"
      return 1
    fi
  else
    print_error "未找到speed_test.sh脚本"
    return 1
  fi
}

# 执行结果上传
run_upload() {
  print_info "正在上传测速结果..."
  
  # 检查基本依赖
  if ! check_basic_deps; then
    return 1
  fi
  
  # 检查上传依赖
  if ! check_upload_deps; then
    print_error "缺少上传所需的依赖，跳过上传"
    return 1
  fi
  
  # 检查脚本
  if ! check_scripts; then
    return 1
  fi
  
  # 执行上传
  if [ -f "${BIN_DIR}/upload_results.sh" ]; then
    bash "${BIN_DIR}/upload_results.sh" "$@"
    local status=$?
    
    # 根据退出状态码处理结果
    case $status in
      0)
        print_success "结果上传完成"
        return 0
        ;;
      1)
        print_error "上传失败：未找到可上传的文件"
        return 1
        ;;
      2)
        print_info "所有上传方式均已禁用，未执行任何上传操作"
        return 0
        ;;
      3)
        print_warn "部分文件上传失败"
        return 1
        ;;
      *)
        print_warn "上传过程出现未知错误，退出码: $status"
        return 1
        ;;
    esac
  else
    print_error "未找到upload_results.sh脚本"
    return 1
  fi
}

# 执行结果通知
run_notify() {
  # 如果已经通知过，跳过
  if [ "${FORCE_NOTIFY}" != "true" ] && [ "${notify_done}" = "true" ]; then
    print_info "已经发送过通知，跳过"
    return 0
  fi
  
  print_info "正在发送通知..."
  
  # 检查脚本
  if [ ! -f "${BIN_DIR}/notify_results.sh" ]; then
    print_error "未找到notify_results.sh脚本"
    return 1
  fi
  
  # 设置执行权限
  chmod +x "${BIN_DIR}/notify_results.sh" 2>/dev/null || true
  
  # 执行通知
  bash "${BIN_DIR}/notify_results.sh" "$@"
  local status=$?
  if [ $status -eq 0 ]; then
    print_success "通知发送完成"
    notify_done="true"
    return 0
  else
    print_error "通知发送失败，退出码: $status"
    return 1
  fi
}

# 执行定时任务
run_schedule() {
  print_info "正在设置定时任务..."
  
  # 检查脚本
  if [ ! -f "${BIN_DIR}/schedule_tasks.sh" ]; then
    print_error "未找到schedule_tasks.sh脚本"
    return 1
  fi
  
  # 设置执行权限
  chmod +x "${BIN_DIR}/schedule_tasks.sh" 2>/dev/null || true
  
  # 执行定时任务
  bash "${BIN_DIR}/schedule_tasks.sh" "$@"
  local status=$?
  if [ $status -eq 0 ]; then
    print_success "定时任务设置完成"
    return 0
  else
    print_error "定时任务设置失败，退出码: $status"
    return 1
  fi
}

# 执行一次性任务
run_once() {
  print_info "正在执行一次性任务..."
  
  # 检查依赖
  if ! check_basic_deps; then
    return 1
  fi
  
  # 检查脚本
  if ! check_scripts; then
    return 1
  fi
  
  # 执行一次性任务
  if [ -f "${BIN_DIR}/schedule_tasks.sh" ]; then
    bash "${BIN_DIR}/schedule_tasks.sh" --run-once "$@"
    return $?
  else
    print_error "未找到schedule_tasks.sh脚本"
    return 1
  fi
}

# 执行完整流程
run_all() {
  print_info "开始执行完整流程..."
  
  # 检查基本依赖
  if ! check_basic_deps; then
    return 1
  fi
  
  # 检查脚本
  if ! check_scripts; then
    return 1
  fi
  
  local success=true
  
  # IP优选
  run_ip_select || success=false
  
  # 如果IP优选成功，继续进行测速
  if [ "$success" = true ] && [ -f "${BIN_DIR}/speed_test.sh" ]; then
    run_speed_test || success=false
  fi
  
  # 上传和通知不影响整体流程的成功与否
  if ([ -f "${PROJECT_ROOT}/results/cfips.txt" ] || [ -f "${PROJECT_ROOT}/results/cfips.csv" ]) && [ -f "${BIN_DIR}/upload_results.sh" ]; then
    # 检查上传依赖
    if check_upload_deps; then
      # 在all命令中，让上传脚本自己处理通知
      export FORCE_NOTIFY=true
      run_upload
      unset FORCE_NOTIFY
      
      # 上传脚本已经处理了通知，不需要额外通知
      local notify_done=true
    else
      print_warn "跳过上传: 缺少base64命令"
    fi
  fi
  
  # 只有当上传脚本未处理通知时，才单独执行通知
  if [ "$notify_done" != true ] && [ -f "${BIN_DIR}/notify_results.sh" ]; then
    run_notify
  fi
  
  if [ "$success" = true ]; then
    print_success "所有操作已完成"
    return 0
  else
    print_warn "操作完成，但部分步骤出现错误"
    return 1
  fi
}

# 展示帮助
show_help() {
  cat << EOF
用法: $0 [命令] [选项]

命令:
  all         执行完整流程 (IP优选->测速->上传->通知)
  select      仅执行IP优选
  test        仅执行IP测速
  upload      仅执行结果上传
  notify      仅发送结果通知
  schedule    设置并启动定时任务
  once        执行一次性任务后退出
  help        显示此帮助信息
  version     显示版本信息

选项:
  根据不同命令，可传递对应脚本支持的参数

示例:
  $0 all                  # 执行完整流程
  $0 select               # 仅执行IP优选
  $0 test --speed-limit 10 # 执行IP测速，设置下载速度下限为10MB/s
  $0 schedule -i 120      # 设置定时任务，间隔120分钟
EOF
}

# 主函数
main() {
  # 如果没有参数，显示帮助
  if [ $# -eq 0 ]; then
    show_version
    echo ""
    show_help
    exit 0
  fi
  
  # 解析第一个参数作为命令
  local cmd="$1"
  shift
  
  # 执行对应命令
  case "$cmd" in
    all)
      run_all "$@"
      ;;
    select)
      run_ip_select "$@"
      ;;
    test)
      run_speed_test "$@"
      ;;
    upload)
      run_upload "$@"
      ;;
    notify)
      run_notify "$@"
      ;;
    schedule)
      run_schedule "$@"
      ;;
    once)
      run_once "$@"
      ;;
    help)
      show_version
      echo ""
      show_help
      ;;
    version)
      show_version
      ;;
    *)
      print_error "未知命令: $cmd"
      echo ""
      show_help
      exit 1
      ;;
  esac
  
  # 返回原始目录
  cd "${ORIGINAL_DIR}" || exit 1
  
  exit $?
}

# 执行主函数
main "$@" 