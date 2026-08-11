"""SIGERIA — API del MVP (4 módulos). FastAPI + SQLite local por defecto.

Arrancar:
    cd backend
    ./.venv/bin/uvicorn app.main:app --reload --port 8010

Docs interactivas: http://127.0.0.1:8010/docs
"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.db.database import init_db
from app.routers import edan, estadisticas, eventos, expedientes, gis, medicion

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


@app.on_event("startup")
def on_startup():
    init_db()


@app.get("/api/salud")
def salud():
    return {"estado": "ok", "servicio": "SIGERIA API", "version": app.version}
