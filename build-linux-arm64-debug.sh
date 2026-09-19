#!/usr/bin/env bash
set -Eeuo pipefail

RID="linux-arm64"
CONFIG="Debug"
OUT="$PWD/artifacts/neo-linux-arm64-debug"

echo "=== Ryujinx Neo Linux ARM64 Debug Build ==="
echo "Arquitetura do runner:"
uname -m
echo

# Localiza o projeto principal
PROJECT=""

for p in \
    "src/Ryujinx/Ryujinx.csproj" \
    "src/Ryujinx.Ava/Ryujinx.Ava.csproj" \
    "Ryujinx/Ryujinx.csproj"
do
    if [[ -f "$p" ]]; then
        PROJECT="$p"
        break
    fi
done

if [[ -z "$PROJECT" ]]; then
    echo "Projeto padrão não encontrado. Procurando..."

    while IFS= read -r p; do
        if grep -q "<OutputType>" "$p"; then
            PROJECT="$p"
            break
        fi
    done < <(find . -type f -name "*.csproj" | sort)
fi

if [[ -z "$PROJECT" ]]; then
    echo "ERRO: não encontrei o projeto executável."
    find . -name "*.csproj"
    exit 1
fi

echo "Projeto:"
echo "$PROJECT"
echo

rm -rf "$OUT"
mkdir -p "$OUT"

echo "=== Restore ==="

dotnet restore "$PROJECT" \
    -r "$RID"

echo
echo "=== Publish ==="

dotnet publish "$PROJECT" \
    -c "$CONFIG" \
    -r "$RID" \
    --self-contained true \
    -o "$OUT" \
    -p:DebugSymbols=true \
    -p:DebugType=portable \
    -p:PublishSingleFile=false \
    -p:PublishTrimmed=false \
    -p:PublishReadyToRun=false

echo
echo "=== Informações da build ==="

{
    echo "branch=$(git branch --show-current)"
    echo "commit=$(git rev-parse HEAD)"
    echo "architecture=$(uname -m)"
    echo "runtime=$RID"
    echo "configuration=$CONFIG"
    echo "project=$PROJECT"
    echo
    dotnet --info
} > "$OUT/BUILD-INFO.txt"

echo
echo "=== Criando pacote ==="

cd "$(dirname "$OUT")"

tar -czf \
    "Ryujinx-Neo-linux-arm64-Debug.tar.gz" \
    "$(basename "$OUT")"

echo
echo "================================="
echo "BUILD FINALIZADA"
echo "================================="
echo
echo "Pacote:"
echo "$PWD/Ryujinx-Neo-linux-arm64-Debug.tar.gz"
