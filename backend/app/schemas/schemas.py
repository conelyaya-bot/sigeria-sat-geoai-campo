"""Esquemas Pydantic — contratos de la API de SIGERIA (módulos MVP 1-4)."""
from __future__ import annotations

from datetime import datetime
from typing import Literal, Optional

from pydantic import BaseModel, Field

SeveridadComponente = Literal["no_aplica", "sin_dano", "leve", "moderado", "severo", "colapso"]

Fenomeno = Literal[
    "sismo", "inundacion", "deslizamiento", "vendaval",
    "incendio", "erosion_socavacion", "creciente_subita", "otro",
]
EstadoOperativo = Literal["operativo", "parcial", "fuera_de_servicio", "sin_evaluar"]
NivelDano = Literal["sin_dano", "leve", "moderado", "severo", "colapso"]
TipoGeom = Literal["Point", "LineString", "Polygon"]
FuentePosicion = Literal["gnss_interno", "gnss_externo", "manual"]
TipoMedicion = Literal["distancia", "area", "pendiente", "altura", "grieta"]
MetodoMedicion = Literal["sensor_telefono", "equipo_externo"]
PrecisionCategoria = Literal["orientativa", "certificada"]
TipoNecesidad = Literal["agua", "alimento", "refugio", "salud", "otro"]


# --- Módulo 1: Evento y objetos -------------------------------------------------

class EventoCrear(BaseModel):
    fenomeno: Fenomeno
    fecha_evento: datetime
    municipio_divipola: str = Field(..., description="Código DIVIPOLA del municipio")
    descripcion: Optional[str] = None
    creado_por: Optional[str] = None


class EventoOut(EventoCrear):
    id_evento: str
    creado_en: str


class ComponenteDanoItem(BaseModel):
    """Una fila de la lista de chequeo (sección 8) — permite calcular de
    verdad, en estadísticas, qué componentes se dañan más, en vez de leer
    el resumen en texto uno por uno."""
    componente: str
    severidad: SeveridadComponente


class ObjetoAfectadoCrear(BaseModel):
    id_evento: str
    tipo_objeto: str
    estado_operativo: EstadoOperativo = "sin_evaluar"
    nivel_dano_preliminar: Optional[NivelDano] = None
    # Ubicación detallada (sección 6 del documento base)
    departamento: Optional[str] = None
    barrio_vereda: Optional[str] = None
    direccion: Optional[str] = None
    # Responsable de la recolección — obligatorio para trazabilidad y para
    # que el dato sea entregable ante UNGRD/departamento/municipio.
    recolector_nombre: Optional[str] = None
    recolector_documento: Optional[str] = None
    recolector_cargo: Optional[str] = None
    recolector_entidad: Optional[str] = None
    # Informante en la vivienda (beneficiario)
    informante_nombre: Optional[str] = None
    informante_documento: Optional[str] = None
    informante_parentesco: Optional[str] = None
    informante_telefono: Optional[str] = None
    requiere_subsidio_arrendamiento: Optional[bool] = None
    resumen_componentes_dano: Optional[str] = None
    # Espacio libre opcional para quien evalúa SÍ sea ingeniero/a y quiera
    # detallar por escrito lo evidenciado — no reemplaza la lista de chequeo.
    observaciones_tecnicas: Optional[str] = None
    personas_afectadas: Optional[int] = None
    # Detalle fila por fila de la lista de chequeo (para estadísticas reales
    # de "qué componentes se dañan más"). Opcional por compatibilidad con
    # llamadas antiguas, pero el formulario móvil siempre lo envía.
    componentes: Optional[list[ComponenteDanoItem]] = None
    creado_por: Optional[str] = None


class ObjetoAfectadoActualizar(BaseModel):
    """Edición de un expediente ya creado — todos los campos opcionales,
    solo se actualiza lo que venga. Permite corregir datos mal digitados o
    completar después foto/GPS que faltaron al momento de la captura."""
    tipo_objeto: Optional[str] = None
    estado_operativo: Optional[EstadoOperativo] = None
    nivel_dano_preliminar: Optional[NivelDano] = None
    departamento: Optional[str] = None
    barrio_vereda: Optional[str] = None
    direccion: Optional[str] = None
    recolector_nombre: Optional[str] = None
    recolector_documento: Optional[str] = None
    recolector_cargo: Optional[str] = None
    recolector_entidad: Optional[str] = None
    informante_nombre: Optional[str] = None
    informante_documento: Optional[str] = None
    informante_parentesco: Optional[str] = None
    informante_telefono: Optional[str] = None
    requiere_subsidio_arrendamiento: Optional[bool] = None
    resumen_componentes_dano: Optional[str] = None
    observaciones_tecnicas: Optional[str] = None
    personas_afectadas: Optional[int] = None
    componentes: Optional[list[ComponenteDanoItem]] = None
    # Permite corregir/agregar la ubicación desde la edición, sin tener que
    # volver a capturar todo el expediente.
    lat: Optional[float] = None
    lon: Optional[float] = None
    precision_gnss_m: Optional[float] = None


class ObjetoAfectadoOut(BaseModel):
    id_objeto: str
    id_evento: str
    tipo_objeto: str
    estado_operativo: EstadoOperativo
    nivel_dano_preliminar: Optional[NivelDano] = None
    departamento: Optional[str] = None
    barrio_vereda: Optional[str] = None
    direccion: Optional[str] = None
    recolector_nombre: Optional[str] = None
    recolector_documento: Optional[str] = None
    recolector_cargo: Optional[str] = None
    recolector_entidad: Optional[str] = None
    informante_nombre: Optional[str] = None
    informante_documento: Optional[str] = None
    informante_parentesco: Optional[str] = None
    informante_telefono: Optional[str] = None
    requiere_subsidio_arrendamiento: Optional[bool] = None
    resumen_componentes_dano: Optional[str] = None
    observaciones_tecnicas: Optional[str] = None
    personas_afectadas: Optional[int] = None
    creado_en: str
    actualizado_en: str


# --- Módulo 2: EDAN básico adaptativo -------------------------------------------

class NecesidadCrear(BaseModel):
    id_objeto: str
    tipo: TipoNecesidad


class NecesidadOut(NecesidadCrear):
    id_necesidad: str
    estado: str
    creado_en: str


class EvidenciaCrear(BaseModel):
    id_objeto: str
    tipo: Literal["foto", "video", "croquis", "escaneo3d"]
    url_almacenamiento: str
    usuario_id: Optional[str] = None
    # Contenido real de la imagen en base64 (opcional). Si viene, el backend
    # la guarda de verdad en disco (workspace/evidencias/) y el reporte PDF
    # puede mostrarla en un recuadro real, no solo el nombre del archivo.
    contenido_base64: Optional[str] = None


class EvidenciaOut(EvidenciaCrear):
    id_evidencia: str
    creado_en: str


# --- Módulo 3: GIS offline -------------------------------------------------------

class GeometriaCrear(BaseModel):
    id_objeto: str
    geom_tipo: TipoGeom
    geom_geojson: dict = Field(..., description="Geometry GeoJSON, EPSG:4326")
    precision_gnss_m: Optional[float] = None
    fuente_posicion: FuentePosicion = "gnss_interno"


class GeometriaOut(GeometriaCrear):
    id_geometria: str
    capturado_en: str


# --- Módulo 4: Medición móvil -----------------------------------------------------

class MedicionCrear(BaseModel):
    id_objeto: str
    tipo: TipoMedicion
    valor: float
    unidad: str
    metodo: MetodoMedicion
    precision_categoria: PrecisionCategoria


class MedicionOut(MedicionCrear):
    id_medicion: str
    creado_en: str


# --- Inspección técnica AIS ------------------------------------------------
# "Guía Técnica para la Inspección de Edificaciones Después de un Sismo"
# (Asociación Colombiana de Ingeniería Sísmica) — formulario oficial que usa
# la Unidad de Gestión del Riesgo (nacional y local). Reemplaza el checklist
# simplificado de 8 componentes: los nombres de campo y las opciones de cada
# uno siguen EXACTAMENTE el formulario en papel (2 páginas), sección por
# sección, para que el dato levantado sea directamente utilizable ante esas
# entidades — no una aproximación propia de SIGERIA.

TipoVia = Literal["carrera", "calle", "transv", "diag", "avda", "otro"]
InspeccionTipo = Literal["exterior_interior", "no_se_pudo_entrar"]
UsoPredominanteAis = Literal[
    "residencial", "comercial", "educacional", "salud", "hotelero", "oficinas",
    "industrial", "institucional", "bodegas", "estacionamientos", "otros",
]
SistemaEstructural = Literal[
    "11_portico_concreto", "12_muros_estructurales", "13_sistemas_duales", "14_prefabricados",
    "21_mamposteria_confinada", "22_mamposteria_reforzada", "23_mamposteria_no_reforzada",
    "31_porticos_arriostrados", "32_porticos_no_arriostrados",
    "41_porticos_paneles_madera", "42_porticos_madera_paneles_otros",
    "51_muros_bahareque", "52_muros_tapia",
    "50_mixta", "60_otros",
]
TipoEntrepiso = Literal[
    "11_placa_maciza", "12_placa_aligerada", "13_reticular_celulado",
    "21_lamina_colaborante", "22_vigas_acero", "23_cerchas",
    "31_vigas_madera", "32_mixta_madera",
    "40_otros",
]
AnioConstruccionAis = Literal["antes_1930", "1930_1984", "1985_1997", "desde_1998"]
SiNoIndeterminado = Literal["si", "no", "no_determinado"]
ExisteColapso = Literal["no", "parcial", "total"]
GradoDanoAis = Literal["ninguno", "leve", "moderado", "fuerte", "severo"]
InstalacionAfectada = Literal["acueducto", "alcantarillado", "energia", "gas"]
NivelPuntualGeneral = Literal["no", "puntual", "general"]
ClasificacionHabitabilidad = Literal["verde", "amarillo", "naranja", "rojo"]
VisitaEspecializada = Literal["estructural", "geotecnico", "servicios_publicos"]
IntervencionRecomendada = Literal[
    "planeacion_control_fisico", "policia_ejercito", "transito", "bomberos_rescate"
]
MedidaSeguridad = Literal[
    "restringir_paso_peatones", "restringir_trafico_vehicular", "evacuar_parcial",
    "evacuar_total", "manejo_sustancias_peligrosas", "apuntalar",
    "demoler_elementos_peligro", "evacuar_edificaciones_vecinas",
]
ServicioDesconectar = Literal["energia", "gas", "agua"]
CalidadBuenaRegularMala = Literal["buena", "regular", "mala"]
PosicionManzana = Literal["esquina", "intermedia", "libre_un_costado", "libre_dos_costados"]
HuboReparacion = Literal["total", "parcial", "ninguna"]
HuboMuertosHeridos = Literal["no", "si", "no_se_sabe"]


class InspeccionAisCrear(BaseModel):
    id_objeto: str

    # Encabezado / identificación catastral
    localidad: Optional[str] = None
    nombre_barrio: Optional[str] = None
    ident_catastral_barrio: Optional[str] = None
    ident_catastral_manzana: Optional[str] = None
    ident_catastral_predio: Optional[str] = None
    ident_catastral_construccion: Optional[str] = None
    formulario_numero: Optional[str] = None
    inspeccion_tipo: Optional[InspeccionTipo] = None

    # Identificación de la edificación
    tipo_via: Optional[TipoVia] = None
    numero_via: Optional[str] = None
    nombre_edificacion: Optional[str] = None
    uso_predominante: Optional[UsoPredominanteAis] = None
    uso_predominante_planta_baja: Optional[UsoPredominanteAis] = None
    niveles_sobre_terreno: Optional[int] = None
    sotanos: Optional[int] = None
    pisos_total: Optional[int] = None
    dimension_frente_m: Optional[float] = None
    dimension_fondo_m: Optional[float] = None

    # Descripción de la estructura
    sistema_estructural: Optional[SistemaEstructural] = None
    sistema_estructural_otro: Optional[str] = None
    tipo_entrepiso: Optional[TipoEntrepiso] = None
    tipo_entrepiso_otro: Optional[str] = None
    anio_construccion: Optional[AnioConstruccionAis] = None

    # Estado general de la edificación
    existe_colapso: Optional[ExisteColapso] = None
    desviacion_inclinacion: Optional[SiNoIndeterminado] = None
    falla_asentamiento_cimentacion: Optional[SiNoIndeterminado] = None

    # Daños en elementos arquitectónicos
    dano_muros_fachada: Optional[GradoDanoAis] = None
    dano_muros_divisorios: Optional[GradoDanoAis] = None
    dano_cielo_rasos: Optional[GradoDanoAis] = None
    dano_cubierta: Optional[GradoDanoAis] = None
    dano_escaleras: Optional[GradoDanoAis] = None
    instalaciones_afectadas: Optional[list[InstalacionAfectada]] = None
    dano_instalaciones: Optional[GradoDanoAis] = None
    dano_tanques_elevados: Optional[GradoDanoAis] = None

    # Problemas geotécnicos
    falla_talud: Optional[NivelPuntualGeneral] = None
    asentamiento_subsidencia_licuacion: Optional[NivelPuntualGeneral] = None

    # Daños en elementos estructurales (piso de mayor afectación)
    nivel_entrepiso_mayor_dano: Optional[str] = None
    dano_columnas_muros_portantes: Optional[GradoDanoAis] = None
    dano_vigas: Optional[GradoDanoAis] = None
    dano_nudos_conexion: Optional[GradoDanoAis] = None
    dano_entrepisos: Optional[GradoDanoAis] = None

    # Clasificación global — clasificacion_global_dano y
    # clasificacion_habitabilidad se pueden mandar ya calculados desde el
    # cliente (misma tabla de la guía: % → clasificación → color), pero
    # también se recalculan en el backend por si vienen vacíos.
    pct_dano_global: Optional[float] = None
    clasificacion_global_dano: Optional[GradoDanoAis] = None
    clasificacion_habitabilidad: Optional[ClasificacionHabitabilidad] = None
    existe_clasificacion_previa: Optional[bool] = None
    clasificacion_previa_cual: Optional[str] = None

    # Recomendaciones y medidas de seguridad
    requiere_visita_especializada: Optional[list[VisitaEspecializada]] = None
    recomienda_intervencion: Optional[list[IntervencionRecomendada]] = None
    medidas_seguridad: Optional[list[MedidaSeguridad]] = None
    desconectar_servicios: Optional[list[ServicioDesconectar]] = None
    lugares_medidas_seguridad_texto: Optional[str] = None

    # Condiciones preexistentes
    calidad_construccion: Optional[CalidadBuenaRegularMala] = None
    posicion_edificacion_manzana: Optional[PosicionManzana] = None
    configuracion_planta: Optional[CalidadBuenaRegularMala] = None
    configuracion_altura: Optional[CalidadBuenaRegularMala] = None
    configuracion_estructural: Optional[CalidadBuenaRegularMala] = None
    indicios_danos_sismos_anteriores: Optional[bool] = None
    hubo_reparacion: Optional[HuboReparacion] = None

    # Efecto en los ocupantes
    hubo_muertos_heridos: Optional[HuboMuertosHeridos] = None
    numero_personas_fallecidas: Optional[int] = None
    numero_heridos: Optional[int] = None

    # Ocupación de la edificación
    edificacion_habitada: Optional[bool] = None
    num_unidades_existentes: Optional[int] = None
    num_unidades_no_habitables: Optional[int] = None

    comentarios: Optional[str] = None

    # Inspectores
    codigo_comision: Optional[str] = None
    numero_evaluadores: Optional[int] = None
    nombre_lider_comision: Optional[str] = None

    fecha_inspeccion: Optional[datetime] = None
    creado_por: Optional[str] = None


class InspeccionAisOut(InspeccionAisCrear):
    id_inspeccion: str
    creado_en: str
    actualizado_en: str
