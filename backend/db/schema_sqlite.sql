-- SIGERIA — esquema de desarrollo local (SQLite, cero instalación)
-- La geometría se guarda como GeoJSON en TEXT (columna geom_geojson) en vez de tipo geometry real.
-- Mismo patrón que backend_encuestas/db_local.py del proyecto Escuchar Turbo.

CREATE TABLE IF NOT EXISTS usuario (
    id_usuario      TEXT PRIMARY KEY,
    nombre          TEXT NOT NULL,
    rol             TEXT NOT NULL,
    verificado      INTEGER NOT NULL DEFAULT 0,
    creado_en       TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS evento (
    id_evento       TEXT PRIMARY KEY,
    fenomeno        TEXT NOT NULL,
    fecha_evento    TEXT NOT NULL,
    municipio_divipola TEXT NOT NULL,
    descripcion     TEXT,
    creado_por      TEXT,
    creado_en       TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS objeto_afectado (
    id_objeto       TEXT PRIMARY KEY,
    id_evento       TEXT NOT NULL REFERENCES evento(id_evento),
    tipo_objeto     TEXT NOT NULL,
    estado_operativo TEXT NOT NULL DEFAULT 'sin_evaluar',
    nivel_dano_preliminar TEXT,
    -- Ubicación detallada del objeto/vivienda (sección 6: "identificar
    -- municipio, zona, barrio/vereda"). Departamento es catálogo cerrado
    -- (33 DANE) en el cliente; aquí se guarda el nombre ya validado.
    departamento    TEXT,
    barrio_vereda   TEXT,
    direccion       TEXT,
    -- Responsable de la recolección (brigadista/encuestador que levanta el dato)
    recolector_nombre     TEXT,
    recolector_documento  TEXT,
    recolector_cargo      TEXT,
    recolector_entidad    TEXT,
    -- Quien entrega la información en la vivienda (beneficiario/informante)
    informante_nombre       TEXT,
    informante_documento    TEXT,
    informante_parentesco   TEXT,   -- relación con el hogar: jefe de hogar, cónyuge, etc.
    informante_telefono     TEXT,
    -- Necesidad específica de vivienda temporal (EDAN — atención humanitaria)
    requiere_subsidio_arrendamiento INTEGER,  -- NULL=sin evaluar, 0=no, 1=sí
    -- Resumen legible de la lista de chequeo por componente (columnas, muros,
    -- cubierta, etc. — sección 8 del documento base). El detalle fila por
    -- fila queda para las tablas Componente/Daño de fase 3 (roadmap); esto
    -- documenta ya la selección sin volver a pedir texto libre.
    resumen_componentes_dano TEXT,
    -- Espacio libre opcional: solo si quien evalúa es ingeniero/a y quiere
    -- detallar por escrito lo evidenciado. No reemplaza la lista de chequeo.
    observaciones_tecnicas TEXT,
    -- Personas del hogar afectadas por el evento (sección 26: indicadores de
    -- afectados) — se capturaba en el formulario pero no se guardaba.
    personas_afectadas INTEGER,
    creado_por      TEXT,
    creado_en       TEXT NOT NULL DEFAULT (datetime('now')),
    actualizado_en  TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Detalle fila por fila de la lista de chequeo de componentes (columnas,
-- muros, cubierta, etc.) — antes solo se guardaba el resumen en texto
-- (`objeto_afectado.resumen_componentes_dano`). Esta tabla permite calcular
-- de verdad "qué componentes se dañan más" en estadísticas, no solo leer
-- resúmenes uno por uno.
CREATE TABLE IF NOT EXISTS componente_dano_detalle (
    id_detalle      TEXT PRIMARY KEY,
    id_objeto       TEXT NOT NULL REFERENCES objeto_afectado(id_objeto),
    componente      TEXT NOT NULL,   -- id de mobile/lib/data/componentes_dano.dart (cimentacion, muros, ...)
    severidad       TEXT NOT NULL,   -- no_aplica|sin_dano|leve|moderado|severo|colapso
    creado_en       TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS geometria (
    id_geometria    TEXT PRIMARY KEY,
    id_objeto       TEXT NOT NULL REFERENCES objeto_afectado(id_objeto),
    geom_tipo       TEXT NOT NULL,          -- Point | LineString | Polygon
    geom_geojson    TEXT NOT NULL,          -- geometry GeoJSON como texto, EPSG:4326
    precision_gnss_m REAL,
    fuente_posicion TEXT,
    capturado_en    TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS necesidad (
    id_necesidad    TEXT PRIMARY KEY,
    id_objeto       TEXT NOT NULL REFERENCES objeto_afectado(id_objeto),
    tipo            TEXT NOT NULL,
    estado          TEXT NOT NULL DEFAULT 'abierta',
    creado_en       TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS evidencia (
    id_evidencia    TEXT PRIMARY KEY,
    id_objeto       TEXT NOT NULL REFERENCES objeto_afectado(id_objeto),
    tipo            TEXT NOT NULL,
    url_almacenamiento TEXT NOT NULL,
    usuario_id      TEXT,
    creado_en       TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS medicion (
    id_medicion     TEXT PRIMARY KEY,
    id_objeto       TEXT NOT NULL REFERENCES objeto_afectado(id_objeto),
    tipo            TEXT NOT NULL,
    valor           REAL NOT NULL,
    unidad          TEXT NOT NULL,
    metodo          TEXT NOT NULL,
    precision_categoria TEXT NOT NULL,
    creado_en       TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Inspección técnica AIS (Asociación Colombiana de Ingeniería Sísmica) —
-- "Guía Técnica para la Inspección de Edificaciones Después de un Sismo",
-- formulario oficial que usa la Unidad de Gestión del Riesgo (nacional y
-- local). Reemplaza el checklist simplificado de 8 componentes que tenía
-- SIGERIA antes — ahora la evaluación de daño estructural sigue EXACTAMENTE
-- la estructura y terminología del formulario oficial, campo por campo,
-- para que el dato levantado sea directamente utilizable/entregable ante
-- esas entidades. Una fila por inspección (normalmente una por objeto, pero
-- no se fuerza 1:1 por si se necesita una segunda inspección más adelante).
CREATE TABLE IF NOT EXISTS inspeccion_ais (
    id_inspeccion   TEXT PRIMARY KEY,
    id_objeto       TEXT NOT NULL REFERENCES objeto_afectado(id_objeto),

    -- Encabezado / identificación catastral
    localidad               TEXT,
    nombre_barrio            TEXT,
    ident_catastral_barrio   TEXT,
    ident_catastral_manzana  TEXT,
    ident_catastral_predio   TEXT,
    ident_catastral_construccion TEXT,
    formulario_numero        TEXT,
    inspeccion_tipo           TEXT,     -- exterior_interior | no_se_pudo_entrar

    -- Identificación de la edificación
    tipo_via                 TEXT,      -- carrera|calle|transv|diag|avda|otro
    numero_via                TEXT,
    nombre_edificacion        TEXT,
    uso_predominante           TEXT,
    uso_predominante_planta_baja TEXT,
    niveles_sobre_terreno      INTEGER,
    sotanos                     INTEGER,
    pisos_total                  INTEGER,
    dimension_frente_m            REAL,
    dimension_fondo_m              REAL,

    -- Descripción de la estructura
    sistema_estructural            TEXT,
    sistema_estructural_otro        TEXT,
    tipo_entrepiso                   TEXT,
    tipo_entrepiso_otro               TEXT,
    anio_construccion                  TEXT,

    -- Estado general de la edificación
    existe_colapso                       TEXT,   -- no|parcial|total
    desviacion_inclinacion                TEXT,   -- si|no|no_determinado
    falla_asentamiento_cimentacion         TEXT,   -- si|no|no_determinado

    -- Daños en elementos arquitectónicos (ninguno|leve|moderado|fuerte|severo)
    -- — 11 elementos según la guía IDIGER 2018 (antes solo 7).
    dano_muros_fachada                       TEXT,
    dano_vidrios_exteriores                   TEXT,
    dano_acabados_exteriores                   TEXT,
    dano_muros_divisorios                       TEXT,
    dano_balcones                                TEXT,
    dano_cielo_rasos                              TEXT,
    dano_cubierta                                  TEXT,
    dano_escaleras                                  TEXT,
    instalaciones_afectadas                          TEXT,  -- CSV: acueducto,alcantarillado,energia,gas
    dano_instalaciones                                TEXT,
    dano_ductos_ventilacion                            TEXT,
    dano_tanques_elevados                               TEXT,

    -- Problemas geotécnicos
    falla_talud                                      TEXT,  -- no|puntual|general
    asentamiento_subsidencia_licuacion                TEXT,  -- no|puntual|general
    grietas_terreno_circundante                        TEXT,  -- no|incipientes|generalizadas

    -- Problemas del entorno (sección nueva de la guía 2018 — clasificación E)
    edificio_vecino_critico                              TEXT,  -- no|si|no_determinado
    evento_adverso_inminente                              TEXT,  -- no|si

    -- Daños en elementos estructurales (piso de mayor afectación)
    nivel_entrepiso_mayor_dano                          TEXT,
    dano_columnas_muros_portantes                        TEXT,
    dano_vigas                                            TEXT,
    dano_nudos_conexion                                    TEXT,
    dano_entrepisos                                         TEXT,

    -- Clasificación global — la guía IDIGER 2018 exige 5 evaluaciones
    -- independientes (A-E), cada una con su propia tabla de criterios, y
    -- toma la MÁS CONSERVADORA como resultado final. Se guardan las 5 por
    -- separado (trazabilidad de cuál fue la que definió el resultado) más
    -- la clasificación global ya combinada.
    clasificacion_a_estado_general                             TEXT,  -- habitable|uso_restringido|no_habitable|peligro_colapso
    clasificacion_b_geotecnico                                  TEXT,
    clasificacion_c_no_estructural                               TEXT,
    clasificacion_d_estructural                                   TEXT,
    clasificacion_e_entorno                                        TEXT,
    pct_dano_global                                          REAL,
    clasificacion_global_dano                                 TEXT,  -- ninguno|leve|moderado|fuerte|severo|colapso_total
    clasificacion_habitabilidad                                TEXT, -- verde|amarillo|naranja|rojo
    existe_clasificacion_previa                                 INTEGER,
    clasificacion_previa_cual                                    TEXT,

    -- Recomendaciones y medidas de seguridad (listas separadas por coma)
    requiere_visita_especializada                                 TEXT,
    recomienda_intervencion                                        TEXT,
    medidas_seguridad                                               TEXT,
    desconectar_servicios                                            TEXT,
    lugares_medidas_seguridad_texto                                   TEXT,

    -- Condiciones preexistentes — sección 3.3 de la guía IDIGER 2018.
    -- No entran en la clasificación automática A-E (la guía dice
    -- explícitamente que quedan "a criterio del evaluador"); son factores
    -- de vulnerabilidad que documentan POR QUÉ se dio el daño observado.
    calidad_construccion                                               TEXT,  -- buena|regular|mala
    posicion_edificacion_manzana                                        TEXT,
    configuracion_planta                                                 TEXT,
    configuracion_altura                                                  TEXT,
    configuracion_estructural                                              TEXT,
    tipo_suelo                                                              TEXT,  -- duro|medio|blando
    tipo_cimentacion                                                         TEXT,  -- superficial|profunda|no_determinado
    calidad_cimentacion                                                       TEXT,  -- buena|regular|mala|no_determinado
    condiciones_topograficas                                                   TEXT,
    tipo_cubierta                                                               TEXT,  -- maciza|liviana
    condiciones_amarre_cubierta                                                  TEXT,  -- buena|regular|mala
    efecto_columna_corta                                                          TEXT,  -- si|no
    continuidad_columnas_vigas                                                     TEXT,  -- si|no
    evidencia_anclaje_no_estructural                                                TEXT,  -- si|no|no_sabe
    indicios_danos_sismos_anteriores                                                 INTEGER,
    hubo_reparacion                                                                   TEXT,  -- total|parcial|ninguna|no_determinado
    reforzamiento_estructural_anterior                                                 TEXT,  -- total|parcial|ninguna|no_determinado

    -- Efecto en los ocupantes
    hubo_muertos_heridos                                                      TEXT,  -- no|si|no_se_sabe
    numero_personas_fallecidas                                                 INTEGER,
    numero_heridos                                                              INTEGER,

    -- Ocupación de la edificación
    edificacion_habitada                                                        INTEGER,
    numero_ocupantes                                                             INTEGER,
    num_unidades_existentes                                                       INTEGER,
    num_unidades_no_habitables                                                     INTEGER,

    -- Persona para contacto — email nuevo en la guía 2018 (nombre/teléfono
    -- ya se reutilizan de objeto_afectado.informante_*, pero el formulario
    -- oficial trae un contacto propio de esta sección; se guarda aquí el
    -- correo para no forzar ese campo en el objeto general).
    email_contacto                                                                  TEXT,

    comentarios                                                                     TEXT,

    -- Inspectores
    codigo_comision                                                                TEXT,
    numero_evaluadores                                                              INTEGER,
    nombre_lider_comision                                                            TEXT,
    otro_inspector                                                                   TEXT,

    fecha_inspeccion       TEXT,
    creado_por             TEXT,
    creado_en              TEXT NOT NULL DEFAULT (datetime('now')),
    actualizado_en         TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS auditoria (
    id_auditoria    INTEGER PRIMARY KEY AUTOINCREMENT,
    tabla           TEXT NOT NULL,
    id_registro     TEXT NOT NULL,
    accion          TEXT NOT NULL,
    usuario_id      TEXT,
    detalle         TEXT,
    creado_en       TEXT NOT NULL DEFAULT (datetime('now'))
);
