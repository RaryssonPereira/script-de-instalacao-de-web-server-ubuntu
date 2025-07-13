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
# - Parte 6: Configuração do SSH e do Firewall.
# - Parte 7: Otimização do Kernel de Rede.
# - Parte 8: Deploy de scripts e crons de utilidade.
# - Parte 9: Instalação do SSMTP.
# - Parte 10: Instalação do MySQL.
# - Parte 11: Instalação do Nginx.
# - Parte 12: Criação do script de backup de configurações.
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
  echo "  - Usar regras Iptables (em vez de UFW): $INSTALL_IPTABLES"
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

  # --- Instalação do WP-CLI ---
  log "Instalando a ferramenta WP-CLI para gerenciamento do WordPress..."
  wget https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -O /usr/local/bin/wp
  chmod +x /usr/local/bin/wp

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
# PARTE 6: CONFIGURAÇÃO DO SERVIDOR SSH E FIREWALL
#######################################################################

# Função principal da Parte 6.
setup_ssh_and_firewall() {
  # Exibe a mensagem de início da função.
  log "Configurando o servidor SSH e o Firewall..."

  # Chama a função auxiliar para perguntar ao usuário qual porta SSH usar.
  configure_ssh_port

  # Altera a porta no arquivo de configuração do SSH para o valor escolhido.
  sed -i -r "s/#?Port [0-9]*/Port $GLOBAL_SSH_PORT/g" /etc/ssh/sshd_config
  # Garante que a autenticação por senha esteja habilitada.
  sed -i -r "s/#?PasswordAuthentication (yes|no)/PasswordAuthentication yes/" /etc/ssh/sshd_config
  # Cria o arquivo de banner com as informações do script e um aviso legal.
  cat >/etc/issue.net <<EOF
###############################################################
#   Este servidor foi configurado com o script webserver-setup.sh
#   Autor: Rarysson Pereira
#   Repo: https://github.com/RaryssonPereira/script-de-instalacao-de-web-server-ubuntu
#
#   AVISO: Este sistema é privado. Todo acesso é monitorado.
###############################################################
EOF
  # Ativa o banner no arquivo de configuração do SSH.
  sed -i -r "s/#?Banner .*$/Banner \/etc\/issue.net/" /etc/ssh/sshd_config
  # Reinicia o serviço SSH para que todas as novas configurações entrem em vigor.
  systemctl restart sshd

  # Se a porta escolhida não for a padrão (22), exibe um alerta importante.
  if [[ "$GLOBAL_SSH_PORT" != "22" ]]; then
    log "ATENÇÃO: A porta do SSH foi alterada para $GLOBAL_SSH_PORT. Use 'ssh -p $GLOBAL_SSH_PORT' para conectar."
  fi

  # Verifica qual firewall o usuário escolheu para configurar.
  if [[ "$INSTALL_IPTABLES" == "S" ]]; then
    # Se o usuário escolheu regras personalizadas, chama a função do iptables.
    setup_firewall_iptables
  else
    # Se não, usa o UFW como firewall padrão e seguro.
    setup_firewall_ufw
  fi
}

# Função auxiliar para configurar a porta do SSH de forma interativa.
configure_ssh_port() {
  # Exibe a mensagem de início da função.
  log "Configurando a porta do serviço SSH..."

  # Exibe um menu de opções para o usuário.
  echo
  log "--------------------- CONFIGURAÇÃO DA PORTA SSH ---------------------"
  log "Escolha a porta que o SSH irá usar para conexões remotas."
  log "[1] Padrão (22)           - Mais compatível, porém alvo constante de ataques."
  log "[2] Segura Recomendada (51439) - Dificulta ataques automatizados."
  log "[3] Digitar uma porta personalizada."
  log "-------------------------------------------------------------------"

  # Declara uma variável local para armazenar a escolha do usuário.
  local choice
  # Pausa o script e lê a opção digitada pelo usuário.
  read -p ">> Escolha uma opção [padrão: 2]: " choice

  # Inicia uma estrutura 'case' para tratar a opção escolhida.
  case "$choice" in
  1)
    # Se a escolha for '1', define a porta SSH como a padrão 22.
    GLOBAL_SSH_PORT=22
    ;;
  3)
    # Se a escolha for '3', inicia um laço para pedir uma porta personalizada.
    while true; do
      # Pede ao usuário para digitar o número da porta personalizada.
      read -p ">> Digite a porta desejada (entre 1024 e 65535): " custom_port
      # Valida se a entrada é um número e está no intervalo permitido (1024-65535).
      if [[ "$custom_port" =~ ^[0-9]+$ && "$custom_port" -ge 1024 && "$custom_port" -le 65535 ]]; then
        # Se a porta for válida, a define e sai do laço 'while'.
        GLOBAL_SSH_PORT=$custom_port
        break
      else
        # Se a porta for inválida, exibe uma mensagem de erro e o laço continua.
        log "ERRO: Porta inválida. Por favor, digite um número entre 1024 e 65535."
      fi
    done
    ;;
  *) # Se a escolha for '2' ou qualquer outra coisa, usa a porta segura recomendada como padrão.
    GLOBAL_SSH_PORT=51439
    ;;
  esac
  # Informa ao usuário qual porta foi definida.
  log "Porta SSH definida como $GLOBAL_SSH_PORT."
}

# Função auxiliar para configurar as regras do firewall UFW (padrão).
setup_firewall_ufw() {
  # Exibe a mensagem de início da função.
  log "Configurando o firewall padrão (UFW)..."
  # Reseta o UFW para as configurações de fábrica, limpando todas as regras existentes.
  ufw --force reset >/dev/null
  # Define a política padrão para negar todas as conexões de entrada.
  ufw default deny incoming
  # Define a política padrão para permitir todas as conexões de saída.
  ufw default allow outgoing
  # Libera a porta SSH que foi configurada, permitindo o acesso remoto.
  ufw allow "$GLOBAL_SSH_PORT/tcp"
  # Libera a porta 80/tcp (HTTP) para tráfego web.
  ufw allow http
  # Libera a porta 443/tcp (HTTPS) para tráfego web seguro.
  ufw allow https
  # Ativa o firewall de forma não-interativa, confirmando a operação.
  echo "y" | ufw enable
  # Informa que o firewall foi ativado.
  log "Firewall UFW ativado. Verificando status:"
  # Exibe o status detalhado do firewall com as regras ativas.
  ufw status verbose
}

# Função auxiliar para configurar as regras do firewall iptables a partir de um arquivo de template.
setup_firewall_iptables() {
  # Exibe a mensagem de início da função.
  log "Configurando o firewall com regras personalizadas (iptables)..."

  # Verifica se o arquivo de template 'rules.v4' existe no diretório atual.
  if [[ ! -f "rules.v4" ]]; then
    # Se o arquivo não for encontrado, avisa o usuário e ativa o UFW como uma medida de segurança.
    log "AVISO: Arquivo 'rules.v4' não encontrado. Configurando UFW como fallback de segurança."
    # Chama a função do UFW para garantir que o servidor tenha um firewall básico.
    setup_firewall_ufw
    # Sai da função atual para não executar os comandos seguintes.
    return
  fi

  # Desabilita o UFW para evitar conflitos com as regras diretas do iptables.
  log "Desabilitando o UFW para usar regras de iptables diretamente."
  ufw --force disable >/dev/null
  # Garante que o diretório padrão do iptables-persistent exista.
  mkdir -p /etc/iptables/
  # Copia o arquivo de regras do repositório para o local correto no sistema.
  cp rules.v4 /etc/iptables/rules.v4
  log "Arquivo de regras 'rules.v4' copiado para /etc/iptables/."

  # Declara uma variável local para armazenar o nome da interface de rede.
  local network_interface
  # Detecta automaticamente o nome da interface de rede principal (ex: eth0, ens3).
  network_interface=$(ip -o -4 route show to default | awk '{print $5}')

  # Se o nome da interface foi detectado com sucesso...
  if [[ -n "$network_interface" ]]; then
    # Adapta o arquivo de regras, substituindo o placeholder 'eth0' pelo nome real da interface.
    log "Adaptando regras de firewall para a interface de rede: $network_interface"
    sed -i "s/eth0/$network_interface/g" /etc/iptables/rules.v4
  else
    # Se não foi possível detectar, avisa o usuário que um ajuste manual pode ser necessário.
    log "AVISO: Não foi possível detectar a interface de rede principal. As regras podem precisar de ajuste manual."
  fi

  # Substitui o placeholder da porta SSH ('22222') pela porta que o usuário escolheu.
  log "Adaptando regras de firewall para a porta SSH: $GLOBAL_SSH_PORT"
  sed -i "s/22222/$GLOBAL_SSH_PORT/g" /etc/iptables/rules.v4

  # Aplica as novas regras de firewall imediatamente.
  log "Aplicando e salvando novas regras de firewall..."
  iptables-restore </etc/iptables/rules.v4
  # Salva as regras ativas para que elas persistam após uma reinicialização.
  netfilter-persistent save
  # Informa que a configuração foi concluída.
  log "Configuração do iptables concluída."
}

#######################################################################
# PARTE 7: OTIMIZAÇÃO DO KERNEL DE REDE (SYSCTL)
#######################################################################
optimize_kernel_network() {
  log "Otimizando parâmetros do kernel de rede para alto desempenho..."

  # Cria um arquivo de configuração dedicado para as otimizações de rede.
  cat >/etc/sysctl.d/99-web-optimizations.conf <<EOF
# --- Otimizações para servidores web com alto tráfego ---
# Aumenta a faixa de portas que o servidor pode usar para conexões de saída.
net.ipv4.ip_local_port_range=1024 65000
# Reduz o tempo que conexões finalizadas ficam na memória, liberando recursos mais rápido.
net.ipv4.tcp_fin_timeout=30
# Aumenta o número máximo de conexões "finalizadas" que o sistema pode manter, evitando recusas em picos de tráfego.
net.ipv4.tcp_max_tw_buckets=2000000
# Aumenta a fila para novas conexões, protegendo contra picos e ataques 'SYN flood'.
net.ipv4.tcp_max_syn_backlog=20480
# Aumenta o número máximo de conexões 'órfãs' (sem um processo associado), prevenindo erros de esgotamento.
net.ipv4.tcp_max_orphans=20000
# Aumenta o número máximo de conexões que podem aguardar na fila para serem aceitas por um serviço (ex: Nginx).
net.core.somaxconn=16384

# --- Otimizações do Firewall e IPv6 ---
# Aumenta a tabela de rastreamento de conexões do firewall, evitando que ele descarte pacotes legítimos sob alta carga.
net.netfilter.nf_conntrack_max=1048576

# --- Otimizações de Memória para Buffers de Rede ---
# Define o tamanho máximo do buffer de recepção para todas as conexões.
net.core.rmem_max=16777216
# Define o tamanho máximo do buffer de envio para todas as conexões.
net.core.wmem_max=16777216
# Define os tamanhos (mínimo, padrão, máximo) do buffer de recepção para conexões TCP.
net.ipv4.tcp_rmem=4096 87380 16777216
# Define os tamanhos (mínimo, padrão, máximo) do buffer de envio para conexões TCP.
net.ipv4.tcp_wmem=4096 65536 16777216

# Desativa o IPv6 em todas as interfaces, se o protocolo não for utilizado.
net.ipv6.conf.all.disable_ipv6 = 1
# Desativa o IPv6 também para novas interfaces que possam ser criadas no futuro.
net.ipv6.conf.default.disable_ipv6 = 1
EOF

  # Aplica as novas configurações do kernel imediatamente, sem precisar reiniciar.
  sysctl -p /etc/sysctl.d/99-web-optimizations.conf >/dev/null
  log "Parâmetros do kernel de rede otimizados."

  # --- Configuração Opcional para /tmp em RAM (tmpfs) ---
  # O trecho abaixo configura o diretório /tmp para ser armazenado na memória RAM.
  #
  # VANTAGEM: Performance extremamente alta para operações de I/O em arquivos temporários.
  # RISCO: Se /tmp encher, ele pode consumir TODA a RAM do servidor, causando instabilidade e travamentos.
  #
  # QUANDO DESCOMENTAR? Apenas se você souber o que está fazendo e seu servidor tiver memória RAM de sobra.
  #
  log "Configurando /tmp para usar tmpfs (armazenamento em RAM)..."
  # # Adiciona a linha ao fstab para montar /tmp como tmpfs na inicialização.
  # # A opção 'size=1G' é um limite de segurança crucial para evitar o consumo total da RAM.
  echo "tmpfs /tmp tmpfs defaults,size=1G,noatime,nosuid,nodev,noexec 0 0" >>/etc/fstab
  log "AVISO: /tmp foi configurado para usar a memória RAM. Esta mudança requer uma REINICIALIZAÇÃO para ter efeito."
}

#######################################################################
# PARTE 8: DEPLOY DE SCRIPTS E CRONS DE UTILIDADE
#######################################################################
deploy_utility_scripts() {
  log "Instalando scripts e crons de utilidade..."

  # --- Monitoramento de Disco ---
  log "Adicionando o script e cron de monitoramento de disco (alerta-espaco-disco.sh)..."
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
  log "Adicionando script e cron de monitoramento de carga (alerta-load-average.sh)..."
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

  # --- Reboot Semanal Automático ---
  log "Adicionando cron de atualização e reboot semanal..."
  #
  cp cron-reboot-semanal /etc/cron.d/cron-reboot-semanal
  chmod 644 /etc/cron.d/cron-reboot-semanal

  # --- Manutenção e Backup do Banco de Dados ---
  log "Adicionando script e cron de manutenção e backup do banco de dados..."
  #
  cp backup-bancos.sh /usr/local/bin/backup-bancos.sh
  chmod +x /usr/local/bin/backup-bancos.sh
  #
  cp cron-backup-bancos /etc/cron.d/cron-backup-bancos
  chmod 644 /etc/cron.d/cron-backup-bancos

  # --- Configuração Personalizada do MySQL ---
  log "Adicionando arquivo de configuração personalizada do MySQL..."
  #
  cp mysql.cnf /etc/mysql/conf.d/mysql.cnf
  chmod 644 /etc/mysql/conf.d/mysql.cnf

  # --- Configuração de Otimização de Imagem (WebP) ---
  log "Adicionando arquivo de configuração para otimização de imagens WebP..."
  #
  cp webp.conf /etc/nginx/conf.d/webp.conf
  chmod 644 /etc/nginx/conf.d/webp.conf

  # --- Cron e Script para Conversão de Imagens para WebP ---
  log "Copiando cron e script para conversão de imagens para WebP..."
  #
  cp converte_webp_antes_3min.sh /usr/local/bin/converte_webp_antes_3min.sh
  chmod +x /usr/local/bin/converte_webp_antes_3min.sh
  #
  cp converte_webp_apos_3min.sh /usr/local/bin/converte_webp_apos_3min.sh
  chmod +x /usr/local/bin/converte_webp_apos_3min.sh
  #
  cp converte-todos-para-webp.sh /usr/local/bin/converte-todos-para-webp.sh
  chmod +x /usr/local/bin/converte-todos-para-webp.sh
  #
  cp cron-conversao-webp /etc/cron.d/cron-conversao-webp
  chmod 644 /etc/cron.d/cron-conversao-webp

  # --- Cron para Tarefas do WordPress ---
  log "Adicionando cron para tarefas do WordPress (cron-wp-uploads)..."
  #
  cp cron-wp-uploads /etc/cron.d/cron-wp-uploads
  chmod 644 /etc/cron.d/cron-wp-uploads

  # --- Cron para Renovação de Certificados SSL ---
  log "Adicionando cron para renovação automática de certificados SSL (cron-certbot-renew)..."
  #
  cp cron-certbot-renew /etc/cron.d/cron-certbot-renew
  chmod 644 /etc/cron.d/cron-certbot-renew

  # --- Verificação de Certificados SSL ---
  log "Adicionando script de verificação de certificados SSL (verificar-certificados-ssl.sh)..."
  #
  cp verificar-certificados-ssl.sh /usr/local/bin/verificar-certificados-ssl.sh
  chmod +x /usr/local/bin/verificar-certificados-ssl.sh

  log "Scripts e crons adicionados e agendados com sucesso."
}

#######################################################################
# PARTE 9: INSTALAÇÃO DO RETRANSMISSOR DE E-MAIL (SSMTP)
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
# PARTE 10: INSTALAÇÃO DO MYSQL (PERCONA SERVER)
#######################################################################
install_mysql() {
  # Exibe a mensagem de início da função.
  log "Iniciando a instalação do Percona Server for MySQL..."

  # --- Seleção da Versão ---
  # Declara variáveis locais para armazenar a string da versão e o nome do pacote.
  local percona_version_string
  local percona_package_name
  local version_choice

  # Exibe um menu de opções para o usuário escolher a versão do MySQL.
  log "----------------- SELEÇÃO DA VERSÃO DO MYSQL -----------------"
  log "Escolha a versão do Percona Server a ser instalada."
  log "[1] 8.0 - Versão mais recente e recomendada."
  log "[2] 5.7 - Versão mais antiga para compatibilidade com sistemas legados."
  log "------------------------------------------------------------"
  # Lê a escolha do usuário.
  read -p ">> Escolha uma opção [padrão: 1]: " version_choice

  # Trata a escolha do usuário com uma estrutura 'case'.
  case "$version_choice" in
  2)
    # Se a escolha for '2', define as variáveis para a versão 5.7.
    log "Versão 5.7 selecionada."
    percona_version_string="ps57"
    percona_package_name="percona-server-server-5.7"
    ;;
  *)
    # Para qualquer outra escolha, usa a versão 8.0 como padrão.
    log "Versão 8.0 selecionada (padrão)."
    percona_version_string="ps80"
    percona_package_name="percona-server-server"
    ;;
  esac

  # --- Configuração do Repositório Percona ---
  # Informa ao usuário que o repositório está sendo configurado.
  log "Configurando o repositório do Percona Server..."
  # Baixa o pacote que configura os repositórios oficiais da Percona.
  wget https://repo.percona.com/apt/percona-release_latest.$(lsb_release -sc)_all.deb -O percona-release.deb
  # Instala o pacote de configuração do repositório.
  dpkg -i percona-release.deb
  # Atualiza a lista de pacotes para incluir os do novo repositório.
  apt-get update -qq
  # Configura o sistema para usar os pacotes da versão escolhida (ps80 ou ps57).
  percona-release setup "$percona_version_string"

  # --- Pré-configuração da Senha ---
  # Define a senha padrão para o usuário 'root' do MySQL.
  local mysql_root_password="uz@r&*2#^Pj9#V&5u5nJ"
  # Informa ao usuário que a senha está sendo pré-configurada.
  log "Pré-configurando a senha do usuário root do MySQL..."
  # Responde automaticamente à pergunta sobre a senha do root, evitando a interrupção do script.
  echo "$percona_package_name $percona_package_name/root_password password $mysql_root_password" | debconf-set-selections
  # Confirma a senha para o instalador.
  echo "$percona_package_name $percona_package_name/root_password_again password $mysql_root_password" | debconf-set-selections

  # --- Instalação dos Pacotes ---
  # Informa ao usuário que a instalação dos pacotes está começando.
  log "Instalando o Percona Server e as ferramentas..."
  # Instala o servidor Percona e as ferramentas de monitoramento e otimização.
  apt-get install -qq -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
    "$percona_package_name" percona-toolkit mysqltuner mytop

  # --- Configuração dos Clientes MySQL ---
  # Cria o arquivo .my.cnf para permitir o login do root sem digitar a senha no terminal.
  cat >/root/.my.cnf <<EOF
[client]
user=root
password="$mysql_root_password"
EOF
  # Define permissões restritas ao arquivo, para que apenas o usuário root possa lê-lo.
  chmod 600 /root/.my.cnf
  # Copia o arquivo de configuração pré-definido para o mytop.
  cp .mytop /root/
  # Define permissões restritas ao arquivo .mytop.
  chmod 600 /root/.mytop

  # --- Otimização de Limite de Arquivos Abertos ---
  # Informa ao usuário que o limite de arquivos será aumentado.
  log "Aumentando o limite de arquivos abertos para o MySQL..."
  # Cria um diretório de override para o serviço do MySQL.
  mkdir -p /etc/systemd/system/mysql.service.d/
  # Cria um arquivo de configuração para definir um novo limite de arquivos abertos.
  cat >/etc/systemd/system/mysql.service.d/override.conf <<EOF
[Service]
LimitNOFILE=100000
EOF
  # Recarrega a configuração do systemd para ler o novo arquivo de override.
  systemctl daemon-reload

  # --- Hardening da Instalação ---
  # Informa ao usuário que o script de segurança será executado.
  log "Executando 'mysql_secure_installation' para hardening..."
  # Alimenta o script de segurança com respostas automáticas para aplicar as melhores práticas.
  mysql_secure_installation <<EOF

y
2
n
y
y
y
EOF

  # Reinicia o serviço MySQL para aplicar todas as configurações.
  log "Reiniciando o serviço MySQL para aplicar as novas configurações..."
  systemctl restart mysql

  # --- Aviso Final ---
  # Exibe um aviso importante para o usuário sobre a senha padrão.
  log "------------------------- ATENÇÃO: SENHA PADRÃO -------------------------"
  log "Uma senha padrão para o usuário 'root' do MySQL foi definida."
  log "É ALTAMENTE RECOMENDADO que você altere esta senha o mais rápido possível."
  log "A senha foi salva no arquivo: /root/.my.cnf"
  log "Lembre-se de atualizar também o arquivo /root/.mytop se alterar a senha."
  log "-------------------------------------------------------------------------"

  # Informa que a instalação desta parte foi concluída.
  log "Instalação do Percona Server concluída."
}

#######################################################################
# PARTE 11: INSTALAÇÃO DO NGINX
#######################################################################
install_nginx() {
  log "Iniciando a instalação do Nginx..."

  # --- Instalação dos Pacotes ---
  log "Adicionando o repositório oficial do Nginx e instalando pacotes..."
  curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/mainline/ubuntu $(lsb_release -cs) nginx" |
    tee /etc/apt/sources.list.d/nginx.list >/dev/null

  apt-get update -qq
  apt-get install -qq -y nginx apachetop webp

  log "Instalando Certbot para certificados SSL/TLS..."
  add-apt-repository -y ppa:certbot/certbot
  apt-get update -qq
  apt-get install -qq -y python3-certbot-nginx

  # --- Configuração Inicial do Nginx ---
  log "Configurando vhost padrão de segurança e criando certificado SSL autoassinado..."
  openssl req -newkey rsa:2048 -x509 -nodes -keyout /etc/nginx/server.key -new -out /etc/nginx/server.crt -subj "/CN=$(hostname)" -config /etc/ssl/openssl.cnf -sha256 -days 3650
  mkdir -p /var/www/default
  cp index.html 404.html 50x.html /var/www/default/
  echo -e "User-agent: *\nDisallow: /" >/var/www/default/robots.txt
  chown -R www-data:www-data /var/www/default
  cp default-vhost.conf /etc/nginx/conf.d/default.conf
  chmod 644 /etc/nginx/conf.d/default.conf

  # --- Otimização do Nginx ---
  log "Otimizando a configuração do Nginx para melhor performance..."
  sed -i 's/user  nginx;/user  www-data;/g' /etc/nginx/nginx.conf
  local cpu_cores
  cpu_cores=$(nproc)
  sed -i "s/worker_processes [0-9]\+;/worker_processes $cpu_cores;/g" /etc/nginx/nginx.conf
  sed -i '/worker_processes/a worker_rlimit_nofile 65535;' /etc/nginx/nginx.conf
  sed -i "s/worker_connections [0-9]\+;/worker_connections 8192;/g" /etc/nginx/nginx.conf
  sed -i -r 's/^\s*access_log/#access_log/g' /etc/nginx/nginx.conf

  # --- Configuração da Compressão Gzip ---
  log "Ativando a compressão Gzip para melhor performance..."
  cat >/etc/nginx/conf.d/gzip.conf <<EOF
gzip on;
gzip_disable "msie6";
gzip_vary on;
gzip_proxied any;
gzip_comp_level 6;
gzip_buffers 16 8k;
gzip_http_version 1.1;
gzip_min_length 256;
gzip_types
    application/atom+xml application/javascript application/json application/ld+json
    application/manifest+json application/rss+xml application/vnd.geo+json
    application/vnd.ms-fontobject application/x-font-ttf application/x-web-app-manifest+json
    application/xhtml+xml application/xml font/opentype image/bmp image/svg+xml
    image/x-icon text/cache-manifest text/css text/plain text/vcard
    text/vnd.rim.location.xloc text/vtt text/x-component text/x-cross-domain-policy;
EOF

  # --- Hardening de Segurança (Nginx Ultimate Bad Bot Blocker) ---
  log "Instalando o Nginx Ultimate Bad Bot Blocker para proteção adicional..."
  wget https://raw.githubusercontent.com/mitchellkrogza/nginx-ultimate-bad-bot-blocker/master/install-ngxblocker -O /usr/local/sbin/install-ngxblocker
  chmod +x /usr/local/sbin/install-ngxblocker
  (cd /usr/local/sbin/ && /usr/local/sbin/install-ngxblocker -x)
  log "Bad Bot Blocker instalado."

  # --- Correção da Lista de Bloqueio ---
  log "Corrigindo a lista de bloqueio para remover IPs conhecidos como falsos positivos..."
  sed -i "s/89.187.173.66\t\t0;/#89.187.173.66\t\t0;/g" /etc/nginx/conf.d/globalblacklist.conf
  sed -i "s/5.188.120.15\t\t0;/#5.188.120.15\t\t0;/g" /etc/nginx/conf.d/globalblacklist.conf
  sed -i "s/195.181.163.194\t\t0;/#195.181.163.194\t\t0;/g" /etc/nginx/conf.d/globalblacklist.conf
  sed -i "s/143.244.38.129\t\t0;/#143.244.38.129\t\t0;/g" /etc/nginx/conf.d/globalblacklist.conf
  sed -i "s/138.199.57.151\t\t0;/#138.199.57.151\t\t0;/g" /etc/nginx/conf.d/globalblacklist.conf

  # --- Configuração do Primeiro Projeto (Opcional) ---
  local project_name
  local domain_name

  echo
  log "Deseja configurar um site inicial agora?"
  read -p ">> Digite o nome do projeto (ex: nome-do-site ou nome-do-sistema) ou 'N' para pular: " project_name

  if [[ "$project_name" != "N" && "$project_name" != "n" ]]; then
    read -p ">> Digite o domínio do projeto (sem o www): (ex: meusite.com.br ou dominio.com): " domain_name

    while [[ -z "$domain_name" ]]; do
      log "ERRO: O domínio não pode ser vazio."
      read -p ">> Digite o domínio principal: " domain_name
    done

    log "Configurando o projeto '$project_name' para o domínio '$domain_name'..."

    # Cria a estrutura de diretórios para o projeto.
    mkdir -p "/var/www/$project_name"
    chown -R www-data:www-data "/var/www/$project_name"
    log "Diretório do projeto criado em /var/www/$project_name"

    # Garante que as pastas de configuração do Nginx existam.
    mkdir -p /etc/nginx/sites-available
    mkdir -p /etc/nginx/sites-enabled

    # Verifica e adiciona a diretiva 'include' no nginx.conf se não existir.
    if ! grep -q "include /etc/nginx/sites-enabled/*;" /etc/nginx/nginx.conf; then
      sed -i '/http {/a \    include /etc/nginx/sites-enabled/*;' /etc/nginx/nginx.conf
      log "Diretiva 'include' adicionada ao nginx.conf."
    fi

    # Copia e personaliza o template de configuração do vhost.
    local vhost_path="/etc/nginx/sites-available/$domain_name.conf"
    cp nginx-site.conf "$vhost_path"
    sed -i "s/DOMINIO/$domain_name/g" "$vhost_path"
    sed -i "s/PROJETO/$project_name/g" "$vhost_path"

    # Ativa o site criando um link simbólico.
    ln -s "$vhost_path" "/etc/nginx/sites-enabled/$domain_name.conf"
    log "Site '$domain_name' ativado."
  fi

  # Reinicia o Nginx para aplicar todas as novas configurações.
  log "Testando a configuração do Nginx e reiniciando o serviço..."
  if nginx -t; then
    systemctl restart nginx
  else
    log "ERRO: A configuração do Nginx contém erros. O serviço não foi reiniciado."
  fi

  log "Instalação do Nginx e ferramentas associadas concluída."
}

#######################################################################
# PARTE 12: CRIAÇÃO DO SCRIPT DE BACKUP DE CONFIGURAÇÕES
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

# Etapa 1: Configuração inicial do hostname.
configure_hostname

# Etapa 2: Laço interativo para seleção de pacotes e confirmação final.
while true; do
  # Reseta as variáveis de instalação a cada vez que o laço recomeça.
  INSTALL_NGINX=""
  INSTALL_APACHE=""
  INSTALL_MYSQL=""
  INSTALL_PHP=""
  INSTALL_REDIS=""
  INSTALL_SSMTP=""
  INSTALL_FAIL2BAN=""
  INSTALL_IPTABLES=""
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
  ask_install "iptables_personalizado" "INSTALL_IPTABLES"
  ask_install "elasticsearch" "INSTALL_ELASTICSEARCH"

  # Mostra o resumo das opções e pede uma confirmação final.
  confirm_selections

  # Se o usuário confirmar com 'S', sai do laço e prossegue.
  if [ $? -eq 0 ]; then
    break
  # Se o usuário digitar 'N', o laço recomeça.
  else
    log "Seleção cancelada. Por favor, responda às perguntas novamente."
    echo
  fi
done

log "Confirmação recebida. Prosseguindo com a instalação..."

# Etapa 3: Instalações e configurações base do sistema.
install_base_system
setup_ssh_and_firewall
optimize_kernel_network

# Etapa 4: Instalação dos serviços selecionados pelo usuário.
if [[ "$INSTALL_SSMTP" == "S" ]]; then
  install_ssmtp
fi

if [[ "$INSTALL_MYSQL" == "S" ]]; then
  install_mysql
fi

if [[ "$INSTALL_NGINX" == "S" ]]; then
  install_nginx
fi
# (As partes de instalação do Apache, etc., virão aqui)

# Etapa 5: Instalação das ferramentas de suporte (utilitários e backup).
deploy_utility_scripts
setup_config_backup_script

# Etapa 6: Finalização do script.
log "Script finalizado com sucesso."
# Cria o arquivo de log para impedir futuras execuções.
date >"$LOG_FILE"
# Encerra o script com código 0 (sucesso).
exit 0
