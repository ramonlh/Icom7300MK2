# Publicación de versiones en GitHub

El repositorio está preparado para publicar una versión con una etiqueta Git. Al subir una etiqueta con formato `vX.Y.Z`, GitHub Actions crea automáticamente:

- una entrada en **GitHub Releases** con notas generadas a partir de los commits;
- `Icom7300Mk2Control_vX.Y.Z.zip`, que contiene el código de esa versión;
- el fichero SHA-256 correspondiente para comprobar la descarga.

## Configuración inicial

Esta operación se realiza una sola vez, después de crear el repositorio en GitHub:

```bash
git remote add origin git@github.com:USUARIO/REPOSITORIO.git
git push -u origin main
```

También se puede utilizar una URL HTTPS si GitHub está configurado con un gestor de credenciales.

En **Settings → Actions → General → Workflow permissions** del repositorio, debe estar permitido que GitHub Actions escriba en el repositorio. El flujo utiliza exclusivamente el token temporal suministrado por GitHub y no necesita guardar contraseñas en el proyecto.

## Publicar una versión

1. Cambiar el número de versión en `CMakeLists.txt`, `main.cpp` y `Main.qml`.
2. Actualizar las novedades en `README.md` y `README.txt`.
3. Compilar y probar la aplicación.
4. Confirmar todos los cambios:

```bash
git add -A
git commit -m "Versión 1.2.12"
```

5. Ejecutar:

```bash
./scripts/publicar-version.sh 1.2.12
```

El script se detiene sin publicar si existen cambios sin confirmar, falta el remoto de GitHub, las versiones declaradas no coinciden o la etiqueta ya existe.
