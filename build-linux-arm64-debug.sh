#!/usr/bin/env bash
set -Eeuo pipefail

RID="linux-arm64"
CONFIG="Debug"
OUT="$PWD/artifacts/neo-linux-arm64-debug"
PACKAGE="$PWD/artifacts/Ryujinx-Neo-linux-arm64-Debug.tar.gz"

MEM_FILE="src/Ryujinx.HLE/Loaders/Processes/ProcessLoaderHelper.cs"

echo "========================================"
echo " Ryujinx Neo Linux ARM64 Debug Build"
echo "========================================"

echo
echo "Arquitetura:"
uname -m

echo
echo "=== Corrigindo NEOV2-MEMLIMIT ==="

if [[ ! -f "$MEM_FILE" ]]; then
    echo "ERRO: arquivo não encontrado:"
    echo "$MEM_FILE"
    exit 1
fi

python3 <<'PY'
from pathlib import Path
import re
import sys

path = Path("src/Ryujinx.HLE/Loaders/Processes/ProcessLoaderHelper.cs")
text = path.read_text()

if "NEOV2-MEMLIMIT" not in text:
    print("ERRO: marcador NEOV2-MEMLIMIT não encontrado.")
    sys.exit(1)

print("Linhas atuais relacionadas à memória:")
for i, line in enumerate(text.splitlines(), 1):
    if (
        "MemorySlack" in line
        or "memoryLimit" in line
        or "NEOV2-MEMLIMIT" in line
        or "applicationRgSize" in line
    ):
        print(f"{i}: {line}")

original = text

# Caso mais provável:
# ulong memoryLimit = applicationRgSize + context.MemorySlack;
patterns = [
    (
        r'(\bmemoryLimit\s*=\s*)applicationRgSize\s*\+\s*context\.MemorySlack(\s*;)',
        r'\1applicationRgSize\2'
    ),
    (
        r'(\b(?:ulong|long|nuint|nint|UInt64|Int64)\s+memoryLimit\s*=\s*)'
        r'applicationRgSize\s*\+\s*context\.MemorySlack(\s*;)',
        r'\1applicationRgSize\2'
    ),
]

changed = False

for pattern, replacement in patterns:
    text, count = re.subn(pattern, replacement, text, count=1)
    if count:
        changed = True
        break

# Fallback: se a soma estiver diretamente no SetLimitValue.
if not changed:
    old = "applicationRgSize + context.MemorySlack"

    if old in text:
        text = text.replace(old, "applicationRgSize", 1)
        changed = True

if not changed:
    print()
    print("ERRO: não encontrei a expressão esperada:")
    print("applicationRgSize + context.MemorySlack")
    print()
    print("Nenhuma alteração foi feita.")
    sys.exit(1)

path.write_text(text)

print()
print("=== Correção aplicada ===")

for i, line in enumerate(text.splitlines(), 1):
    if (
        "MemorySlack" in line
        or "memoryLimit" in line
        or "NEOV2-MEMLIMIT" in line
        or "applicationRgSize" in line
    ):
        print(f"{i}: {line}")

if text == original:
    print("ERRO: arquivo não foi alterado.")
    sys.exit(1)

print()
print("NEOV2-MEMLIMIT corrigido.")
PY

echo
echo "=== Verificação final do patch ==="

grep -n -E \
    "applicationRgSize|memoryLimit|MemorySlack|NEOV2-MEMLIMIT" \
    "$MEM_FILE" \
    | head -40 || true

echo
echo "=== Selecionando projeto executável ==="

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
    while IFS= read -r p; do
        if grep -Eq \
            '<OutputType>[[:space:]]*(Exe|WinExe)[[:space:]]*</OutputType>' \
            "$p" 2>/dev/null
        then
            PROJECT="$p"
            break
        fi
    done < <(
        find . \
            -maxdepth 4 \
            -type f \
            -iname '*Ryujinx*.csproj' \
            | sort
    )
fi

if [[ -z "$PROJECT" ]]; then
    echo "ERRO: não consegui localizar o projeto executável."
    echo
    echo "Projetos encontrados:"
    find . -maxdepth 4 -type f -name '*.csproj' | sort
    exit 1
fi

echo "Projeto selecionado:"
echo "$PROJECT"

echo
echo "=== Limpando saída anterior ==="

rm -rf "$OUT"
rm -f "$PACKAGE"

mkdir -p "$OUT"

echo
echo "=== Restore ARM64 ==="

dotnet restore \
    "$PROJECT" \
    -r "$RID"

echo
echo "=== Publish Linux ARM64 Debug ==="

dotnet publish \
    "$PROJECT" \
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
echo "=== Verificando executável ==="

if [[ ! -f "$OUT/Ryujinx" ]]; then
    echo "ERRO: executável Ryujinx não foi gerado."
    echo
    find "$OUT" -maxdepth 1 -type f | sort | head -100
    exit 1
fi

chmod +x "$OUT/Ryujinx"

file "$OUT/Ryujinx"

echo
echo "=== Cabeçalho ELF ==="

readelf -h "$OUT/Ryujinx" \
    | grep -E 'Class|Machine' \
    || true

echo
echo "=== Criando BUILD-INFO.txt ==="

{
    echo "branch=$(git branch --show-current)"
    echo "commit=$(git rev-parse HEAD)"
    echo "architecture=$(uname -m)"
    echo "runtime=$RID"
    echo "configuration=$CONFIG"
    echo "project=$PROJECT"
    echo "neo_memlimit_fix=MemorySlack_removed_from_memoryLimit"
    echo
    dotnet --info
} > "$OUT/BUILD-INFO.txt"

echo
echo "=== Criando pacote ==="

tar \
    -C "$PWD/artifacts" \
    -czf "$PACKAGE" \
    neo-linux-arm64-debug

echo
echo "========================================"
echo " BUILD FINALIZADA"
echo "========================================"

echo
echo "Executável:"
echo "$OUT/Ryujinx"

echo
echo "Pacote:"
echo "$PACKAGE"

echo
ls -lh "$PACKAGE"
