#!/bin/bash
#
# Realiza o backup (dump) de todos os bancos de dados do usuário,
# comprime os backups e envia uma notificação por e-mail em caso de falha.
#

# --- CONFIGURAÇÃO ---
# EDITAR: E-MAIL DO ADMINISTRADOR QUE RECEBERÁ OS ALERTAS DE FALHA.
ADMIN_EMAIL="seu-email-aqui@exemplo.com"
# Diretório seguro para armazenar os backups dos bancos de dados.
DIRETORIO_BACKUP="/var/backups/mysql-dumps"

# --- INÍCIO DO SCRIPT ---

HOSTNAME=$(hostname)
DIA=$(date +%A)
ARQUIVO_NOTIFICACAO="/tmp/notificacao_backup_bancos.log"

# Garante que o diretório de backup exista.
mkdir -p "$DIRETORIO_BACKUP"

# Cria um arquivo de notificação limpo com o cabeçalho do e-mail.
echo "Subject: [ALERTA] Falha no Backup de Bancos de Dados no Servidor $HOSTNAME" >"$ARQUIVO_NOTIFICACAO"
echo "Ocorreram os seguintes erros durante a rotina de backup:" >>"$ARQUIVO_NOTIFICACAO"
echo "----------------------------------------------------" >>"$ARQUIVO_NOTIFICACAO"

# Lista todos os bancos de dados, excluindo os schemas padrão do sistema.
# O comando 'mysql' irá ler as credenciais automaticamente de /root/.my.cnf
LISTA_BANCOS=$(mysql -Bse "SHOW DATABASES;" | grep -Ev "^(information_schema|performance_schema|mysql|sys)$")

# Para cada banco de dados na lista, realiza o dump.
for BANCO in $LISTA_BANCOS; do
  echo "Realizando backup do banco de dados: $BANCO..."
  arquivo_backup="$DIRETORIO_BACKUP/${BANCO}-${DIA}.sql"

  # Executa o mysqldump e redireciona a saída de erro para o log em caso de falha.
  if ! mysqldump -R --opt "$BANCO" >"$arquivo_backup" 2>>"$ARQUIVO_NOTIFICACAO"; then
    echo "ERRO: Falha ao executar mysqldump para o banco '$BANCO'." >>"$ARQUIVO_NOTIFICACAO"
    continue # Pula para o próximo banco de dados.
  fi

  # Compacta o arquivo de backup e remove o original.
  gzip -f "$arquivo_backup"
done

# Verifica a integridade dos arquivos de backup que foram criados hoje.
echo "Verificando a integridade dos backups..."
for backup_gz in "$DIRETORIO_BACKUP"/*-"$DIA".sql.gz; do
  # Verifica se o arquivo realmente existe antes de tentar lê-lo.
  if [ -f "$backup_gz" ]; then
    # Verifica se a última linha do arquivo contém a mensagem de sucesso do mysqldump.
    if ! zcat "$backup_gz" | tail -n 1 | grep -q "Dump completed on"; then
      echo "ERRO DE INTEGRIDADE: O backup $(basename "$backup_gz") parece estar corrompido ou incompleto." >>"$ARQUIVO_NOTIFICACAO"
    fi
  fi
done

# Se o arquivo de notificação contiver mais linhas do que o cabeçalho inicial, envia o e-mail.
if [ "$(wc -l <"$ARQUIVO_NOTIFICACAO")" -gt 3 ]; then
  /usr/sbin/ssmtp "$ADMIN_EMAIL" <"$ARQUIVO_NOTIFICACAO"
fi

# Limpa o arquivo de notificação temporário.
rm -f "$ARQUIVO_NOTIFICACAO"

echo "Rotina de backup de bancos de dados concluída."
exit 0
