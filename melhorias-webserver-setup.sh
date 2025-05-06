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

    if [[ "$NEW_HOSTNAME" != "N" && "$NEW_HOSTNAME" != "n" ]]; then
        hostnamectl set-hostname "$NEW_HOSTNAME"
        echo "127.0.1.1 $NEW_HOSTNAME" >> /etc/hosts
    fi
}
