#! /bin/bash

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

    fi

fi
