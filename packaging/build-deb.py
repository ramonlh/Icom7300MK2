#!/usr/bin/env python3
"""Build Linux Mint 22 / Ubuntu 24.04 DEBs without root or installing them."""
import argparse
from datetime import datetime, timezone
from email.utils import format_datetime
import gzip
import hashlib
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MAINTAINER = 'ramonlh <ramonlh@users.noreply.github.com>'
HOMEPAGE = 'https://github.com/ramonlh/Icom7300MK2'
QML_DEPENDS = [
    'qml6-module-qtqml', 'qml6-module-qtquick', 'qml6-module-qtquick-window',
    'qml6-module-qtquick-controls', 'qml6-module-qtquick-templates',
    'qml6-module-qtquick-layouts', 'qml6-module-qtqml-models',
    'qml6-module-qtqml-workerscript',
]


def run(*args, **kwargs):
    print('+', ' '.join(map(str, args)), flush=True)
    return subprocess.run(list(map(str, args)), check=True, **kwargs)


def output(*args, **kwargs):
    return subprocess.check_output(list(map(str, args)), text=True, **kwargs).strip()


def version(source):
    match = re.search(r'project\s*\(\s*\w+\s+VERSION\s+(\d+\.\d+\.\d+)',
                      (source / 'CMakeLists.txt').read_text(), re.IGNORECASE)
    if not match:
        raise SystemExit(f'No se puede determinar la versión de {source}')
    return match[1]


def put(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    path.chmod(0o644)


def copy(source, target, mode=0o644):
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)
    target.chmod(mode)


def desktop(source, target, executable, comment=None):
    lines = []
    for line in source.read_text().splitlines():
        if line.startswith('Path='):
            continue
        if line.startswith('Categories=') and 'Network;' not in line:
            line += 'Network;'
        if line.startswith('Exec='):
            line = f'Exec=/usr/bin/{executable}'
        if comment and line.startswith('Comment='):
            line = f'Comment={comment}'
        lines.append(line)
    put(target, '\n'.join(lines) + '\n')
    run('desktop-file-validate', target)


def build(source, directory, jobs, targets, *options):
    run('cmake', '-S', source, '-B', directory, '-G', 'Ninja',
        '-DCMAKE_BUILD_TYPE=Release', '-DCMAKE_INSTALL_PREFIX=/usr',
        '-DCMAKE_SKIP_RPATH=ON', *options)
    run('cmake', '--build', directory, '--parallel', jobs, '--target', *targets)


def package(stage, work, name, ver, arch, description, binaries, extra_depends, dist):
    (stage / 'DEBIAN').mkdir(parents=True, exist_ok=True)
    # dpkg-shlibdeps requires a minimal source control file in its cwd.
    put(work / 'debian/control', f'Source: {name}\nSection: hamradio\n'
        f'Priority: optional\nMaintainer: {MAINTAINER}\n\nPackage: {name}\n'
        f'Architecture: any\nDescription: {description}\n')
    for binary in binaries:
        run('strip', '--strip-unneeded', binary)
    deps = output('dpkg-shlibdeps', '-O', *binaries, cwd=work)
    depends = next(line.split('=', 1)[1] for line in deps.splitlines()
                   if line.startswith('shlibs:Depends='))
    if extra_depends:
        depends += ', ' + ', '.join(extra_depends)
    size = math.ceil(sum(p.stat().st_size for p in stage.rglob('*') if p.is_file()) / 1024)
    put(stage / 'DEBIAN/control', f'Package: {name}\nVersion: {ver}\n'
        f'Section: hamradio\nPriority: optional\nArchitecture: {arch}\n'
        f'Maintainer: {MAINTAINER}\nInstalled-Size: {size}\n'
        f'Depends: {depends}\nRecommends: qt6-wayland\n'
        f'Homepage: {HOMEPAGE}\nDescription: {description}\n'
        ' Aplicación nativa Qt 6 para Linux Mint 22 / Ubuntu 24.04.\n'
        ' Incluye acceso desde el menú; conserva la configuración del usuario.\n')
    md5s = []
    for path in sorted(stage.rglob('*')):
        if path.is_file() and 'DEBIAN' not in path.relative_to(stage).parts:
            md5s.append(f'{hashlib.md5(path.read_bytes()).hexdigest()}  {path.relative_to(stage)}')
    put(stage / 'DEBIAN/md5sums', '\n'.join(md5s) + '\n')
    # Normalize permissions independently of the builder's umask.
    stage.chmod(0o755)
    for path in stage.rglob('*'):
        if path.is_dir():
            path.chmod(0o755)
        elif path.is_file():
            path.chmod(0o755 if path in binaries else 0o644)
    destination = dist / f'{name}_{ver}_{arch}.deb'
    run('dpkg-deb', '--build', '--root-owner-group', stage, destination)
    run('dpkg-deb', '--info', destination)
    return destination


def docs(stage, name, ver, source, quansheng=False):
    directory = stage / 'usr/share/doc' / name
    copy(ROOT / 'packaging/INSTALAR.md', directory / 'INSTALAR.md')
    copy(source / 'README.md', directory / 'README.md')
    if quansheng:
        put(directory / 'copyright', f'Source: {HOMEPAGE}/tree/codex-integracion/quansheng\n\n'
            'Copyright: 2024 nicsure (protocolo original QuanshengDock)\n'
            'Copyright: los autores de QuanshengDock-Linux, según historial Git.\n'
            'License: GPL-2.0-only\n'
            'Este programa se distribuye bajo GNU GPL versión 2.\n'
            'Texto completo: /usr/share/common-licenses/GPL-2 y COPYING.\n'
            'Véase NOTICE para la atribución y referencia upstream.\n')
        copy(source / 'LICENSE', directory / 'COPYING')
        copy(source / 'NOTICE', directory / 'NOTICE')
        copy(source / 'docs/LAN_PROTOCOL.md', directory / 'LAN_PROTOCOL.md')
    else:
        put(directory / 'copyright', f'Source: {HOMEPAGE}\n\n'
            'Copyright: los autores de Icom7300Mk2Control, según historial Git.\n'
            'El proyecto principal no declara todavía una licencia general.\n'
            'Este paquete no cambia los derechos del código original.\n'
            'Los avisos del subsistema Quansheng se conservan en NOTICE.quansheng\n'
            'y COPYING.quansheng. Las bibliotecas Qt son dependencias del sistema.\n')
        copy(ROOT / 'quansheng/LICENSE', directory / 'COPYING.quansheng')
        copy(ROOT / 'quansheng/NOTICE', directory / 'NOTICE.quansheng')
    changelog = (f'{name} ({ver}) noble; urgency=medium\n\n'
                 '  * Primer paquete binario: ejecutables, lanzadores y dependencias Qt.\n\n'
                 f' -- {MAINTAINER}  {format_datetime(datetime.now(timezone.utc))}\n')
    (directory / 'changelog.Debian.gz').write_bytes(gzip.compress(changelog.encode(), mtime=0))
    names = ('qdock-server', 'qdock-server-gui', 'qdock-probe') if quansheng else ('Icom7300Mk2Control',)
    man_dir = stage / 'usr/share/man/man1'
    man_dir.mkdir(parents=True, exist_ok=True)
    for command in names:
        page = ROOT / 'packaging/man' / f'{command}.1'
        (man_dir / f'{command}.1.gz').write_bytes(gzip.compress(page.read_bytes(), mtime=0))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-dir', type=Path, default=ROOT / 'build-packages')
    parser.add_argument('--output', type=Path, help='Destino (por defecto BUILD/dist)')
    parser.add_argument('--jobs', type=int, default=2)
    parser.add_argument('--revision', default='1', help='Revisión Debian, entero positivo')
    args = parser.parse_args()
    if args.jobs < 1 or not re.fullmatch(r'[1-9][0-9]*', args.revision):
        parser.error('--jobs y --revision deben ser positivos')
    for tool in ('cmake', 'ninja', 'dpkg', 'dpkg-deb', 'dpkg-shlibdeps', 'strip', 'desktop-file-validate'):
        if not shutil.which(tool):
            raise SystemExit(f'Falta herramienta: {tool}')
    os_info = dict(line.split('=', 1) for line in Path('/etc/os-release').read_text().splitlines()
                   if '=' in line)
    base = os_info.get('UBUNTU_CODENAME', os_info.get('VERSION_CODENAME', '')).strip('"')
    if base != 'noble':
        raise SystemExit('Construir estos paquetes en Linux Mint 22 / Ubuntu 24.04 (noble).')
    arch = output('dpkg', '--print-architecture')
    if arch != 'amd64':
        raise SystemExit('Este empaquetado está validado únicamente para amd64.')
    build_root = args.build_dir.resolve()
    dist = args.output.resolve() if args.output else build_root / 'dist'
    dist.mkdir(parents=True, exist_ok=True)
    main_build, server_build = build_root / 'icom', build_root / 'quansheng'
    build(ROOT, main_build, args.jobs, ['Icom7300Mk2Control'], '-DICOM_BUILD_TESTS=OFF')
    build(ROOT / 'quansheng', server_build, args.jobs,
          ['qdock-server', 'qdock-server-gui', 'qdock-probe'],
          '-DQDOCK_SERIAL=ON', '-DBUILD_TESTING=OFF')
    packages = []
    with tempfile.TemporaryDirectory(prefix='deb-stage-', dir=build_root) as temp:
        work = Path(temp)
        stage = work / 'icom'
        run('cmake', '--install', main_build, '--prefix', '/usr',
            env=dict(os.environ, DESTDIR=str(stage)))
        desktop(ROOT / 'org.icom.Icom7300Mk2Control.desktop',
                stage / 'usr/share/applications/org.icom.Icom7300Mk2Control.desktop',
                'Icom7300Mk2Control', 'Control Icom IC-7300MK2 y cliente LAN Quansheng')
        ver = version(ROOT) + '-' + args.revision
        docs(stage, 'icom7300mk2-control', ver, ROOT)
        packages.append(package(stage, work, 'icom7300mk2-control', ver, arch,
            'Control Icom IC-7300MK2 y cliente LAN Quansheng',
            [stage / 'usr/bin/Icom7300Mk2Control'], QML_DEPENDS, dist))

        stage = work / 'server'
        binaries = []
        for name in ('qdock-server', 'qdock-server-gui', 'qdock-probe'):
            dest = stage / 'usr/bin' / name
            copy(server_build / name, dest, 0o755)
            binaries.append(dest)
        desktop(ROOT / 'quansheng/tools/qdock-server-gui.desktop',
                stage / 'usr/share/applications/qdock-server-pavilion.desktop', 'qdock-server-gui')
        ver = version(ROOT / 'quansheng') + '-' + args.revision
        docs(stage, 'qdock-server', ver, ROOT / 'quansheng', quansheng=True)
        packages.append(package(stage, work, 'qdock-server', ver, arch,
            'Servidor LAN y panel de control para Quansheng UV-K5', binaries, [], dist))
    for path in packages:
        put(Path(str(path) + '.sha256'), f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n')
    copy(ROOT / 'packaging/INSTALAR.md', dist / 'INSTALAR.md')
    print('\nPaquetes creados (no instalados):', *(str(p) for p in packages), sep='\n')


if __name__ == '__main__':
    main()
