# Instaladores Linux Mint / Ubuntu

Paquetes para **Linux Mint 22.x / Ubuntu 24.04, x86-64 (amd64)**.
No se ha comprobado su instalación en otras distribuciones o versiones.

## Elegir el paquete

- **HP principal:** `icom7300mk2-control_1.2.13-1_amd64.deb`.
  Incluye la aplicación Icom, el cliente LAN Quansheng y el acceso al menú.
- **Pavilion:** `qdock-server_0.1.0-1_amd64.deb`.
  Incluye `qdock-server`, su interfaz gráfica y `qdock-probe`.
  No es necesario instalarlo en el HP principal para usar el cliente LAN.

No incluyen configuraciones personales, tokens ni bibliotecas Qt privadas.
APT instala las dependencias desde los repositorios del sistema. DECODIUM,
fldigi, QSSTV y JS8Call siguen siendo aplicaciones opcionales independientes.

## Instalar

Cerrar la aplicación o detener el servidor antes de instalar/actualizar.
Abrir el `.deb` con doble clic y utilizar el instalador de paquetes de Mint,
o ejecutar en el directorio de descarga:

```bash
# En el HP principal:
sudo apt install ./icom7300mk2-control_1.2.13-1_amd64.deb

# En el Pavilion:
sudo apt install ./qdock-server_0.1.0-1_amd64.deb
```

Se instalan en `/usr/bin`, con accesos en el menú de aplicaciones.
La instalación no inicia programas, no abre puertos serie ni modifica grupos,
servicios, firewall o configuraciones guardadas. PTT requiere habilitación
explícita en el servidor.

Para abrir inequívocamente la versión del paquete:

```bash
/usr/bin/Icom7300Mk2Control
/usr/bin/qdock-server-gui
```

Los accesos antiguos del escritorio/panel pueden seguir apuntando al ejecutable
compilado en tu carpeta personal. Además, un lanzador del mismo nombre bajo
`~/.local/share/applications` tiene prioridad sobre el instalado en
`/usr/share/applications`. El instalador no elimina tus accesos personales:
revísalos y vuelve a anclar el lanzador correcto si deseas usar el paquete.

Los ajustes Icom existentes y el token Quansheng se conservan. En una instalación
nueva del servidor, preparar el mismo token que se introducirá en el cliente:

```bash
mkdir -p "$HOME/.config/qdock"
# Ejecutar solo si todavía no existe el archivo de token:
if [ ! -e "$HOME/.config/qdock/lan-token" ]; then
    (umask 077; read -r -s -p 'Token LAN (16-256 bytes): ' qdock_token
     printf '\n'
     printf '%s\n' "$qdock_token" > "$HOME/.config/qdock/lan-token")
fi
```

El usuario debe tener acceso al puerto serie (normalmente mediante el grupo
`dialout`). Los paquetes no cambian esa autorización. En el Pavilion, seleccionar
el puerto al que está conectado el UV-K5; en el cliente, la dirección LAN y token
del servidor. Para PTT, marcar **Permitir PTT** antes de iniciar el servidor.

## Verificar y desinstalar

Junto a cada paquete hay un archivo `.sha256`:

```bash
sha256sum -c icom7300mk2-control_1.2.13-1_amd64.deb.sha256
sha256sum -c qdock-server_0.1.0-1_amd64.deb.sha256
```

```bash
sudo apt remove icom7300mk2-control
sudo apt remove qdock-server
```

APT retira los archivos del paquete. Las preferencias personales permanecen.

## Regenerar desde el repositorio

Con las dependencias de compilación Qt 6 ya instaladas, hacen falta Python 3,
CMake, Ninja, un compilador C++, binutils, dpkg-dev y desktop-file-utils.
Desde la raíz del repositorio:

```bash
python3 packaging/build-deb.py
```

El script compila en `build-packages/icom` y `build-packages/quansheng`, sin usar
ni sobrescribir las compilaciones habituales. Los `.deb`, sus hashes y esta guía
quedan en `build-packages/dist`. No requiere sudo, no instala paquetes y no inicia
las aplicaciones. Calcula las dependencias ELF mediante `dpkg-shlibdeps` y añade
los módulos QML que se cargan dinámicamente. Los lanzadores empaquetados utilizan
`/usr/bin`, sin cambiar los lanzadores de desarrollo.

Para otra revisión de empaquetado: `python3 packaging/build-deb.py --revision 2`.

## Publicación en GitHub

El flujo `.github/workflows/publicar-instaladores.yml` compila en Ubuntu 24.04
y adjunta los dos DEB, hashes e instrucciones a una release existente.
Se activa subiendo una etiqueta `debs-vX.Y.Z` sobre el commit de empaquetado,
o mediante ejecución manual con `release_tag=vX.Y.Z`.

Antes de publicar comprueba que el código de la aplicación y del servidor es
idéntico al de `vX.Y.Z`; solo permite diferencias de empaquetado, este flujo y
los README. No mueve la etiqueta original ni sustituye el ZIP fuente. No
sobrescribe adjuntos existentes: una repetición con los mismos nombres se detiene.
