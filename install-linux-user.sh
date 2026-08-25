#!/usr/bin/env bash
set -euo pipefail

APP_ID="es.ramonlorenzo.Icom7300Mk2Control"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPLICATIONS_DIR="${HOME}/.local/share/applications"
ICONS_BASE="${HOME}/.local/share/icons/hicolor"

mkdir -p "${APPLICATIONS_DIR}"
install -m 0644 \
    "${SOURCE_DIR}/${APP_ID}.desktop" \
    "${APPLICATIONS_DIR}/${APP_ID}.desktop"

for SIZE in 32 48 64 128 256 512; do
    DESTINATION="${ICONS_BASE}/${SIZE}x${SIZE}/apps"
    mkdir -p "${DESTINATION}"
    install -m 0644 \
        "${SOURCE_DIR}/icons/icom7300mk2_control_${SIZE}.png" \
        "${DESTINATION}/${APP_ID}.png"
done

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "${APPLICATIONS_DIR}" || true
fi

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache \
        --force \
        --ignore-theme-index \
        "${HOME}/.local/share/icons/hicolor" || true
fi

echo
echo "Icono y lanzador instalados para el usuario actual."
echo "Cierra la aplicación completamente y vuelve a abrirla."
echo "En algunos paneles puede ser necesario quitar el acceso anclado"
echo "anterior y volver a anclar la aplicación."
