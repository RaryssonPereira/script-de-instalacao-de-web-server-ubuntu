#!/usr/bin/env bash

#######################################################################
# SCRIPT DE SETUP BÁSICO DE SERVIDOR
#
# Autor: Rarysson Pereira
# Data: 14/06/2025
# Versão: 4.0
#
# Descrição:
# Prepara um novo servidor Ubuntu para hospedagem.
# - Parte 1: Verificações iniciais, funções e correções de ambiente.
# - Parte 2: Configuração do hostname.
# - Parte 3: Menu interativo para seleção de pacotes.
# - Parte 4: Resumo e confirmação final.
# - Parte 5: Atualização do sistema e ferramentas base.
# - Parte 6: Configuração do retransmissor de e-mail (SMTP).
# - Parte 7: Criação de um script de backup de configurações (padrão).
#
#######################################################################

# --- Constantes e Variáveis Globais ---
# Usar 'readonly' torna a variável imutável, evitando alterações acidentais.
# Arquivo usado como "trava" para impedir que o script seja executado mais de uma vez.
readonly LOG_FILE="/var/log/setup_base.log"
# Nome do script, usado como um rótulo nas mensagens de log para fácil identificação.
readonly SCRIPT_NAME="webserver-setup"

#######################################################################
# PARTE 1: VERIFICAÇÕES E FUNÇÕES DE LOG
#######################################################################

# Função para registrar mensagens de log e exibi-las no console.
log() {
  echo "[$(date +'%b %d %H:%M:%S')] ${SCRIPT_NAME}: $1"
}

# Função para encerrar o script com uma mensagem de erro.
die() {
  log "ERRO: $1"
  exit 1
}

# Garante que o script não foi executado antes.
if [ -f "$LOG_FILE" ]; then
  # Exibe a data da execução anterior, lendo o conteúdo do arquivo de log.
  log "Script já executado em: $(cat "$LOG_FILE"). Saindo..."
  exit 0
fi

# Verifica se o script está sendo executado como root.
# Comandos de configuração do sistema exigem privilégios de superusuário.
if [[ $EUID -ne 0 ]]; then
  die "Este script precisa ser executado como root ou com sudo."
fi

# --- INÍCIO DA SEÇÃO OPCIONAL: CORREÇÕES CLOUD-INIT ---
# O trecho abaixo é útil em provedores de nuvem (AWS, DigitalOcean, Google Cloud, etc.)
# que usam 'cloud-init' para configurar o servidor.
#
# QUANDO DESCOMENTAR?
# - Se você notar que o HOSTNAME do servidor é revertido para o original após uma reinicialização.
# - Se encontrar problemas de permissão com o comando 'sudo'.
#
# Em ambientes que não usam cloud-init (como virtualizadores locais), estas linhas não são necessárias.

# #Aplica correções para ambientes específicos com cloud-init (OPCIONAL).
# log "Verificando configurações de cloud-init..."
#
# # Remove o arquivo de configuração de sudo do cloud-init que pode causar problemas.
# if [ -f /etc/sudoers.d/90-cloud-init-users ]; then
#     rm -f /etc/sudoers.d/90-cloud-init-users
# fi
#
# # Impede que o cloud-init altere o hostname definido por este script ao reiniciar o servidor.
# echo 'preserve_hostname: true' >/etc/cloud/cloud.cfg.d/98_preserve_hostname.cfg
# --- FIM DA SEÇÃO OPCIONAL ---

# Se chegou até aqui, as verificações passaram e o script pode continuar.
log "Verificações iniciais concluídas com sucesso. Iniciando o setup..."

#######################################################################
# PARTE 2: CONFIGURAÇÃO DO HOSTNAME
#######################################################################

configure_hostname() {
  # Exibe a mensagem de início da função.
  log "Iniciando a configuração do hostname..."

  # Declara uma variável local para o IP do servidor.
  local IP_SERVER
  # Obtém o IP público com um timeout de 5 segundos.
  IP_SERVER=$(curl -s --max-time 5 https://api.ipify.org)

  # Exibe o nome atual do servidor.
  log "Hostname atual: $(hostname)"

  # Se a obtenção do IP foi bem-sucedida...
  if [[ -n "$IP_SERVER" ]]; then
    # Declara uma variável local para o hostname reverso.
    local REVERSE_HOSTNAME
    # Tenta descobrir o nome DNS associado ao IP.
    REVERSE_HOSTNAME=$(host "$IP_SERVER" | awk '/pointer/ {print $5}' | sed 's/\.$//')
    # Se um nome reverso foi encontrado...
    if [[ -n "$REVERSE_HOSTNAME" ]]; then
      # Exibe o nome reverso encontrado.
      log "Hostname reverso detectado: $REVERSE_HOSTNAME"
    # Se nenhum nome reverso foi encontrado...
    else
      # Informa que a busca não teve resultados.
      log "Nenhum hostname reverso encontrado para o IP $IP_SERVER."
    fi
  fi

  # Pausa o script e pede ao usuário para digitar o novo hostname.
  read -p ">> Digite o novo hostname (ou pressione Enter para manter o atual): " NEW_HOSTNAME

  # Se o usuário digitou algum nome...
  if [[ -n "$NEW_HOSTNAME" ]]; then
    # Valida se o nome digitado contém apenas caracteres permitidos.
    if ! [[ "$NEW_HOSTNAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
      # Se for inválido, encerra o script com uma mensagem de erro.
      die "Hostname '$NEW_HOSTNAME' é inválido. Use apenas letras, números e hífens."
    fi

    # Informa que o hostname será alterado.
    log "Alterando hostname para '$NEW_HOSTNAME'..."
    # Altera efetivamente o nome do servidor no sistema.
    hostnamectl set-hostname "$NEW_HOSTNAME"

    # Informa que o arquivo /etc/hosts será atualizado.
    log "Atualizando /etc/hosts para garantir a resolução local..."
    # Remove a linha de configuração antiga do IP 127.0.1.1.
    sed -i.bak '/^127\.0\.1\.1\s/d' /etc/hosts
    # Adiciona a nova linha, associando o IP local ao novo hostname.
    echo -e "127.0.1.1\t$NEW_HOSTNAME" >>/etc/hosts

    # Informa que a alteração foi bem-sucedida e mostra o novo nome.
    log "Hostname alterado com sucesso para: $(hostname)"
  # Se o usuário não digitou nada...
  else
    # Informa que o nome atual será mantido.
    log "Nenhum hostname inserido. Mantendo o nome atual: $(hostname)."
  fi
}

#######################################################################
# PARTE 3: SELEÇÃO DE PACOTES
#######################################################################

ask_install() {
  # Captura os argumentos da função: $1 é o nome do pacote, $2 é o nome da variável de controle.
  local package=$1
  local var_name=$2

  # Trava para impedir a instalação de outros pacotes (exceto fail2ban) se Elasticsearch já foi selecionado.
  if [[ "$INSTALL_ELASTICSEARCH" == "S" && "$package" != "fail2ban" && "$package" != "elasticsearch" ]]; then
    log "AVISO: Elasticsearch já foi selecionado. Apenas Fail2Ban pode ser instalado em conjunto."
    printf -v "$var_name" "N"
    return
  fi

  # Lógica de conflito para impedir que Nginx e Apache sejam instalados juntos.
  if [[ "$package" == "apache" && "$INSTALL_NGINX" == "S" ]]; then
    log "AVISO: Nginx já foi selecionado. Não é possível instalar o Apache."
    printf -v "$var_name" "N"
    return
  fi
  if [[ "$package" == "nginx" && "$INSTALL_APACHE" == "S" ]]; then
    log "AVISO: Apache já foi selecionado. Não é possível instalar o Nginx."
    printf -v "$var_name" "N"
    return
  fi

  # Exibe um aviso especial antes de perguntar sobre a instalação do Elasticsearch.
  if [[ "$package" == "elasticsearch" ]]; then
    echo # Linha em branco para espaçamento visual.
    log "--------------------------------------------------------------------"
    log "ATENÇÃO: Elasticsearch é recomendado para um servidor dedicado."
    log "Ao confirmar, as outras instalações (Nginx, Apache, MySQL, PHP, Redis) serão desativadas."
    log "Apenas o Fail2Ban poderá ser instalado em conjunto."
    log "--------------------------------------------------------------------"
  fi

  # Pede a confirmação do usuário e armazena a resposta.
  local answer
  read -p "Deseja instalar $package? (S/N): " answer
  # Converte a resposta para maiúscula para padronizar a verificação.
  answer=${answer^^}

  # Laço que repete a pergunta até que o usuário digite 'S' ou 'N'.
  while [[ "$answer" != "S" && "$answer" != "N" ]]; do
    echo "Resposta inválida. Por favor, digite S ou N."
    read -p "Deseja instalar $package? (S/N): " answer
    answer=${answer^^}
  done

  # Se Elasticsearch for confirmado, força a desativação dos outros serviços conflitantes.
  if [[ "$package" == "elasticsearch" && "$answer" == "S" ]]; then
    log "Confirmada a instalação do Elasticsearch. Desativando outros serviços..."
    INSTALL_NGINX="N"
    INSTALL_APACHE="N"
    INSTALL_MYSQL="N"
    INSTALL_PHP="N"
    INSTALL_REDIS="N"
  fi

  # Atribui a resposta ('S' ou 'N') à variável de controle global (ex: INSTALL_NGINX="S").
  printf -v "$var_name" "$answer"

  # Se a instalação foi confirmada, exibe uma mensagem de log.
  if [[ "$answer" == "S" ]]; then
    log "$package foi selecionado para instalação."
  fi
}

#######################################################################
# PARTE 4: RESUMO E CONFIRMAÇÃO FINAL
#######################################################################

confirm_selections() {
  # Exibe um resumo de todas as opções selecionadas pelo usuário.
  echo # Linha em branco para espaçamento.
  log "--------------------- RESUMO DAS OPÇÕES ---------------------"
  log "Por favor, confirme as seleções abaixo:"
  echo
  echo "  - Novo Hostname: $(hostname)"
  echo "  - Instalar Nginx: $INSTALL_NGINX"
  echo "  - Instalar Apache: $INSTALL_APACHE"
  echo "  - Instalar MySQL: $INSTALL_MYSQL"
  echo "  - Instalar PHP: $INSTALL_PHP"
  echo "  - Instalar Redis: $INSTALL_REDIS"
  echo "  - Instalar SSMTP (Email Relay): $INSTALL_SSMTP"
  echo "  - Instalar Fail2Ban: $INSTALL_FAIL2BAN"
  echo "  - Instalar Elasticsearch: $INSTALL_ELASTICSEARCH"
  echo

  # Pede uma confirmação final antes de prosseguir.
  local confirmation
  read -p "Deseja prosseguir com a instalação usando essas configurações? (S/N): " confirmation
  confirmation=${confirmation^^}

  # Garante que a resposta seja 'S' ou 'N'.
  while [[ "$confirmation" != "S" && "$confirmation" != "N" ]]; do
    echo "Resposta inválida. Por favor, digite S ou N."
    read -p "Deseja prosseguir? (S/N): " confirmation
    confirmation=${confirmation^^}
  done

  # Retorna um código de status para o laço principal: 0 para 'S' (sucesso) e 1 para 'N' (refazer).
  if [[ "$confirmation" == "S" ]]; then
    return 0
  else
    return 1
  fi
}

#######################################################################
# PARTE 5: ATUALIZAÇÃO DO SISTEMA E FERRAMENTAS BASE
#######################################################################

install_base_system() {
  # --- Preparação do Ambiente ---
  log "Configurando ambiente para instalação não-interativa..."
  # Impede que os pacotes façam perguntas durante a instalação.
  export DEBIAN_FRONTEND=noninteractive
  # Define que os serviços devem ser reiniciados automaticamente após atualizações, sem perguntar.
  export NEEDRESTART_MODE=a
  # Garante que o padrão de caracteres do sistema seja UTF-8 para evitar problemas com acentuação.
  echo 'CONTENT_TYPE="text/plain; charset=utf-8"' >>/etc/environment

  # --- Pré-configuração de Pacotes Específicos ---
  log "Pré-configurando respostas para pacotes interativos..."
  # Responde 'sim' automaticamente à pergunta do iptables-persistent sobre salvar regras de firewall.
  echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections
  echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections

  # --- Instalação de Pacotes ---
  log "Atualizando a lista de pacotes do sistema..."
  # Baixa a lista de pacotes mais recente dos repositórios do Ubuntu.
  apt-get update -qq

  log "Instalando pacotes essenciais e ferramentas de administração..."
  # Instala uma lista completa de ferramentas úteis de forma silenciosa, resiliente e automática.
  apt-get install -qq -y --ignore-missing \
    -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
    software-properties-common debconf-utils htop curl git vim bc ntpdate \
    jq byobu net-tools wget whois dnsutils speedtest-cli traceroute \
    build-essential unzip ufw ncdu rsync iotop mlocate lsof iptables-persistent

  # --- Repositórios Externos ---
  log "Adicionando repositório PPA para o PHP (Ondřej Surý)..."
  # Adiciona um repositório de terceiros confiável para ter acesso a versões mais recentes do PHP.
  add-apt-repository ppa:ondrej/php -y
  # Atualiza a lista de pacotes novamente para incluir os pacotes do novo repositório.
  apt-get update -qq

  # --- Configuração de Localidade e Fuso Horário ---
  log "Ajustando fuso horário para America/Sao_Paulo e localidade para en_US.UTF-8..."
  # Define o fuso horário diretamente no arquivo de configuração do sistema.
  echo "America/Sao_Paulo" >/etc/timezone
  # Força as variáveis de ambiente de localidade para o padrão americano com UTF-8.
  echo 'LC_ALL=en_US.UTF-8' >/etc/default/locale
  echo 'LANG=en_US.UTF-8' >>/etc/default/locale
  # Descomenta a linha da localidade 'en_US.UTF-8' no arquivo de geração.
  sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
  # Gera os arquivos de sistema para a localidade recém-ativada.
  locale-gen
  # Reconfigura o pacote de dados de fuso horário para aplicar as mudanças.
  dpkg-reconfigure --frontend noninteractive tzdata
  # Usa o comando moderno para garantir que a mudança de fuso horário seja aplicada.
  timedatectl set-timezone America/Sao_Paulo
}

#######################################################################
# PARTE 6: INSTALAÇÃO DO RETRANSMISSOR DE E-MAIL (SSMTP)
#######################################################################

install_ssmtp() {
  log "Instalando o retransmissor de e-mail SSMTP..."
  apt-get install -qq -y ssmtp

  # Cria o arquivo de configuração do SSMTP como um template seguro.
  # O usuário precisará editar este arquivo com suas credenciais.
  cat >/etc/ssmtp/ssmtp.conf <<EOF
#
# Arquivo de configuração para o sSMTP.
# Edite os campos abaixo com as informações do seu provedor de e-mail.
#

# O e-mail que receberá as mensagens do sistema (alertas, cron, etc.).
root=seu-email-de-destino@exemplo.com

# O servidor SMTP do seu provedor de e-mail (ex: smtp.gmail.com:587).
mailhub=smtp.seu-provedor.com:587

# O hostname do servidor.
hostname=$(hostname)

# Usuário e senha para autenticação no servidor SMTP.
AuthUser=seu-email-de-envio@exemplo.com
AuthPass=sua-senha-aqui

# Usar STARTTLS para segurança (recomendado).
UseSTARTTLS=YES

# Permite que aplicações definam o endereço 'De' (From).
FromLineOverride=YES
EOF

  # Ajusta as permissões do arquivo para proteger as credenciais.
  chmod 640 /etc/ssmtp/ssmtp.conf
  chown root:mail /etc/ssmtp/ssmtp.conf

  log "------------------------- AÇÃO NECESSÁRIA -------------------------"
  log "O SSMTP foi instalado, mas precisa ser configurado manualmente."
  log "Edite o arquivo /etc/ssmtp/ssmtp.conf com suas credenciais de e-mail."
  log "-------------------------------------------------------------------"
}

#######################################################################
# PARTE 7: CRIAÇÃO DO SCRIPT DE BACKUP DE CONFIGURAÇÕES
#######################################################################
setup_config_backup_script() {
  # Exibe a mensagem de início da função.
  log "Configurando o script de backup de configurações..."

  # Define o diretório seguro onde os backups serão armazenados.
  local backup_dir="/var/backups/config"
  # Garante que o diretório de backup exista.
  mkdir -p "$backup_dir"

  # Define o caminho padrão do Linux para scripts customizados pelo administrador.
  local script_path="/usr/local/bin/backup_configs.sh"

  # Usa um "here document" (cat << EOF) para escrever um bloco de texto no novo script de backup.
  cat >"$script_path" <<EOF
#!/bin/bash
# Script de backup de configurações gerado por webserver-setup.

# Define o dia da semana (ex: Segunda-feira) para rotação de 7 dias. O '\$' impede a expansão imediata.
DIA=\$(date +%A)
# Define o diretório de backup dentro do script gerado.
BACKUP_DIR="$backup_dir"

# Garante que o diretório de backup exista sempre que o script for executado.
mkdir -p "\$BACKUP_DIR"

# Exibe uma mensagem de log no início da execução do backup.
echo "Iniciando backup de configurações para o dia: \$DIA..."

EOF

  # Adiciona comandos de backup ao novo script, apenas se o serviço correspondente foi selecionado.
  if [[ "$INSTALL_NGINX" == "S" ]]; then
    # Adiciona uma linha ao script que só executa o 'tar' se o diretório /etc/nginx existir.
    echo '[[ -d /etc/nginx ]] && tar -pczf "\$BACKUP_DIR/nginx-\$DIA.tar.gz" /etc/nginx' >>"$script_path"
  fi
  if [[ "$INSTALL_APACHE" == "S" ]]; then
    echo '[[ -d /etc/apache2 ]] && tar -pczf "\$BACKUP_DIR/apache2-\$DIA.tar.gz" /etc/apache2' >>"$script_path"
  fi
  if [[ "$INSTALL_MYSQL" == "S" ]]; then
    echo '[[ -d /etc/mysql ]] && tar -pczf "\$BACKUP_DIR/mysql-\$DIA.tar.gz" /etc/mysql' >>"$script_path"
  fi
  if [[ "$INSTALL_PHP" == "S" ]]; then
    echo '[[ -d /etc/php ]] && tar -pczf "\$BACKUP_DIR/php-\$DIA.tar.gz" /etc/php' >>"$script_path"
  fi
  if [[ "$INSTALL_REDIS" == "S" ]]; then
    echo '[[ -d /etc/redis ]] && tar -pczf "\$BACKUP_DIR/redis-\$DIA.tar.gz" /etc/redis' >>"$script_path"
  fi
  if [[ "$INSTALL_ELASTICSEARCH" == "S" ]]; then
    echo '[[ -d /etc/elasticsearch ]] && tar -pczf "\$BACKUP_DIR/elasticsearch-\$DIA.tar.gz" /etc/elasticsearch' >>"$script_path"
  fi

  # Adiciona backups de configurações gerais que sempre devem ser feitos.
  echo 'tar -pczf "\$BACKUP_DIR/crontabs-\$DIA.tar.gz" /etc/cron*' >>"$script_path"
  echo '[[ -d /etc/letsencrypt ]] && tar -pczf "\$BACKUP_DIR/letsencrypt-\$DIA.tar.gz" /etc/letsencrypt' >>"$script_path"
  echo 'tar -pczf "\$BACKUP_DIR/hosts-\$DIA.tar.gz" /etc/hosts' >>"$script_path"

  # Torna o novo script de backup executável para que possa ser chamado pelo sistema ou pelo cron.
  chmod +x "$script_path"

  # Copia o arquivo cron pré-configurado do repositório para o diretório do sistema.
  log "Agendando o script de backup para execução diária..."
  cp cron-backup-config /etc/cron.d/backup-configs

  # Garante permissões corretas para o arquivo cron.
  chmod 644 /etc/cron.d/backup-configs

  # Adiciona uma mensagem de conclusão ao script de backup.
  echo 'echo "Backup de configurações concluído."' >>"$script_path"

  # Exibe uma mensagem informativa ao usuário com os próximos passos.
  log "------------------------- INFORMAÇÃO --------------------------"
  log "Script de backup de configurações criado em: $script_path"
  log "Para automatizar, adicione-o ao crontab do root (crontab -e)."
  log "Exemplo para rodar todo dia às 3 da manhã:"
  log "0 3 * * * $script_path"
  log "-------------------------------------------------------------------"
}

# --- EXECUÇÃO PRINCIPAL ---

configure_hostname

# Laço principal para as perguntas. Permite ao usuário refazer a seleção.
while true; do
  INSTALL_NGINX=""
  INSTALL_APACHE=""
  INSTALL_MYSQL=""
  INSTALL_PHP=""
  INSTALL_REDIS=""
  INSTALL_SSMTP=""
  INSTALL_FAIL2BAN=""
  INSTALL_ELASTICSEARCH=""

  log "Iniciando seleção de pacotes para instalação..."
  ask_install "nginx" "INSTALL_NGINX"
  ask_install "apache" "INSTALL_APACHE"
  ask_install "mysql" "INSTALL_MYSQL"
  ask_install "php" "INSTALL_PHP"
  ask_install "redis" "INSTALL_REDIS"
  ask_install "ssmtp" "INSTALL_SSMTP"
  ask_install "fail2ban" "INSTALL_FAIL2BAN"
  ask_install "elasticsearch" "INSTALL_ELASTICSEARCH"

  # Mostra o resumo e pede a confirmação final.
  confirm_selections

  # Se a função 'confirm_selections' retornou 0 (usuário digitou 'S')...
  if [ $? -eq 0 ]; then
    # ...quebra o laço e prossegue para a instalação.
    break
  else
    # ...informa ao usuário que as perguntas serão feitas novamente.
    log "Seleção cancelada. Por favor, responda às perguntas novamente."
    echo
  fi
done

log "Confirmação recebida. Prosseguindo com a instalação..."

# Executa a atualização do sistema e instala ferramentas base
install_base_system

# --- Instalação dos Serviços Selecionados ---
# A instalação de cada serviço será chamada aqui, se selecionado.

if [[ "$INSTALL_SSMTP" == "S" ]]; then
  install_ssmtp
fi

# As partes de instalação do Nginx, Apache, etc., virão aqui.

# Criação do script de backup (agora é padrão).
setup_config_backup_script

log "Script finalizado com sucesso."
# Cria o arquivo de log para travar futuras execuções, salvando apenas a data.
date >"$LOG_FILE"

exit 0
