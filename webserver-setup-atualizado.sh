ask_install() {
    # Cria uma variável local chamada package e atribui o valor do primeiro argumento passado para a função ($1).
    local package=$1
    # Cria uma segunda variável local chamada var e atribui o valor do segundo argumento ($2).
    local var=$2

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



# === Perguntas de instalação ===
ask_install "Nginx" INSTALL_NGINX

if [[ "$INSTALL_NGINX" == "N" ]]; then
    ask_install "Apache" INSTALL_APACHE
else
    INSTALL_APACHE="N"
fi

ask_install "PHP" INSTALL_PHP
ask_install "MySQL" INSTALL_MYSQL
ask_install "Redis" INSTALL_REDIS
ask_install "Elasticsearch" INSTALL_ELASTIC
ask_install "Fail2Ban" INSTALL_FAIL2BAN

# Executa a instalação com base nas escolhas
install_packages


# === Execução final ===
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

    # Se o usuário escolheu instalar Nginx (INSTALL_NGINX="S"), ele instala silenciosamente e automaticamente o servidor web Nginx.
    [[ "$INSTALL_NGINX" == "S" ]] && apt-get install -qq -y nginx

    # Se o usuário escolheu instalar Apache (INSTALL_APACHE="S"), ele instala silenciosamente e automaticamente o servidor web Apache2.
    [[ "$INSTALL_APACHE" == "S" ]] && apt-get install -qq -y apache2

    # Se o usuário escolheu instalar PhP (INSTALL_PHP="S"), ele instala silenciosamente o PHP 8.2 (FPM), com várias extensões importantes.
    [[ "$INSTALL_PHP" == "S" ]] && apt-get install -qq -y php8.2-fpm php8.2-mysql php8.2-curl php8.2-gd php8.2-mbstring php8.2-redis php8.2-xml php8.2-soap php8.2-zip

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

