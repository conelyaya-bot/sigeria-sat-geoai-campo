"""
Capa de acceso a datos de SIGERIA.

Por defecto usa SQLite (cero instalación, cero permisos), leyendo/escribiendo
directo con sqlite3 de la librería estándar — mismo patrón que
`backend_encuestas/db_local.py` del proyecto Escuchar Turbo (ver memoria de
proyecto). La geometría se guarda como GeoJSON en texto.

Si se define la variable de entorno DATABASE_URL apuntando a Postgres
(postgresql://usuario:clave@host:5432/sigeria) el backend puede migrarse a
SQLAlchemy + GeoAlchemy2 sobre `schema_postgis.sql` sin cambiar los routers,
porque estos solo llaman a las funciones de este módulo.
"""
from __future__ import annotations

import json
import os
import sqlite3
import uuid
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator

BASE_DIR = Path(__file__).resolve().parents[3]  # backend/app/db -> SIGERIA_SAT_GeoAI_Campo
DB_PATH = Path(os.environ.get("SIGERIA_DB_PATH", BASE_DIR / "workspace" / "sigeria_local.db"))
SCHEMA_PATH = Path(__file__).resolve().parents[2] / "db" / "schema_sqlite.sql"

DB_PATH.parent.mkdir(parents=True, exist_ok=True)


def _connect() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def init_db() -> None:
    """Crea el esquema si no existe. Llamar al arrancar la app."""
    with _connect() as conn:
        conn.executescript(SCHEMA_PATH.read_text(encoding="utf-8"))


@contextmanager
def get_conn() -> Iterator[sqlite3.Connection]:
    conn = _connect()
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def new_uuid() -> str:
    return str(uuid.uuid4())


CODIGOS_FENOMENO = {
    "sismo": "SIS",
    "inundacion": "INU",
    "deslizamiento": "DES",
    "vendaval": "VEN",
    "incendio": "INC",
    "erosion_socavacion": "ERO",
    "creciente_subita": "CRE",
    "otro": "OTR",
}


def generar_id_evento(conn: sqlite3.Connection) -> str:
    """SIGERIA-EVT-<AAAA>-<NNNNNN> — secuencial por año, sin texto aleatorio.
    (Antes usaba un fragmento de UUID al azar; se corrigió porque un código
    con letras/números sueltos sin patrón se lee como "código raro" en campo.)
    """
    anio = datetime.now().year
    prefijo = f"SIGERIA-EVT-{anio}-"
    cur = conn.execute(
        "SELECT COUNT(*) AS n FROM evento WHERE id_evento LIKE ?", (prefijo + "%",)
    )
    n = cur.fetchone()["n"] + 1
    return f"{prefijo}{n:06d}"


def generar_id_objeto(municipio_divipola: str, fenomeno: str, conn: sqlite3.Connection) -> str:
    """SIGERIA-CHO-<DIVIPOLA>-<FEN>-<AAAA>-<NNNNNN> — ver docs/MODELO_DATOS.md"""
    anio = datetime.now().year
    fen_cod = CODIGOS_FENOMENO.get(fenomeno, "OTR")
    prefijo = f"SIGERIA-CHO-{municipio_divipola}-{fen_cod}-{anio}-"
    cur = conn.execute(
        "SELECT COUNT(*) AS n FROM objeto_afectado WHERE id_objeto LIKE ?",
        (prefijo + "%",),
    )
    n = cur.fetchone()["n"] + 1
    return f"{prefijo}{n:06d}"


def row_to_dict(row: sqlite3.Row) -> dict[str, Any]:
    return {k: row[k] for k in row.keys()}
