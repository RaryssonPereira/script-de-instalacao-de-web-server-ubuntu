#!/bin/bash
#
# Script para monitorar o uso de disco e inodes e enviar um alerta por e-mail
# se os limites forem ultrapassados.
#

# --- CONFIGURAÇÃO ---
# EDITAR: E-MAIL DO ADMINISTRADOR QUE RECEBERÁ OS ALERTAS.
ADMIN_EMAIL="seu-email-aqui@exemplo.com"

# Limite de uso em porcentagem (ex: 90 para 90%).
ALERT_THRESHOLD=90

# --- INÍCIO DO SCRIPT ---

# Pega o nome do servidor para usar nos alertas.
HOSTNAME=$(hostname)

# Cria uma variável vazia para armazenar o corpo do e-mail.
# Só enviaremos o e-mail se esta variável tiver conteúdo no final.
REPORT_BODY=""

# 1. Verifica o espaço em disco
# O comando 'df' lista o uso de disco. O 'awk' processa a saída.
# Se o uso ($5) for maior ou igual ao limite (ALERT_THRESHOLD), ele adiciona uma linha ao nosso relatório.
DISK_ALERTS=$(df -h | grep -vE '^Filesystem|tmpfs|cdrom|snap' | awk -v threshold="$ALERT_THRESHOLD" '
{
    usage = $5;
    gsub(/%/, "", usage);
    if (usage >= threshold) {
        printf "ALERTA DE ESPAÇO: A partição %s está com %s de uso.\n", $6, $5;
    }
}')

# Se algum alerta de disco foi encontrado, adiciona ao corpo do relatório.
if [ -n "$DISK_ALERTS" ]; then
    REPORT_BODY+="$DISK_ALERTS\n"
fi


# 2. Verifica o uso de inodes
# Similar ao anterior, mas usa 'df -i' para checar o uso de inodes.
INODE_ALERTS=$(df -i | grep -vE '^Filesystem|tmpfs|cdrom|snap' | awk -v threshold="$ALERT_THRESHOLD" '
{
    usage = $5;
    gsub(/%/, "", usage);
    if (usage >= threshold) {
        printf "ALERTA DE INODES: A partição %s está com %s de inodes em uso.\n", $6, $5;
    }
}')

# Se algum alerta de inode foi encontrado, adiciona ao corpo do relatório.
if [ -n "$INODE_ALERTS" ]; then
    REPORT_BODY+="$INODE_ALERTS\n"
fi


# 3. Verificação específica da pasta /tmp
TMP_USAGE=$(df -h /tmp | awk 'NR==2 {print $5}' | tr -d '%')
if [ "$TMP_USAGE" -ge "$ALERT_THRESHOLD" ]; then
    TMP_ALERT="ALERTA CRÍTICO: A pasta /tmp atingiu $TMP_USAGE% de uso!"
    REPORT_BODY+="$TMP_ALERT\n"
fi


# 4. Envia o e-mail (se houver algo a relatar)
# O script só executa esta parte se a variável REPORT_BODY não estiver vazia.
if [ -n "$REPORT_BODY" ]; then
    # Monta o cabeçalho e o corpo do e-mail e envia usando ssmtp.
    # O comando 'ssmtp -t' lê os destinatários diretamente do cabeçalho do e-mail.
    (
        echo "To: $ADMIN_EMAIL"
        echo "From: Alertas do Servidor <noreply@$HOSTNAME>"
        echo "Subject: [ALERTA] Uso de Disco Elevado no Servidor: $HOSTNAME"
        echo
        echo "O seguinte alerta foi gerado no servidor $HOSTNAME:"
        echo "----------------------------------------------------"
        echo -e "$REPORT_BODY"
        echo "----------------------------------------------------"
        echo "Este é um e-mail automático. Por favor, não responda."
    ) | ssmtp -t
fi

# Fim do script
exit 0
