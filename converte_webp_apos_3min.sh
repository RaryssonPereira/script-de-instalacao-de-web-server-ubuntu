#!/bin/bash

# === SCRIPT: converte_webp_apos_3min.sh ===
# Este script converte imagens para WebP que foram modificadas há MAIS de 3 minutos,
# evitando conflitos com uploads recentes já tratados por outro script via cron.
# Ideal para execução diária no diretório de uploads do WordPress.

# ⚙️ Verifica se o utilitário 'cwebp' está instalado. Se não estiver, instala automaticamente.
if ! command -v cwebp &>/dev/null; then
    echo "🔧 O pacote 'webp' não está instalado. Instalando automaticamente..."
    sudo apt update && sudo apt install -y webp
fi

# 📁 Define o diretório a ser processado com base no argumento passado ($1)
DIRETORIO="$1"

# ⚠️ Se o diretório não foi informado ou não existir, exibe erro e sai
if [ -z "$DIRETORIO" ] || [ ! -d "$DIRETORIO" ]; then
    echo "❌ Diretório inválido ou não informado."
    echo "Uso: bash converte_webp_apos_3min.sh /var/www/site/wp-content/uploads/$(date +%Y)/$(date +%m)"
    exit 1
fi

# 🛠 Cria um arquivo temporário para guardar a lista de imagens modificadas há mais de 3 minutos
ARQUIVO_DE_IMAGENS=$(mktemp /tmp/webp_apos3min.XXXXXX)

# 🔍 Busca imagens com mais de 3 minutos (extensões insensíveis a maiúsculas/minúsculas)
find "$DIRETORIO" -type f -cmin +3 \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.gif" \) >"$ARQUIVO_DE_IMAGENS"

# 📊 Conta quantas imagens foram encontradas
QUANTIDADE=$(wc -l <"$ARQUIVO_DE_IMAGENS")
POSICAO=0

# 🔁 Processa cada imagem encontrada
while IFS= read -r ARQUIVO; do
    ((POSICAO++))
    NOME_ARQUIVO=$(basename "$ARQUIVO")
    DESTINO_WEBP="${ARQUIVO}.webp"

    if [ -e "$DESTINO_WEBP" ]; then
        if [ "$ARQUIVO" -nt "$DESTINO_WEBP" ]; then
            echo -e '\n########################################################################\n'
            echo "📸 [$POSICAO/$QUANTIDADE] Atualizando versão webp de $NOME_ARQUIVO"
            cwebp "$ARQUIVO" -o "$DESTINO_WEBP"
            echo -e '########################################################################\n'
        else
            echo "✔️ [$POSICAO/$QUANTIDADE] $NOME_ARQUIVO já possui versão webp atualizada."
        fi
    else
        echo -e '\n########################################################################\n'
        echo "🆕 [$POSICAO/$QUANTIDADE] Criando versão webp de $NOME_ARQUIVO"
        cwebp "$ARQUIVO" -o "$DESTINO_WEBP"
        echo -e '########################################################################\n'
    fi
done <"$ARQUIVO_DE_IMAGENS"

# 🧹 Remove o arquivo temporário criado
rm -f "$ARQUIVO_DE_IMAGENS"

echo "✅ Conversão concluída."
