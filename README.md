<p align="center"><img src="docs/branding/sigeria_logo_original.png" width="180" alt="Logo SIGERIA"></p>

# SIGERIA — Sistema Inteligente Geoespacial para Evaluación, Respuesta e Inspección de Afectaciones

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
