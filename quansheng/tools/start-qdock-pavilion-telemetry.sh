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

echo "Servidor Quansheng con telemetría EXPERIMENTAL"
echo "Consulta frecuencia cada 2 s, RSSI cada segundo y 50 registros a los 3,5 s y después cada 30 s."
echo "Permite lectura EEPROM solicitada desde el cliente; nunca escribe EEPROM."
echo "Frecuencia, TX/PTT, teclas y escritura de registros/GPIO siguen bloqueados."
echo

if [[ ! -x "${SERVER}" ]]; then
    echo "No se encuentra el servidor: ${SERVER}"
    exit 1
fi
if [[ ! -e "${DEVICE}" ]]; then
    echo "No se encuentra el dispositivo serie: ${DEVICE}"
    exit 1
fi
printf -v command '%q ' env "QDOCK_LAN_TOKEN=${TOKEN}" "${SERVER}" \
    --serial "${DEVICE}" --seconds 86400 --listen 0.0.0.0 --port 8765 \
    --allow-rssi-query --allow-register-query --allow-eeprom-query
exec sg dialout -c "${command}"
