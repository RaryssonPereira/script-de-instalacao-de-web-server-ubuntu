#!/bin/bash

set -euo pipefail

LOG_FILE="/var/log/setup_base.log"

# Verifica execução prévia
if [ -f "$LOG_FILE" ]; then
    echo "Script já executado em: $(cat $LOG_FILE). Saindo..."
    exit
fi

# Funções
configure_hostname() {
    IP_SERVER=$(curl -s https://api.ipify.org)
    REVERSE_HOSTNAME=$(host "$IP_SERVER" | awk '/pointer/ {print $5}' | sed 's/\.$//')

    echo "Hostname atual: $(hostname)"
    echo "Hostname reverso detectado: $REVERSE_HOSTNAME"
    read -p "Digite o novo hostname (ou N para não alterar): " NEW_HOSTNAME

    if [[ "$NEW_HOSTNAME" != "N" && "$NEW_HOSTNAME" != "n" ]]; then
        hostnamectl set-hostname "$NEW_HOSTNAME"
        echo "127.0.1.1 $NEW_HOSTNAME" >> /etc/hosts
    fi
}

ask_install() {
    local package=$1
    local var=$2
    read -p "Instalar $package? (S/N): " answer
    answer=$(echo "$answer" | tr '[:lower:]' '[:upper:]')
    while [[ "$answer" != "S" && "$answer" != "N" ]]; do
        echo "Resposta inválida. Digite S ou N."
        read -p "Instalar $package? (S/N): " answer
        answer=$(echo "$answer" | tr '[:lower:]' '[:upper:]')
    done
    eval $var="$answer"
}

install_packages() {
    echo "Atualizando pacotes básicos..."
    apt-get update -qq && apt-get install -qq -y software-properties-common debconf-utils htop curl git vim bc ntpdate jq

    # Adiciona repositório com versões recentes do PHP
    add-apt-repository ppa:ondrej/php -y
    apt-get update -qq

    timedatectl set-timezone America/Sao_Paulo
    locale-gen en_US.UTF-8
    update-locale LANG=en_US.UTF-8

    [[ "$INSTALL_NGINX" == "S" ]] && apt-get install -qq -y nginx
    [[ "$INSTALL_PHP" == "S" ]] && apt-get install -qq -y php8.2-fpm php8.2-mysql php8.2-curl php8.2-gd php8.2-mbstring php8.2-redis php8.2-xml php8.2-soap php8.2-zip
    [[ "$INSTALL_MYSQL" == "S" ]] && apt-get install -qq -y mysql-server mysqltuner percona-toolkit mytop
    
# Instala Redis 7.x (repositório oficial Redis Labs)
add-apt-repository ppa:redislabs/redis -y
apt-get update -qq
[[ "$INSTALL_REDIS" == "S" ]] && apt-get install -qq -y redis
    
# Instala Elasticsearch 8.x (versão oficial)
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elastic-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/elastic-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" | tee /etc/apt/sources.list.d/elastic-8.x.list
apt-get update -qq

[[ "$INSTALL_ELASTIC" == "S" ]] && apt-get install -qq -y elasticsearch
    [[ "$INSTALL_FAIL2BAN" == "S" ]] && apt-get install -qq -y fail2ban
}

configure_ssh() {
    echo "Portas comuns: [1] 22 (padrão), [2] 51439 (ServerDo.in), [3] 48291 (personalizada)"
    read -rp "👉 Qual porta deseja usar para o SSH? [1/2/3]: " ssh_option

    # Define a porta de acordo com a escolha do usuário
    case "$ssh_option" in
        1) ssh_port="22" ;;
        2) ssh_port="51439" ;;
        3) ssh_port="48291" ;;
        *) echo "Opção inválida. Usando porta padrão 22."; ssh_port="22" ;;
    esac

    # Substitui ou define a diretiva Port no arquivo de configuração do SSH
    sed -i "s/^#Port .*/Port $ssh_port/" /etc/ssh/sshd_config
    sed -i "s/^Port .*/Port $ssh_port/" /etc/ssh/sshd_config

    # Garante que autenticação por senha está habilitada
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

    echo "🔐 Porta SSH configurada para $ssh_port"

    # Reinicia o serviço SSH para aplicar mudanças
    systemctl restart ssh
}

optimize_sysctl() {
cat <<EOF >> /etc/sysctl.conf
net.ipv4.ip_local_port_range=1025 64000
net.ipv4.tcp_fin_timeout=6
net.ipv4.tcp_max_syn_backlog=65536
net.core.somaxconn=16384
net.ipv6.conf.all.disable_ipv6=1
EOF
sysctl -p
}

install_monitoring() {
    wget https://repo.zabbix.com/zabbix/5.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_5.0-1+focal_all.deb
    dpkg -i zabbix-release_5.0-1+focal_all.deb
    apt update && apt install -y zabbix-agent
    systemctl enable --now zabbix-agent
}

# Execução do script
configure_hostname

ask_install "NGINX" INSTALL_NGINX
ask_install "PHP" INSTALL_PHP
ask_install "MySQL (Percona)" INSTALL_MYSQL
ask_install "Redis" INSTALL_REDIS
ask_install "Elasticsearch" INSTALL_ELASTIC
ask_install "Fail2ban" INSTALL_FAIL2BAN

install_packages
configure_ssh
optimize_sysctl
install_monitoring

# Log de conclusão
mkdir -p $(dirname "$LOG_FILE")
date > "$LOG_FILE"
echo "Instalação e configuração concluídas com sucesso."
