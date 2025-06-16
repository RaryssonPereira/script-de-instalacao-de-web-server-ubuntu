#!/bin/bash
#
# Script para monitorar a carga (load average) do servidor e enviar um
# relatório detalhado por e-mail se o limite for ultrapassado.
#

# --- CONFIGURAÇÃO ---
# EDITAR: E-MAIL DO ADMINISTRADOR QUE RECEBERÁ OS ALERTAS.
ADMIN_EMAIL="seu-email-aqui@exemplo.com"

# --- LÓGICA DO ALERTA ---
# O script irá alertar se a carga do último minuto for o dobro do número de núcleos de CPU.
# Ex: 4 núcleos -> alerta se a carga for >= 8.
# Você pode descomentar a linha abaixo para definir um limite manual.
# ALERTA_MANUAL=10

# --- INÍCIO DO SCRIPT ---

CPU_CORES=$(nproc)
LOAD_ALERT_THRESHOLD=${ALERTA_MANUAL:-$((CPU_CORES * 2))}
CURRENT_LOAD=$(cut -d' ' -f1 < /proc/loadavg | cut -d. -f1)
HOSTNAME=$(hostname)

# Só continua se a carga atual for maior ou igual ao limite.
if [[ "$CURRENT_LOAD" -ge "$LOAD_ALERT_THRESHOLD" ]]; then

    # Coleta todas as informações de diagnóstico e as armazena em uma única variável.
    REPORT_BODY=$(
        # Cabeçalho do relatório
        echo "Carga do servidor $HOSTNAME está alta!"
        echo
        echo "Limite de Alerta: $LOAD_ALERT_THRESHOLD | Carga Atual: $CURRENT_LOAD"
        echo "----------------------------------------------------"

        # Informações gerais de uso
        echo "Uso de CPU: $(vmstat 1 2 | tail -1 | awk '{print 100-$15}')%"
        echo "Uso de RAM: $(free | awk '/Mem/{printf(\"%.2f\"), $3/$2*100}')%"
        echo

        # IPs com mais conexões
        echo "TOP 10 IPs COM MAIS CONEXÕES:"
        netstat -tn 2>/dev/null | grep -v "127.0.0.1" | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -nr | head
        echo

        # Processos que mais consomem recursos
        echo "TOP 10 PROCESSOS POR USO DE MEMÓRIA:"
        ps aux --sort -%mem | head -n11
        echo

        echo "TOP 10 PROCESSOS POR USO DE CPU:"
        ps aux --sort -%cpu | head -n11
        echo
    )

    # Envia o relatório completo por e-mail.
    (
        echo "To: $ADMIN_EMAIL"
        echo "From: Alertas do Servidor <noreply@$HOSTNAME>"
        echo "Subject: [ALERTA] Carga Elevada no Servidor: $HOSTNAME"
        echo
        echo "O seguinte relatório de diagnóstico foi gerado no servidor $HOSTNAME:"
        echo
        echo -e "$REPORT_BODY"
    ) | ssmtp -t

fi

exit 0
