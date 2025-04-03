#!/bin/bash
export LANG=en_US.UTF-8

# ====== 配置加载器 ======
# 此脚本用于从YAML配置文件中加载配置项

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config/config.yml"

# 默认配置文件路径
DEFAULT_CONFIG_FILE="${SCRIPT_DIR}/config/config.yml.template"

# 如果配置文件不存在，尝试从模板创建
if [ ! -f "$CONFIG_FILE" ]; then
  if [ -f "$DEFAULT_CONFIG_FILE" ]; then
    echo "[信息] 配置文件不存在，正在从模板创建..."
    cp "$DEFAULT_CONFIG_FILE" "$CONFIG_FILE"
    if [ $? -ne 0 ]; then
      echo "[错误] 无法创建配置文件"
      exit 1
    fi
    echo "[成功] 已创建配置文件: $CONFIG_FILE"
  else
    echo "[错误] 配置文件和模板都不存在，无法继续"
    exit 1
  fi
fi

# 检查是否指定了其他配置文件路径
if [ -n "$1" ] && [ -f "$1" ]; then
  CONFIG_FILE="$1"
  echo "使用指定的配置文件路径: $CONFIG_FILE"
fi

# 检查配置文件是否存在
if [ ! -f "$CONFIG_FILE" ]; then
  echo "[错误] 配置文件不存在: $CONFIG_FILE"
  exit 1
fi

# 从YAML获取配置，根据可用的工具选择方法
get_config() {
  local key="$1"
  local default_value="$2"
  local value=""
  
  # 命令存在性检查函数
  command_exists() {
    command -v "$1" >/dev/null 2>&1
  }
  
  # 首先尝试yq (v4版本，支持表达式)
  if command_exists yq && yq --version | grep -q "version 4"; then
    value=$(yq eval ".$key" "$CONFIG_FILE" 2>/dev/null)
    if [ "$value" = "null" ]; then
      value=""
    fi
  # 尝试yq (v3版本，使用read命令)
  elif command_exists yq && yq --version | grep -q "version 3"; then
    value=$(yq read "$CONFIG_FILE" "$key" 2>/dev/null)
    if [ "$value" = "null" ]; then
      value=""
    fi
  # 尝试使用Python和PyYAML
  elif command_exists python3 && python3 -c "import yaml" 2>/dev/null; then
    value=$(python3 -c "
import yaml, sys
try:
    with open('$CONFIG_FILE', 'r') as f:
        y = yaml.safe_load(f)
    keys = '$key'.split('.')
    result = y
    for k in keys:
        if isinstance(result, dict) and k in result:
            result = result[k]
        else:
            result = None
            break
    print(result if result is not None else '')
except Exception as e:
    print('', file=sys.stderr)
" 2>/dev/null)
  # 尝试使用Python 2和PyYAML
  elif command_exists python && python -c "import yaml" 2>/dev/null; then
    value=$(python -c "
import yaml, sys
try:
    with open('$CONFIG_FILE', 'r') as f:
        y = yaml.safe_load(f)
    keys = '$key'.split('.')
    result = y
    for k in keys:
        if isinstance(result, dict) and k in result:
            result = result[k]
        else:
            result = None
            break
    print result if result is not None else ''
except Exception as e:
    sys.stderr.write('')
" 2>/dev/null)
  # 使用grep和sed的简单解析方法（有限支持）
  else
    # 将key转换为格式类似 ".ip_select.candidate_num:"
    local pattern=$(echo ".$key:" | sed 's/\./\\./g')
    value=$(grep -E "^[[:space:]]*$pattern" "$CONFIG_FILE" | sed -E 's/.*:[[:space:]]*([^[:space:]#]*).*/\1/')
  fi
  
  # 如果未获取到值，使用默认值
  if [ -z "$value" ] && [ -n "$default_value" ]; then
    echo "$default_value"
  else
    echo "$value"
  fi
}

# 获取数组配置项
get_array_config() {
  local key="$1"
  local values=()
  
  # 命令存在性检查函数
  command_exists() {
    command -v "$1" >/dev/null 2>&1
  }
  
  # 首先尝试yq (v4版本，支持表达式)
  if command_exists yq && yq --version | grep -q "version 4"; then
    # 检查键是否存在并且是数组
    local is_array=$(yq eval ".$key | type" "$CONFIG_FILE" 2>/dev/null)
    if [ "$is_array" = "array" ]; then
      local count=$(yq eval ".$key | length" "$CONFIG_FILE" 2>/dev/null)
      for i in $(seq 0 $((count - 1))); do
        local item=$(yq eval ".$key[$i]" "$CONFIG_FILE" 2>/dev/null)
        echo "$item"
      done
    fi
  # 尝试yq (v3版本)
  elif command_exists yq && yq --version | grep -q "version 3"; then
    yq read "$CONFIG_FILE" "$key" 2>/dev/null | while read -r line; do
      # 只输出数组项，跳过数组标记
      if [[ "$line" == "- "* ]]; then
        echo "${line#- }"
      fi
    done
  # 尝试使用Python和PyYAML
  elif command_exists python3 && python3 -c "import yaml" 2>/dev/null; then
    python3 -c "
import yaml, sys
try:
    with open('$CONFIG_FILE', 'r') as f:
        y = yaml.safe_load(f)
    keys = '$key'.split('.')
    result = y
    for k in keys:
        if isinstance(result, dict) and k in result:
            result = result[k]
        else:
            result = None
            break
    if isinstance(result, list):
        for item in result:
            print(item)
except Exception as e:
    pass
" 2>/dev/null
  # 尝试使用Python 2和PyYAML
  elif command_exists python && python -c "import yaml" 2>/dev/null; then
    python -c "
import yaml, sys
try:
    with open('$CONFIG_FILE', 'r') as f:
        y = yaml.safe_load(f)
    keys = '$key'.split('.')
    result = y
    for k in keys:
        if isinstance(result, dict) and k in result:
            result = result[k]
        else:
            result = None
            break
    if isinstance(result, list):
        for item in result:
            print item
except Exception as e:
    pass
" 2>/dev/null
  # 使用grep的简单解析方法（非常有限的支持）
  else
    # 将key转换为格式类似 ".upload.files.default:"
    local pattern=$(echo ".$key:" | sed 's/\./\\./g')
    # 查找数组开始
    local line_num=$(grep -n -E "^[[:space:]]*$pattern" "$CONFIG_FILE" | cut -d ':' -f 1)
    if [ -n "$line_num" ]; then
      # 提取数组项
      awk -v ln="$line_num" 'NR > ln && /^[[:space:]]*-/ {gsub(/^[[:space:]]*-[[:space:]]*/, ""); print}' "$CONFIG_FILE" | grep -v '^[[:space:]]*$'
    fi
  fi
}

# 验证配置文件格式
validate_config() {
  local config_file="$1"
  
  # 命令存在性检查函数
  command_exists() {
    command -v "$1" >/dev/null 2>&1
  }
  
  # 尝试yq验证
  if command_exists yq; then
    if ! yq eval . "$config_file" > /dev/null 2>&1; then
      echo "[错误] 配置文件格式无效: $config_file"
      return 1
    fi
  # 尝试Python验证
  elif command_exists python3 && python3 -c "import yaml" 2>/dev/null; then
    if ! python3 -c "import yaml, sys; yaml.safe_load(open('$config_file')); print('验证通过')" > /dev/null 2>&1; then
      echo "[错误] 配置文件格式无效: $config_file"
      return 1
    fi
  # 尝试Python 2验证
  elif command_exists python && python -c "import yaml" 2>/dev/null; then
    if ! python -c "import yaml, sys; yaml.safe_load(open('$config_file')); print('验证通过')" > /dev/null 2>&1; then
      echo "[错误] 配置文件格式无效: $config_file"
      return 1
    fi
  # 无法验证
  else
    echo "[警告] 无法验证配置文件格式，继续执行但可能有风险"
  fi
  
  return 0
}

# 验证配置文件
validate_config "$CONFIG_FILE" || {
  echo "[警告] 配置文件验证失败，但将继续尝试加载"
}

# 导出函数以便其他脚本使用
export -f get_config get_array_config validate_config 