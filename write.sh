#! /bin/bash

# Se o usuário escolheu instalar PhP (INSTALL_PHP="S"), ele instala silenciosamente o PHP 8.2 (FPM), com várias extensões importantes.
if [[ "$INSTALL_PHP" == "S" ]]; then

    # Instala o núcleo do PHP 8.2 (cli, fpm, cgi) e várias extensões úteis para CMSs e APIs.
    # As opções --force-confdef e --force-confold evitam prompts interativos de conflito de configuração, usando as versões antigas.
    sudo apt-get install -qq -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" php8.2-cli php8.2-common
    sudo apt-get install -qq -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" php8.2-fpm php8.2-cgi
    sudo apt-get install -qq -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" php8.2-mysql php8.2-bcmath php8.2-curl php8.2-gd php8.2-mbstring php8.2-redis php8.2-xml php8.2-soap php8.2-zip

    # Otimizando o PHP-FPM (php-fpm.conf e www.conf). Evita falhas completas no pool PHP-FPM reiniciando os workers em caso de pane.
    # - emergency_restart_threshold = 10: se 10 processos falharem rapidamente, reinicia.
    sed -i -r "s/^.emergency_restart_threshold.*$/emergency_restart_threshold = 10/" /etc/php/8.2/fpm/php-fpm.conf
    # - emergency_restart_interval = 1m: considera esse intervalo para o monitoramento.
    sed -i -r "s/^.emergency_restart_interval.*$/emergency_restart_interval = 1m/" /etc/php/8.2/fpm/php-fpm.conf
    # - process_control_timeout = 10s: evita travamentos ao tentar matar processos zumbis.
    sed -i -r "s/^.process_control_timeout.*$/process_control_timeout = 10s/" /etc/php/8.2/fpm/php-fpm.conf

    # Ajustes de performance para o gerenciador de processos do FPM (modo dynamic).
    # - pm.max_children = 180: número máximo de processos simultâneos.
    sed -i -r "s/^pm.max_children.*$/pm.max_children = 180/" /etc/php/8.2/fpm/pool.d/www.conf
    # -
    sed -i -r "s/^pm.start_servers.*$/pm.start_servers = 25/" /etc/php/8.2/fpm/pool.d/www.conf
    # -
    sed -i -r "s/^pm.min_spare_servers.*$/pm.min_spare_servers = 10/" /etc/php/8.2/fpm/pool.d/www.conf
    # -
    sed -i -r "s/^pm.max_spare_servers.*$/pm.max_spare_servers = 30/" /etc/php/8.2/fpm/pool.d/www.conf
    # - request_terminate_timeout = 60s: se uma requisição demorar mais de 60s, mata o processo.
    sed -i -r "s/^.request_terminate_timeout.*$/request_terminate_timeout = 60s/" /etc/php/8.2/fpm/pool.d/www.conf

    # Altera o FPM para escutar por IP/porta (127.0.0.1:9000) em vez de socket Unix (.sock), o que facilita integração com Nginx via TCP.
    sed -i '/listen = \/run/c\listen = 127.0.0.1:9000' /etc/php/8.2/fpm/pool.d/www.conf

    # Endurecendo a segurança do PHP, desativa funções perigosas que podem ser exploradas em RCEs, shells remotos etc.
    sed -i 's/disable_functions =/disable_functions = show_source, system, shell_exec, passthru, exec, phpinfo, popen, proc_open, allow_url_fopen, symlink/g' /etc/php/8.2/fpm/php.ini

    # Path de sessões como /tmp.
    sed -i -r "s/^;session.save_path.*$/session.save_path=\/tmp/" /etc/php/8.2/fpm/php.ini

    # Tempo de vida da sessão como 8h.
    sed -i -r "s/^session.gc_maxlifetime.*$/session.gc_maxlifetime = 28800/" /etc/php/8.2/fpm/php.ini

    # Nome customizado do cookie de sessão para evitar conflitos (RARYSESSID).
    sed -i -r "s/^session.name.*$/session.name = RARYSESSID/" /etc/php/8.2/fpm/php.ini

    # Aumenta limites de arquivos por processo, eleva o número de arquivos que processos PHP/Nginx podem abrir — importante para alto tráfego e uploads.
    echo "*       soft    nofile  20000
*       hard    nofile  40000" >>/etc/security/limits.conf

    # Copia o cron de limpeza de sessões PHP para /etc/cron.d/, apenas se ainda não estiver presente.
    [[ ! -f /etc/cron.d/php-session-cleaner ]] && cp php-session-cleaner /etc/cron.d/

    # Reinicia o PHP-FPM para aplicar tudo.
    service php8.2-fpm restart
fi
