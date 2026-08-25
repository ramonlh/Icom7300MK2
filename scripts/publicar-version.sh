#!/usr/bin/env bash

set -euo pipefail

usage() {
    echo "Uso: $0 X.Y.Z"
    echo "Ejemplo: $0 1.2.12"
}

if [[ $# -ne 1 ]] || [[ ! $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    usage >&2
    exit 2
fi

version="$1"
tag="v${version}"
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Error: esta carpeta todavía no es un repositorio Git." >&2
    exit 1
fi

if ! git remote get-url origin >/dev/null 2>&1; then
    echo "Error: falta configurar el remoto 'origin' de GitHub." >&2
    echo "Ejemplo: git remote add origin git@github.com:USUARIO/REPOSITORIO.git" >&2
    exit 1
fi

remote_url="$(git remote get-url origin)"
if [[ $remote_url != *github.com* ]]; then
    echo "Error: el remoto 'origin' no parece pertenecer a GitHub: $remote_url" >&2
    exit 1
fi

if [[ -n $(git status --porcelain) ]]; then
    echo "Error: hay cambios sin confirmar. Revíselos y cree un commit antes de publicar." >&2
    git status --short >&2
    exit 1
fi

current_branch="$(git branch --show-current)"
if [[ -z $current_branch ]]; then
    echo "Error: no se puede publicar desde un HEAD separado." >&2
    exit 1
fi

cmake_version="$(sed -nE 's/^[[:space:]]*VERSION[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' CMakeLists.txt | head -n1)"
cpp_version="$(sed -nE 's/.*QStringLiteral\("([0-9]+\.[0-9]+\.[0-9]+)"\).*/\1/p' main.cpp | head -n1)"
qml_version="$(sed -nE 's/.*Versión ([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' Main.qml | head -n1)"

for declared_version in "$cmake_version" "$cpp_version" "$qml_version"; do
    if [[ $declared_version != "$version" ]]; then
        echo "Error: la versión solicitada ($version) no coincide en CMakeLists.txt, main.cpp y Main.qml." >&2
        echo "Detectadas: CMake=$cmake_version, C++=$cpp_version, QML=$qml_version" >&2
        exit 1
    fi
done

if git show-ref --verify --quiet "refs/tags/$tag"; then
    echo "Error: la etiqueta $tag ya existe localmente." >&2
    exit 1
fi

if git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1; then
    echo "Error: la etiqueta $tag ya existe en GitHub." >&2
    exit 1
fi

echo "Publicando $tag desde la rama $current_branch en $remote_url"
git tag -a "$tag" -m "Icom7300Mk2Control $tag"

if ! git push origin "$current_branch"; then
    git tag -d "$tag" >/dev/null
    echo "Error: no se pudo subir la rama; se eliminó la etiqueta local." >&2
    exit 1
fi

if ! git push origin "$tag"; then
    echo "Error: la rama se subió, pero no la etiqueta. Puede reintentarlo con:" >&2
    echo "  git push origin $tag" >&2
    exit 1
fi

echo "Publicación enviada. GitHub Actions creará automáticamente el ZIP y el Release de $tag."
