#!/bin/bash

USERNAME=$(whoami | tr '[:upper:]' '[:lower:]')

echo -e "\e[1;33m系统初始化中,请稍等....\033[0m"
bash -c 'ps aux | grep $(whoami) | grep -v "sshd\|bash\|grep" | awk "{print \$2}" | xargs -r kill -9 >/dev/null 2>&1' >/dev/null 2>&1
devil www list | awk 'NF>=2 && $1 ~ /\./ {print $1}' | while read -r domain; do devil www del "$domain"; done
find "$HOME" -mindepth 1 ! -name "domains" ! -name "mail" ! -name "repo" ! -name "backups" -exec rm -rf {} + > /dev/null 2>&1

devil port list | grep -E "^\s*[0-9]+" | while read -r line; do
    port=$(echo "$line" | awk '{print $1}')
    proto=$(echo "$line" | awk '{print $2}')

    if [[ "$proto" != "tcp" && "$proto" != "udp" ]]; then
        continue
    fi

    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        continue
    fi
    devil port del "${proto}" "${port}" > /dev/null 2>&1;
done

port_list=$(devil port list)
tcp_ports=$(echo "$port_list" | grep -c "tcp")
udp_ports=$(echo "$port_list" | grep -c "udp")

if [[ $tcp_ports -lt 1 ]]; then
    while true; do
        tcp_port=$(shuf -i 10000-65535 -n 1)
        result=$(devil port add tcp $tcp_port 2>&1)
        if [[ $result == *"succesfully"* ]]; then
            echo -e "\e[1;32m已添加新的TCP端口: $tcp_port\033[0m\n"
            break
        else
            echo -e "\e[1;33m端口 $tcp_port 不可用，尝试其他端口...\033[0m\n"
        fi
    done
fi

if [[ $udp_ports -lt 2 ]]; then
    udp_ports_to_add=$((2 - udp_ports))
    udp_ports_added=0
    while [[ $udp_ports_added -lt $udp_ports_to_add ]]; do
        udp_port=$(shuf -i 10000-65535 -n 1)
        result=$(devil port add udp $udp_port 2>&1)
        if [[ $result == *"succesfully"* ]]; then
            echo -e "\e[1;32m已添加新的UDP端口: $udp_port\033[0m\n"
            if [[ $udp_ports_added -eq 0 ]]; then
                udp_port1=$udp_port
            else
                udp_port2=$udp_port
            fi
            udp_ports_added=$((udp_ports_added + 1))
        else
            echo -e "\e[1;33m端口 $udp_port 不可用，尝试其他端口...\033[0m\n"
        fi
    done
fi

devil binexec on >/dev/null 2>&1

echo -e "\e[1;32m系统完全初始化完成\033[0m\n"
