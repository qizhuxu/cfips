# 数据文件目录

此目录包含IP优选和测速所需的数据文件。

## 关键文件

- `ips-v4.txt`: IPv4地址库，包含Cloudflare的IPv4地址段
- `ips-v6.txt`: IPv6地址库，包含Cloudflare的IPv6地址段
- `locations.json`: 地理位置库，用于IP的地理位置解析
- `cf`: Cloudflare IP优选工具（用于测试IP连接性和延迟）
- `CloudflareST`: Cloudflare IP测速工具（用于测试IP的下载速度）

**注意**: 自定义IP文件`custom_ips.txt`已移动到`config`目录中。

## 关于可执行文件

项目使用两个主要工具：

1. `cf`: 轻量级IP优选工具，用于测试IP的连接性和延迟。
   - 确保该文件具有执行权限：`chmod +x cf`

2. `CloudflareST`: 专业测速工具，用于测试IP的下载速度和实际性能。
   - 确保该文件具有执行权限：`chmod +x CloudflareST`

## 自定义IP

您可以在`config/custom_ips.txt`文件中添加自己收集的优质IP，每行一个IP地址。系统会在优选过程中将这些IP纳入测试范围。

## 数据更新

定期更新IP库和地理位置库有助于获取更准确的优选结果。我们将在未来添加自动更新数据的功能。 