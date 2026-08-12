<p align="center"><img src="docs/branding/sigeria_logo_original.png" width="180" alt="Logo SIGERIA"></p>

# SIGERIA — Sistema Inteligente Geoespacial para Evaluación, Respuesta e Inspección de Afectaciones

> 🟢 **App en vivo (HTTPS real):** https://35-196-65-232.sslip.io — desplegada de verdad
> en una VM de Google Cloud (nivel Always Free, gratis para siempre), con certificado
> real de Let's Encrypt (candado verde, sin advertencias). IP fija, no cambia. Cualquiera
> con el enlace puede abrirla y usarla ya mismo — ver "Novena/Décima vuelta" más abajo
> para el detalle técnico del despliegue y del HTTPS.

**SIGERIA Campo | módulo de SAT-GeoAI Chocó.** Plataforma móvil + web + GIS + IA para
capturar, georreferenciar, medir, validar, consolidar y analizar daños y necesidades
producidos por eventos naturales o socio-naturales, bajo el principio de **captura única**.

> Basado en `docs/Documento_General_SIGERIA_v1.2.docx` (documento de conceptualización
> v1.0, 11 ago 2026). Este README documenta lo que **ya se construyó y se probó** en esta
> sesión — no repite todo el contenido del documento original, léelo para el marco
> completo (normativo, roadmap detallado, riesgos, etc.).

## Estado real de cada pieza (honesto)

| Pieza | Estado | Cómo se verificó |
|---|---|---|
| Matriz Maestra (Excel) | ✅ Generada, primeras filas del MVP pobladas | Abierta y guardada en Excel real |
| Modelo de datos + DDL | ✅ Completo (PostGIS prod + SQLite dev) | Revisión manual |
| **Backend FastAPI (4 módulos MVP)** | ✅ **Corriendo y probado end-to-end** | `curl` real: crear evento→objeto→geometría→necesidad→medición→consolidado→GeoJSON |
| **Dashboard web (sala de crisis)** | ✅ **Probado en navegador real** | Mapa, marcador, KPIs y logo verificados con capturas de pantalla |
| **Proyecto QGIS + plugin** | ✅ **Construido, abierto y verificado en QGIS real** | Render PNG con 31 municipios + objeto demo; plugin cargado y activado en vivo |
| App móvil Flutter | ✅ **Compila y corre de verdad** (target web) | Flutter instalado (Homebrew), `flutter test`/`analyze` limpios, `flutter build web` OK, navegado y probado en el navegador: home→formulario adaptativo real |
| Investigación GitHub/plataformas | ✅ Completa | `research/HALLAZGOS.md` |

## Estructura

```
SIGERIA_SAT_GeoAI_Campo/
├── docs/                         Documento original, Matriz Maestra, modelo de datos, decisiones pendientes
├── backend/                      API FastAPI (Python) — 4 módulos del MVP
│   ├── app/                      código: db, models, routers, schemas
│   ├── db/                       schema_postgis.sql (producción) y schema_sqlite.sql (desarrollo)
│   └── .venv/                    entorno virtual ya creado con las dependencias instaladas
├── mobile/                       Scaffold Flutter offline-first (SIGERIA Campo)
├── web/                          Dashboard "sala de crisis" (HTML+JS+MapLibre, sin build)
├── gis/                          Proyecto QGIS piloto (.qgz) + capas + plugin fuente
├── qgis_plugin/sigeria_importador/  Plugin QGIS (también instalado y activo en el perfil de QGIS)
├── research/                     Hallazgos de investigación (GitHub, ODK/Kobo/QField, EDAN/RUD)
└── workspace/                    Base SQLite local (se recrea sola, vacía)
```

## Cómo correr cada parte

### Backend (API del MVP)

```bash
cd backend
./.venv/bin/uvicorn app.main:app --reload --port 8010
# Docs interactivas: http://127.0.0.1:8010/docs
```

Endpoints principales (los 4 módulos del MVP, sección 22 del documento base):

- `POST /api/eventos`, `POST /api/eventos/objetos` — Módulo 1: Evento y objetos
- `POST /api/edan/necesidades`, `/evidencias`, `GET /api/edan/consolidado/{id_evento}` — Módulo 2: EDAN
- `POST /api/gis/geometrias`, `GET /api/gis/geojson/{id_evento}` — Módulo 3: GIS offline
- `POST /api/mediciones` — Módulo 4: Medición móvil

### Dashboard web

```bash
cd web
python3 -m http.server 8744
# abrir http://localhost:8744
```
(También configurado como servidor con nombre `sigeria-web` en `.claude/launch.json` del
proyecto padre, para abrirlo con el panel de vista previa.)

### Proyecto QGIS

Abrir `gis/SIGERIA_piloto_choco.qgz` en QGIS-LTR. Incluye basemap OSM, los 31 municipios
reales del Chocó (reutilizados de `PLAN_ENERGETICO_CHOCO`, fuente GADM) y un objeto
afectado de demostración simbolizado por severidad. El plugin **SIGERIA Importador EDAN**
ya está instalado y activo (menú *Complementos* o *Vectorial → SIGERIA*): permite cargar
el GeoJSON del backend (archivo o URL en vivo) y simbolizarlo automáticamente.

### App móvil (Flutter — instalado y verificado)

```bash
export PATH="/opt/homebrew/bin:$PATH"
cd mobile
flutter test        # pasa: home muestra los 4 módulos
flutter analyze      # sin issues
flutter build web && python3 -m http.server 8745 --directory build/web
```

No hay Android SDK ni Xcode completo en esta máquina, así que **el target verificado es
web**; para Android/iOS falta instalar Android Studio / Xcode. Ver `mobile/README_MOBILE.md`
para el detalle honesto de qué falta.

## Principio de captura única, demostrado

La prueba end-to-end de esta sesión generó el objeto
`SIGERIA-CHO-27001-SIS-2026-000001` (Quibdó, sismo) y con un solo registro alimentó
automáticamente: el consolidado EDAN, el mapa/GeoJSON, y quedó listo para el proyecto QGIS
y el dashboard web — sin volver a digitar nada. Esa es la propuesta de valor central de
SIGERIA (sección 12 del documento base).

## Segunda vuelta (2026-08-11) — integración real, mapa satelital, reportes oficiales

A pedido del usuario se corrigió la estructura de fondo y se agregó:

- **Expediente único**: los 4 módulos dejaron de ser formularios sueltos — ahora son un
  `Stepper` de un solo flujo (`mobile/lib/screens/nuevo_expediente_screen.dart`) que crea
  UN `id_objeto` y le vincula geometría, EDAN, mediciones y foto. Sin repetir datos.
- **Responsable de la recolección** e **Informante en la vivienda** (beneficiario) — con
  nombre, documento y datos de contacto, para trazabilidad institucional.
- **¿Requiere subsidio de arrendamiento?** — campo de necesidad EDAN.
- **Foto real de la vivienda** (cámara, no "subir archivo") vinculada al código del
  expediente vía `POST /api/edan/evidencias` — verificado.
- **Mapa "estilo Google Earth"**: satelital libre (Esri World Imagery) + calle + híbrido,
  con selector de capas y el objeto afectado señalado en su ubicación real — inspirado en
  la estructura de SW Maps (galería de mapas base + capas + cámara geoetiquetada).
- **`GET /api/estadisticas/general`**: totales por departamento, municipio, fenómeno,
  severidad y recolector — para reportes ante UNGRD (nacional), gobernación (departamental)
  y alcaldía (municipal), y para ver el avance cuando varias brigadas capturan a la vez.
- Bug real de crasheo silencioso en el nuevo Stepper, encontrado con `flutter test`
  (no con clics de navegador) y corregido — ver `mobile/README_MOBILE.md`.

Ver también `mobile/README_MOBILE.md` para el detalle técnico completo de esta vuelta.

## Tercera vuelta (2026-08-11) — checklist de daños, cámara real, ciclo cerrado, PDF y Drive

- **Checklist de daños por componente** (sin texto libre): 8 componentes constructivos
  (cimentación, columnas, vigas, muros, losas, escaleras, cubierta, no estructurales),
  cada uno con severidad de una lista (sin daño/leve/parcial/estructural/colapso) —
  el nivel de daño preliminar se calcula solo, tomando el peor componente. Así alguien
  sin formación técnica no tiene que redactar un diagnóstico.
- **Cámara real de verdad**: la foto tomada en la app se sube en base64 y el backend la
  guarda de verdad en `backend/workspace/evidencias/` (antes solo se guardaba el nombre
  del archivo). Verificado con `curl`: foto real → PDF con la foto real en su recuadro.
- **Mini-mapa conectado**: al elegir el departamento en el paso 1, el mapa del paso 3 ya
  aparece centrado en su capital como referencia; al capturar el GPS real, el punto se
  dibuja de inmediato en ese mismo mini-mapa.
- **Ciclo cerrado**: "Guardar expediente completo" → confirmación → mapa real en vivo
  (`GET /api/gis/geojson/{id_evento}`) con el punto recién guardado → volver al menú
  principal listo para otro expediente, sin arrastrar el formulario anterior.
- **Código de evento limpio y secuencial**: `SIGERIA-EVT-<año>-<consecutivo>` (antes tenía
  un sufijo hexadecimal al azar). El código de vivienda (`SIGERIA-CHO-<DIVIPOLA>-<FEN>-<año>-<consecutivo>`)
  ya era secuencial desde el principio, arrancando en 000001 por municipio+fenómeno+año.
- **Reporte PDF profesional** (`GET /api/expedientes/{id_objeto}/reporte.pdf`, con `reportlab`):
  ficha completa con identificación, responsable/informante, checklist de daños, necesidades,
  mediciones, georreferenciación y **fotos reales en recuadros** — verificado visualmente.
- **Carpeta real en Google Drive** ("SIGERIA - Expedientes", con README y un expediente de
  ejemplo) como destino de almacenamiento. La subida automática desde el backend queda
  pendiente de credenciales de Google Cloud (paso de configuración del usuario, no técnico);
  mientras tanto `GET /api/expedientes/{id_objeto}/exportar` deja todo listo para automatizarlo.
- **Pendiente de confirmación** (no aplicado a propósito): agregar tenencia de la vivienda
  (propia/arrendada), correo electrónico del informante y separar fotos por dentro/por fuera
  — comparado contra el flyer oficial del RUD (sismo Quibdó, 10 ago 2026).

## Cuarta vuelta (2026-08-11) — municipios reales de Colombia, DIVIPOLA automático

- **Catálogo oficial de 1.122 municipios** (`mobile/lib/data/colombia_municipios.dart`),
  descargado del dataset DANE/DIVIPOLA de datos.gov.co (`gdxc-w37w`), con nombre,
  código DIVIPOLA y coordenadas reales de cada uno. El dropdown "Municipio" del paso 1
  se filtra según el departamento elegido; **el código DIVIPOLA ya no se escribe a mano** —
  se genera solo al seleccionar el municipio.
- El mini-mapa del paso 3 ahora centra en la **coordenada real del municipio** elegido
  (no solo la capital del departamento) apenas se selecciona.
- Corregido el label "Fenómeno" que se veía cortado arriba del primer campo del formulario.
- Mapa base "Calle" cambiado de un estilo vectorial genérico a **teselas reales de
  OpenStreetMap** (edificios, vías, nombres) para más nivel de detalle.

## Quinta vuelta (2026-08-11) — mapa general en vivo, ficha por punto, control de versiones

- **Mapa general en vivo** (`GET /api/gis/geojson_general`): "Abrir mapa real" y el menú
  ya no muestran un evento suelto — cargan la **malla de todos los expedientes guardados**,
  creciendo en tiempo real. Chip con el conteo de puntos visible en el mapa.
- **Ficha al tocar un punto**: cada punto del mapa se puede tocar y abre una hoja con todos
  los datos del objeto afectado **y su foto real** (traída del servidor) — verificado en
  navegador de punta a punta: clic en el punto → ficha → foto.
- **Menú**: se agregaron los 4 pasos del expediente (antes solo estaban como tarjetas en
  Inicio), dejando claro que las 4 entradas abren el mismo expediente único.
- **Control de versiones**: se inicializó Git en el proyecto (antes no existía ningún
  repositorio) — 2 commits, `.gitignore` cubre `.venv/`, `build/`, bases de datos locales
  y evidencias. Motivado por revisión del libro *Pro Git* que el usuario tenía en Descargas.

## Sexta vuelta (2026-08-11) — cámara real (getUserMedia), mapa en vivo embebido en Inicio

- **Cámara real, no buscador de archivos**: nueva pantalla `CamaraCapturaScreen`
  (`mobile/lib/screens/camara_captura_screen.dart`) con el paquete `camera`/`camera_web` —
  vista previa en vivo, botón de captura, cambio frontal/trasera, y respaldo explícito
  "Elegir de la galería" si el dispositivo no tiene cámara o el permiso fue denegado.
  Reemplaza el `image_picker` con `ImageSource.camera`, que en navegadores de escritorio
  (Mac/Windows/Linux) **siempre** abre el buscador de archivos — es una limitación real
  del navegador (el atributo HTML `capture` solo lo respetan navegadores móviles), no un
  bug de la app; confirmado por búsqueda en web antes de construir la solución.
- **Bug real encontrado y corregido en el camino**: tras agregar el paquete `camera`, un
  primer intento de probar la cámara en el navegador mostró
  `MissingPluginException(No implementation found for method availableCameras...)`.
  La causa no era el navegador — era una **caché de build de Flutter desactualizada**:
  `.dart_tool/flutter_build/` tenía dos versiones distintas de
  `web_plugin_registrant.dart` (una vieja, sin `camera_web`, y una nueva ya correcta), y
  el build servido estaba usando la vieja. Se corrigió con `flutter clean` + `flutter pub
  get` + `flutter build web` — reconstrucción limpia, un solo registrant, ya con
  `CameraPlugin.registerWith(registrar)` incluido. Verificado leyendo el JS generado y
  confirmando el registrant único antes de volver a probar.
- **Verificación honesta en este entorno**: al pedir la cámara ya no aparece la excepción
  anterior — ahora la app pide permiso real de cámara (`getUserMedia`) y este navegador de
  pruebas (sandbox) la bloquea por política, mostrando
  `CameraException(CameraAccessDenied, ...)` con el botón de respaldo a la galería
  funcionando. Es exactamente el comportamiento honesto que el código ya contemplaba — en
  un navegador normal de usuario (Chrome/Safari/Firefox) o en el teléfono, el permiso se
  pedirá igual y, si se concede, la vista previa en vivo funcionará.
- **Mapa en vivo movido al espacio principal de Inicio**: nuevo widget
  `MapaVivoEmbed` (`mobile/lib/widgets/mapa_vivo_embed.dart`) — el espacio que antes
  ocupaban las 4 tarjetas de módulos ahora muestra el mapa satelital real con la malla de
  puntos creciendo, tocable igual que el mapa completo (abre la misma ficha con foto). Los
  4 módulos se movieron al menú lateral (ya reflejado en la Quinta vuelta). Responde a la
  sugerencia del usuario que había quedado sin contestar en la ronda anterior.

## Séptima vuelta (2026-08-11) — zoom del mapa, cámara frontal/trasera, NP, observaciones técnicas y Estadísticas

- **Zoom con botones +/-** en el mapa completo y en el mapa embebido de Inicio
  (`ControlZoomMapa` en `mobile/lib/screens/mapa_screen.dart`) — no depende solo del
  pellizco táctil. Atribución del basemap satelital recortada a un crédito simple (quedaba
  cortada y con jerga técnica sobre "API key" que no le sirve al usuario de campo).
- **Cámara: etiqueta frontal/trasera visible** en `CamaraCapturaScreen` — en una
  computadora (Mac) siempre muestra "frontal" porque es la única cámara que el sistema
  reporta (no hay trasera que elegir); en celular ya prefería trasera para fotos de campo.
  No era un bug, era falta de contexto en pantalla — ahora se explica.
- **"NP — No aplica"** agregado a la severidad de cada componente del checklist de daños
  (`mobile/lib/data/componentes_dano.dart`) — para cuando ese elemento no existe en la
  vivienda (p. ej. "Escaleras" en una casa de un piso). Excluido a propósito del cálculo
  del nivel de daño y del resumen de componentes afectados.
- **Observaciones técnicas (opcional)**: campo de texto libre al final del paso EDAN, solo
  para cuando quien evalúa es ingeniero/a y quiere detallar por escrito lo evidenciado — no
  reemplaza la lista de chequeo, que sigue siendo obligatoria para cualquier persona.
  Columna nueva en backend (`observaciones_tecnicas`), migrada con `ALTER TABLE` en la base
  ya existente, y agregada al reporte PDF.
- **Pantalla de Estadísticas nueva** (`mobile/lib/screens/estadisticas_screen.dart`), con
  todo el análisis hecho en Python en el backend, no en el cliente:
  - `GET /api/estadisticas/general` ahora acepta `departamento`/`municipio_divipola` y
    suma `total_personas_afectadas` (campo que el formulario ya capturaba pero **nunca se
    enviaba al backend** — bug real encontrado al construir esta pantalla, corregido).
  - `GET /api/estadisticas/componentes` (nuevo): "¿qué se daña más?" — cuenta por
    componente constructivo y severidad, a partir de una tabla nueva
    `componente_dano_detalle` (antes solo existía el resumen en texto, sin poder agregarlo
    de verdad). Excluye `sin_dano`/`no_aplica` del ranking.
  - `GET /api/estadisticas/registro_reciente` (nuevo): los últimos expedientes guardados,
    más reciente primero — la "ventana de registro en vivo" que pidió el usuario. La
    pantalla se refresca sola cada 20 s mientras está abierta (`Timer.periodic`).
  - `GET /api/gis/geojson_general` ahora también acepta el filtro por zona, reusado tanto
    en la pantalla de Estadísticas como en el panel de Capas del mapa completo.
  - Verificado end-to-end con `curl`: crear expediente con `personas_afectadas` y
    `componentes` (incluyendo `no_aplica`) → los 4 endpoints devuelven exactamente lo
    esperado, con y sin filtro por departamento.
- **Lección de esta ronda sobre el navegador de pruebas**: la entrega de clics
  (`computer{action:"left_click"}`) se volvió errática de forma intermitente e
  impredecible al verificar el Drawer/menú lateral — mismos clics, mismas coordenadas,
  a veces navegaban y a veces no, incluso disparando el evento manualmente por
  JavaScript (`PointerEvent`/`MouseEvent`). Confirmado que NO es un bug de la app:
  `flutter analyze` (0 errores), `flutter test` (navegación real por `tester.tap()`,
  2/2 pasa) y verificación directa de los 4 endpoints nuevos por `curl` fueron
  concluyentes. Recomendado probar la pantalla de Estadísticas en un navegador real de
  usuario (no el sandbox de pruebas), donde los clics sí son eventos nativos del SO.

## Octava vuelta (2026-08-11) — publicado en GitHub + Drive por departamento

- **Repositorio privado en GitHub**: `https://github.com/conelyaya-bot/sigeria-sat-geoai-campo`
  (código completo, `git push` real, verificado listando el contenido del repo por API).
  Publicarlo requirió autenticar `gh` CLI con OAuth (flujo de dispositivo) — el paso que
  más costó no fue el código sino la verificación en dos pasos (2FA) de GitHub Mobile,
  que hay que aprobar desde el teléfono antes de que el token quede activo.

### Vincular Google Drive por departamento (sin credenciales de Google Cloud)

La subida automática de fotos a Drive vía la API de Google requiere un proyecto de Google
Cloud con credenciales — eso lo tiene que crear cada organización, no se puede automatizar
desde aquí (ver Tercera vuelta). Pero hay una forma real de "vincular" Drive **sin ninguna
API**: usando **Google Drive para escritorio** (la app oficial de Google que sincroniza una
carpeta del computador con Drive) y apuntando el backend a esa carpeta.

**Pasos para que cualquier departamento de gestión del riesgo use su propio Drive:**

1. Instalar [Google Drive para escritorio](https://www.google.com/drive/download/) en el
   computador donde corre el backend, con la cuenta de Google de ese departamento.
2. Dentro de su Drive, crear una carpeta, p. ej. `SIGERIA - Expedientes - <Departamento>`.
   Drive la sincroniza sola a una ruta local (en Mac, algo como
   `~/Library/CloudStorage/GoogleDrive-<correo>/Mi unidad/SIGERIA - Expedientes - Chocó`).
3. Arrancar el backend con la variable de entorno apuntando a esa ruta:
   ```bash
   export SIGERIA_CARPETA_EVIDENCIAS="/ruta/a/esa/carpeta/sincronizada"
   export SIGERIA_DB_PATH="/ruta/a/esa/carpeta/sincronizada/sigeria_local.db"
   uvicorn app.main:app --host 0.0.0.0 --port 8010
   ```
4. Desde ese momento, cada foto de evidencia que la app guarde queda en esa carpeta —
   y Google Drive la sube sola, sin que el backend sepa nada de la API de Drive.

Esto significa que **cada departamento puede tener su propio SIGERIA aislado**, con sus
propios datos en su propio Drive, corriendo la misma base de código — sin pedirle a nadie
credenciales de Google Cloud ni tocar una sola línea de Python. Es el mismo principio que
ya se usaba para `SIGERIA_DB_PATH` (la base de datos también es configurable así desde la
Segunda vuelta), extendido ahora a las fotos.

**Limitación honesta**: esto solo sincroniza *archivos*, no da un enlace clicable a Drive
dentro de la app todavía — la persona debe abrir Drive por su cuenta para ver la carpeta.
Un enlace directo dentro de la app (botón "Ver en Drive") requeriría guardar la URL de la
carpeta como config y mostrarla en el menú — queda anotado como mejora futura, no
implementada aún porque no había una carpeta de Drive real conectada a este backend para
probarlo de verdad (solo la carpeta creada a mano en la Tercera vuelta, sin backend
conectado a ella).

## Novena vuelta (2026-08-11/12) — desplegada de verdad en Google Cloud (gratis, para siempre)

**http://35.196.65.232** — la app completa (backend + interfaz) corriendo en una VM real,
pública, con IP fija. No es una demo temporal: usa el nivel **Always Free** de Google
Cloud (1 VM `e2-micro` + 30 GB de disco, gratis para siempre mientras no se pase de esos
límites — no es un crédito de prueba que se acaba).

- **Un solo servicio sirve todo**: se modificó `backend/app/main.py` para montar la app
  Flutter Web ya compilada (`backend/app/static_web/`, generada con
  `flutter build web --dart-define=SIGERIA_API=` — vacío a propósito, para que las
  peticiones queden relativas al mismo dominio) como archivos estáticos, DESPUÉS de las
  rutas `/api/...`. Un usuario que entra a `http://35.196.65.232` ve la app; la misma app
  le pide los datos a `/api/...` en el mismo dominio, sin configurar ninguna URL.
- **Máquina**: `sigeria-campo`, tipo `e2-micro`, zona `us-east1-b` (una de las 3 zonas
  elegibles para Always Free — `us-west1-a` había gotado su cupo por saturación temporal
  al momento del despliegue), Debian 12, disco de 30 GB.
- **Arranca sola y se reinicia sola si falla**: un *startup script* de la VM instala
  Python/git, clona el repo (público, sin credenciales), instala dependencias en un
  venv, y registra un servicio `systemd` (`sigeria.service`) con `Restart=always` —
  si la VM se reinicia (o el proceso se cae), vuelve a levantarse sin intervención manual.
- **Datos persistentes de verdad**: `SIGERIA_DB_PATH` y `SIGERIA_CARPETA_EVIDENCIAS`
  (las mismas variables de entorno de la Séptima/Octava vuelta) apuntan a
  `/opt/sigeria-data/` en el disco de arranque de la VM — sobrevive reinicios y apagados
  (solo se perdería si alguien borra la instancia completa, no con un simple reinicio).
- **IP fija**: se reservó la IP efímera como estática (`sigeria-campo-ip`) para que el
  enlace nunca cambie, ni siquiera si la VM se reinicia.
- **Firewall abierto solo para HTTP** (`tcp:80`, regla `sigeria-allow-http`) — el puerto
  SSH sigue protegido por las reglas por defecto de Google Cloud (solo con `gcloud`
  autenticado, no expuesto a cualquiera).
- **Verificado real, no solo "debería funcionar"**: `curl` contra la IP pública confirmó
  `/api/salud`, la interfaz cargando (`200 text/html`), un evento creado de verdad vía
  `POST /api/eventos` (con ID secuencial real), y navegador real (Browser pane) mostrando
  la app funcionando desde la IP pública, no desde `localhost`.

### Cómo actualizar la app en vivo cuando se agregue código nuevo

```bash
gcloud compute ssh sigeria-campo --zone=us-east1-b --project=campa2026-7a020 \
  --command="cd /opt/sigeria && sudo git pull && cd backend && sudo ./.venv/bin/pip install -r requirements.txt && sudo systemctl restart sigeria"
```

(El *startup script* completo, para volver a crear la VM desde cero si hiciera falta,
queda documentado en este README — no vive en un archivo aparte del repo todavía; queda
anotado como pendiente moverlo a `deploy/startup.sh` en el repo para no depender de que
alguien lo tenga guardado aparte.)

### Limitaciones honestas de este despliegue

- Es **una sola VM pequeña** (2 vCPU compartidas, 1 GB RAM) — suficiente para un piloto o
  una demo con varios usuarios a la vez, no para una carga masiva de producción nacional.
- La base de datos sigue siendo **SQLite**, no PostgreSQL/PostGIS — sigue pendiente la
  migración documentada desde el inicio del proyecto (`docs/MODELO_DATOS.md`).
- **Actualizado (Décima vuelta): ya va por HTTPS real.** Se resolvió el problema de "no
  hay dominio propio" usando **sslip.io** — un servicio gratuito que da un nombre
  (`35-196-65-232.sslip.io`) que resuelve directo a la IP sin configurar DNS. Con ese
  nombre sí se pudo emitir un certificado real de Let's Encrypt vía `certbot --nginx`.
  Nginx quedó de proxy reverso en 80/443 (redirige HTTP→HTTPS automático); `uvicorn` pasó
  a escuchar solo en `127.0.0.1:8080` (ya no expuesto directo a internet). El certificado
  se renueva solo (`certbot.timer` ya activo). La URL con el **candado real** para
  compartir es `https://35-196-65-232.sslip.io` — la IP sola (`http://35.196.65.232`)
  sigue funcionando pero sin ese candado, no es la que hay que repartir.
- El repositorio de GitHub se puso en **público** (antes era privado) porque la máquina
  necesita clonarlo sin credenciales — se decidió así con el usuario porque el código no
  tiene secretos ni datos reales de personas (esos viven en la base de datos de cada
  despliegue, no en el repo).

## Próximos pasos reales (no aspiracionales)

1. Instalar Flutter y compilar el scaffold móvil contra el backend ya funcional.
2. Completar la Matriz Maestra con el resto de fenómenos/sectores (secciones 8-9 del
   documento base) — hoy solo tiene las filas mínimas del MVP.
3. Decidir el checklist de `docs/DECISIONES_PENDIENTES.md` antes de cualquier piloto real.
4. Migrar el backend de SQLite a PostgreSQL+PostGIS cuando haya credenciales/instalación
   confirmadas (ver nota en `docs/MODELO_DATOS.md`).

---
*SIGERIA es un nombre de trabajo. No se presenta como herramienta oficial de la UNGRD.
No sustituye dictamen profesional, protocolo institucional ni instrumentos oficiales
EDAN/RUD.*
