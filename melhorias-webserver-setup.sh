#! /bin/bash

# Caminho onde será salvo o log desse script
LOG_FILE="/var/log/setup_base.log"

# Verifica se esse Script (webserver-setup.sh) já foi executado antes
if [ -f "$LOG_FILE=" ]; then
    echo "Não vamos seguir o script webserver-setup. Já foi executado antes em: $(cat $LOG_FILE). Saindo..."
    exit
fi

# Define o Hostname do Servidor
configure_hostname() {
    # Consulta o IP público do Servidor usando um serviço externo
    IP_SERVER=$(curl -s https://api.ipify.org) # O -s no curl significa "silent". Ele suprime a barra de progresso e mensagens de erro que normalmente são exibidas no terminal.
    # Faz a consulta reversa do IP para obter o Hostname
    REVERSE_HOSTNAME=$(host "$IP_SERVER" | awk '/pointer/ {print $5}' | sed 's/\.$//')

    echo "Hostname atual: $(hostname)"
    echo "Hostname reverso detectado: $REVERSE_HOSTNAME"
    read -p "Digite o novo hostname (ou N para não alterar): " NEW_HOSTNAME

    # Se o usuário informou um novo hostname (diferente de "N" ou "n")
    if [[ "$NEW_HOSTNAME" != "N" && "$NEW_HOSTNAME" != "n" ]]; then
        # Define o novo hostname com hostnamectl
        hostnamectl set-hostname "$NEW_HOSTNAME"
        # Adiciona uma entrada no /etc/hosts para que o nome seja resolvido localmente
        echo "127.0.1.1 $NEW_HOSTNAME" >>/etc/hosts
    fi
}

ask_install() {
    # Cria uma variável local chamada package e atribui o valor do primeiro argumento passado para a função ($1).
    local package=$1
    # Cria uma segunda variável local chamada var e atribui o valor do segundo argumento ($2).
    local var=$2

    # Se o pacote atual for "apache" e o Nginx já tiver sido selecionado antes, impede a instalação do APACHE para evitar conflito entre servidores web.
    if [[ "$package" == "apache" && "$INSTALL_NGINX" == "S" ]]; then
        echo "Nginx já foi selecionado. Não é possível instalar Apache no mesmo servidor."
        eval $var="N"
        return
    fi

    # Se o pacote atual for "nginx" e o Apache já tiver sido selecionado antes, impede a instalação do NGINX para evitar conflito entre servidores web.
    if [[ "$package" == "nginx" && "$INSTALL_APACHE" == "S" ]]; then
        echo "Apache já foi selecionado. Não é possível instalar Nginx no mesmo servidor."
        eval $var="N"
        return
    fi

    # Mostra ao usuário a pergunta: "Instalar nginx? (S/N):" e resposta digitada pelo usuário será armazenada na variável answer.
    read -p "Instalar $package? (S/N): " answer

    # Converte a resposta para letra maiúscula, com o comando tr. Isso padroniza a entrada e evita ter que testar s, S, n, N separadamente.
    answer=$(echo "$answer" | tr '[:lower:]' '[:upper:]')

    # Inicia um loop de validação: enquanto a resposta for diferente de "S" e de "N", continua repetindo.
    while [[ "$answer" != "S" && "$answer" != "N" ]]; do
        # Mostra um aviso amigável caso o usuário tenha digitado algo errado.
        echo "Resposta inválida. Digite S ou N."
        # Pergunta novamente, usando o mesmo texto da primeira vez.
        read -p "Instalar $package? (S/N): " answer
        # Converte novamente para maiúsculas, repetindo o padrão da primeira pergunta.
        answer=$(echo "$answer" | tr '[:lower:]' '[:upper:]')
        # Finaliza o while. Se a resposta estiver correta ("S" ou "N"), sai do loop.
    done

    # Essa linha é o truque da função: ela usa eval para definir uma variável com nome contido em $var e atribui o valor de answer.
    # Se $var="INSTALL_NGINX" e answer="S", o comando que será executado é: INSTALL_NGINX="S"
    eval $var="$answer"
}

install_packages() {
    echo "Atualizando pacotes básicos..."

    # Atualiza e Instala silenciosamente (-qq) e automaticamente (-y) lista dos pacotes disponíveis no repositório e essenciais para administração básica.
    apt-get update -qq && apt-get install -qq -y software-properties-common debconf-utils htop curl git vim bc ntpdate jq byobu net-tools wget whois dnsutils speedtest-cli traceroute

    # Adiciona automaticamente (-y) o repositório de pacotes mantido por Ondrej Sury, que contém versões mais recentes e atualizadas do PHP.
    add-apt-repository ppa:ondrej/php -y
    apt-get update -qq

    # Ajusta o fuso horário para São Paulo (GMT-3).
    timedatectl set-timezone America/Sao_Paulo

    # Gera o locale (formatação de idioma e caracteres) americano em UTF-8.
    locale-gen en_US.UTF-8

    # Define como padrão o locale gerado.
    update-locale LANG=en_US.UTF-8

    # Se o usuário escolheu instalar Nginx (INSTALL_NGINX="S"), ele instala silenciosamente a versão estável e segura do repositório oficial do nginx.org
    if [[ "$INSTALL_NGINX" == "S" ]]; then
        echo "Instalando Nginx a partir do repositório oficial (nginx.org)..."

        # Adiciona a chave pública do repositório oficial do Nginx
        curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg

        # Adiciona o repositório oficial do Nginx para Ubuntu 22.04 (Jammy)
        echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/ubuntu $(lsb_release -cs) nginx" |
            tee /etc/apt/sources.list.d/nginx.list >/dev/null

        # Atualiza os pacotes e instala o Nginx
        apt-get update -qq
        apt-get install -qq -y nginx
    fi

    # Se o usuário escolheu instalar Apache (INSTALL_APACHE="S"), instala a versão mais recente e estável via PPA oficial mantido por Ondřej Surý.
    if [[ "$INSTALL_APACHE" == "S" ]]; then
        echo "Instalando Apache a partir do PPA oficial (ondrej/apache2)..."

        # Instala o pacote 'software-properties-common', que contém o utilitário 'add-apt-repository' necessário para adicionar PPAs
        apt-get install -qq -y software-properties-common

        # Adiciona o repositório PPA do Ondřej Surý, que mantém versões recentes e seguras do Apache para Ubuntu
        add-apt-repository -y ppa:ondrej/apache2

        # Atualiza a lista de pacotes após adicionar o novo repositório
        apt-get update -qq

        # Instala o Apache a partir do repositório recém-adicionado
        apt-get install -qq -y apache2
    fi

    # Se o usuário escolheu instalar PhP (INSTALL_PHP="S"), ele instala silenciosamente o PHP 8.2 (FPM), com várias extensões importantes.
    [[ "$INSTALL_PHP" == "S" ]] && apt-get install -qq -y php8.2-fpm php8.2-mysql php8.2-curl php8.2-gd php8.2-mbstring php8.2-redis php8.2-xml php8.2-soap php8.2-zip

    sudo apt-get install -qq -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" php8.2-cli php8.2-common
    sudo apt-get install -qq -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" php8.2-fpm php8.2-cgi
    sudo apt-get install -qq -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" php8.2-mysql php8.2-bcmath php8.2-curl php8.2-gd php8.2-mbstring php8.2-redis php8.2-xml php8.2-soap php8.2-zip

    sed -i -r "s/^.emergency_restart_threshold.*$/emergency_restart_threshold = 10/" /etc/php/8.2/fpm/php-fpm.conf
    sed -i -r "s/^.emergency_restart_interval.*$/emergency_restart_interval = 1m/" /etc/php/8.2/fpm/php-fpm.conf
    sed -i -r "s/^.process_control_timeout.*$/process_control_timeout = 10s/" /etc/php/8.2/fpm/php-fpm.conf

    sed -i -r "s/^pm.max_children.*$/pm.max_children = 180/" /etc/php/8.2/fpm/pool.d/www.conf
    sed -i -r "s/^pm.start_servers.*$/pm.start_servers = 25/" /etc/php/8.2/fpm/pool.d/www.conf
    sed -i -r "s/^pm.min_spare_servers.*$/pm.min_spare_servers = 10/" /etc/php/8.2/fpm/pool.d/www.conf
    sed -i -r "s/^pm.max_spare_servers.*$/pm.max_spare_servers = 30/" /etc/php/8.2/fpm/pool.d/www.conf
    sed -i -r "s/^.request_terminate_timeout.*$/request_terminate_timeout = 60s/" /etc/php/8.2/fpm/pool.d/www.conf
    sed -i '/listen = \/run/c\listen = 127.0.0.1:9000' /etc/php/8.2/fpm/pool.d/www.conf
    sed -i 's/disable_functions =/disable_functions = show_source, system, shell_exec, passthru, exec, phpinfo, popen, proc_open, allow_url_fopen, symlink/g' /etc/php/8.2/fpm/php.ini
    sed -i -r "s/^;session.save_path.*$/session.save_path=\/tmp/" /etc/php/8.2/fpm/php.ini
    sed -i -r "s/^session.gc_maxlifetime.*$/session.gc_maxlifetime = 28800/" /etc/php/8.2/fpm/php.ini
    sed -i -r "s/^session.name.*$/session.name = serverdoID/" /etc/php/8.2/fpm/php.ini



    # Se o usuário escolheu instalar MySQL (INSTALL_MYSQL="S"), ele instala silenciosamente o MySQL e ferramentas essenciais.
    [[ "$INSTALL_MYSQL" == "S" ]] && apt-get install -qq -y mysql-server mysqltuner percona-toolkit mytop

    # Se o usuário escolheu instalar Redis (INSTALL_REDIS="S"), ele:
    # - Adiciona o repositório oficial da Redis Labs para ter versões recentes do Redis.
    # - Instala Redis 7.x (repositório oficial Redis Labs).
    if [[ "$INSTALL_REDIS" == "S" ]]; then
        add-apt-repository ppa:redislabs/redis -y
        apt-get update -qq
        apt-get install -qq -y redis
    fi

    # Se o usuário escolheu instalar Elastic (INSTALL_ELASTIC="S"), ele:
    # - Baixa a chave GPG do Elasticsearch para garantir a segurança e autenticidade dos pacotes.
    # - Adiciona o repositório oficial do Elasticsearch 8.x ao sistema.
    # - Instala Elasticsearch 8.x (versão oficial).
    if [[ "$INSTALL_ELASTIC" == "S" ]]; then
        wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elastic-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/elastic-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" | tee /etc/apt/sources.list.d/elastic-8.x.list
        apt-get update -qq
        apt-get install -qq -y elasticsearch
    fi

    # Se o usuário escolheu instalar Fail2Ban (INSTALL_FAIL2BAN="S"), ele instala silenciosamente o Fail2Ban, ferramenta que protege o servidor contra ataques automatizados por força bruta bloqueando IPs após tentativas excessivas.
    [[ "$INSTALL_FAIL2BAN" == "S" ]] && apt-get install -qq -y fail2ban
}

# TENHO ANALISAR O CÓDIGO ABAIXO AINDA

configure_ssh() {
    echo "Portas comuns: [1] 22 (padrão), [2] 51439 (ServerDo.in), [3] 48291 (personalizada)"
    read -rp "👉 Qual porta deseja usar para o SSH? [1/2/3]: " ssh_option

    # Define a porta de acordo com a escolha do usuário
    case "$ssh_option" in
    1) ssh_port="22" ;;
    2) ssh_port="51439" ;;
    3) ssh_port="48291" ;;
    *)
        echo "Opção inválida. Usando porta padrão 22."
        ssh_port="22"
        ;;
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
    cat <<EOF >>/etc/sysctl.conf
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
ask_install "APACHE" INSTALL_APACHE
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
date >"$LOG_FILE"
echo "Instalação e configuração concluídas com sucesso."
