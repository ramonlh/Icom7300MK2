#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${QDOCK_SERVER_DIR:-$(cd -- "${SCRIPT_DIR}/.." && pwd)}"
DEVICE="${QDOCK_SERIAL_DEVICE:-/dev/ttyUSB0}"
PROBE="${PROJECT_DIR}/build/qdock-probe"

pause() { read -r -p "Pulsa Enter para continuar..." _; }

run_as_dialout() {
    local command
    printf -v command '%q ' "$@"
    sg dialout -c "${command}"
}

show_status() {
    echo; echo "=== Diagnóstico READ-ONLY ==="
    echo "Esperado: ${DEVICE}, 38400 baudios, 8N1, raw, sin control de flujo"; echo
    if [[ ! -e "${DEVICE}" ]]; then
        echo "ERROR: no existe ${DEVICE}. Reconecta el PL2303 y repite la prueba."
        return 1
    fi
    ls -l "${DEVICE}"
    echo; echo "Identificación USB:"
    udevadm info --query=property --name="${DEVICE}" 2>/dev/null \
        | grep -E '^(ID_VENDOR=|ID_MODEL=|ID_SERIAL=|ID_USB_DRIVER=)' || true
    echo; echo "Procesos que usan el puerto:"
    if ! fuser -v "${DEVICE}" 2>&1; then echo "Ninguno."; fi
    echo; echo "Configuración visible actual:"
    run_as_dialout stty -F "${DEVICE}" -a 2>&1 || true
}

capture_sample() {
    local capture
    local log
    local probe_pid
    local remaining
    local status
    capture="/tmp/qdock-pavilion-diagnostico-$(date +%Y%m%d-%H%M%S)-$$.raw"
    log="${capture%.raw}.log"
    echo
    if [[ ! -x "${PROBE}" ]]; then
        echo "ERROR: no se encuentra ${PROBE}. Compila primero el proyecto."
        return 1
    fi
    if [[ ! -e "${DEVICE}" ]]; then echo "ERROR: no existe ${DEVICE}."; return 1; fi
    if fuser "${DEVICE}" >/dev/null 2>&1; then
        echo "ERROR: ${DEVICE} está ocupado. Detén antes qdock-server con Ctrl+C."
        fuser -v "${DEVICE}" 2>&1 || true
        return 1
    fi
    echo "Se abrirá ${DEVICE} 30 segundos únicamente en lectura; no se enviarán comandos."
    read -r -p "Pulsa Enter para comenzar o Ctrl+C para cancelar..." _
    run_as_dialout "${PROBE}" --port "${DEVICE}" --seconds 30 --capture "${capture}" \
        >"${log}" 2>&1 &
    probe_pid=$!
    for ((remaining = 30; remaining > 0; --remaining)); do
        if ! kill -0 "${probe_pid}" 2>/dev/null; then break; fi
        printf '\rCapturando... %2d segundos restantes ' "${remaining}"
        sleep 1
    done
    if wait "${probe_pid}"; then status=0; else status=$?; fi
    printf '\rCaptura finalizada.                     \n'
    if ((status != 0)); then
        echo "ERROR: la captura no pudo completarse; no se analizará ningún archivo anterior."
        echo "Detalle:"
        tail -n 12 "${log}" 2>/dev/null || true
        return 1
    fi
    echo "Resumen del receptor:"
    tail -n 3 "${log}" 2>/dev/null || true
    echo; echo "Captura: ${capture}"; echo "Primeros 128 bytes:"
    od -An -tx1 -N128 "${capture}" 2>/dev/null || true
    echo
    if LC_ALL=C grep -a -q $'\xAB\xCD' "${capture}"; then
        echo "RESULTADO: se encontró al menos una cabecera AB CD válida."
    else
        echo "AVISO: no se encontró ninguna cabecera AB CD."
        echo "Si predominan 00 o patrones repetidos, aplica el reinicio físico."
    fi
}

show_reset_advice() {
    echo; echo "=== Reinicio físico recomendado ==="
    echo "1. Detén qdock-server o qdock-probe con Ctrl+C."
    echo "2. Apaga la radio."
    echo "3. Desconecta el USB del Pavilion durante 10 segundos."
    echo "4. Reconecta el USB, enciende la radio y déjala en su pantalla normal."
    echo "5. Ejecuta primero la captura READ-ONLY de 30 segundos."
    echo; echo "No se reinicia el USB por software, no se matan procesos y no se transmite nada."
}

while true; do
    clear
    echo "QUANSHENG UV-K5 · Diagnóstico del puerto serie"
    echo "1) Verificar puerto, permisos, controlador y procesos"
    echo "2) Capturar 30 segundos en modo READ-ONLY"
    echo "3) Mostrar procedimiento de reinicio recomendado"
    echo "4) Salir"; echo
    read -r -n 1 -p "Elige una opción: " choice
    echo
    case "${choice}" in
        1) show_status; pause ;;
        2) capture_sample; pause ;;
        3) show_reset_advice; pause ;;
        4) exit 0 ;;
        *) echo "Opción no válida."; pause ;;
    esac
done
