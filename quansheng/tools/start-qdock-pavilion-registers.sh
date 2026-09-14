#!/usr/bin/env bash
set -u

project_dir="/home/ramon/qdock-readonly"
program="$project_dir/build/qdock-register-query"
serial_port="/dev/ttyUSB0"
result_file="/tmp/qdock-registers-$(date +%Y%m%d-%H%M%S).jsonl"

echo "QUANSHENG UV-K5 · Lectura experimental de registros BK4819"
echo "Rango: 0x00-0x7F (128 registros, tres consultas)"
echo "No se escriben registros, EEPROM ni GPIO; TX/PTT permanecen bloqueados."
echo

if [[ ! -x "$program" ]]; then
    echo "No se encuentra el programa: $program"
    echo "Compila primero el proyecto situado en: $project_dir"
    exit 1
fi

if [[ ! -e "$serial_port" ]]; then
    echo "No existe el puerto: $serial_port"
    exit 1
fi

if fuser "$serial_port" >/dev/null 2>&1; then
    echo "El puerto está ocupado. Detén antes qdock-server u otro programa serie."
    fuser -v "$serial_port"
    exit 1
fi

echo "Resultado: $result_file"
echo
if [[ -r "$serial_port" && -w "$serial_port" ]]; then
    "$program" "$serial_port" | tee "$result_file"
else
    current_user="$(id -un)"
    if ! id -nG "$current_user" | tr ' ' '\n' | grep -qx dialout; then
        echo "El usuario $current_user no pertenece al grupo dialout."
        exit 1
    fi
    echo "Activando temporalmente el grupo dialout para acceder al puerto."
    sg dialout -c "'$program' '$serial_port'" | tee "$result_file"
fi
status=${PIPESTATUS[0]}
echo
if [[ $status -eq 0 ]]; then
    echo "Lectura completada y guardada en: $result_file"
else
    echo "La lectura terminó con error $status. Archivo parcial: $result_file"
fi
exit "$status"
