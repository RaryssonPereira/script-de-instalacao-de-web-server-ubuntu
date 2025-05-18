#!/bin/bash

# === SCRIPT: converte-todos-para-webp.sh ===
# Este script converte todas as imagens de um diretório (como wp-content/uploads) para o formato .webp.
# Ele cria ou atualiza a versão .webp apenas se ela não existir ou se estiver desatualizada em relação à imagem original.
# Ideal para uso manual em sites WordPress após migração ou como manutenção periódica.

# ---------------------------------------------------------
# ETAPA 1: Verifica se o utilitário 'cwebp' está instalado
# ---------------------------------------------------------

# Verifica se o comando 'cwebp' está disponível no sistema
if ! command -v cwebp &> /dev/null; then
    echo "🔧 O utilitário 'cwebp' não está instalado. Instalando automaticamente..."

    # Atualiza a lista de pacotes e instala o pacote 'webp', que contém o comando cwebp
    sudo apt update && sudo apt install -y webp
fi

# ---------------------------------------------------------
# ETAPA 2: Valida o argumento passado para o script
# ---------------------------------------------------------

# Se o primeiro argumento ($1) estiver vazio ou não for um diretório válido
if [ -z "$1" ] || [ ! -d "$1" ]; then
    echo "❌ Por favor, forneça um diretório válido como argumento."
    echo "Uso correto: bash converte-todos-para-webp.sh /var/www/site/wp-content/uploads"
    exit 1  # Encerra o script com código de erro
fi

# Salva o diretório informado na variável DIRETORIO
DIRETORIO="$1"

# Mostra qual diretório será processado
echo "✅ Iniciando conversão no diretório: $DIRETORIO"

# ---------------------------------------------------------
# ETAPA 3: Busca e armazena todas as imagens do diretório
# ---------------------------------------------------------

# Cria um arquivo temporário para guardar a lista de imagens encontradas
arquivo_de_imagens=$(mktemp /tmp/webp_todos.XXXXXX)

# Busca arquivos com extensões .png, .jpg, .jpeg e .gif, ignorando maiúsculas/minúsculas
# A opção -type f garante que só arquivos sejam listados (não diretórios)
find "$DIRETORIO" -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.gif' \) > "$arquivo_de_imagens"

# Conta quantas imagens foram encontradas
quantidade_de_imagens=$(wc -l < "$arquivo_de_imagens")

# Inicializa um contador para mostrar o progresso
posicao_atual=0

# ---------------------------------------------------------
# ETAPA 4: Processa imagem por imagem
# ---------------------------------------------------------

# Lê o arquivo linha por linha (cada linha contém o caminho completo de uma imagem)
while IFS= read -r arquivo; do
    # Incrementa a posição atual no progresso
    posicao_atual=$((posicao_atual + 1))

    # Extrai o nome do arquivo (sem o caminho)
    nome_arquivo=$(basename "$arquivo")

    # Define o caminho do arquivo .webp correspondente
    arquivo_webp="${arquivo}.webp"

    # Se o arquivo .webp já existe
    if [ -e "$arquivo_webp" ]; then
        # Compara datas: se o arquivo original for mais novo que o .webp
        if [ "$arquivo" -nt "$arquivo_webp" ]; then
            echo -e '\n########################################################################'
            echo "📸 [$posicao_atual/$quantidade_de_imagens] Atualizando versão webp de $nome_arquivo"
            cwebp "$arquivo" -o "$arquivo_webp"
            echo '########################################################################'
        else
            # Se o .webp já está atualizado, exibe aviso e segue para a próxima imagem
            echo "✔️ [$posicao_atual/$quantidade_de_imagens] Versão webp de $nome_arquivo já está atualizada."
        fi
    else
        # Se o arquivo .webp ainda não existe, cria a nova versão
        echo -e '\n########################################################################'
        echo "🆕 [$posicao_atual/$quantidade_de_imagens] Criando versão webp de $nome_arquivo"
        cwebp "$arquivo" -o "$arquivo_webp"
        echo '########################################################################'
    fi

done < "$arquivo_de_imagens"

# ---------------------------------------------------------
# ETAPA 5: Limpeza final
# ---------------------------------------------------------

# Remove o arquivo temporário com a lista de imagens
rm -f "$arquivo_de_imagens"

# Exibe mensagem de conclusão
echo "✅ Conversão finalizada com sucesso."