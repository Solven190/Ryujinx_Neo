#!/usr/bin/env bash
set -Eeuo pipefail

RID="linux-arm64"
CONFIG="Debug"
OUT="$PWD/artifacts/neo-linux-arm64-debug"

MEM_FILE="src/Ryujinx.HLE/Loaders/Processes/ProcessLoaderHelper.cs"

echo "========================================"
echo " Ryujinx Neo Linux ARM64 Debug Build"
echo "========================================"

echo
echo "Arquitetura:"
uname -m
echo

# ============================================================
# FIX NEOV2-MEMLIMIT
# ============================================================

echo "=== Corrigindo NEOV2-MEMLIMIT ==="

if [[ ! -f "$MEM_FILE" ]]; then
    echo "ERRO: arquivo não encontrado:"
    echo "$MEM_FILE"
    exit 1
fi

# Guarda cópia apenas para diagnóstico no runner.
cp "$MEM_FILE" "${MEM_FILE}.before-memfix"

python3 <<'PY'
from pathlib import Path
import re
import sys

path = Path("src/Ryujinx.HLE/Loaders/Processes/ProcessLoaderHelper.cs")

text = path.read_text()

if "NEOV2-MEMLIMIT" not in text:
    print("ERRO: marcador NEOV2-MEMLIMIT não encontrado.")
    sys.exit(1)

original = text

lines = text.splitlines(True)

marker_indexes = [
    i for i, line in enumerate(lines)
    if "NEOV2-MEMLIMIT" in line
]

print("Marcador NEOV2-MEMLIMIT encontrado nas linhas:")
for i in marker_indexes:
    print(f"  {i + 1}: {lines[i].strip()}")

changed = False

# ------------------------------------------------------------
# Procura uma declaração/atribuição relacionada a "slack"
# contendo exatamente 12 GiB.
#
# Exemplos cobertos:
#
# 12L * 1024 * 1024 * 1024
# 12UL * 1024 * 1024 * 1024
# 12 * 1024L * 1024 * 1024
# 12L << 30
# 12UL << 30
# 0x300000000
# ------------------------------------------------------------

patterns = [
    (
        re.compile(
            r'(?i)(\bslack\b[^\n=]*=\s*)'
            r'12(?P<suffix>UL|LU|L|U)?'
            r'\s*\*\s*1024(?:[UL]*)'
            r'\s*\*\s*1024(?:[UL]*)'
            r'\s*\*\s*1024(?:[UL]*)'
        ),
        lambda m: m.group(1) + (
            "0UL" if "U" in (m.group("suffix") or "") else "0L"
        )
    ),

    (
        re.compile(
            r'(?i)(\bslack\b[^\n=]*=\s*)'
            r'12(?P<suffix>UL|LU|L|U)?'
            r'\s*<<\s*30'
        ),
        lambda m: m.group(1) + (
            "0UL" if "U" in (m.group("suffix") or "") else "0L"
        )
    ),

    (
        re.compile(
            r'(?i)(\bslack\b[^\n=]*=\s*)'
            r'0x300000000(?:UL|LU|L|U)?'
        ),
        lambda m: m.group(1) + "0L"
    ),
]

new_lines = []

for idx, line in enumerate(lines):

    new_line = line

    # Só alteramos linhas relacionadas explicitamente a slack.
    if "slack" in line.lower():

        for pattern, replacement in patterns:
            candidate, count = pattern.subn(replacement, new_line)

            if count:
                print()
                print(f"CORRIGINDO LINHA {idx + 1}")
                print("ANTES:")
                print(new_line.rstrip())
                print()
                print("DEPOIS:")
                print(candidate.rstrip())

                new_line = candidate
                changed = True
                break

    new_lines.append(new_line)

text = "".join(new_lines)

# ------------------------------------------------------------
# Fallback:
# caso o código use outro nome de variável, procura 12 GiB
# perto do marcador NEOV2-MEMLIMIT.
# ------------------------------------------------------------

if not changed:

    print()
    print("Não encontrei uma variável chamada slack.")
    print("Tentando localizar 12 GiB perto do marcador...")

    lines = text.splitlines(True)

    for marker in marker_indexes:

        start = max(0, marker - 80)
        end = min(len(lines), marker + 80)

        for idx in range(start, end):

            line = lines[idx]

            replacements = [
                (
                    r'12UL\s*\*\s*1024UL?\s*\*\s*1024UL?\s*\*\s*1024UL?',
                    '0UL'
                ),
                (
                    r'12L\s*\*\s*1024L?\s*\*\s*1024L?\s*\*\s*1024L?',
                    '0L'
                ),
                (
                    r'12\s*\*\s*1024L\s*\*\s*1024\s*\*\s*1024',
                    '0L'
                ),
                (
                    r'12UL?\s*<<\s*30',
                    '0UL'
                ),
                (
                    r'12L\s*<<\s*30',
                    '0L'
                ),
                (
                    r'0x300000000UL?',
                    '0UL'
                ),
                (
                    r'0x300000000L?',
                    '0L'
                ),
            ]

            for pattern, replacement in replacements:

                candidate, count = re.subn(
                    pattern,
                    replacement,
                    line
                )

                if count:

                    print()
                    print(f"CORRIGINDO LINHA {idx + 1}")
                    print("ANTES:")
                    print(line.rstrip())

                    print()
                    print("DEPOIS:")
                    print(candidate.rstrip())

                    lines[idx] = candidate
                    changed = True
                    break

            if changed:
                break

        if changed:
            break

    text = "".join(lines)

# ------------------------------------------------------------
# Segurança: não gera build se não conseguiu corrigir.
# ------------------------------------------------------------

if not changed:

    print()
    print("ERRO:")
    print("Não consegui localizar automaticamente o slack de 12 GiB.")
    print()
    print("Contexto do NEOV2-MEMLIMIT:")

    lines = original.splitlines()

    for marker in marker_indexes:
        start = max(0, marker - 25)
        end = min(len(lines), marker + 26)

        for i in range(start, end):
            print(f"{i + 1:4}: {lines[i]}")

    sys.exit(1)

path.write_text(text)

print()
print("NEOV2-MEMLIMIT corrigido com sucesso.")
PY

echo
echo "=== Verificação da correção ==="

grep -n -i \
    -E "NEOV2-MEMLIMIT|slack" \
    "$MEM_FILE" \
    | head -30 || true

echo
echo "=== Selecionando projeto ==="

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

    echo "ERRO: projeto executável não encontrado."

    find . \
        -maxdepth 4 \
        -type f \
        -name '*.csproj' \
        | sort

    exit 1
fi

echo "Projeto:"
echo "$PROJECT"

echo
echo "=== Limpando build anterior ==="

rm -rf "$OUT"
mkdir -p "$OUT"

echo
echo "=== Restore ARM64 ==="

dotnet restore \
    "$PROJECT" \
    -r "$RID"

echo
echo "=== Publish ARM64 Debug ==="

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

    echo "ERRO: Ryujinx não foi gerado."

    find "$OUT" \
        -maxdepth 1 \
        -type f \
        | sort \
        | head -100

    exit 1
fi

chmod +x "$OUT/Ryujinx"

file "$OUT/Ryujinx"

echo

readelf -h "$OUT/Ryujinx" \
    | grep -E 'Class|Machine' \
    || true

echo
echo "=== BUILD-INFO ==="

{
    echo "branch=$(git branch --show-current)"
    echo "commit=$(git rev-parse HEAD)"
    echo "architecture=$(uname -m)"
    echo "runtime=$RID"
    echo "configuration=$CONFIG"
    echo "project=$PROJECT"
    echo "neo_memlimit_fix=12GiB_slack_disabled"
    echo

    dotnet --info

} > "$OUT/BUILD-INFO.txt"

echo
echo "=== Criando pacote ==="

PACKAGE="$PWD/artifacts/Ryujinx-Neo-linux-arm64-Debug.tar.gz"

rm -f "$PACKAGE"

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
