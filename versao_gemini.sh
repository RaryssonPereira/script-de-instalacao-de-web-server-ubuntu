#!/usr/bin/env bash

#######################################################################
# SCRIPT DE SETUP BÁSICO DE SERVIDOR
#
# Autor: Rarysson Pereira
# Data: 15/06/2025
# Versão: 17.0
#
# Descrição:
# Prepara um novo servidor Ubuntu para hospedagem.
# - Parte 1: Verificações iniciais, funções e correções de ambiente.
# - Parte 2: Configuração do hostname.
# - Parte 3: Menu interativo para seleção de pacotes.
# - Parte 4: Resumo e confirmação final.
# - Parte 5: Atualização do sistema e instalação de ferramentas base.
# - Parte 6: Configuração do Servidor SSH.
# - Parte 7: Deploy de scripts e crons de utilidade (monitoramento).
# - Parte 8: Configuração do retransmissor de e-mail (SMTP).
# - Parte 9: Criação de um script de backup de configurações.
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

  # --- Configuração Opcional para Backup Dedicado (rsync) ---
  # O trecho abaixo prepara o servidor para ser acessado por um servidor de backup dedicado via SSH.
  #
  # QUANDO DESCOMENTAR E USAR?
  # - Se você tiver um segundo servidor (servidor de backup) e quiser que ele puxe os backups
  #   deste servidor de forma segura e sem senha, usando chaves SSH.
  #
  # log "Configurando usuário 'rsync' para backups dedicados..."
  # # Cria um usuário de sistema chamado 'rsync' sem senha, apenas para tarefas de backup.
  # adduser --quiet rsync --disabled-password --gecos ""
  #
  # # Adiciona a chave SSH PÚBLICA do seu SERVIDOR DE BACKUP abaixo.
  # # Isso autoriza o servidor de backup a se conectar como o usuário 'rsync'.
  # mkdir -p /home/rsync/.ssh
  # echo "ssh-rsa AAAA...chave-publica-do-seu-servidor-de-backup... rsync@servidor-backup" > /home/rsync/.ssh/authorized_keys
  #
  # # Garante as permissões corretas para a pasta e o arquivo de chaves.
  # chown -R rsync:rsync /home/rsync/.ssh
  # chmod 700 /home/rsync/.ssh
  # chmod 600 /home/rsync/.ssh/authorized_keys
}

#######################################################################
# PARTE 6: CONFIGURAÇÃO DO SERVIDOR SSH
#######################################################################

# Função auxiliar da Parte 6 para configurar a porta do SSH de forma interativa.
configure_ssh_port() {
  log "Configurando a porta do serviço SSH..."
  local SSH_PORT

  echo
  log "--------------------- CONFIGURAÇÃO DA PORTA SSH ---------------------"
  log "Escolha a porta que o SSH irá usar para conexões remotas."
  log "[1] Padrão (22)           - Mais compatível, porém alvo constante de ataques."
  log "[2] Segura Recomendada (48291) - Dificulta ataques automatizados."
  log "[3] Digitar uma porta personalizada."
  log "-------------------------------------------------------------------"

  local choice
  read -p ">> Escolha uma opção [padrão: 2]: " choice

  case "$choice" in
  1)
    SSH_PORT=22
    ;;
  3)
    while true; do
      read -p ">> Digite a porta desejada (entre 1024 e 65535): " custom_port
      if [[ "$custom_port" =~ ^[0-9]+$ && "$custom_port" -ge 1024 && "$custom_port" -le 65535 ]]; then
        SSH_PORT=$custom_port
        break
      else
        log "ERRO: Porta inválida. Por favor, digite um número entre 1024 e 65535."
      fi
    done
    ;;
  *) # Opção 2 ou qualquer outra entrada se torna o padrão.
    SSH_PORT=48291
    ;;
  esac

  log "Definindo a porta do SSH para $SSH_PORT..."
  sed -i -r "s/#?Port [0-9]*/Port $SSH_PORT/g" /etc/ssh/sshd_config

  if [[ "$SSH_PORT" != "22" ]]; then
    echo
    log "------------------------- ATENÇÃO -------------------------"
    log "A porta do SSH foi alterada para $SSH_PORT."
    log "Para conectar, use: ssh seu_usuario@servidor -p $SSH_PORT"
    log "---------------------------------------------------------"
    echo
  fi
}

# Função principal da Parte 6.
setup_ssh() {
  log "Configurando o servidor SSH para maior segurança..."

  # Chama a função interativa para definir a porta do SSH.
  configure_ssh_port

  # Garante que a autenticação por senha esteja habilitada.
  sed -i -r "s/#?PasswordAuthentication (yes|no)/PasswordAuthentication yes/" /etc/ssh/sshd_config

  # Configura um banner de aviso que será exibido antes do login.
  cat >/etc/issue.net <<EOF
###############################################################
#                                                             #
#   Este servidor foi configurado com o script webserver-setup.sh
#   Autor: Rarysson Pereira
#   Repo: https://github.com/RaryssonPereira/script-de-instalacao-de-web-server-ubuntu
#
#   AVISO: Este sistema é privado. Todo acesso é monitorado.
#                                                             #
###############################################################
EOF
  sed -i -r "s/#?Banner .*$/Banner \/etc\/issue.net/" /etc/ssh/sshd_config

  # Reinicia o serviço SSH para aplicar as novas configurações.
  systemctl restart sshd
}

#######################################################################
# PARTE 7: DEPLOY DE SCRIPTS E CRONS DE UTILIDADE
#######################################################################
deploy_utility_scripts() {

  # --- Monitoramento de Disco ---
  log "Instalando scripts de utilidade (monitoramento de disco)..."
  #
  # Copia o script de monitoramento para o diretório de binários locais.
  cp alerta-espaco-disco.sh /usr/local/bin/alerta-espaco-disco.sh
  # Garante que o script seja executável.
  chmod +x /usr/local/bin/alerta-espaco-disco.sh
  #
  # Copia a tarefa agendada para o diretório do cron.
  cp cron-alerta-espaco-disco /etc/cron.d/cron-alerta-espaco-disco
  # Garante as permissões corretas para o arquivo cron.
  chmod 644 /etc/cron.d/cron-alerta-espaco-disco

  # --- Monitoramento de Carga do Servidor ---
  log "Copiando script de monitoramento de carga (load average)..."
  #
  # Copia o script de alerta de carga para o diretório de binários locais do sistema.
  cp alerta-load-average.sh /usr/local/bin/alerta-load-average.sh
  # Torna o script executável para que possa ser chamado pelo cron.
  chmod +x /usr/local/bin/alerta-load-average.sh
  #
  # Copia o arquivo de tarefa agendada para o diretório do cron.
  cp cron-alerta-load-average /etc/cron.d/cron-alerta-load-average
  # Garante as permissões corretas para o arquivo cron, por segurança.
  chmod 644 /etc/cron.d/cron-alerta-load-average

  # --- Manutenção Semanal Automática ---
  log "Copiando cron de atualização e reboot semanal..."
  cp cron-reboot-semanal /etc/cron.d/cron-reboot-semanal
  chmod 644 /etc/cron.d/cron-reboot-semanal

  log "Script de monitoramento de disco instalado e agendado."
}

#######################################################################
# PARTE 8: INSTALAÇÃO DO RETRANSMISSOR DE E-MAIL (SSMTP)
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
# PARTE 9: CRIAÇÃO DO SCRIPT DE BACKUP DE CONFIGURAÇÕES
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
  log "Tarefa de automação copiada para: /etc/cron.d/backup-configs"
  log "O backup será executado automaticamente todos os dias."
  log "-------------------------------------------------------------------"
}

# --- EXECUÇÃO PRINCIPAL ---

# Etapa 1: Chama a função para configurar o hostname do servidor.
configure_hostname

# Etapa 2: Inicia um laço que permite ao usuário refazer a seleção de pacotes se errar.
while true; do
  # Reseta as variáveis de instalação a cada vez que o laço recomeça.
  INSTALL_NGINX=""
  INSTALL_APACHE=""
  INSTALL_MYSQL=""
  INSTALL_PHP=""
  INSTALL_REDIS=""
  INSTALL_SSMTP=""
  INSTALL_FAIL2BAN=""
  INSTALL_ELASTICSEARCH=""

  # Exibe o menu interativo de perguntas para cada serviço.
  log "Iniciando seleção de pacotes para instalação..."
  ask_install "nginx" "INSTALL_NGINX"
  ask_install "apache" "INSTALL_APACHE"
  ask_install "mysql" "INSTALL_MYSQL"
  ask_install "php" "INSTALL_PHP"
  ask_install "redis" "INSTALL_REDIS"
  ask_install "ssmtp" "INSTALL_SSMTP"
  ask_install "fail2ban" "INSTALL_FAIL2BAN"
  ask_install "elasticsearch" "INSTALL_ELASTICSEARCH"

  # Mostra o resumo das opções e pede uma confirmação final.
  confirm_selections

  # Verifica a resposta do usuário: se for 'S' (código 0), quebra o laço.
  if [ $? -eq 0 ]; then
    break
  # Se for 'N' (código 1), informa o usuário e o laço recomeça.
  else
    log "Seleção cancelada. Por favor, responda às perguntas novamente."
    echo
  fi
done

# Etapa 3: Após a confirmação, prossegue com as instalações.
log "Confirmação recebida. Prosseguindo com a instalação..."

# Instala as atualizações do sistema e as ferramentas base.
install_base_system

# Instala e configura o SSHD do servidor de forma interativa.
setup_ssh

# Etapa 4: Inicia a instalação dos serviços que foram selecionados pelo usuário.
# --- Instalação dos Serviços Selecionados ---

# Instala o SSMTP se o usuário escolheu 'S'.
if [[ "$INSTALL_SSMTP" == "S" ]]; then
  install_ssmtp
fi

# (As partes de instalação do Nginx, Apache, etc., virão aqui)

# Instala os scripts de utilidade (monitoramento de disco e carga).
deploy_utility_scripts

# Etapa 5: Cria e agenda o script de backup de configurações como uma ação padrão.
setup_config_backup_script

# Etapa 6: Finaliza o script.
log "Script finalizado com sucesso."
# Cria o arquivo de log para impedir futuras execuções.
date >"$LOG_FILE"
# Encerra o script com código 0 (sucesso).
exit 0
