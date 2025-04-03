#!/bin/bash
# 路径处理库
# 用于统一管理项目中的所有路径

# 获取脚本所在目录
CURRENT_FILE="$(readlink -f "${BASH_SOURCE[0]}")"
UTILS_DIR="$(dirname "${CURRENT_FILE}")"
PROJECT_ROOT="$(cd "${UTILS_DIR}/.." && pwd)"

# 定义目录结构变量
BIN_DIR="${PROJECT_ROOT}/bin"
CONFIG_DIR="${PROJECT_ROOT}/config"
DATA_DIR="${PROJECT_ROOT}/data"
LOGS_DIR="${PROJECT_ROOT}/logs"
RESULTS_DIR="${PROJECT_ROOT}/results"
UTILS_DIR="${PROJECT_ROOT}/utils"
EXEC_DIR="${PROJECT_ROOT}/bin/exec"

# 检查并创建目录函数
check_dir() {
  local dir="$1"
  local name="$2"
  
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    if [ $? -eq 0 ]; then
      echo "[信息] 已创建${name}目录: $dir"
    else
      echo "[错误] 无法创建${name}目录: $dir"
      return 1
    fi
  fi
  return 0
}

# 输出调试信息（如果需要）
if [ "${DEBUG_PATHS}" = "true" ]; then
  echo "路径配置:"
  echo "PROJECT_ROOT = ${PROJECT_ROOT}"
  echo "BIN_DIR = ${BIN_DIR}"
  echo "CONFIG_DIR = ${CONFIG_DIR}"
  echo "DATA_DIR = ${DATA_DIR}"
  echo "EXEC_DIR = ${EXEC_DIR}"
  echo "LOGS_DIR = ${LOGS_DIR}"
  echo "RESULTS_DIR = ${RESULTS_DIR}"
  echo "UTILS_DIR = ${UTILS_DIR}"
fi

# 确保关键目录存在
ensure_dirs() {
  # 创建必要的目录
  check_dir "$LOGS_DIR" "日志"
  check_dir "$RESULTS_DIR" "结果"
  check_dir "$DATA_DIR" "数据"
  check_dir "$EXEC_DIR" "执行文件"
}

# 初始化时自动确保目录存在
ensure_dirs

# 导出所有变量
export PROJECT_ROOT
export BIN_DIR
export CONFIG_DIR
export DATA_DIR
export EXEC_DIR
export LOGS_DIR
export RESULTS_DIR
export UTILS_DIR
export -f check_dir
export -f ensure_dirs 