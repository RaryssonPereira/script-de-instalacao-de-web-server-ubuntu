#! /bin/bash
# ============================================ TUDO ABAIXO ESTÁ SENDO DESENVOLVIDO ============================================ #

# Se o usuário escolheu instalar Nginx (INSTALL_NGINX="S"), ele instala silenciosamente a versão estável e segura do repositório oficial do nginx.org
if [[ "$INSTALL_NGINX" == "S" ]]; then
    echo "Instalando Nginx a partir do repositório oficial (nginx.org)..."

    # Adiciona a chave pública do repositório oficial do Nginx
    curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg

    # Adiciona o repositório oficial do Nginx para Ubuntu 22.04 (Jammy)
    echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/ubuntu $(lsb_release -cs) nginx" |
        tee /etc/apt/sources.list.d/nginx.list >/dev/null

    # Atualiza os pacotes e instala o Nginx
    apt-get update -qq
    apt-get install -qq -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" nginx

    # Instala apachetop para monitoramento de requisições em tempo real
    apt-get install -qq -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" apachetop

    # Instala WebP utilitários para otimização de imagens
    apt-get install -qq -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" webp

    # Adiciona repositório do Certbot e instala o plugin para Nginx (Let's Encrypt)
    add-apt-repository -y ppa:certbot/certbot
    apt-get update -qq
    apt install -qq -y python3-certbot-nginx

    # Pergunta ao usuário se deseja configurar um projeto Nginx (estrutura em /var/www/projeto)
    echo
    echo 'Deseja configurar um projeto em /var/www/?'
    echo 'Digite o nome do projeto (ex: google ou laminas-framework) ou "N" para pular:'
    read projectname

    # Enquanto o usuário não digitar nada, continua pedindo uma entrada válida
    while [ -z "$projectname" ]; do
        echo 'Nenhuma opção digitada, favor digitar uma opção válida:'
        read projectname
    done

    # Se o usuário não digitou "N" ou "n", ou seja, deseja configurar o projeto
    if [[ "$projectname" != "N" && "$projectname" != "n" ]]; then
        echo 'Digite o domínio do projeto (sem o www): (ex: dominio.com.br ou google.com.br)'
        read domainname

        # Enquanto o domínio estiver vazio, continua pedindo uma entrada válida
        while [ -z "$domainname" ]; do
            echo 'Nenhuma opção digitada, favor digitar uma opção válida:'
            read domainname
        done
    fi

    # Verifica se a variável projectname não é "N" ou "n", ou seja, o usuário não recusou a criação do projeto.
    if [ "$projectname" != 'N' ] && [ "$projectname" != 'n' ]; then

        # Cria o diretório do projeto dentro de /var/www/, por exemplo: /var/www/meusite
        mkdir /var/www
        mkdir /var/www/$projectname

        # Define que o usuário e grupo www-data (padrão do Nginx/PHP) sejam os donos da pasta do projeto.
        chown -R "www-data:www-data" "/var/www/$projectname"

        # Cria as pastas sites-available e sites-enabled, no estilo do Apache, para separar arquivos de configuração de vhosts.
        mkdir /etc/nginx/sites-available
        mkdir /etc/nginx/sites-enabled

        # Substitui os placeholders DOMINIO e PROJETO no arquivo nginx.conf por seus respectivos valores (meusite.com.br, meusite, etc.).
        sed -i "s/DOMINIO/$domainname/g" nginx.conf
        sed -i "s/PROJETO/$projectname/g" nginx.conf

        # Copia o nginx.conf (já com os placeholders substituídos) para sites-available com o nome do domínio como nome de arquivo.
        cp nginx.conf "/etc/nginx/sites-available/$domainname.conf"

        # webp.conf: configuração do Nginx para suporte a WebP.
        cp webp.conf "/etc/nginx/conf.d/"

        # wp-cron-uploads: reajuste de permissões do diretório upload mensal
        cp wp-cron-uploads /etc/cron.d/

        # cron-certbot-renew: Executa o comando certbot renew no dia 1 de cada mês às 00:05.
        cp cron-certbot-renew /etc/cron.d/

        # verificar-certificados-ssl.sh: Esse script verifica se os certificados SSL dos domínios configurados no Nginx estão prestes a expirar.
        cp verificar-certificados-ssl.sh /opt/scripts/

        # cron-conversao-webp: Converter imagens recém-modificadas para WebP a cada 3 minutos
        cp cron-conversao-webp /etc/cron.d/

        # converte_webp_3min.sh: Este script busca por imagens recém-criadas ou modificadas no diretório /uploads de sites WordPress
        cp converte_webp_3min.sh /opt/scripts/

        # converte-todos-para-webp.sh: Este script converte todas as imagens de um diretório (como wp-content/uploads) para o formato .webp.
        cp converte-todos-para-webp.sh /opt/scripts/

        # Substitui o placeholder TROCADOMAIN pelo domínio informado + versão com www
        sed -i -r "s/TROCADOMAIN/$domainname www.$domainname/" "/etc/nginx/sites-available/$domainname.conf"

        # Substitui o placeholder TROCAPROJECT pelo caminho completo do diretório do projeto
        sed -i -r "s/TROCAPROJECT/ \/var\/www\/$projectname/" "/etc/nginx/sites-available/$domainname.conf"

        # Cria um link simbólico em sites-enabled para ativar o virtual host
        ln -s "/etc/nginx/sites-available/$domainname.conf" "/etc/nginx/sites-enabled/$domainname.conf"
    fi

    # Comenta a diretiva log_format no nginx.conf (caso esteja ativa), desabilitando o formato de log global
    sed -i -r "s/log_format /#log_format/g" "/etc/nginx/nginx.conf"

    # Comenta a diretiva access_log no nginx.conf, evitando logs globais se vhosts cuidarem disso
    sed -i -r "s/access_log /#access_log/g" "/etc/nginx/nginx.conf"

    # Detecta quantos núcleos de CPU estão disponíveis para configurar os workers
    variavel=$(cat /proc/cpuinfo | grep processor | wc -l)

    # Define o número de conexões por worker (usado para cálculo de worker_connections)
    variavel2=1024

    # Adiciona no início do nginx.conf a diretiva worker_rlimit_nofile para permitir mais arquivos abertos por worker
    sed -i '1s/^/worker_rlimit_nofile 65535;\n/' /etc/nginx/nginx.conf

    # Altera worker_processes para o número de CPUs detectadas, otimizando paralelismo
    sed -i "s/worker_processes  1/worker_processes $variavel/g" /etc/nginx/nginx.conf

    # Calcula o total de conexões possíveis (núcleos × 1024)
    resultado=$(($variavel * $variavel2))

    # Altera worker_connections para suportar mais conexões simultâneas
    sed -i "s/worker_connections  1024/worker_connections $resultado/g" /etc/nginx/nginx.conf

    # Comenta qualquer linha que contenha a palavra "status" (útil para ocultar endpoints como /nginx_status)
    sed -i -r "/status/s/ /#/" "/etc/nginx/nginx.conf"

    # Comenta qualquer linha que contenha "http_user_agent" (pode desabilitar bloqueios customizados)
    sed -i -r "/http_user_agent/s/ /#/" "/etc/nginx/nginx.conf"

    # Insere o include de vhosts (estilo Apache) no bloco http
    sed -i -r "s/http .*/ http { \n include \/etc\/nginx\/sites-enabled\/*; /" "/etc/nginx/nginx.conf"

    # Altera o usuário do processo do Nginx de nginx para www-data (padrão do PHP-FPM no Ubuntu)
    sed -i 's/user  nginx/user  www-data/g' /etc/nginx/nginx.conf

    # Verifica se o include dos vhosts já existe, e se não existir, adiciona após o comentário #gzip
    if ! egrep 'sites-enabled' /etc/nginx/nginx.conf; then
        sed -i -r '/#gzip/ a include \/etc\/nginx\/sites-enabled\/*; ' "/etc/nginx/nginx.conf"
    fi

    # Cria ou sobrescreve o arquivo gzip.conf com diretivas otimizadas de compressão Gzip para performance e SEO
    echo 'gzip  on;
      gzip_disable "msie6";
      gzip_vary on;
      gzip_proxied any;
      gzip_comp_level 6;
      gzip_buffers 16 8k;
      gzip_http_version 1.1;
      gzip_min_length 256;
      gzip_types application/javascript text/plain text/css application/json application/x-javascript text/xml application/xml application/xml+rss text/javascript application/vnd.ms-fontobject application/x-font-ttf font/opentype image/svg+xml image/x-icon;' >/etc/nginx/conf.d/gzip.conf

fi
