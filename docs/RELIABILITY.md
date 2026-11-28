# Validación móvil

## Sincronización

Las consultas pendientes se intentan enviar al guardar, recuperar conectividad, volver a primer plano y abrir la aplicación. Mientras está activa hay revisiones periódicas. El acceso bloqueado o una cuenta distinta no envían datos de otro usuario.

Cada consulta mantiene su UUID, clave de idempotencia y foto. Un fallo de red o una respuesta perdida se reintenta con esos mismos identificadores; un cierre de sesión no elimina pendientes. Hay una sola sincronización simultánea por propietario. Los fallos transitorios tienen espera progresiva persistida; un reintento manual puede adelantarla.

El seguimiento consulta únicamente los recibos autorizados de la cuenta o sesión invitada correspondiente. Conserva la última actualización local y evita reemplazarla por una respuesta anterior. La confirmación del envío y el estado de atención se muestran por separado. Solicitar ayuda sigue siendo posible cuando falla la orientación de IA, conservando esa condición en el envío.

El coordinador no ejecuta sincronización continua cuando Android ha terminado el proceso. Los pendientes se recuperan al abrir de nuevo la app. Las notificaciones remotas, una vez configurado Firebase, utilizan el servicio de mensajería de Android.

## Firebase Android

1. Usar el proyecto Firebase propio de Lifeline.
2. Registrar la aplicación Android con paquete `com.example.lifeline_mobile`.
3. Guardar su configuración en `android/app/google-services.json` (ignorado por Git).
4. Habilitar FCM y configurar el backend con la cuenta de servicio del mismo proyecto.
5. Compilar un APK nuevo y conceder el permiso de notificaciones en el teléfono.

Sin el archivo de configuración no funcionan las notificaciones remotas, aunque siguen funcionando los estados y avisos internos. No basta con instalar la CLI ni con iniciar sesión en Firebase.

## Compilar e instalar

```powershell
flutter test
flutter analyze
flutter build apk --release --dart-define=API_BASE_URL=https://backend-lifeline-endwcsfcdtfqaaa2.canadacentral-01.azurewebsites.net
```

El modelo se incluye en el APK; comprobar espacio libre para descargar e instalar un archivo de varios GB. La versión de estas correcciones es `1.0.1+2`.

Instalar como actualización sobre la app existente y conservar la misma firma. No desinstalar una app con pendientes. Si Android informa de una firma incompatible, detener la instalación y recuperar la clave de firma de la versión instalada. La configuración actual del proyecto firma la variante release con la clave debug existente del equipo; debe sustituirse por una clave de distribución estable en una publicación futura coordinada.

## Comprobaciones con teléfono

1. Crear una consulta sin red, cerrar y volver a abrir: permanece pendiente con los mismos datos.
2. Recuperar internet: pasa a confirmada sin pulsar enviar y aparece un solo caso.
3. Repetir el intento durante una conexión inestable: no aparecen casos duplicados.
4. Cerrar sesión/cambiar de cuenta: conservar pendientes y mostrar únicamente los autorizados.
5. Ciudadano e invitado: verificar cambios de asignación, atención y cierre; abrir sin red y conservar la última información.
6. Con Firebase configurado: probar app abierta, en segundo plano y cerrada normalmente. Tocar el aviso debe abrir un detalle autorizado y consultar el estado vigente. Android puede impedir mensajes después de «Forzar detención» hasta volver a abrir la app.
7. Denegar notificaciones: la confirmación visible y el seguimiento deben seguir funcionando.

Las pruebas automatizadas no sustituyen la entrega real de FCM ni la prueba de instalación sobre el APK que ya usa el equipo.
