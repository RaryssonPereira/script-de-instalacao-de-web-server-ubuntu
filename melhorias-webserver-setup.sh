#! /bin/bash

# Caminho onde será salvo o log desse script
LOG_FILE="/var/log/setup_base.log"

# Verifica se o script já foi executado antes
if [ -f "$LOG_FILE=" ]; then
    echo "Não vamos seguir o script webserver-setup. Já foi executado antes em: $(cat $LOG_FILE). Saindo..."
    exit
fi
