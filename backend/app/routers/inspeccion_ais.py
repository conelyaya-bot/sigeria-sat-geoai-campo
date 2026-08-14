"""Inspección técnica AIS — "Guía Técnica para la Inspección de Edificaciones
Después de un Sismo" (IDIGER / Asociación Colombiana de Ingeniería Sísmica,
4ª edición, marzo de 2018 — confirmado vigente, sin edición más reciente al
verificar). Formulario oficial que usa la Unidad de Gestión del Riesgo
(nacional y local); reemplaza el checklist simplificado de 8 componentes que
tenía SIGERIA antes.

Clasificación de habitabilidad — sección 2.9 de la guía: NO es un simple
porcentaje de daño. Son 5 evaluaciones independientes, cada una con su
propia tabla de criterios (Tablas 2, 3, 4, 7 y 8 de la guía):
    A. Estado general de la edificación   (Tabla 2)
    B. Problemas geotécnicos               (Tabla 3)
    C. Daños en elementos NO estructurales (Tabla 4)
    D. Daños en elementos estructurales    (Tabla 7)
    E. Problemas del entorno               (Tabla 8)
El resultado final es "la más conservadora" (peor) de las 5 — así lo dice
la guía textualmente en la sección 2.9.

Los campos de selección múltiple (instalaciones afectadas, medidas de
seguridad, etc.) se guardan como texto separado por comas en SQLite (no hay
tipo array nativo) y se reconstruyen como lista al leer.
"""
from __future__ import annotations

from fastapi import APIRouter, HTTPException

from app.db.database import get_conn, new_uuid, now_iso, row_to_dict
from app.schemas.schemas import InspeccionAisCrear, InspeccionAisOut

router = APIRouter(prefix="/api/inspeccion-ais", tags=["Inspección técnica AIS"])

# Campos que se guardan como CSV en la tabla (listas de selección múltiple).
_CAMPOS_LISTA = [
    "instalaciones_afectadas", "requiere_visita_especializada",
    "recomienda_intervencion", "medidas_seguridad", "desconectar_servicios",
]

# Orden de severidad para poder tomar "la más conservadora" con max().
_ORDEN_CLASIFICACION = ["habitable", "uso_restringido", "no_habitable", "peligro_colapso"]
_ORDEN_GRADO_DANO = ["ninguno", "leve", "moderado", "fuerte", "severo"]


def _peor(*valores: str | None) -> str | None:
    """Toma el peor (más conservador) de varios valores, ignorando None."""
    presentes = [v for v in valores if v]
    if not presentes:
        return None
    return max(presentes, key=_ORDEN_CLASIFICACION.index)


def _peor_grado(*valores: str | None) -> str | None:
    presentes = [v for v in valores if v]
    if not presentes:
        return None
    return max(presentes, key=_ORDEN_GRADO_DANO.index)


# --- A. Estado general de la edificación (Tabla 2) --------------------------
# Cada pregunta de la tabla oficial mapea el mismo código de respuesta a más
# de una columna a la vez (p.ej. "No colapso" es compatible con Habitable Y
# con Uso restringido) — la guía deja el matiz fino al criterio del
# evaluador según el texto de "Comentarios". Para automatizarlo de forma
# reproducible se toma, en cada ambigüedad, la lectura MÁS CONSERVADORA
# (la más severa de las opciones compatibles) — nunca se subestima el
# riesgo por una simplificación de cómputo.
def _clasificacion_a(d: dict) -> str | None:
    mapa_colapso = {"no": "habitable", "parcial": "no_habitable", "total": "peligro_colapso"}
    mapa_si_no = {"no": "habitable", "si": "no_habitable", "no_determinado": "no_habitable"}
    return _peor(
        mapa_colapso.get(d.get("existe_colapso")),
        mapa_si_no.get(d.get("desviacion_inclinacion")),
        mapa_si_no.get(d.get("falla_asentamiento_cimentacion")),
    )


# --- B. Problemas geotécnicos (Tabla 3) --------------------------------------
def _clasificacion_b(d: dict) -> str | None:
    mapa_npg = {"no": "habitable", "puntual": "no_habitable", "general": "peligro_colapso"}
    mapa_grietas = {"no": "habitable", "incipientes": "no_habitable", "generalizadas": "peligro_colapso"}
    return _peor(
        mapa_npg.get(d.get("falla_talud")),
        mapa_npg.get(d.get("asentamiento_subsidencia_licuacion")),
        mapa_grietas.get(d.get("grietas_terreno_circundante")),
    )


# --- C. Daños en elementos NO estructurales (Tabla 4) ------------------------
# La tabla oficial cruza grado de daño con % de área afectada; SIGERIA no
# pide estimar ese % por elemento (poco realista para personal sin
# formación estructural en campo), así que se usa el grado MÁS CRÍTICO entre
# los 11 elementos como aproximación, leyendo la tabla en su rama más
# conservadora para cada grado (p.ej. "Moderado" puede ser Habitable o Uso
# restringido según el %; se asume Uso restringido si no hay más dato).
_ELEMENTOS_NO_ESTRUCTURALES = [
    "dano_muros_fachada", "dano_vidrios_exteriores", "dano_acabados_exteriores",
    "dano_muros_divisorios", "dano_balcones", "dano_cielo_rasos", "dano_cubierta",
    "dano_escaleras", "dano_instalaciones", "dano_ductos_ventilacion", "dano_tanques_elevados",
]
_TABLA4 = {
    "ninguno": "habitable", "leve": "habitable",
    "moderado": "uso_restringido", "fuerte": "no_habitable", "severo": "no_habitable",
}


def _clasificacion_c(d: dict) -> str | None:
    peor_grado = _peor_grado(*(d.get(c) for c in _ELEMENTOS_NO_ESTRUCTURALES))
    return _TABLA4.get(peor_grado) if peor_grado else None


# --- D. Daños en elementos estructurales (Tabla 7) ---------------------------
# Mismo principio que C — se toma el elemento estructural más crítico entre
# los 4 evaluados, con la rama más conservadora de la Tabla 7 (aquí el
# criterio es más estricto que en no-estructurales porque compromete la
# capacidad de resistir cargas).
_ELEMENTOS_ESTRUCTURALES = [
    "dano_columnas_muros_portantes", "dano_vigas", "dano_nudos_conexion", "dano_entrepisos",
]
_TABLA7 = {
    "ninguno": "habitable", "leve": "uso_restringido",
    "moderado": "no_habitable", "fuerte": "no_habitable", "severo": "peligro_colapso",
}


def _clasificacion_d(d: dict) -> str | None:
    peor_grado = _peor_grado(*(d.get(c) for c in _ELEMENTOS_ESTRUCTURALES))
    return _TABLA7.get(peor_grado) if peor_grado else None


# --- E. Problemas del entorno (Tabla 8) --------------------------------------
# Esta tabla oficial solo llega hasta "No habitable" — el entorno por sí
# solo no puede clasificar en "Peligro de colapso" (eso depende de la
# edificación misma, evaluado en A-D).
def _clasificacion_e(d: dict) -> str | None:
    mapa_vecino = {"no": "habitable", "si": "no_habitable", "no_determinado": "no_habitable"}
    mapa_evento = {"no": "habitable", "si": "no_habitable"}
    resultado = _peor(
        mapa_vecino.get(d.get("edificio_vecino_critico")),
        mapa_evento.get(d.get("evento_adverso_inminente")),
    )
    if resultado == "peligro_colapso":  # nunca debería pasar, pero se acota por si acaso
        return "no_habitable"
    return resultado


_COLOR_HABITABILIDAD = {
    "habitable": "verde",
    "uso_restringido": "amarillo",
    "no_habitable": "naranja",
    "peligro_colapso": "rojo",
}

# Puente hacia `objeto_afectado.nivel_dano_preliminar` (ya usado por el mapa
# y las estadísticas para colorear puntos) desde la clasificación de
# habitabilidad final — más fiel que derivarlo del % de daño, que ahora es
# solo un dato complementario (sección 2.10 de la guía, para estimar
# pérdidas económicas, no para decidir habitabilidad).
_NIVEL_DANO_DESDE_HABITABILIDAD = {
    "habitable": "sin_dano",
    "uso_restringido": "moderado",
    "no_habitable": "severo",
    "peligro_colapso": "colapso",
}


def _clasificacion_desde_porcentaje(pct: float) -> str:
    """% de daño global -> clasificación de daño (Tabla 10, sección 2.10) —
    dato complementario para pérdidas económicas, ya NO decide habitabilidad
    (eso lo hace exclusivamente el sistema A-E, sección 2.9)."""
    if pct <= 0:
        return "ninguno"
    if pct <= 10:
        return "leve"
    if pct <= 30:
        return "moderado"
    if pct <= 60:
        return "fuerte"
    return "severo"


def _calcular_clasificaciones(datos: dict) -> None:
    """Recalcula SIEMPRE las 5 sub-clasificaciones y la global a partir de
    las respuestas — lo que venga del cliente en esos campos es solo un
    adelanto visual, la autoridad es el backend (misma regla que ya
    aplicaba antes de esta revisión)."""
    a = _clasificacion_a(datos)
    b = _clasificacion_b(datos)
    c = _clasificacion_c(datos)
    d = _clasificacion_d(datos)
    e = _clasificacion_e(datos)
    datos["clasificacion_a_estado_general"] = a
    datos["clasificacion_b_geotecnico"] = b
    datos["clasificacion_c_no_estructural"] = c
    datos["clasificacion_d_estructural"] = d
    datos["clasificacion_e_entorno"] = e

    final = _peor(a, b, c, d, e)
    if final:
        datos["clasificacion_habitabilidad"] = _COLOR_HABITABILIDAD[final]

    if datos.get("pct_dano_global") is not None:
        datos["clasificacion_global_dano"] = _clasificacion_desde_porcentaje(datos["pct_dano_global"])


def _a_fila(payload: InspeccionAisCrear) -> dict:
    datos = payload.model_dump(exclude={"id_objeto"})
    for campo in _CAMPOS_LISTA:
        valor = datos.get(campo)
        datos[campo] = ",".join(valor) if valor else None
    if datos.get("fecha_inspeccion") is not None:
        datos["fecha_inspeccion"] = payload.fecha_inspeccion.isoformat()  # type: ignore[union-attr]

    _calcular_clasificaciones(datos)
    return datos


def _fila_a_salida(row) -> dict:
    fila = row_to_dict(row)
    for campo in _CAMPOS_LISTA:
        fila[campo] = fila[campo].split(",") if fila.get(campo) else []
    return fila


def _sincronizar_objeto_afectado(conn, id_objeto: str, datos: dict) -> None:
    """El mapa y las estadísticas ya leen `nivel_dano_preliminar` y
    `resumen_componentes_dano` de `objeto_afectado` — en vez de duplicar esa
    lógica, la inspección AIS actualiza esos mismos campos con su propia
    clasificación, así todo lo ya construido (colores del mapa, ranking de
    daños) sigue funcionando sin cambios, ahora alimentado por el sistema
    A-E oficial en vez del checklist simplificado."""
    color = datos.get("clasificacion_habitabilidad")
    if not color:
        return
    final = _peor(
        datos.get("clasificacion_a_estado_general"), datos.get("clasificacion_b_geotecnico"),
        datos.get("clasificacion_c_no_estructural"), datos.get("clasificacion_d_estructural"),
        datos.get("clasificacion_e_entorno"),
    )
    nivel = _NIVEL_DANO_DESDE_HABITABILIDAD.get(final)
    resumen = (
        f"Inspección AIS — habitabilidad: {color} "
        f"(A:{datos.get('clasificacion_a_estado_general', '?')} "
        f"B:{datos.get('clasificacion_b_geotecnico', '?')} "
        f"C:{datos.get('clasificacion_c_no_estructural', '?')} "
        f"D:{datos.get('clasificacion_d_estructural', '?')} "
        f"E:{datos.get('clasificacion_e_entorno', '?')})"
    )
    conn.execute(
        "UPDATE objeto_afectado SET nivel_dano_preliminar=?, resumen_componentes_dano=?, "
        "actualizado_en=? WHERE id_objeto=?",
        (nivel, resumen, now_iso(), id_objeto),
    )


@router.post("", response_model=InspeccionAisOut)
def crear_inspeccion(payload: InspeccionAisCrear):
    with get_conn() as conn:
        existe = conn.execute(
            "SELECT 1 FROM objeto_afectado WHERE id_objeto=?", (payload.id_objeto,)
        ).fetchone()
        if not existe:
            raise HTTPException(404, f"Objeto afectado {payload.id_objeto} no existe")

        datos = _a_fila(payload)
        id_inspeccion = new_uuid()
        columnas = ["id_inspeccion", "id_objeto", *datos.keys()]
        marcadores = ",".join("?" * len(columnas))
        conn.execute(
            f"INSERT INTO inspeccion_ais ({','.join(columnas)}) VALUES ({marcadores})",
            (id_inspeccion, payload.id_objeto, *datos.values()),
        )
        _sincronizar_objeto_afectado(conn, payload.id_objeto, datos)
        conn.execute(
            "INSERT INTO auditoria (tabla, id_registro, accion, usuario_id) VALUES (?,?,?,?)",
            ("inspeccion_ais", id_inspeccion, "crear", payload.creado_por),
        )
        row = conn.execute(
            "SELECT * FROM inspeccion_ais WHERE id_inspeccion=?", (id_inspeccion,)
        ).fetchone()
        return _fila_a_salida(row)


@router.get("/{id_objeto}")
def obtener_inspeccion(id_objeto: str):
    """Devuelve la inspección más reciente de ese objeto (normalmente hay
    una sola). `null` si todavía no se ha hecho ninguna."""
    with get_conn() as conn:
        row = conn.execute(
            "SELECT * FROM inspeccion_ais WHERE id_objeto=? ORDER BY creado_en DESC LIMIT 1",
            (id_objeto,),
        ).fetchone()
        return _fila_a_salida(row) if row else None


@router.put("/{id_inspeccion}", response_model=InspeccionAisOut)
def editar_inspeccion(id_inspeccion: str, payload: InspeccionAisCrear):
    with get_conn() as conn:
        actual = conn.execute(
            "SELECT * FROM inspeccion_ais WHERE id_inspeccion=?", (id_inspeccion,)
        ).fetchone()
        if not actual:
            raise HTTPException(404, "Esa inspección no existe")

        datos = _a_fila(payload)
        asignaciones = ", ".join(f"{c} = ?" for c in datos)
        conn.execute(
            f"UPDATE inspeccion_ais SET {asignaciones}, actualizado_en = ? WHERE id_inspeccion = ?",
            (*datos.values(), now_iso(), id_inspeccion),
        )
        _sincronizar_objeto_afectado(conn, payload.id_objeto, datos)
        row = conn.execute(
            "SELECT * FROM inspeccion_ais WHERE id_inspeccion=?", (id_inspeccion,)
        ).fetchone()
        return _fila_a_salida(row)
