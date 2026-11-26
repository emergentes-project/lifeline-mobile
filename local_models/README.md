# Gemma 4 E2B para APK directo

El archivo `gemma-4-E2B-it.litertlm` vive en esta carpeta y se excluye de Git.
Antes de compilar, ejecuta `tool/prepare_bundled_model.ps1`; verifica el
SHA-256 y copia el modelo a los recursos privados de Android. Luego ejecuta
`flutter build apk`. Gradle rechaza una compilación si falta el modelo.

El APK contiene el modelo. Al abrir la app por primera vez, Android lo copia
automáticamente a `files/models/` y verifica de nuevo su integridad. El usuario
no tiene que seleccionar ni descargar ningún archivo.
