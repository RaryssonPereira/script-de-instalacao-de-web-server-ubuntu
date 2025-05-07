#! /bin/bash

# Caminho onde será salvo o log desse script
LOG_FILE="/var/log/setup_base.log"

# Verifica se esse Script (webserver-setup.sh) já foi executado antes
if [ -f "$LOG_FILE=" ]; then
    echo "Não vamos seguir o script webserver-setup. Já foi executado antes em: $(cat $LOG_FILE). Saindo..."
    exit
fi

# Define o Hostname do Servidor
configure_hostname(){
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
        echo "127.0.1.1 $NEW_HOSTNAME" >> /etc/hosts 
    fi
}

ask_install(){
    # Cria uma variável local chamada package e atribui o valor do primeiro argumento passado para a função ($1).
    local package=$1
    # Cria uma segunda variável local chamada var e atribui o valor do segundo argumento ($2).
    local var=$2

    # Mostra ao usuário a pergunta: "Instalar nginx? (S/N):" e resposta digitada pelo usuário será armazenada na variável answer.
    read -p "Instalar $package? (S/N): " answer
    # Converte a resposta para letra maiúscula, com o comando tr. Isso padroniza a entrada e evita ter que testar s, S, n, N separadamente.
    answer=$(echo "$answer" | tr '[:lower:]' '[:upper:]')
}
