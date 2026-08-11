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


@router.get("/general")
def estadisticas_generales():
    """Resumen consolidado de TODOS los eventos y objetos capturados —
    listo para reportar a nivel nacional, departamental y municipal."""
    with get_conn() as conn:
        total_eventos = conn.execute("SELECT COUNT(*) n FROM evento").fetchone()["n"]
        total_objetos = conn.execute("SELECT COUNT(*) n FROM objeto_afectado").fetchone()["n"]

        por_departamento = _contar(
            conn,
            """SELECT COALESCE(departamento, 'sin dato') AS departamento, COUNT(*) AS total
               FROM objeto_afectado GROUP BY departamento ORDER BY total DESC""",
        )
        por_municipio = _contar(
            conn,
            """SELECT e.municipio_divipola AS municipio, COUNT(*) AS total
               FROM objeto_afectado o JOIN evento e ON e.id_evento = o.id_evento
               GROUP BY e.municipio_divipola ORDER BY total DESC""",
        )
        por_fenomeno = _contar(
            conn,
            """SELECT e.fenomeno AS fenomeno, COUNT(*) AS total
               FROM objeto_afectado o JOIN evento e ON e.id_evento = o.id_evento
               GROUP BY e.fenomeno ORDER BY total DESC""",
        )
        por_severidad = _contar(
            conn,
            """SELECT COALESCE(nivel_dano_preliminar, 'sin_evaluar') AS severidad, COUNT(*) AS total
               FROM objeto_afectado GROUP BY nivel_dano_preliminar ORDER BY total DESC""",
        )
        por_estado_operativo = _contar(
            conn,
            """SELECT estado_operativo, COUNT(*) AS total
               FROM objeto_afectado GROUP BY estado_operativo ORDER BY total DESC""",
        )
        subsidio_arrendamiento = _contar(
            conn,
            """SELECT CASE requiere_subsidio_arrendamiento
                        WHEN 1 THEN 'si' WHEN 0 THEN 'no' ELSE 'sin_evaluar' END AS respuesta,
                      COUNT(*) AS total
               FROM objeto_afectado GROUP BY requiere_subsidio_arrendamiento""",
        )

        # Uso multiusuario: cuántos recolectores distintos han capturado datos,
        # y cuántos registros lleva cada uno — indicador operativo de campo.
        por_recolector = _contar(
            conn,
            """SELECT COALESCE(recolector_nombre, 'sin registrar') AS recolector,
                      recolector_entidad, COUNT(*) AS total
               FROM objeto_afectado GROUP BY recolector_nombre, recolector_entidad
               ORDER BY total DESC""",
        )

        return {
            "total_eventos": total_eventos,
            "total_objetos_afectados": total_objetos,
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
