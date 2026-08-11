# SIGERIA Campo — app móvil (Flutter)

## Actualización 2026-08-11 (segunda vuelta) — integración real + mapa satelital

A pedido del usuario, la app se rediseñó siguiendo la estructura de **SW Maps**
(galería de mapas base, capas, cámara geoetiquetada, señalización en el mapa
de lo capturado) y se corrigió el problema de fondo: los 4 módulos **ya no
son formularios sueltos** — ahora son los 4 pasos de un `Stepper` único
(`lib/screens/nuevo_expediente_screen.dart`) que arma **un solo expediente**
por vivienda/familia con un solo código (`id_objeto`). Bajo ese mismo código
quedan la ubicación, la evaluación EDAN, la geometría GPS, las mediciones y
la foto — nada se vuelve a preguntar dos veces.

Agregado en esta vuelta:
- **Mapa base "estilo Google Earth"**: Esri World Imagery (satelital libre,
  sin API key — Google Satellite real requiere facturación que este proyecto
  no tiene configurada). Selector Calle/Satelital/Híbrido en `mapa_screen.dart`
  y en el paso 3 del expediente. Verificado con imagen real del Chocó.
- **Departamento** (33 DANE, `lib/data/colombia_departamentos.dart`),
  **Municipio + código DIVIPOLA**, **Barrio/corregimiento/vereda** y
  **Dirección** — todos en el paso 1.
- **Responsable de la recolección** (nombre, documento, cargo, entidad) y
  **Informante en la vivienda** (nombre, documento, parentesco, teléfono) —
  para que el dato sea entregable ante UNGRD/departamento/municipio con
  trazabilidad de quién lo levantó y quién lo entregó.
- **¿Requiere subsidio de arrendamiento?** (sí/no) en el paso EDAN.
- **Cámara real** arreglada: `image_picker` con `ImageSource.camera` (antes
  era un botón sin acción). La foto se guarda ligada al `id_objeto` del
  expediente vía `POST /api/edan/evidencias` — verificado con curl.
- Endpoint nuevo `GET /api/estadisticas/general` (backend) para reportes
  agregados por departamento/municipio/fenómeno/severidad/recolector —
  pensado para uso multiusuario (varias brigadas a la vez) y entrega
  institucional en los 3 niveles.

**Bug real encontrado y corregido con el test de widgets** (no con clics de
navegador, que en esta sesión de automatización tuvieron problemas de mapeo
de coordenadas ajenos a la app — ver más abajo): el estado inicial
`'sin_evaluar'` del dropdown "Estado operativo" no estaba en su propia lista
de opciones, lo cual hacía que `NuevoExpedienteScreen` **crasheara en
silencio** al construirse (assertion error de `DropdownButtonFormField`),
dejando la app aparentemente "sin responder a ningún clic". `flutter test`
lo detectó de inmediato; los clics de navegador por sí solos no lo hubieran
diagnosticado. Corregido agregando `'sin_evaluar'` a las opciones. También se
agregó `isExpanded: true` a los dropdowns (el nombre largo del departamento
"Archipiélago de San Andrés..." desbordaba el layout).

**Verificación real**: `flutter analyze` (0 errores, solo *info* de estilo),
`flutter test` (2/2 — incluye un test que navega al expediente, verifica los
campos del paso 1 y avanza al paso 2), `flutter build web` (compila),
navegador real (Home, menú, mapa satelital con marcador en ubicación real,
y el paso 1 completo del expediente visible con todos los campos nuevos).
El backend se probó end-to-end con `curl` con TODOS los campos nuevos
(responsable, informante, subsidio, foto vinculada al código) — ver sección
"Principio de captura única, demostrado" del README principal.


**Estado real (actualizado):** Flutter 3.44.9 instalado vía Homebrew en esta máquina.
`flutter create` generó `android/`, `ios/`, `web/`. `flutter pub get`, `flutter analyze`
(sin issues) y `flutter test` (pasa) corridos de verdad. `flutter build web` compila y se
verificó **en navegador real**: la pantalla home muestra los 4 módulos y el formulario
adaptativo (módulo 2) carga `assets/matriz_maestra.json` y arma los campos dinámicamente
tal como está descrito abajo — no es una maqueta, es la app corriendo.

**Lo que falta (honesto):** no hay Android SDK ni Xcode completo en esta máquina, así que
no se probó en emulador/dispositivo Android ni iOS — solo en el target web de Flutter.
`maplibre_gl` se subió de `0.19.0` a `0.26.2` porque la versión vieja no compilaba para web
(API `platformViewRegistry` obsoleta). GPS real, cámara real y sqflite real tampoco se
probaron (dependen de un dispositivo/emulador).

## Cómo correrlo

```bash
export PATH="/opt/homebrew/bin:$PATH"   # flutter quedó en Homebrew
cd mobile
flutter pub get
flutter test                 # prueba de humo: los 4 módulos aparecen
flutter analyze              # 0 issues
flutter build web            # compila para navegador (verificado)
python3 -m http.server 8745 --directory build/web   # servir y abrir

# Para Android/iOS reales: instalar Android Studio (SDK) o Xcode completo,
# luego `flutter run` con un emulador/dispositivo conectado.
```

## Arquitectura

- **Offline-first real**: `services/db_local.dart` usa `sqflite` como fuente de verdad en
  el dispositivo (igual patrón que `backend/app/db/database.py` del backend, y que
  `db_local.py` del proyecto Escuchar Turbo — SQLite sin dependencias pesadas).
- **Cola de sincronización**: `services/sync_queue.dart` — cada registro creado offline
  entra a una cola con estado `pendiente|sincronizado|error`, reintenta con backoff cuando
  hay conectividad (`connectivity_plus`).
- **Mapa**: `maplibre_gl` (mapas base offline descargables, MBTiles), acorde a la sección 16.
- **Formulario adaptativo**: `widgets/formulario_adaptativo.dart` lee la Matriz Maestra
  (`docs/Matriz_Maestra_SIGERIA.xlsx` exportada a JSON) y muestra solo los campos cuya
  condición (`Condición_para_mostrar`) se cumple para el fenómeno/objeto/perfil actuales —
  mismo principio que la columna `relevant` de XLSForm (ver `research/HALLAZGOS.md`).
- **Captura única**: un mismo `ObjetoAfectado` acumula geometría, mediciones, evidencia y
  necesidades en el modelo local; al sincronizar, cada tabla local se mapea 1:1 a los
  endpoints `/api/eventos`, `/api/edan`, `/api/gis`, `/api/mediciones` del backend.

## Estructura

```
mobile/
├── pubspec.yaml
├── lib/
│   ├── main.dart
│   ├── models/            # Evento, ObjetoAfectado, Geometria, Medicion, Necesidad
│   ├── services/          # db_local.dart, api_client.dart, sync_queue.dart, gps_service.dart
│   ├── screens/           # home, nuevo_evento, ficha_objeto, mapa_offline, medicion
│   └── widgets/           # formulario_adaptativo.dart, campo_dinamico.dart
└── assets/                # matriz_maestra.json (exportar desde el Excel), mapas offline
```

Los 4 módulos del MVP (sección 22 del documento) están representados 1:1 en `screens/`.
