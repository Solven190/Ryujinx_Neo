#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$(realpath "$0")")"

RID="linux-arm64"
CONFIG="Debug"
OUT="$PWD/artifacts/neo-linux-arm64-debug"

echo "=== Ryujinx Neo Linux ARM64 Debug Build ==="
echo "Arquitetura do runner:"
uname -m
echo

PROJECT="src/Ryujinx/Ryujinx.csproj"
test -f "$PROJECT"

echo "Projeto:"
echo "$PROJECT"
echo

rm -rf "$OUT"
mkdir -p "$OUT"

echo "=== Clean ==="
dotnet clean "$PROJECT" -c "$CONFIG" -r "$RID"

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

echo "=== Verificando assemblies, símbolos e runtime ARM64 ==="
for file in Ryujinx Ryujinx.dll Ryujinx.pdb Ryujinx.Common.dll Ryujinx.Common.pdb \
    Ryujinx.Graphics.Vulkan.dll Ryujinx.Graphics.Vulkan.pdb libcoreclr.so \
    libhostfxr.so libhostpolicy.so Ryujinx.runtimeconfig.json Ryujinx.deps.json; do
    test -s "$OUT/$file"
done
file "$OUT/Ryujinx" "$OUT/libcoreclr.so"
readelf -h "$OUT/Ryujinx" | grep -q 'Machine:.*AArch64'
readelf -h "$OUT/libcoreclr.so" | grep -q 'Machine:.*AArch64'
chmod +x "$OUT/Ryujinx" "$OUT/Ryujinx.sh"

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
