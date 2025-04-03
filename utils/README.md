# 路径处理库

本目录包含项目中所有脚本使用的通用路径处理库，解决了脚本中路径获取不一致的问题。

## 主要文件

- `paths.sh`: 定义了所有项目目录的路径，确保所有脚本使用统一的路径结构
- `config_loader.sh`: 读取配置文件的工具，现在使用paths.sh获取标准路径
- `log_manager.sh`: 日志管理工具，同样使用paths.sh获取标准路径

## 路径变量

paths.sh定义了以下标准路径变量：

- `PROJECT_ROOT`: 项目根目录
- `BIN_DIR`: 二进制文件目录 (PROJECT_ROOT/bin)
- `CONFIG_DIR`: 配置文件目录 (PROJECT_ROOT/config)
- `DATA_DIR`: 数据文件目录 (PROJECT_ROOT/data)
- `EXEC_DIR`: 可执行文件目录 (PROJECT_ROOT/exec)
- `LOGS_DIR`: 日志文件目录 (PROJECT_ROOT/logs)
- `RESULTS_DIR`: 结果文件目录 (PROJECT_ROOT/results)
- `UTILS_DIR`: 工具脚本目录 (PROJECT_ROOT/utils)

## 使用方法

在脚本开头加载paths.sh：

```bash
#!/bin/bash

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"  # 假设脚本在项目的子目录中

# 加载路径库
if [ -f "${PROJECT_DIR}/utils/paths.sh" ]; then
  source "${PROJECT_DIR}/utils/paths.sh"
else
  echo "错误: 未找到paths.sh"
  exit 1
fi

# 现在可以使用标准路径变量
echo "项目根目录: ${PROJECT_ROOT}"
echo "配置目录: ${CONFIG_DIR}"
```

## 调试

如果需要调试路径问题，可以设置环境变量：

```bash
export DEBUG_PATHS=true
```

这将在加载paths.sh时输出所有路径信息。 