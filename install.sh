#!/usr/bin/env bash
# 检测区
# -------------------------------------------------------------
# 检查系统
export LANG=en_US.UTF-8

echoContent() {
    case $1 in
    # 红色
    "red")
        ${echoType} "\033[31m${printN}$2 \033[0m"
        ;;
        # 天蓝色
    "skyBlue")
        ${echoType} "\033[1;36m${printN}$2 \033[0m"
        ;;
        # 绿色
    "green")
        ${echoType} "\033[32m${printN}$2 \033[0m"
        ;;
        # 白色
    "white")
        ${echoType} "\033[37m${printN}$2 \033[0m"
        ;;
    "magenta")
        ${echoType} "\033[31m${printN}$2 \033[0m"
        ;;
        # 黄色
    "yellow")
        ${echoType} "\033[33m${printN}$2 \033[0m"
        ;;
    esac
}

# 检查系统
checkSystem() {
    if [[ -n $(find /etc -name "redhat-release") ]] || grep </proc/version -q -i "centos"; then
        mkdir -p /etc/yum.repos.d

        if [[ -f "/etc/centos-release" ]]; then
            centosVersion=$(rpm -q centos-release | awk -F "[-]" '{print $3}' | awk -F "[.]" '{print $1}')

            if [[ -z "${centosVersion}" ]] && grep </etc/centos-release -q -i "release 8"; then
                centosVersion=8
            fi
        fi

        release="centos"
        installType='yum -y install'
        removeType='yum -y remove'
        upgrade="yum update -y --skip-broken"
    elif [[ -f "/etc/issue" ]] && grep </etc/issue -q -i "debian" || [[ -f "/proc/version" ]] && grep </etc/issue -q -i "debian" || [[ -f "/etc/os-release" ]] && grep </etc/os-release -q -i "ID=debian"; then
        release="debian"
        installType='apt -y install'
        upgrade="apt update"
        updateReleaseInfoChange='apt-get --allow-releaseinfo-change update'
        removeType='apt -y autoremove'

    elif [[ -f "/etc/issue" ]] && grep </etc/issue -q -i "ubuntu" || [[ -f "/proc/version" ]] && grep </etc/issue -q -i "ubuntu"; then
        release="ubuntu"
        installType='apt -y install'
        upgrade="apt update"
        updateReleaseInfoChange='apt-get --allow-releaseinfo-change update'
        removeType='apt -y autoremove'
        if grep </etc/issue -q -i "16."; then
            release=
        fi
    elif [[ -f "/etc/issue" ]] && grep </etc/issue -q -i "Alpine" || [[ -f "/proc/version" ]] && grep </proc/version -q -i "Alpine"; then
        release="alpine"
        installType='apk add'
        upgrade="apk update"
        removeType='apt del'
        nginxConfigPath=/etc/nginx/http.d/
    fi

    if [[ -z ${release} ]]; then
        echoContent red "\n本脚本不支持此系统，请将下方日志反馈给开发者\n"
        echoContent yellow "$(cat /etc/issue)"
        echoContent yellow "$(cat /proc/version)"
        exit 0
    fi
}

# 检查CPU提供商
checkCPUVendor() {
    if [[ -n $(which uname) ]]; then
        if [[ "$(uname)" == "Linux" ]]; then
            case "$(uname -m)" in
            'amd64' | 'x86_64')
                xrayCoreCPUVendor="Xray-linux-64"
                ;;
            'armv8' | 'aarch64')
                xrayCoreCPUVendor="Xray-linux-arm64-v8a"
                ;;
            *)
                echo "  不支持此CPU架构--->"
                exit 1
                ;;
            esac
        fi
    else
        echoContent red "  无法识别此CPU架构，默认amd64、x86_64--->"
        xrayCoreCPUVendor="Xray-linux-64"
    fi
}

# 初始化全局变量
initVar() {
    installType='yum -y install'
    removeType='yum -y remove'
    upgrade="yum -y update"
    echoType='echo -e'

    # 核心支持的cpu版本
    xrayCoreCPUVendor=""

    # 域名
    domain=
    # 安装总进度
    totalProgress=1

    # 1.xray-core安装
    coreInstallType=

    # 核心安装path
    ctlPath=
    # 当前的个性化安装方式 01234
    currentInstallProtocolType=

    # v2ray-core、xray-core配置文件的路径
    configPath=

    # xray-core reality状态
    realityStatus=

    # nginx订阅端口
    subscribePort=

    # 配置文件的path
    currentPath=

    # 配置文件的host
    currentHost=

    # 安装时选择的core类型
    selectCoreType=

    # 默认core版本
    v2rayCoreVersion=

    # 随机路径
    customPath=

    # centos version
    centosVersion=

    # UUID
    currentUUID=

    # clients
    currentClients=

    # previousClients
    previousClients=

    localIP=

    # 定时任务执行任务名称 RenewTLS-更新证书 UpdateGeo-更新geo文件
    cronName=$1

    # tls安装失败后尝试的次数
    installTLSCount=

    # BTPanel状态
    btDomain=
    # nginx配置文件路径
    nginxConfigPath=/etc/nginx/conf.d/
    nginxStaticPath=/usr/share/nginx/html/

    # 是否为预览版
    prereleaseStatus=false

    # ssl类型
    sslType=
    # SSL CF API Token
    cfAPIToken=

    # ssl邮箱
    sslEmail=

    # 检查天数
    sslRenewalDays=90

    # dns tls domain
    dnsTLSDomain=
    ipType=

    # 自定义端口
    customPort=

    # 当前Reality私钥
    currentRealityPrivateKey=
}

# 读取tls证书详情
readAcmeTLS() {
    local readAcmeDomain=
    if [[ -n "${currentHost}" ]]; then
        readAcmeDomain="${currentHost}"
    fi

    if [[ -n "${domain}" ]]; then
        readAcmeDomain="${domain}"
    fi

    dnsTLSDomain=$(echo "${readAcmeDomain}" | awk -F "." '{$1="";print $0}' | sed 's/^[[:space:]]*//' | sed 's/ /./g')
    if [[ -d "$HOME/.acme.sh/*.${dnsTLSDomain}_ecc" && -f "$HOME/.acme.sh/*.${dnsTLSDomain}_ecc/*.${dnsTLSDomain}.key" && -f "$HOME/.acme.sh/*.${dnsTLSDomain}_ecc/*.${dnsTLSDomain}.cer" ]]; then
        installedDNSAPIStatus=true
    fi
}

# 读取nginx订阅端口
readNginxSubscribe() {
    subscribeType="https"
    if [[ -f "${nginxConfigPath}subscribe.conf" ]]; then
        subscribePort=$(grep "listen" "${nginxConfigPath}subscribe.conf" | awk '{print $2}')
        subscribeDomain=$(grep "server_name" "${nginxConfigPath}subscribe.conf" | awk '{print $2}')
        subscribeDomain=${subscribeDomain//;/}
        if [[ -n "${currentHost}" && "${subscribeDomain}" != "${currentHost}" ]]; then
            subscribePort=
            subscribeType=
        else
            if ! grep "listen" "${nginxConfigPath}subscribe.conf" | grep -q "ssl"; then
                subscribeType="http"
            fi
        fi
    fi
}

# 检测安装方式
readInstallType() {
    coreInstallType=
    configPath=

    # 1.检测安装目录
    if [[ -d "/etc/v2ray-agent" ]]; then
        if [[ -f "/etc/v2ray-agent/xray/xray" ]]; then
            # 检测xray-core
            if [[ -d "/etc/v2ray-agent/xray/conf" ]] && [[ -f "/etc/v2ray-agent/xray/conf/02_VLESS_TCP_inbounds.json" ]]; then
                # xray-core
                configPath=/etc/v2ray-agent/xray/conf/
                ctlPath=/etc/v2ray-agent/xray
                coreInstallType=2
            fi
        fi
    fi

    # 2.检测xray透明代理
    if [[ -f "/usr/local/bin/xray" ]] && [[ -d "/etc/xray" ]]; then
        if [[ -f "/etc/xray/02_VLESS_TCP_inbounds.json" ]]; then
            configPath=/etc/xray
            coreInstallType=3
            ctlPath=/usr/local/bin
        fi
    fi

    # 3.检测sing-box
    if [[ -f "/usr/local/bin/sing-box" ]]; then
        if [[ -f "/etc/sing-box/config.json" ]]; then
            coreInstallType=4
            ctlPath=/usr/local/bin
            configPath=/etc/sing-box
        fi
    fi

    # 4.检测nginx
    if [[ -f "/usr/sbin/nginx" ]]; then
        if [[ -d "/usr/share/nginx/html" ]]; then
            nginxConfigPath=/etc/nginx/conf.d/
            nginxStaticPath=/usr/share/nginx/html/
        fi
    fi

    # 5.检测hysteria
    if [[ -f "/usr/local/bin/hysteria" ]]; then
        if [[ -f "/etc/hysteria/config.json" ]]; then
            coreInstallType=5
            ctlPath=/usr/local/bin
            configPath=/etc/hysteria
        fi
    fi

    # 6.检测tuic
    if [[ -f "/usr/local/bin/tuic" ]]; then
        if [[ -f "/etc/tuic/config.json" ]]; then
            coreInstallType=6
            ctlPath=/usr/local/bin
            configPath=/etc/tuic
        fi
    fi
}

# 重置变量
resetVar() {
    currentHost=
    currentPath=
    currentInstallProtocolType=
}

# 系统升级
upgradeSystem() {
    echoContent skyBlue "\n进度 $1/${totalProgress} : 系统升级\n"

    if [[ "${release}" == "centos" ]]; then
        ${upgrade}
    else
        if [[ -n "${updateReleaseInfoChange}" ]]; then
            ${updateReleaseInfoChange}
        fi

        ${upgrade}
    fi
}

# 安装基础软件
installBaseSoftware() {
    echoContent skyBlue "\n进度 $1/${totalProgress} : 安装基础软件包\n"
    if [[ "${release}" == "centos" ]]; then
        ${installType} wget curl tar
    else
        ${installType} wget curl gnupg2 tar
    fi
}

# 安装v2ray-core或xray-core
installXray() {
    echoContent skyBlue "\n进度 $1/${totalProgress} : 安装/更新xray-core\n"

    # 1.安装xray-core
    if [[ "${release}" == "centos" ]]; then
        ${installType} lsof
    else
        ${installType} lsof
    fi

    # 清理安装
    rm -rf /etc/systemd/system/xray.service
    rm -rf /usr/local/bin/xray
    rm -rf /etc/xray

    if [[ ! -d "/etc/xray" ]]; then
        mkdir -p /etc/xray
    fi

    # 读取版本
    if [[ -z "${v2rayCoreVersion}" ]]; then
        v2rayCoreVersion=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases | grep tag_name | head -1 | awk -F '[:,"v]' '{print $6}')
    fi

    wget -N --no-check-certificate https://github.com/XTLS/Xray-core/releases/download/v"${v2rayCoreVersion}"/Xray-linux-64.zip

    if [[ -f "Xray-linux-64.zip" ]]; then
        unzip -d Xray Xray-linux-64.zip
        rm -rf Xray-linux-64.zip
        mv -f Xray/* /usr/local/bin
        rm -rf Xray
    else
        echoContent red "  安装失败，请检查下载链接"
        exit 1
    fi

    # 创建 xray 配置文件目录
    mkdir -p /etc/xray

    # 创建 xray systemd 服务
    cat <<EOF >/etc/systemd/system/xray.service
[Unit]
Description=Xray Service
Documentation=https://github.com/XTLS/Xray-core/
After=network.target nss-lookup.target

[Service]
User=nobody
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -confdir /etc/xray
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=4096
LimitNOFILE=1024000
EOF

    # 启动 xray 服务
    systemctl daemon-reload
    systemctl enable xray
    systemctl restart xray
}

# 安装证书
installTLS() {
    if [[ -z "${domain}" ]]; then
        echoContent red "  未配置域名，无法安装TLS证书"
        exit 1
    fi

    if [[ -z "${sslEmail}" ]]; then
        sslEmail="ssl@${domain}"
    fi

    # 安装 acme.sh
    curl https://get.acme.sh | sh

    # 安装TLS证书
    ~/.acme.sh/acme.sh --issue -d "${domain}" --standalone
    ~/.acme.sh/acme.sh --installcert -d "${domain}" --key-file /etc/xray/xray.key --fullchain-file /etc/xray/xray.crt

    # 设置权限
    chmod 644 /etc/xray/xray.key
    chmod 644 /etc/xray/xray.crt
}

# 配置VLESS+TCP+TLS
configVLESS_TCP_TLS() {
    if [[ ! -d "/etc/xray" ]]; then
        echoContent red "  Xray 安装失败，请检查安装日志"
        exit 1
    fi

    # 生成 xray 配置文件
    cat <<EOF >/etc/xray/config.json
{
  "inbounds": [
    {
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${currentUUID}",
            "add": "${domain}"
          }
        ],
        "decryption": "none",
        "fallbacks": [
          {
            "dest": 80
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "/etc/xray/xray.crt",
              "keyFile": "/etc/xray/xray.key"
            }
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF

    # 重启 xray 服务
    systemctl restart xray
}

# 更新订阅链接
update_subscription() {
    echoContent skyBlue "\n进度 $1/${totalProgress} : 更新订阅链接\n"
    read -p "请输入新的订阅链接：" new_subscription_url
    echo "更新订阅链接为：${new_subscription_url}"
    # 在这里添加更新订阅链接的代码
}

# 查看订阅链接
view_subscription() {
    echoContent skyBlue "\n进度 $1/${totalProgress} : 查看订阅链接\n"
    echo "查看订阅链接的网址为：https://www.1373737.xyz/subscription"
}

# 启动API服务
start_api_service() {
    echoContent skyBlue "\n进度 $1/${totalProgress} : 启动API服务\n"
    # 在这里添加启动API服务的代码
}

# 主函数
main() {
    initVar
    checkSystem
    checkCPUVendor
    readInstallType

    upgradeSystem 1
    installBaseSoftware 2
    installXray 3
    installTLS 4
    configVLESS_TCP_TLS 5
    update_subscription 6
    view_subscription 7
    start_api_service 8

    echoContent green "  所有步骤完成!"
}

main
