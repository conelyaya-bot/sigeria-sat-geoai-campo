"""Módulo MVP 4: Medición móvil — distancia, área, pendiente/inclinación, foto calibrada."""
from __future__ import annotations

from fastapi import APIRouter, HTTPException

from app.db.database import get_conn, new_uuid, row_to_dict
from app.schemas.schemas import MedicionCrear, MedicionOut

router = APIRouter(prefix="/api/mediciones", tags=["4. Medición móvil"])

# Rangos razonables por tipo — sección 21 "Reglas de calidad de dato": fuera de rango
# no bloquea, solo se marca para confirmación (igual que en la Matriz Maestra MED-002/003).
RANGOS_ORIENTATIVOS = {
    "distancia": (0, 500),      # m
    "area": (0, 100000),        # m2
    "pendiente": (0, 90),       # grados
    "altura": (0, 100),         # m
    "grieta": (0, 5),           # m (ancho/longitud de grieta)
}


@router.post("", response_model=MedicionOut)
def crear_medicion(payload: MedicionCrear):
    with get_conn() as conn:
        existe = conn.execute(
            "SELECT 1 FROM objeto_afectado WHERE id_objeto=?", (payload.id_objeto,)
        ).fetchone()
        if not existe:
            raise HTTPException(404, f"Objeto afectado {payload.id_objeto} no existe")

        id_medicion = new_uuid()
        conn.execute(
            """INSERT INTO medicion
               (id_medicion, id_objeto, tipo, valor, unidad, metodo, precision_categoria)
               VALUES (?,?,?,?,?,?,?)""",
            (id_medicion, payload.id_objeto, payload.tipo, payload.valor, payload.unidad,
             payload.metodo, payload.precision_categoria),
        )
        row = conn.execute(
            "SELECT * FROM medicion WHERE id_medicion=?", (id_medicion,)
        ).fetchone()
        out = row_to_dict(row)

        lo, hi = RANGOS_ORIENTATIVOS.get(payload.tipo, (None, None))
        out["fuera_de_rango"] = bool(lo is not None and not (lo <= payload.valor <= hi))
        return out


@router.get("/objeto/{id_objeto}", response_model=list[MedicionOut])
def mediciones_de_objeto(id_objeto: str):
    with get_conn() as conn:
        rows = conn.execute(
            "SELECT * FROM medicion WHERE id_objeto=? ORDER BY creado_en DESC", (id_objeto,)
        ).fetchall()
        return [row_to_dict(r) for r in rows]
