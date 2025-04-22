# Cloudflare IP Optimization Tool (CFIPS-Auto)

<div align="center">

[![Docker](https://img.shields.io/badge/Docker-Support-blue)](https://hub.docker.com/r/qiqi8699/cfips-auto)
[![Version](https://img.shields.io/badge/Version-1.0.0-brightgreen)](https://github.com/yourusername/cfips-auto)
[![License](https://img.shields.io/badge/License-MIT-yellow)](LICENSE)

</div>

This is an automated tool for optimizing and speed-testing Cloudflare IP addresses, helping users obtain the best Cloudflare nodes to improve network access speed and stability. Deployed via Docker, it's simple to use and supports web interface triggering and scheduled tasks.

## 💡 Sponsorship Statement

This project is powered by the "Free VPS Plan for Open Source Projects" from [VTEXS](https://console.vtexs.com/?affid=1513).
Thank you VTEXS for supporting the open source community!

## 📋 Features

- **📊 Multi-region IP Selection**: Filter the best Cloudflare IPs by region (US, Asia, Europe)
- **⚡ High-precision Speed Testing**: Test download speed and latency of optimized IPs
- **📤 Result Sharing**: Upload results to Cloudflare KV storage or GitHub Gist
- **📱 Notifications**: Support for Telegram and WeChat Enterprise bot result notifications
- **⏱️ Scheduled Execution**: Support for scheduled automatic IP optimization and speed testing
- **🌐 Web Interface**: Simple web interface to trigger optimization and speed testing
- **📝 Custom IPs**: Support for adding custom IPs for testing
- **Fully Automated Process**: One-click IP optimization, speed testing, and result processing
- **Containerized Deployment**: Docker container deployment for convenience
- **Scheduled Tasks**: Support for scheduled execution to maintain IP list timeliness
- **Multi-region Coverage**: IP optimization for multiple regions including Asia, Europe, Americas
- **Accurate Speed Testing**: Improved speed testing mechanism for more reliable results
- **Result Notifications**: Multiple notification methods including Telegram and WeChat Enterprise bots
- **Result Uploading**: Support for uploading to GitHub Gist, Cloudflare KV, etc.
- **IPv6 Support**: Support for IPv6 network environments, automatic detection and optimization
- **Port Configuration**: Support for specifying ports (443, 8443, 2053, etc.) or random ports

## 🚀 Quick Start

### System Requirements

- Docker 19.03+
- Docker Compose 1.27+

### Using Docker Compose (Recommended)

1. Install [Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/install/)

2. Download this project, or directly create a `docker-compose.yml` file:

```yaml
# Usage Instructions:
# 1. Run `docker-compose up -d` to start the service
# 2. Run `docker-compose logs -f` to view logs
# 3. Result files are saved in the `./results` directory
# 4. Custom IP file is located at `./config/custom_ips.txt`
# 5. To rebuild the image for latest updates, uncomment the build option and comment out the image option
# 6. The service will run as a scheduled task by default, with interval configurable in config.yml
# 7. IPv6 network is supported, if not needed you can delete the networks configuration section

version: '3'

# Configure network, enable IPv6 support
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
      - "15000:15000"  # IP optimization port
      - "15001:15001"  # Speed testing port
    volumes:
      - ./config:/app/config  # Configuration directory
      - ./results:/app/results  # Results output directory
      - ./logs:/app/logs  # Logs directory
    environment:
      - TZ=Asia/Shanghai
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "test", "-f", "/tmp/healthy"]
      interval: 5m
      timeout: 10s
      retries: 3
    # Use custom network to support IPv6
    networks:
      - cfips-network
```

3. Create related directories and configuration files:

```bash
mkdir -p config results logs
```

4. Start the service:

```bash
docker-compose up -d
```

5. View service logs:

```bash
docker-compose logs -f
```

### IPv6 Support Information

- The default docker-compose.yml is already configured to support IPv6 networks
- The system will automatically detect the host machine's IPv6 connectivity
- If available IPv6 network is detected, both IPv4 and IPv6 will be tested
- If your host machine supports IPv6 but the container cannot connect, please check:
  - Whether Docker daemon configuration has enabled IPv6 support
  - Whether the host firewall allows IPv6 traffic
  - Ensure the host machine itself has available IPv6 connection

If IPv6 support is not needed, you can remove the networks related configuration from the docker-compose.yml file.

#### One-click Enable Docker IPv6 Support

The project provides a one-click configuration script to help you quickly enable Docker's IPv6 support on the host machine:

```bash
# Download script
curl -O https://raw.githubusercontent.com/yourusername/cfips-auto/main/scripts/enable-docker-ipv6.sh

# Add execution permission
chmod +x enable-docker-ipv6.sh

# Run script with sudo (root permission required to modify Docker configuration)
sudo ./enable-docker-ipv6.sh
```

**Important Notes:**
- This script must be run on the **host system**, not inside the Docker container
- The script will automatically backup existing Docker configuration
- It will automatically restart the Docker service to apply changes
- After running, you may need to rebuild Docker networks and restart containers

### Non-Docker Deployment

For direct deployment on Linux systems, ensure the system has the following dependencies installed:

- bash
- curl
- awk
- sed
- grep
- jq

After cloning the repository, execute:

```bash
chmod +x setup-permissions.sh
./setup-permissions.sh
./start.sh all
```

## 📂 Directory Structure

- **config/** - Configuration directory, contains config.yml and custom IP files
- **results/** - Optimization and speed test results output directory
- **logs/** - Log files directory
- **data/** - Tools and data files (for container internal use, no need to mount)
- **bin/** - Function execution scripts directory
- **utils/** - Utility function scripts directory

## 🎮 Usage

### Web Interface Usage

- Visit `http://[host IP]:15000` to trigger IP optimization function
- Visit `http://[host IP]:15001` to trigger IP speed testing function

### Command Line Usage

Execute in Docker environment:

```bash
# Execute complete process (optimization + speed testing + upload + notification)
docker exec -it cfips-auto /app/start.sh all

# Only execute IP optimization
docker exec -it cfips-auto /app/start.sh select

# Only execute speed testing
docker exec -it cfips-auto /app/start.sh test

# Set scheduled task (execute every 6 hours)
docker exec -it cfips-auto /app/start.sh schedule -i 360
```

### Custom IPs

1. Edit the `config/custom_ips.txt` file, add your collected quality IP addresses, one IP per line
2. Ensure custom IP library function is enabled in `config.yml`:

   ```yaml
   ip_select:
     custom_ips:
       enabled: true
       files:
         - "config/custom_ips.txt"
   ```

## ⚙️ Configuration Details

The project's configuration file is located at `config/config.yml`, supporting the following main configurations:

### IP Optimization Configuration

```yaml
ip_select:
  candidate_num: 20          # Number of candidate IPs per region
  final_num: 6               # Number of final selected IPs per region
  port: 15000                # Optimization function listening port
  allow_external: true       # Whether to allow external connections

  # Custom IP library configuration
  custom_ips:
    enabled: true            # Whether to enable custom IP library
    files:
      - "config/custom_ips.txt"  # Custom IP file path

  # IP port configuration
  port_config:
    enabled: true            # Whether to add port information in results
    default_port: 443        # Default port, options: 443, 8443, 2053, 2083, 2087, 2086
    random_port: false       # Whether to use random port (randomly select from available ports)
```

### Speed Testing Configuration

```yaml
speed_test:
  speed_limit: 0             # Download speed lower limit (MB/s), 0 for no limit
  latency_limit: 500         # Latency upper limit (ms)
  test_count: 0              # Number of IPs to test (0 = test all)
  thread_num: 4              # Speed testing thread count
  test_url: ""               # Custom speed testing URL (leave empty to use default)
  port: 15001                # Speed testing function listening port
  allow_external: true       # Whether to allow external connections
```

### Result Upload Configuration

```yaml
upload:
  # Cloudflare KV configuration
  cloudflare:
    enabled: true            # Whether to enable Cloudflare KV upload
    domain: "example.com"    # Cloudflare KV domain
    token: "your_token"      # Cloudflare KV token

  # GitHub Gist configuration
  github:
    enabled: false           # Whether to enable GitHub Gist upload
    token: ""                # GitHub personal access token
    gist_id: ""              # Gist ID (if updating an existing Gist)
    description: "Cloudflare IP Optimization Speed Test Results"
```

### Notification Configuration

```yaml
notification:
  # Telegram configuration
  telegram:
    enabled: false           # Whether to enable Telegram notification
    bot_token: ""            # Telegram bot token
    chat_id: ""              # Telegram chat ID

  # WeChat Enterprise bot configuration
  wechat:
    enabled: false           # Whether to enable WeChat Enterprise bot notification
    key: ""                  # WeChat Enterprise bot key
```

### Scheduled Task Configuration

```yaml
schedule:
  interval: 360              # Scheduled execution interval (minutes), default 360 minutes (6 hours)
```

The service runs as a scheduled task by default, no additional configuration needed. You only need to set the execution interval. You can also modify it via command line:

```bash
# Set scheduled task interval to 2 hours
docker exec -it cfips-auto /app/start.sh schedule -i 120
```

## 🔄 Recent Updates

- **Added Port Configuration Support**: Can add port information (443, 8443, 2053, etc.) in results, supports random port selection
- **IPv6 One-click Configuration Tool**: Added script to automatically configure Docker daemon to enable IPv6 support
- **Added IPv6 Support**: docker-compose.yml configuration now supports IPv6 networks, can test both IPv4 and IPv6
- **Configuration System Restructuring**: Removed hardcoded configuration values from scripts, fully rely on configuration files, improved consistency and maintainability
- **Log System Optimization**: Console output simplified to key information, detailed logs saved to files, reduced log interference
- **Default Scheduled Task Enabled**: Container automatically runs in scheduled task mode at startup, no need to manually enable
- **Health Check Mechanism**: Added container health check to avoid container restart loop issues
- **IPv6 Detection Optimization**: Added more IPv6 test addresses, improved IPv6 network detection success rate
- **Execution Log Optimization**: CloudflareST execution no longer records verbose logs, reduced disk usage
- **YQ Integration**: Added yq tool to Docker image, improved YAML configuration file parsing reliability
- **Simplified Configuration**: Custom IP files moved from data directory to config directory
- **Streamlined Mounting**: data directory no longer needs to be mounted to host, simplified deployment configuration
- **Build Options**: Added local image build option, convenient for users to get latest updates

## 📁 Output Files Description

This tool generates the following output files in the `results` directory:

1. **cfips.csv**: Original format IP optimization results, including detailed test data
2. **cfips.txt**: Formatted IP optimization results, format is `IP:port#city`, e.g. `198.41.219.14:443#Newark`
3. **result.csv**: Original speed test result data
4. **result_ip.txt**: Formatted speed test results, format is `IP:port#city | 15Mb/s`, e.g. `104.16.106.54:8443#Mumbai | 15Mb/s`

## ❓ FAQ

### How to view optimization results?

Optimization results are saved in the `results` directory, main files include:
- `cfips.csv` - Detailed information of optimized IPs
- `cfips.txt` - Formatted IP#city results
- `result.csv` - Detailed results after speed testing
- `result_ip.txt` - Simplified IP results after speed testing

### How to add my collected IPs?

Add IP addresses to the `config/custom_ips.txt` file, one IP address per line, supports IPv4 and IPv6, then ensure the custom IP library function is enabled in the configuration file.

### Why are there no speed test results?

Usually due to network environment limitations or speed test conditions set too high. Try lowering the `speed_limit` or increasing the `latency_limit` value in the configuration file.

### How to update configuration?

After modifying the `config/config.yml` file, you don't need to restart the container, the new configuration will be automatically applied the next time the task is executed.

## 🔒 Privacy and Security

This tool only tests public Cloudflare IP addresses and does not collect or upload user personal information. The upload function requires users to provide their own tokens and service configuration.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details

## 🤝 Contributions

Welcome to submit issue reports and improvement suggestions!

---

<div align="center">
<b>Cloudflare IP Optimization Tool</b> - Make your network connection faster and more stable
</div>
