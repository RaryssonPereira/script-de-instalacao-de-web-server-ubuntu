#!/bin/bash

# === SCRIPT: converte_webp_antes_3min.sh ===
# Este script verifica imagens criadas ou modificadas nos últimos 3 minutos
# no diretório informado como argumento, e converte para .webp apenas se necessário.
# Ideal para execução via cron com foco em imagens recém-enviadas em /uploads.

# Verifica se o utilitário 'cwebp' está instalado. Se não estiver, instala automaticamente.
if ! command -v cwebp &>/dev/null; then
    echo " O pacote 'webp' não está instalado. Instalando automaticamente..."
    sudo apt update && sudo apt install -y webp
fi

# Define o diretório a ser processado com base no argumento passado ($1)
DIRETORIO="$1"

# Se o diretório não foi informado ou não existir, exibe erro e sai
if [ -z "$DIRETORIO" ] || [ ! -d "$DIRETORIO" ]; then
    echo " Diretório inválido ou não informado."
    echo "Uso: bash converte_webp_antes_3min.sh /var/www/site/wp-content/uploads/$(date +%Y)/$(date +%m)"
    exit 1
fi

# Cria um arquivo temporário para guardar a lista de imagens modificadas recentemente
arquivo_de_imagens=$(mktemp /tmp/webp_recentes.XXXXXX)

# Busca imagens modificadas nos últimos 3 minutos com extensões comuns (insensível a maiúsculas/minúsculas)
find "$DIRETORIO" -cmin -3 | grep -Ei '\.(png|jpg|jpeg|gif)$' >"$arquivo_de_imagens"

# Conta quantas imagens foram encontradas
quantidade_de_imagens=$(wc -l <"$arquivo_de_imagens")
posicao_atual=0

# Processa cada imagem encontrada
while IFS= read -r arquivo; do
    nome_arquivo=$(basename "$arquivo")
    posicao_atual=$((posicao_atual + 1))
    arquivo_webp="${arquivo}.webp"

    # Se já existe uma versão .webp
    if [ -e "$arquivo_webp" ]; then
        # E se a original for mais nova, atualiza o .webp
        if [ "$arquivo" -nt "$arquivo_webp" ]; then
            echo -e '\n########################################################################\n'
            echo " [$posicao_atual/$quantidade_de_imagens] Atualizando versão webp de $nome_arquivo"
            cwebp "$arquivo" -o "$arquivo_webp"
            echo '########################################################################\n'
        else
            # Já está atualizado
            echo "✔️ [$posicao_atual/$quantidade_de_imagens] $nome_arquivo já possui versão webp atualizada."
        fi
    else
        # Se não existe .webp, cria pela primeira vez
        echo -e '\n########################################################################\n'
        echo " [$posicao_atual/$quantidade_de_imagens] Criando versão webp de $nome_arquivo"
        cwebp "$arquivo" -o "$arquivo_webp"
        echo '########################################################################\n'
    fi
done <"$arquivo_de_imagens"

# Remove o arquivo temporário criado
rm -f "$arquivo_de_imagens"
