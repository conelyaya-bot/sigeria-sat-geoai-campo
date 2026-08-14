-- SIGERIA — esquema de producción (PostgreSQL + PostGIS)
-- Requiere: CREATE EXTENSION IF NOT EXISTS postgis;

CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE usuario (
    id_usuario      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre          TEXT NOT NULL,
    rol             TEXT NOT NULL CHECK (rol IN (
                        'ciudadania','brigadista','organismo_respuesta','profesional',
                        'especialista','sector','coordinador','administrador')),
    verificado      BOOLEAN NOT NULL DEFAULT FALSE,
    creado_en       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE evento (
    id_evento       TEXT PRIMARY KEY,               -- SIGERIA-EVT-<AAAA>-<NNNN>
    fenomeno        TEXT NOT NULL CHECK (fenomeno IN (
                        'sismo','inundacion','deslizamiento','vendaval','incendio',
                        'erosion_socavacion','creciente_subita','otro')),
    fecha_evento    TIMESTAMPTZ NOT NULL,
    municipio_divipola TEXT NOT NULL,
    descripcion     TEXT,
    creado_por      UUID REFERENCES usuario(id_usuario),
    creado_en       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE objeto_afectado (
    id_objeto       TEXT PRIMARY KEY,                -- SIGERIA-CHO-DIVIPOLA-FEN-AAAA-NNNNNN
    id_evento       TEXT NOT NULL REFERENCES evento(id_evento),
    tipo_objeto     TEXT NOT NULL,                    -- vivienda, salud, educacion, via, puente...
    estado_operativo TEXT NOT NULL DEFAULT 'sin_evaluar'
                        CHECK (estado_operativo IN ('operativo','parcial','fuera_de_servicio','sin_evaluar')),
    nivel_dano_preliminar TEXT CHECK (nivel_dano_preliminar IN
                        ('sin_dano','leve','moderado','severo','colapso')),
    -- Ubicación detallada del objeto/vivienda (sección 6 del documento base)
    departamento    TEXT,
    barrio_vereda   TEXT,
    direccion       TEXT,
    -- Responsable de la recolección (brigadista/encuestador)
    recolector_nombre     TEXT,
    recolector_documento  TEXT,
    recolector_cargo      TEXT,
    recolector_entidad    TEXT,
    -- Informante en la vivienda (beneficiario que entrega la información)
    informante_nombre       TEXT,
    informante_documento    TEXT,
    informante_parentesco   TEXT,
    informante_telefono     TEXT,
    -- Necesidad de vivienda temporal (atención humanitaria)
    requiere_subsidio_arrendamiento BOOLEAN,
    -- Resumen legible de la lista de chequeo por componente (sección 8)
    resumen_componentes_dano TEXT,
    -- Espacio libre opcional: solo si quien evalúa es ingeniero/a y quiere
    -- detallar por escrito lo evidenciado. No reemplaza la lista de chequeo.
    observaciones_tecnicas TEXT,
    -- Personas del hogar afectadas por el evento (sección 26: indicadores de
    -- afectados) — se capturaba en el formulario pero no se guardaba.
    personas_afectadas INTEGER,
    creado_por      UUID REFERENCES usuario(id_usuario),
    creado_en       TIMESTAMPTZ NOT NULL DEFAULT now(),
    actualizado_en  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Detalle fila por fila de la lista de chequeo de componentes — permite
-- calcular de verdad "qué componentes se dañan más" en estadísticas.
CREATE TABLE componente_dano_detalle (
    id_detalle      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_objeto       TEXT NOT NULL REFERENCES objeto_afectado(id_objeto),
    componente      TEXT NOT NULL,
    severidad       TEXT NOT NULL CHECK (severidad IN
                        ('no_aplica','sin_dano','leve','moderado','severo','colapso')),
    creado_en       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_componente_dano_objeto ON componente_dano_detalle (id_objeto);

CREATE TABLE geometria (
    id_geometria    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_objeto       TEXT NOT NULL REFERENCES objeto_afectado(id_objeto),
    geom            geometry(Geometry, 4326) NOT NULL,   -- point | linestring | polygon
    precision_gnss_m REAL,
    fuente_posicion TEXT CHECK (fuente_posicion IN ('gnss_interno','gnss_externo','manual')),
    capturado_en    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_geometria_geom ON geometria USING GIST (geom);

CREATE TABLE necesidad (
    id_necesidad    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_objeto       TEXT NOT NULL REFERENCES objeto_afectado(id_objeto),
    tipo            TEXT NOT NULL,        -- agua, alimento, refugio, salud, otro
    estado          TEXT NOT NULL DEFAULT 'abierta' CHECK (estado IN ('abierta','atendida','cerrada')),
    creado_en       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE evidencia (
    id_evidencia    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_objeto       TEXT NOT NULL REFERENCES objeto_afectado(id_objeto),
    tipo            TEXT NOT NULL CHECK (tipo IN ('foto','video','croquis','escaneo3d')),
    url_almacenamiento TEXT NOT NULL,
    usuario_id      UUID REFERENCES usuario(id_usuario),
    creado_en       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE medicion (
    id_medicion     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_objeto       TEXT NOT NULL REFERENCES objeto_afectado(id_objeto),
    tipo            TEXT NOT NULL CHECK (tipo IN ('distancia','area','pendiente','altura','grieta')),
    valor           REAL NOT NULL,
    unidad          TEXT NOT NULL,
    metodo          TEXT NOT NULL CHECK (metodo IN ('sensor_telefono','equipo_externo')),
    precision_categoria TEXT NOT NULL CHECK (precision_categoria IN ('orientativa','certificada')),
    creado_en       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Inspección técnica AIS — mismo formulario oficial de la Unidad de Gestión
-- del Riesgo (ver comentario equivalente en schema_sqlite.sql). Columnas
-- codificadas se dejan como TEXT libre (no CHECK) salvo la clasificación de
-- habitabilidad, que es la que colorea el mapa/estadísticas y sí conviene
-- restringir.
CREATE TABLE inspeccion_ais (
    id_inspeccion   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_objeto       TEXT NOT NULL REFERENCES objeto_afectado(id_objeto),
    localidad TEXT, nombre_barrio TEXT,
    ident_catastral_barrio TEXT, ident_catastral_manzana TEXT,
    ident_catastral_predio TEXT, ident_catastral_construccion TEXT,
    formulario_numero TEXT, inspeccion_tipo TEXT,
    tipo_via TEXT, numero_via TEXT, nombre_edificacion TEXT,
    uso_predominante TEXT, uso_predominante_planta_baja TEXT,
    niveles_sobre_terreno INTEGER, sotanos INTEGER, pisos_total INTEGER,
    dimension_frente_m REAL, dimension_fondo_m REAL,
    sistema_estructural TEXT, sistema_estructural_otro TEXT,
    tipo_entrepiso TEXT, tipo_entrepiso_otro TEXT, anio_construccion TEXT,
    existe_colapso TEXT, desviacion_inclinacion TEXT,
    falla_asentamiento_cimentacion TEXT,
    dano_muros_fachada TEXT, dano_vidrios_exteriores TEXT, dano_acabados_exteriores TEXT,
    dano_muros_divisorios TEXT, dano_balcones TEXT, dano_cielo_rasos TEXT,
    dano_cubierta TEXT, dano_escaleras TEXT, instalaciones_afectadas TEXT,
    dano_instalaciones TEXT, dano_ductos_ventilacion TEXT, dano_tanques_elevados TEXT,
    falla_talud TEXT, asentamiento_subsidencia_licuacion TEXT, grietas_terreno_circundante TEXT,
    edificio_vecino_critico TEXT, evento_adverso_inminente TEXT,
    nivel_entrepiso_mayor_dano TEXT, dano_columnas_muros_portantes TEXT,
    dano_vigas TEXT, dano_nudos_conexion TEXT, dano_entrepisos TEXT,
    clasificacion_a_estado_general TEXT, clasificacion_b_geotecnico TEXT,
    clasificacion_c_no_estructural TEXT, clasificacion_d_estructural TEXT,
    clasificacion_e_entorno TEXT,
    pct_dano_global REAL, clasificacion_global_dano TEXT,
    clasificacion_habitabilidad TEXT
        CHECK (clasificacion_habitabilidad IN ('verde','amarillo','naranja','rojo')),
    existe_clasificacion_previa BOOLEAN, clasificacion_previa_cual TEXT,
    requiere_visita_especializada TEXT, recomienda_intervencion TEXT,
    medidas_seguridad TEXT, desconectar_servicios TEXT,
    lugares_medidas_seguridad_texto TEXT,
    calidad_construccion TEXT, posicion_edificacion_manzana TEXT,
    configuracion_planta TEXT, configuracion_altura TEXT,
    configuracion_estructural TEXT, tipo_suelo TEXT, tipo_cimentacion TEXT,
    calidad_cimentacion TEXT, condiciones_topograficas TEXT, tipo_cubierta TEXT,
    condiciones_amarre_cubierta TEXT, efecto_columna_corta TEXT,
    continuidad_columnas_vigas TEXT, evidencia_anclaje_no_estructural TEXT,
    indicios_danos_sismos_anteriores BOOLEAN,
    hubo_reparacion TEXT, reforzamiento_estructural_anterior TEXT,
    hubo_muertos_heridos TEXT, numero_personas_fallecidas INTEGER,
    numero_heridos INTEGER,
    edificacion_habitada BOOLEAN, numero_ocupantes INTEGER, num_unidades_existentes INTEGER,
    num_unidades_no_habitables INTEGER,
    email_contacto TEXT,
    comentarios TEXT,
    codigo_comision TEXT, numero_evaluadores INTEGER, nombre_lider_comision TEXT,
    otro_inspector TEXT,
    fecha_inspeccion TIMESTAMPTZ,
    creado_por      UUID REFERENCES usuario(id_usuario),
    creado_en       TIMESTAMPTZ NOT NULL DEFAULT now(),
    actualizado_en  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE auditoria (
    id_auditoria    BIGSERIAL PRIMARY KEY,
    tabla           TEXT NOT NULL,
    id_registro     TEXT NOT NULL,
    accion          TEXT NOT NULL CHECK (accion IN ('crear','modificar','validar','sincronizar','cerrar')),
    usuario_id      UUID REFERENCES usuario(id_usuario),
    detalle         JSONB,
    creado_en       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Vista de conveniencia para el dashboard web (mapa de eventos)
CREATE VIEW v_mapa_objetos AS
SELECT o.id_objeto, o.tipo_objeto, o.estado_operativo, o.nivel_dano_preliminar,
       e.fenomeno, e.municipio_divipola, e.fecha_evento, g.geom, g.precision_gnss_m
FROM objeto_afectado o
JOIN evento e ON e.id_evento = o.id_evento
LEFT JOIN geometria g ON g.id_objeto = o.id_objeto;
