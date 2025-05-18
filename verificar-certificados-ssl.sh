#!/bin/bash

# === SCRIPT: VERIFICAR-CERTIFICADOS-SSL ===
# Esse script verifica se os certificados SSL dos domínios configurados no Nginx estão prestes a expirar.
# Ele se conecta via HTTPS usando openssl, extrai a data de expiração dos certificados e mostra alertas
# para domínios que vencerão em até 10 dias, ordenados dos que estão mais próximos do vencimento.

# Lista todos os arquivos .conf dentro do diretório de sites habilitados no Nginx
# Remove a extensão .conf de cada nome de arquivo (presumindo que o nome do arquivo seja o domínio)
# Ignora arquivos chamados "default" (configuração genérica do Nginx)
# Salva essa lista de domínios em um arquivo temporário
ls /etc/nginx/sites-enabled/ | sed "s/.conf//g" | grep -v default > /tmp/lista_dominios-ssl

# Define a variável com o caminho do arquivo gerado contendo a lista de domínios
domain_file="/tmp/lista_dominios-ssl"

# Define a função que verifica a expiração do certificado de um domínio
check_certificate_expiration() {
    domain=$1  # Primeiro argumento passado para a função: o domínio a ser verificado

    # Usa openssl para se conectar ao domínio na porta 443 (HTTPS)
    # e extrai a data de expiração do certificado com o comando x509
    expiration_date=$(echo | openssl s_client -servername "$domain" -connect "$domain":443 2>/dev/null \
        | openssl x509 -noout -enddate 2>/dev/null | awk -F "=" '{print $2}')

    # Se a data de expiração for encontrada com sucesso
    if [ "$expiration_date" != "" ]; then
        # Converte a data de expiração para timestamp (segundos desde 1970)
        expiration_epoch=$(date -d "$expiration_date" +%s)

        # Captura o timestamp atual
        current_epoch=$(date +%s)

        # Calcula quantos dias faltam até o vencimento (diferença de segundos dividida por 86400)
        remaining_days=$(( ($expiration_epoch - $current_epoch) / 86400 ))

        # Se o certificado vence em até 10 dias (mas ainda não venceu), exibe os dados
        if (( remaining_days <= 10 && remaining_days >= 0 )); then
            # Imprime os dados em formato de tabela simples (separados por "|") para futura ordenação
            echo "$remaining_days|$domain|$expiration_date"
        fi
    fi
}

# Para cada domínio listado no arquivo temporário
while read -r domain; do
    # Chama a função para verificar o certificado daquele domínio
    check_certificate_expiration "$domain"
done < "$domain_file" \
# Ordena a saída anterior por número de dias restantes (do menor para o maior)
| sort -n -t"|" -k1 \
# Quebra cada linha de resultado em três campos: dias|domínio|data, e imprime formatado
| while IFS="|" read -r days domain date; do
    echo "Domínio: $domain"
    echo "Data de expiração: $date"
    echo "Dias restantes: $days"
    echo "----------------------------------------"
done

# === MELHORIAS FUTURAS SUGERIDAS ===
# - Ignorar domínios que não respondem na porta 443 para evitar lentidão ou travamentos
# - Enviar alertas automáticos por e-mail, Telegram ou Slack quando certificados estiverem perto do vencimento
# - Registrar logs com data/hora das verificações e domínios com erro ou sucesso
# - Verificar subdomínios comuns (ex: www.dominio.com) mesmo que não estejam nos arquivos .conf
# - Validar se o domínio resolve corretamente (tem IP público) antes de tentar a conexão