"""SIGERIA — API del MVP (4 módulos). FastAPI + SQLite local por defecto.

Arrancar en desarrollo:
    cd backend
    ./.venv/bin/uvicorn app.main:app --reload --port 8010

Arrancar en producción (Google Cloud VM, Railway, etc. — respeta $PORT):
    uvicorn app.main:app --host 0.0.0.0 --port $PORT

Docs interactivas: http://127.0.0.1:8010/docs

Este mismo proceso sirve DOS cosas a la vez, para que un solo servicio alcance:
  - La API bajo /api/... (los routers de los 4 módulos + estadísticas + expedientes).
  - La app Flutter Web ya compilada, servida como archivos estáticos desde
    app/static_web/ (generada con `flutter build web --dart-define=SIGERIA_API=`
    — vacío a propósito: en producción la app y la API viven en el mismo dominio,
    así que las peticiones relativas ya apuntan al lugar correcto sin configurar nada).
"""
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from app.db.database import init_db
from app.routers import edan, estadisticas, eventos, expedientes, gis, inspeccion_ais, medicion

app = FastAPI(
    title="SIGERIA API",
    description=(
        "Sistema Inteligente Geoespacial para Evaluación, Respuesta e Inspección "
        "de Afectaciones — API del MVP (Evento y objetos, EDAN básico, GIS offline, "
        "Medición móvil). Integrado al ecosistema SAT-GeoAI Chocó."
    ),
    version="0.1.0-mvp",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # ajustar en producción
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(eventos.router)
app.include_router(edan.router)
app.include_router(gis.router)
app.include_router(medicion.router)
app.include_router(estadisticas.router)
app.include_router(expedientes.router)
app.include_router(inspeccion_ais.router)


@app.on_event("startup")
def on_startup():
    init_db()


@app.get("/api/salud")
def salud():
    return {"estado": "ok", "servicio": "SIGERIA API", "version": app.version}


# --- App Flutter Web (archivos estáticos) -----------------------------------
# Va DESPUÉS de las rutas /api/... a propósito: FastAPI resuelve en orden de
# declaración, así que /api/* ya quedó resuelto por los routers de arriba antes
# de llegar aquí. Si no existe static_web/ (p. ej. corriendo solo el backend en
# desarrollo sin haber compilado el Flutter Web), simplemente no se monta —
# la API sigue funcionando igual, solo no hay interfaz en "/".
_CARPETA_WEB = Path(__file__).resolve().parent / "static_web"
if _CARPETA_WEB.exists():
    app.mount("/assets", StaticFiles(directory=_CARPETA_WEB / "assets"), name="assets")
    app.mount("/canvaskit", StaticFiles(directory=_CARPETA_WEB / "canvaskit"), name="canvaskit")
    app.mount("/icons", StaticFiles(directory=_CARPETA_WEB / "icons"), name="icons")

    @app.get("/{ruta_completa:path}", include_in_schema=False)
    def servir_app(ruta_completa: str):
        """Sirve la app Flutter Web. Cualquier ruta que no sea un archivo real
        (p. ej. una recargada por el navegador dentro de la app) cae a
        index.html — así el router interno de Flutter la resuelve él mismo."""
        candidato = _CARPETA_WEB / ruta_completa
        if ruta_completa and candidato.is_file():
            return FileResponse(candidato)
        return FileResponse(_CARPETA_WEB / "index.html")
