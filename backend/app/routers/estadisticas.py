"""Estadísticas para reportes oficiales — pensado para dos necesidades reales:

1. La app la van a usar MUCHAS personas a la vez (brigadistas, ingenieros,
   coordinadores) levantando información en paralelo — este endpoint permite
   ver el avance consolidado sin tener que sumar manualmente lo de cada uno.
2. La información se debe poder entregar ante un ente NACIONAL (UNGRD),
   DEPARTAMENTAL y MUNICIPAL — por eso todo se agrupa también por
   departamento y municipio, no solo por evento (sección 26 del documento
   base: "Indicadores operativos").
"""
from __future__ import annotations

from fastapi import APIRouter

from app.db.database import get_conn

router = APIRouter(prefix="/api/estadisticas", tags=["Estadísticas / reportes oficiales"])


def _contar(conn, sql: str, params: tuple = ()) -> list[dict]:
    return [dict(r) for r in conn.execute(sql, params).fetchall()]


def _filtro_depto_municipio(departamento: str | None, municipio_divipola: str | None):
    """Arma el `WHERE ... AND ...` común a todas las consultas de este
    módulo — filtrar por lo que el usuario elija en el visor del mapa
    (departamento y/o municipio), no solo ver el país entero mezclado."""
    condiciones, params = [], []
    if departamento:
        condiciones.append("o.departamento = ?")
        params.append(departamento)
    if municipio_divipola:
        condiciones.append("e.municipio_divipola = ?")
        params.append(municipio_divipola)
    where = (" WHERE " + " AND ".join(condiciones)) if condiciones else ""
    return where, tuple(params)


@router.get("/general")
def estadisticas_generales(departamento: str | None = None, municipio_divipola: str | None = None):
    """Resumen consolidado de TODOS los eventos y objetos capturados —
    listo para reportar a nivel nacional, departamental y municipal.
    Si se pasan `departamento`/`municipio_divipola`, filtra a esa zona (lo
    que se elige en el visor del mapa)."""
    where, params = _filtro_depto_municipio(departamento, municipio_divipola)
    join = "FROM objeto_afectado o JOIN evento e ON e.id_evento = o.id_evento"
    with get_conn() as conn:
        total_objetos = conn.execute(
            f"SELECT COUNT(*) n {join}{where}", params
        ).fetchone()["n"]
        total_eventos = conn.execute(
            f"SELECT COUNT(DISTINCT e.id_evento) n {join}{where}", params
        ).fetchone()["n"]
        total_personas_afectadas = conn.execute(
            f"SELECT COALESCE(SUM(o.personas_afectadas), 0) n {join}{where}", params
        ).fetchone()["n"]

        por_departamento = _contar(
            conn,
            f"""SELECT COALESCE(o.departamento, 'sin dato') AS departamento, COUNT(*) AS total
               {join}{where} GROUP BY o.departamento ORDER BY total DESC""",
            params,
        )
        por_municipio = _contar(
            conn,
            f"""SELECT e.municipio_divipola AS municipio, COUNT(*) AS total
               {join}{where} GROUP BY e.municipio_divipola ORDER BY total DESC""",
            params,
        )
        por_fenomeno = _contar(
            conn,
            f"""SELECT e.fenomeno AS fenomeno, COUNT(*) AS total
               {join}{where} GROUP BY e.fenomeno ORDER BY total DESC""",
            params,
        )
        por_severidad = _contar(
            conn,
            f"""SELECT COALESCE(o.nivel_dano_preliminar, 'sin_evaluar') AS severidad, COUNT(*) AS total
               {join}{where} GROUP BY o.nivel_dano_preliminar ORDER BY total DESC""",
            params,
        )
        por_estado_operativo = _contar(
            conn,
            f"""SELECT o.estado_operativo, COUNT(*) AS total
               {join}{where} GROUP BY o.estado_operativo ORDER BY total DESC""",
            params,
        )
        subsidio_arrendamiento = _contar(
            conn,
            f"""SELECT CASE o.requiere_subsidio_arrendamiento
                        WHEN 1 THEN 'si' WHEN 0 THEN 'no' ELSE 'sin_evaluar' END AS respuesta,
                      COUNT(*) AS total
               {join}{where} GROUP BY o.requiere_subsidio_arrendamiento""",
            params,
        )

        # Uso multiusuario: cuántos recolectores distintos han capturado datos,
        # y cuántos registros lleva cada uno — indicador operativo de campo.
        por_recolector = _contar(
            conn,
            f"""SELECT COALESCE(o.recolector_nombre, 'sin registrar') AS recolector,
                      o.recolector_entidad, COUNT(*) AS total
               {join}{where} GROUP BY o.recolector_nombre, o.recolector_entidad
               ORDER BY total DESC""",
            params,
        )

        return {
            "total_eventos": total_eventos,
            "total_objetos_afectados": total_objetos,
            "total_personas_afectadas": total_personas_afectadas,
            "por_departamento": por_departamento,
            "por_municipio_divipola": por_municipio,
            "por_fenomeno": por_fenomeno,
            "por_severidad_preliminar": por_severidad,
            "por_estado_operativo": por_estado_operativo,
            "requiere_subsidio_arrendamiento": subsidio_arrendamiento,
            "por_recolector": por_recolector,
            "usuarios_recolectores_activos": len(
                [r for r in por_recolector if r["recolector"] != "sin registrar"]
            ),
        }


@router.get("/componentes")
def estadisticas_componentes(departamento: str | None = None, municipio_divipola: str | None = None):
    """'¿Qué se daña más?' — cuenta, por componente constructivo (columnas,
    muros, cubierta, etc.), cuántas veces se marcó cada nivel de severidad,
    a partir del detalle fila por fila (`componente_dano_detalle`). Excluye
    'sin_dano' y 'no_aplica' del ranking: no son daño, son la ausencia de él.
    Filtrable por departamento/municipio, igual que el resto del módulo."""
    condiciones = ["d.severidad NOT IN ('sin_dano', 'no_aplica')"]
    params: list = []
    if departamento:
        condiciones.append("o.departamento = ?")
        params.append(departamento)
    if municipio_divipola:
        condiciones.append("e.municipio_divipola = ?")
        params.append(municipio_divipola)
    where = " AND ".join(condiciones)

    with get_conn() as conn:
        por_componente = _contar(
            conn,
            f"""SELECT d.componente, COUNT(*) AS total
               FROM componente_dano_detalle d
               JOIN objeto_afectado o ON o.id_objeto = d.id_objeto
               JOIN evento e ON e.id_evento = o.id_evento
               WHERE {where}
               GROUP BY d.componente ORDER BY total DESC""",
            tuple(params),
        )
        por_componente_y_severidad = _contar(
            conn,
            f"""SELECT d.componente, d.severidad, COUNT(*) AS total
               FROM componente_dano_detalle d
               JOIN objeto_afectado o ON o.id_objeto = d.id_objeto
               JOIN evento e ON e.id_evento = o.id_evento
               WHERE {where}
               GROUP BY d.componente, d.severidad ORDER BY total DESC""",
            tuple(params),
        )
        return {
            "componentes_mas_afectados": por_componente,
            "detalle_componente_severidad": por_componente_y_severidad,
        }


@router.get("/registro_reciente")
def registro_reciente(
    limite: int = 20, departamento: str | None = None, municipio_divipola: str | None = None
):
    """Ventana de 'lo que se va registrando' — los últimos expedientes
    creados, más reciente primero, para una vista tipo bitácora en vivo."""
    condiciones, params = [], []
    if departamento:
        condiciones.append("o.departamento = ?")
        params.append(departamento)
    if municipio_divipola:
        condiciones.append("e.municipio_divipola = ?")
        params.append(municipio_divipola)
    where = (" WHERE " + " AND ".join(condiciones)) if condiciones else ""
    params.append(max(1, min(limite, 200)))

    with get_conn() as conn:
        filas = _contar(
            conn,
            f"""SELECT o.id_objeto, o.tipo_objeto, o.estado_operativo, o.nivel_dano_preliminar,
                      o.departamento, e.municipio_divipola, e.fenomeno,
                      o.recolector_nombre, o.creado_en
               FROM objeto_afectado o JOIN evento e ON e.id_evento = o.id_evento
               {where}
               ORDER BY o.creado_en DESC
               LIMIT ?""",
            tuple(params),
        )
        return {"registros": filas}
