#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${QDOCK_SERVER_DIR:-$(cd -- "${SCRIPT_DIR}/.." && pwd)}"
SERVER="${PROJECT_DIR}/build/qdock-server"
DEVICE="/dev/ttyUSB0"
TOKEN="${QDOCK_LAN_TOKEN:-prueba-local-quansheng-2026}"

if [[ ! -x "${SERVER}" ]]; then
    echo "No se encuentra el servidor: ${SERVER}" >&2
    echo "Compila primero el proyecto situado en: ${PROJECT_DIR}" >&2
    read -r -p "Pulsa Enter para cerrar..." _
    exit 1
fi

if [[ ! -e "${DEVICE}" ]]; then
    echo "No se encuentra el dispositivo serie: ${DEVICE}" >&2
    echo "Conecta el PL2303 y comprueba el puerto antes de continuar." >&2
    read -r -p "Pulsa Enter para cerrar..." _
    exit 1
fi

echo "Servidor Quansheng de observación READ-ONLY"
echo "Proyecto: ${PROJECT_DIR}"
echo "Escucha: 0.0.0.0:8765"
echo "Serie:   ${DEVICE}"
echo "No se envían comandos a la radio."
echo "Frecuencia, TX, PTT, teclas, EEPROM y comandos genéricos permanecen bloqueados."
echo

printf -v SERVER_COMMAND '%q ' env "QDOCK_LAN_TOKEN=${TOKEN}" "${SERVER}" \
    --serial "${DEVICE}" --seconds 86400 --listen 0.0.0.0 --port 8765
exec sg dialout -c "${SERVER_COMMAND}"
