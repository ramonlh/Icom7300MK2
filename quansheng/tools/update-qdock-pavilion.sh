#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REMOTE="${QDOCK_PAVILION_SSH:-ramon@192.168.1.78}"
REMOTE_DIR="${QDOCK_PAVILION_DIR:-/home/ramon/qdock-readonly}"

echo "Sincronizando Quansheng con ${REMOTE}:${REMOTE_DIR}"
rsync -av \
    --exclude build/ \
    --exclude reference/ \
    --exclude '*.raw' \
    --exclude .git/ \
    "${SOURCE_DIR}/" "${REMOTE}:${REMOTE_DIR}/"

echo "Compilando y probando en el Pavilion"
ssh "${REMOTE}" bash -s -- "${REMOTE_DIR}" <<'REMOTE_SCRIPT'
set -euo pipefail
project_dir="$1"
cd "${project_dir}"
cmake -S . -B build -DQDOCK_SERIAL=ON
cmake --build build -j2
ctest --test-dir build --output-on-failure

launcher_dir="${HOME}/.local/share/applications"
desktop_dir="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
if [[ -z "${desktop_dir}" ]]; then
    desktop_dir="${HOME}/Desktop"
fi
mkdir -p "${launcher_dir}"
mkdir -p "${desktop_dir}"
chmod 755 tools/start-qdock-pavilion-telemetry.sh
install -m 644 tools/qdock-server-gui.desktop \
    "${launcher_dir}/qdock-server-pavilion.desktop"
install -m 755 tools/qdock-server-gui.desktop \
    "${desktop_dir}/Servidor-Quansheng-UV-K5.desktop"
if command -v gio >/dev/null 2>&1; then
    gio set "${desktop_dir}/Servidor-Quansheng-UV-K5.desktop" \
        metadata::trusted true >/dev/null 2>&1 || true
fi
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "${launcher_dir}" >/dev/null 2>&1 || true
fi
echo "Lanzador actualizado: ${launcher_dir}/qdock-server-pavilion.desktop"
echo "Acceso de escritorio: ${desktop_dir}/Servidor-Quansheng-UV-K5.desktop"
REMOTE_SCRIPT

echo "Actualización terminada. El lanzador usará ${REMOTE_DIR}/build/qdock-server-gui."
