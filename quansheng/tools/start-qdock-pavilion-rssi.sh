#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${QDOCK_SERVER_DIR:-$(cd -- "${SCRIPT_DIR}/.." && pwd)}"
SERVER="${PROJECT_DIR}/build/qdock-server"
DEVICE="/dev/ttyUSB0"
if [[ -z "${QDOCK_LAN_TOKEN:-}" ]]; then
    read -r -s -p "Token LAN nuevo (mínimo 16 caracteres): " QDOCK_LAN_TOKEN
    echo
fi
if [[ ${#QDOCK_LAN_TOKEN} -lt 16 ]]; then
    echo "El token LAN debe tener al menos 16 caracteres." >&2
    exit 1
fi
TOKEN="${QDOCK_LAN_TOKEN}"
[[ -x "${SERVER}" ]] || { echo "No se encuentra ${SERVER}"; read -r; exit 1; }
[[ -e "${DEVICE}" ]] || { echo "No se encuentra ${DEVICE}"; read -r; exit 1; }
echo "Servidor Quansheng con consulta RSSI EXPERIMENTAL"
echo "Proyecto: ${PROJECT_DIR}"
echo "Envía únicamente GetRssi 0x0527 una vez por segundo."
echo "Frecuencia, TX/PTT, teclas, EEPROM, registros y GPIO siguen bloqueados."
printf -v command '%q ' env "QDOCK_LAN_TOKEN=${TOKEN}" "${SERVER}" \
  --serial "${DEVICE}" --seconds 86400 --listen 0.0.0.0 --port 8765 --allow-rssi-query
exec sg dialout -c "${command}"
