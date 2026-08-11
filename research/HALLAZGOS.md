# Investigación: herramientas y estándares comparables (GitHub y otras plataformas)

> Objetivo: identificar qué ya existe (código, formularios, estándares) que SIGERIA puede
> reutilizar, referenciar o diferenciarse de, antes de programar desde cero.
> Búsqueda realizada 2026-08-11 vía WebSearch. Todas las URLs deben verificarse en el
> momento de usarlas (proyectos open source cambian de estado con frecuencia).

## 1. Recolección de formularios offline (referencia directa para el "motor de formularios adaptativos")

| Proyecto | Qué aporta | Licencia | Relevancia para SIGERIA |
|---|---|---|---|
| **ODK (Open Data Kit)** — [github.com/getodk](https://github.com/getodk) | Suite madura: ODK Collect (Android), ODK Central (servidor), XLSForm (autoría de formularios en Excel con lógica condicional). Usado por OMS, Cruz Roja, ONU. | Apache 2.0 | Referencia obligada para el "motor de formularios adaptativos" (sección 7-8 del documento). SIGERIA puede modelar su lógica de `relevant`/`constraint` de XLSForm para las reglas de "condición para mostrar el campo" de la Matriz Maestra. No cubre GIS técnico ni mediciones con sensores — ahí está el diferencial de SIGERIA. |
| **XLSForm spec** — [xlsform.org](https://xlsform.org) | Estándar abierto para describir formularios complejos en una hoja de cálculo (columnas `type`, `name`, `label`, `relevant`, `constraint`, `calculation`). | — | Se puede usar **como formato de exportación/edición** de la Matriz Maestra de SIGERIA (sección 24), aprovechando herramientas ya existentes (Enketo, ODK Validate) para validarla. |
| **KoboToolbox** — [github.com/kobotoolbox](https://github.com/kobotoolbox) | Fork de ODK co-desarrollado con OCHA, con biblioteca de plantillas humanitarias (evaluaciones de necesidades, shelter, WASH). | AGPL/GPL según repo | Buena fuente de **plantillas de preguntas ya validadas en campo humanitario** para adaptar a los módulos sectoriales (salud, educación, agua/saneamiento) de la sección 9. |
| **Enketo** — [github.com/enketo](https://github.com/enketo) | Motor web/offline de formularios XForms/XLSForm, usado como frontend de ODK Central y Kobo. | Apache 2.0 | Si se opta por reusar el estándar XLSForm, Enketo permite renderizar el mismo formulario en navegador (útil para el módulo web/"sala de crisis" o para brigadas sin app nativa). |

## 2. GIS de campo offline (referencia directa para el módulo "GIS de campo")

| Proyecto | Qué aporta | Licencia | Relevancia |
|---|---|---|---|
| **QField** — [github.com/opengisch/QField](https://github.com/opengisch/QField) | App móvil que abre proyectos QGIS nativos (.qgz) offline, edición de geometría punto/línea/polígono, formularios QGIS. | GPLv2 | SIGERIA ya usa QGIS como "SIG servidor/escritorio" (sección 16) — **QField permite prototipar el módulo GIS offline sin programar una app desde cero**, usando el mismo proyecto `.qgz` que se genera con el MCP `qgis-earthengine`. Útil como piloto rápido antes de invertir en Flutter+MapLibre nativo. |
| **Mergin Maps** — [github.com/MerginMaps](https://github.com/MerginMaps) | Servidor + apps móviles para edición multiusuario de datos QGIS con sincronización y control de versiones por registro (resuelve conflictos). | AGPLv3 (server), apps gratuitas | Su motor de sincronización/versionado por registro es exactamente el problema descrito en la sección 18 ("control de versiones por registro y resolución de conflictos") — vale la pena estudiar su arquitectura antes de programar la cola de sincronización de SIGERIA. |
| **SMASH** (Surveyor's Mobile Application for Spatial Happiness) — en `fluttergems/awesome-open-source-flutter-apps` | App Flutter de mapeo digital de campo, open source. | GPLv3 | Ejemplo real de **app Flutter + GIS offline** ya construida — referencia de arquitectura de código para `mobile/`. |

## 3. Backend / stack de referencia (FastAPI + PostGIS)

| Proyecto | Qué aporta |
|---|---|
| [grillazz/fastapi-postgis](https://github.com/grillazz/fastapi-postgis) | Integración FastAPI + SQLAlchemy + GeoAlchemy2 + PostGIS vía psycopg — patrón base para `backend/`. |
| [fastapi/full-stack-fastapi-template](https://github.com/fastapi/full-stack-fastapi-template) | Plantilla oficial FastAPI+React+PostgreSQL+Docker — referencia de estructura de proyecto y CI. |
| [mkeller3/FastGeospatial](https://github.com/mkeller3/FastGeospatial) | API geoespacial sobre PostGIS con FastAPI — patrones de endpoints espaciales (bbox, GeoJSON). |
| [fer-ri/offline-first-flutter-boilerplate](https://github.com/fer-ri/offline-first-flutter-boilerplate) | Boilerplate Flutter con sincronización bidireccional REST — referencia para la cola offline del móvil. |

## 4. Visión por computador / detección de daños (referencia para el módulo GeoAI, sección 15)

Existen múltiples proyectos abiertos de detección de grietas en concreto con CNN/segmentación
(U-Net, ResNet, MobileNet): `tssteja/structural-damage-detection`, `cilab-ufersa/crack_detection_app`,
`ayush-agarwal-0502/Concrete-Crack-Detection`, lista curada en el topic
[`damage-detection`](https://github.com/topics/damage-detection) y el listado
[`nantonzhang/Awesome-Crack-Detection`](https://github.com/nantonzhang/Awesome-Crack-Detection).
Ninguno está listo para producción ni entrenado con contexto colombiano/tropical, pero sirven
como punto de partida técnico para la Fase 4 (GeoAI) del roadmap — **no para el MVP**, que
según el propio documento (sección 22) debe ir sin IA todavía.

En el proyecto [[proyecto-transicion-energetica-choco]] ya se probó en esta misma máquina un
pipeline con **MobileSAM en ONNX** (sin PyTorch, corre en equipo con 8.6GB RAM) para
segmentación asistida por clic sobre imágenes Sentinel-2 — el mismo patrón (`segmentador_ia`
plugin QGIS) es reutilizable como base técnica cuando SIGERIA llegue a la Fase 4 GeoAI.

## 5. Plataformas institucionales colombianas (para el diccionario de interoperabilidad, sección 13)

- **UNGRD — Listado Maestro de Documentos**: confirma vigente el formato `FR-1703-SMD-08/09`
  de Evaluación de Daños y Análisis de Necesidades.
  https://portal.gestiondelriesgo.gov.co/Documents/SIPLAG/Listado-Maestro-de-Documentos-UNGRD.xls
- **Caja de herramientas para el manejo de desastres (2ª edición)** — repositorio institucional
  con formatos EDAN e inspección de vivienda:
  https://repositorio.gestiondelriesgo.gov.co:8443/handle/20.500.11762/18505
  (incluye el `Manual Operativo para la Evaluación de Daños y Análisis de Necesidades`, PDF directo).
- **RUD (Registro Único de Damnificados)** — portal activo: https://rud.gestiondelriesgo.gov.co/home/
  y manual de usuario (ejemplo departamental, Boyacá):
  https://www.boyaca.gov.co/SecInfraestructura/images/OPAD/documentos/rud.pdf
- **SNIGRD** (Sistema Nacional de Información para la Gestión del Riesgo de Desastres):
  https://snigrd.gestiondelriesgo.gov.co/

## 6. Conclusión — qué construir vs. qué reusar en el MVP

1. **No reinventar el motor de formularios desde cero.** Se recomienda que la Matriz Maestra
   (sección 24 del documento) se edite/exporte en **formato XLSForm-compatible** desde el
   principio: reduce riesgo, permite validar con herramientas ya existentes (`pyxform`,
   `ODK Validate`) y deja abierta la opción de usar Enketo/ODK Collect como fallback web/Android
   si el desarrollo de la app Flutter se atrasa.
2. **QField/Mergin Maps son la ruta más rápida para validar el módulo GIS offline en campo**
   antes de tener la app Flutter nativa terminada — puede usarse como piloto paralelo con el
   mismo `.qgz` que ya genera el MCP `qgis-earthengine` en este proyecto.
3. **Ningún proyecto encontrado cubre el diferencial real de SIGERIA**: unir formulario
   multiamenaza + inspección por componente + mediciones con sensores del teléfono + EDAN/RUD
   colombiano + captura única, todo offline-first. Esto confirma que SIGERIA es una integración
   original y no una app duplicada — coincide con la sección 25 del documento (comparación
   estratégica).
4. La IA de detección de daños queda para la Fase 4 (GeoAI), reusando el patrón MobileSAM ONNX
   ya validado en este equipo (ver [[proyecto-transicion-energetica-choco]]), no para el MVP.

Ver también `docs/DECISIONES_PENDIENTES.md` (sección 30 del documento original) para las
decisiones institucionales que ninguna investigación técnica puede resolver por el equipo.
