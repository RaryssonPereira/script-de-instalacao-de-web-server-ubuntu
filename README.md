# 🛠️ Webserver Setup com Shell Script

Este projeto contém um script escrito em **Shell Script (Bash)** para realizar configurações iniciais em servidores Linux, preparando-os para funcionar como servidores web. Entre as tarefas realizadas estão a instalação automatizada de ferramentas essenciais como **Nginx**, **PHP**, **MySQL (Percona)**, **Redis**, **Elasticsearch**, **Fail2ban** e ajustes básicos de segurança e desempenho.

🎯 O objetivo principal é servir como **base de aprendizado para estudantes e iniciantes** em administração de servidores, automação com Bash e boas práticas de provisionamento de ambientes web.

---

## 📜 Sobre o script

**Arquivo**: `webserver-setup.sh`  
**Criado por**: [Rarysson](https://github.com/RaryssonPereira)  
**Objetivo**: Automatizar a instalação e configuração de serviços web essenciais com ênfase em segurança, otimização de desempenho e monitoramento básico.

---

## 📌 Funcionalidades

- Detecta automaticamente o **IP público** do servidor  
- Realiza consulta **DNS reversa (PTR)** para facilitar ajuste do hostname  
- Instalação opcional dos seguintes serviços:
  - **Nginx** (Servidor web)
  - **PHP 8.2** (PHP-FPM e extensões)
  - **MySQL (Percona Server)**
  - **Redis**
  - **Elasticsearch**
  - **Fail2ban** (Proteção contra tentativas de intrusão)
- Ajustes no **SSH** para melhor segurança
- Otimizações no kernel do Linux via **sysctl**
- Instalação e ativação do **Zabbix Agent** para monitoramento

---

## ⚙️ Pré-requisitos

- ✅ Sistema operacional Linux baseado em Debian/Ubuntu  
- ✅ Permissões de root (ou uso do `sudo`)  
- ✅ Ferramentas instaladas:

  - `curl`, `wget`
  - `awk`, `sed`, `tr`, `hostnamectl`
  - *(opcional)* `zabbix-agent`

---

## 📂 Arquivos afetados pelo script

- `/etc/hostname`  
- `/etc/hosts`  
- `/etc/sysctl.conf`  
- `/etc/ssh/sshd_config`  
- `/etc/zabbix/zabbix_agentd.conf` *(se instalado)*  
- `/var/log/setup_base.log` *(log de instalação gerado)*

---

## 🚨 Avisos importantes

- O **hostname antigo pode ser sobrescrito** conforme escolha do usuário  
- O **PTR (reverso) do IP precisa estar corretamente configurado** para detecção automática  
- O script instala versões específicas de pacotes; verifique compatibilidade antes de executar em produção
- É recomendável executar inicialmente em ambientes de teste ou máquinas virtuais

---

## 🧠 Exemplos de aprendizado

- Automatizar tarefas com comandos Bash  
- Instalar e configurar servidores web  
- Realizar ajustes seguros com `sed` e manipular arquivos de configuração  
- Otimizar performance e segurança do sistema Linux  
- Instalar e integrar agentes de monitoramento (Zabbix)

---

## ▶️ Como usar

### 1. Torne o script executável

```bash
chmod +x webserver-setup.sh
```

### 2. Execute com permissões de root

```bash
sudo ./webserver-setup.sh
```

---

## 🧪 Sugestão

> Você pode adaptar trechos do script para incluir ou excluir serviços específicos conforme suas necessidades de aprendizado.

---

## ❤️ Contribuindo

Sinta-se à vontade para contribuir com este projeto:
- Relatando bugs  
- Sugerindo melhorias  
- Criando novas funcionalidades

Abra uma **Issue** ou envie um **Pull Request** ✨

---

## 📜 Licença

Distribuído sob a licença **MIT**.  
Você pode **usar, modificar e compartilhar** como quiser!

---

## ✨ Créditos

Criado com carinho por **Rarysson**,  
pensado para quem está começando e quer aprender Linux de forma prática, útil e automatizada. 🚀

