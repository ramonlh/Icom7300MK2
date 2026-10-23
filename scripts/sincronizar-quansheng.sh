#!/usr/bin/env bash

# Publica quansheng/ de la rama main en la rama main de QuanshengDock-Linux.
# El desarrollo se hace aquí; QuanshengDock-Linux es una copia sincronizada.

set -euo pipefail

remote_url="${QDOCK_MIRROR_URL:-git@github.com:ramonlh/QuanshengDock-Linux.git}"
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

if [[ -n "$(git status --porcelain -- quansheng)" ]]; then
    echo "Error: hay cambios sin confirmar en quansheng/." >&2
    exit 1
fi

if [[ "$(git rev-parse HEAD)" != "$(git rev-parse main)" ]]; then
    echo "Error: sincroniza desde la rama main." >&2
    exit 1
fi

echo "Separando el historial de quansheng/…"
split="$(git subtree split --prefix=quansheng main)"
echo "Commit equivalente: ${split}"

# Push normal: si alguien cambió la copia directamente, falla en vez de
# sobrescribir esos cambios.
git push "$remote_url" "${split}:refs/heads/main"
echo "QuanshengDock-Linux sincronizado con quansheng/ (${split})."
