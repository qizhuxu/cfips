# Cloudflare IP优选工具 (CFIPS-Auto)

<div align="center">

[![Docker](https://img.shields.io/badge/Docker-Support-blue)](https://hub.docker.com/r/qiqi8699/cfips-auto)
[![Version](https://img.shields.io/badge/Version-1.0.0-brightgreen)](https://github.com/yourusername/cfips-auto)
[![License](https://img.shields.io/badge/License-MIT-yellow)](LICENSE)

</div>

这是一个自动化工具，用于优选和测速Cloudflare的IP地址，帮助用户获取最佳的Cloudflare节点，以提高网络访问速度和稳定性。通过Docker方式部署，简单易用，支持Web界面触发和定时任务。

## 📋 功能特性

- **📊 多区域IP优选**：按地区（美国、亚洲、欧洲）筛选最佳Cloudflare IP
- **⚡ 高精度测速**：对优选后的IP进行下载速度和延迟测试
- **📤 结果分享**：支持上传结果到Cloudflare KV存储或GitHub Gist
- **📱 消息通知**：支持Telegram和微信企业机器人推送测速结果
- **⏱️ 定时执行**：支持定时自动执行IP优选和测速任务
- **🌐 Web接口**：提供简易的Web接口触发优选和测速功能
- **📝 自定义IP**：支持添加自定义IP进行测试
- **全自动化流程**：一键完成IP优选、测速、结果处理
- **容器化部署**：支持Docker容器化部署，更加便捷
- **定时任务**：支持设置定时执行，保持IP列表的时效性
- **多地区覆盖**：针对亚洲、欧洲、美洲等多个地区进行IP优选
- **测速准确**：使用改进的测速机制，结果更加准确可靠
- **结果推送**：支持Telegram、微信企业机器人等多种推送方式
- **结果上传**：支持上传到 GitHub Gist、Cloudflare KV等
- **IPv6支持**：支持IPv6网络环境，自动检测并优选IPv6地址
- **端口配置**：支持为IP地址指定端口(443、8443、2053等)或随机端口

## 🚀 快速开始

### 系统要求

- Docker 19.03+
- Docker Compose 1.27+

### 使用 Docker Compose (推荐)

1. 安装 [Docker](https://docs.docker.com/get-docker/) 和 [Docker Compose](https://docs.docker.com/compose/install/)

2. 下载本项目，或者直接创建 `docker-compose.yml` 文件：

```yaml
# 使用说明:
# 1. 执行 `docker-compose up -d` 启动服务
# 2. 执行 `docker-compose logs -f` 查看日志
# 3. 结果文件保存在 `./results` 目录中
# 4. 自定义IP文件位于 `./config/custom_ips.txt`
# 5. 如需重新构建镜像以获取最新更新，请取消注释build选项并注释image选项
# 6. 服务将默认以定时任务方式运行，间隔可在config.yml中设置
# 7. 已支持IPv6网络，如不需要可删除networks部分的配置

version: '3'

# 配置网络，启用IPv6支持
networks:
  cfips-network:
    driver: bridge
    enable_ipv6: true
    ipam:
      config:
        - subnet: 172.28.0.0/16
          gateway: 172.28.0.1
        - subnet: 2001:db8::/64
          gateway: 2001:db8::1

services:
  cfips:
    image: qiqi8699/cfips-auto:latest
    container_name: cfips-auto
    ports:
      - "15000:15000"  # IP优选端口
      - "15001:15001"  # 测速端口
    volumes:
      - ./config:/app/config  # 配置文件目录
      - ./results:/app/results  # 结果输出目录
      - ./logs:/app/logs  # 日志目录
    environment:
      - TZ=Asia/Shanghai
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "test", "-f", "/tmp/healthy"]
      interval: 5m
      timeout: 10s
      retries: 3
    # 使用自定义网络以支持IPv6
    networks:
      - cfips-network
```

3. 创建相关目录和配置文件：

```bash
mkdir -p config results logs
```

4. 启动服务：

```bash
docker-compose up -d
```

5. 查看服务日志：

```bash
docker-compose logs -f
```

### IPv6 支持说明

- 默认 docker-compose.yml 已配置支持 IPv6 网络
- 系统会自动检测宿主机的 IPv6 连接性
- 如果检测到可用的 IPv6 网络，将同时测试 IPv4 和 IPv6
- 如果您的宿主机支持 IPv6 但容器无法连接，请检查：
  - Docker daemon 配置是否启用了 IPv6 支持
  - 宿主机防火墙是否允许 IPv6 流量
  - 需确保宿主机本身有可用的 IPv6 连接

如果不需要 IPv6 支持，可以从 docker-compose.yml 文件中移除 networks 相关配置。

#### 一键启用 Docker IPv6 支持

项目提供了一键配置脚本，帮助您在宿主机上快速启用 Docker 的 IPv6 支持：

```bash
# 下载脚本
curl -O https://raw.githubusercontent.com/yourusername/cfips-auto/main/scripts/enable-docker-ipv6.sh

# 添加执行权限
chmod +x enable-docker-ipv6.sh

# 使用sudo运行脚本（需要root权限修改Docker配置）
sudo ./enable-docker-ipv6.sh
```

**重要说明：**
- 此脚本必须在**宿主机系统**上运行，不是在Docker容器内
- 脚本会自动备份现有的Docker配置
- 会自动重启Docker服务以应用更改
- 运行后可能需要重建Docker网络和重启容器

### 非Docker部署

如需在Linux系统上直接部署，请确保系统已安装以下依赖：

- bash
- curl
- awk
- sed
- grep
- jq

克隆仓库后执行：

```bash
chmod +x setup-permissions.sh
./setup-permissions.sh
./start.sh all
```

## 📂 目录结构

- **config/** - 配置文件目录，包含config.yml和自定义IP文件
- **results/** - 优选和测速结果输出目录
- **logs/** - 日志文件目录
- **data/** - 工具和数据文件（容器内部使用，不需要挂载）
- **bin/** - 功能执行脚本目录
- **utils/** - 工具函数脚本目录

## 🎮 使用方法

### Web界面使用

- 访问 `http://[主机IP]:15000` 触发IP优选功能
- 访问 `http://[主机IP]:15001` 触发IP测速功能

### 命令行使用

Docker环境下执行：

```bash
# 执行完整流程（优选+测速+上传+通知）
docker exec -it cfips-auto /app/start.sh all

# 仅执行IP优选
docker exec -it cfips-auto /app/start.sh select

# 仅执行测速
docker exec -it cfips-auto /app/start.sh test

# 设置定时任务（每6小时执行一次）
docker exec -it cfips-auto /app/start.sh schedule -i 360
```

### 自定义IP

1. 编辑 `config/custom_ips.txt` 文件，添加自己收集的优质IP地址，每行一个IP
2. 确保在 `config.yml` 中启用自定义IP库功能：

   ```yaml
   ip_select:
     custom_ips:
       enabled: true
       files:
         - "config/custom_ips.txt"
   ```

## ⚙️ 配置详解

项目的配置文件位于 `config/config.yml`，支持以下主要配置：

### IP优选配置

```yaml
ip_select:
  candidate_num: 20          # 每个地区候选IP数量
  final_num: 6               # 每个地区最终选取的IP数量
  port: 15000                # 优选功能监听端口
  allow_external: true       # 是否允许外部连接
  
  # 自定义IP库配置
  custom_ips:
    enabled: true            # 是否启用自定义IP库
    files:
      - "config/custom_ips.txt"  # 自定义IP文件路径
  
  # IP端口配置
  port_config:
    enabled: true            # 是否在结果中添加端口信息
    default_port: 443        # 默认端口，可选: 443, 8443, 2053, 2083, 2087, 2086
    random_port: false       # 是否使用随机端口(从可选端口中随机选择)
```

### 测速配置

```yaml
speed_test:
  speed_limit: 0             # 下载速度下限(MB/s)，0为不限制
  latency_limit: 500         # 延迟上限(ms)
  test_count: 0              # 测试IP数量(0=测试全部)
  thread_num: 4              # 测速线程数
  test_url: ""               # 自定义测速地址(留空使用默认)
  port: 15001                # 测速功能监听端口
  allow_external: true       # 是否允许外部连接
```

### 结果上传配置

```yaml
upload:
  # Cloudflare KV配置
  cloudflare:
    enabled: true            # 是否启用Cloudflare KV上传
    domain: "example.com"    # Cloudflare KV域名
    token: "your_token"      # Cloudflare KV令牌
  
  # GitHub Gist配置
  github:
    enabled: false           # 是否启用GitHub Gist上传
    token: ""                # GitHub个人访问令牌
    gist_id: ""              # Gist ID (如果已有Gist要更新)
    description: "Cloudflare IP优选测速结果"
```

### 通知推送配置

```yaml
notification:
  # Telegram配置
  telegram:
    enabled: false           # 是否启用Telegram通知
    bot_token: ""            # Telegram机器人Token
    chat_id: ""              # Telegram聊天ID
  
  # 微信企业机器人配置
  wechat:
    enabled: false           # 是否启用微信企业机器人通知
    key: ""                  # 微信企业机器人key
```

### 定时任务配置

```yaml
schedule:
  interval: 360              # 定时执行间隔(分钟)，默认360分钟(6小时)
```

服务默认以定时任务方式运行，无需额外配置。您只需设置执行间隔即可。也可以通过命令行修改：

```bash
# 设置定时任务间隔为2小时
docker exec -it cfips-auto /app/start.sh schedule -i 120
```

## 🔄 最近更新

- **新增端口配置支持**: 可在结果中添加端口信息(443、8443、2053等)，支持随机端口选择
- **IPv6一键配置工具**: 新增脚本自动配置Docker daemon开启IPv6支持
- **新增IPv6支持**: docker-compose.yml 配置已支持 IPv6 网络，可以同时测试 IPv4 和 IPv6
- **配置系统重构**: 移除脚本中的硬编码配置值，完全依赖配置文件，提高一致性和可维护性
- **日志系统优化**: 控制台输出精简为关键信息，详细日志保存到文件，减少日志干扰
- **默认启用定时任务**: 容器启动时自动以定时任务模式运行，无需手动启用
- **健康检查机制**: 添加容器健康检查，避免容器重启循环问题
- **IPv6检测优化**: 增加了更多的IPv6测试地址，提高IPv6网络检测的成功率
- **执行日志优化**: CloudflareST执行时不再记录冗长日志，减少磁盘占用
- **YQ集成**: 添加yq工具到Docker镜像，提高YAML配置文件解析的可靠性
- **简化配置**: 自定义IP文件已从data目录移动到config目录
- **精简挂载**: data目录不再需要挂载到宿主机，简化了部署配置
- **构建选项**: 添加本地构建镜像选项，方便用户获取最新更新

## 📁 输出文件说明

本工具会在 `results` 目录生成以下输出文件：

1. **cfips.csv**: 原始格式的IP优选结果，包含详细测试数据
2. **cfips.txt**: 格式化后的IP优选结果，格式为 `IP:端口#城市`，例如 `198.41.219.14:443#Newark`
3. **result.csv**: 测速的原始结果数据
4. **result_ip.txt**: 格式化后的测速结果，格式为 `IP:端口#城市 | 15Mb/s`，例如 `104.16.106.54:8443#Mumbai | 15Mb/s`

## ❓ 常见问题

### 如何查看优选结果？

优选结果会保存在 `results` 目录中，主要文件包括：
- `cfips.csv` - 优选后的IP详细信息
- `cfips.txt` - 格式化的IP#城市结果
- `result.csv` - 测速后的详细结果
- `result_ip.txt` - 测速后的精简IP结果

### 如何添加自己收集的IP？

将IP地址添加到 `config/custom_ips.txt` 文件中，每行一个IP地址，支持IPv4和IPv6，然后确保在配置文件中启用自定义IP库功能。

### 为什么没有测速结果？

通常是由于网络环境限制或测速条件设置过高导致的。尝试在配置文件中降低 `speed_limit` 或提高 `latency_limit` 值。

### 如何更新配置？

修改 `config/config.yml` 文件后，不需要重启容器，下次执行任务时会自动应用新配置。

## 🔒 隐私与安全

本工具仅测试公开的Cloudflare IP地址，不会收集或上传用户个人信息。上传功能需要用户提供自己的令牌和服务配置。

## 📄 许可证

本项目采用 MIT 许可证 - 详情请参阅 [LICENSE](LICENSE) 文件

## 🤝 贡献

欢迎提交问题报告和改进建议！

---

<div align="center">
<b>Cloudflare IP优选工具</b> - 让你的网络连接更快、更稳定
</div> 
