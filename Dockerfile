FROM alpine:3.16

# 安装基本依赖
RUN apk add --no-cache bash curl wget jq sed grep

# 安装yq用于解析YAML
RUN wget https://github.com/mikefarah/yq/releases/download/v4.30.8/yq_linux_amd64 -O /usr/bin/yq && \
    chmod +x /usr/bin/yq

# 创建工作目录
WORKDIR /app

# 复制项目文件
COPY . .

# 复制配置模板
RUN cp /app/config/config.yml /app/config/config.yml.template

# 设置可执行文件权限
RUN mkdir -p /app/data
# 移动cf（IP优选工具）
RUN if [ -f /app/exec/cf ]; then \
        mv /app/exec/cf /app/data/ && \
        chmod +x /app/data/cf; \
    fi
# 移动CloudflareST（测速工具）
RUN if [ -f /app/exec/CloudflareST ]; then \
        mv /app/exec/CloudflareST /app/data/ && \
        chmod +x /app/data/CloudflareST; \
    fi

# 设置脚本权限
RUN chmod +x /app/bin/*.sh
RUN chmod +x /app/utils/*.sh
RUN chmod +x /app/start.sh
RUN chmod +x /app/docker-entrypoint.sh

# 创建数据卷挂载点
VOLUME ["/app/config", "/app/results", "/app/data"]

# 暴露端口
EXPOSE 15000 15001

# 设置环境变量
ENV TZ=Asia/Shanghai
ENV CONFIG_PATH="/app/config/config.yml"
ENV RESULTS_DIR="/app/results"

# 设置启动命令
ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["all"] 