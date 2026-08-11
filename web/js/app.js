/* SIGERIA — dashboard web "sala de crisis" (piloto MVP)
 * Consume el GeoJSON expuesto por GET /api/gis/geojson/{id_evento} del backend
 * (backend/app/routers/gis.py) o el archivo estático de demo. Sin dependencias
 * de build: HTML+JS plano + MapLibre GL por CDN, para poder abrirlo con
 * cualquier servidor estático (o QField/QGIS puede leer el mismo GeoJSON).
 */

const API_BASE = "http://127.0.0.1:8010";
const ID_EVENTO_DEMO = "SIGERIA-EVT-2026-a5e3f907"; // el que generó el backend en la prueba end-to-end

const COLOR_SEVERIDAD = {
  sin_evaluar: "#8a8f98",
  sin_dano: "#2e8b57",
  leve: "#c9b400",
  moderado: "#e08a1e",
  severo: "#d1392b",
  colapso: "#6b0f1a",
};

const map = new maplibregl.Map({
  container: "map",
  style: "https://demotiles.maplibre.org/style.json", // basemap abierto, sin API key
  center: [-76.66, 5.7], // Quibdó / Chocó aproximado
  zoom: 9,
});
map.addControl(new maplibregl.NavigationControl(), "top-right");

let marcadores = [];

async function cargarDatos(fuente) {
  let geojson;
  try {
    if (fuente === "api") {
      const resp = await fetch(`${API_BASE}/api/gis/geojson/${ID_EVENTO_DEMO}`);
      if (!resp.ok) throw new Error("Backend no disponible en " + API_BASE);
      geojson = await resp.json();
    } else {
      const resp = await fetch(fuente);
      geojson = await resp.json();
    }
  } catch (err) {
    console.error(err);
    alert(
      "No se pudo cargar la fuente de datos.\n" +
        (fuente === "api"
          ? "Verifica que el backend esté corriendo: cd backend && ./.venv/bin/uvicorn app.main:app --port 8010"
          : String(err))
    );
    return;
  }
  render(geojson);
}

function render(geojson) {
  marcadores.forEach((m) => m.remove());
  marcadores = [];

  const features = geojson.features || [];
  let severos = 0;
  let fueraServicio = 0;

  const ul = document.getElementById("ul-objetos");
  ul.innerHTML = "";

  const bounds = new maplibregl.LngLatBounds();

  for (const f of features) {
    const p = f.properties;
    const color = COLOR_SEVERIDAD[p.nivel_dano_preliminar] || COLOR_SEVERIDAD.sin_evaluar;

    if (["severo", "colapso"].includes(p.nivel_dano_preliminar)) severos++;
    if (p.estado_operativo === "fuera_de_servicio") fueraServicio++;

    if (f.geometry && f.geometry.type === "Point") {
      const [lng, lat] = f.geometry.coordinates;
      const el = document.createElement("div");
      el.style.cssText = `width:16px;height:16px;border-radius:50%;background:${color};border:2px solid white;box-shadow:0 0 4px rgba(0,0,0,.4);cursor:pointer;`;
      const marker = new maplibregl.Marker({ element: el })
        .setLngLat([lng, lat])
        .setPopup(
          new maplibregl.Popup({ offset: 12 }).setHTML(
            `<b>${p.id_objeto}</b><br/>${p.tipo_objeto} · ${p.fenomeno}<br/>
             Daño: ${p.nivel_dano_preliminar || "sin evaluar"}<br/>
             Estado: ${p.estado_operativo}<br/>
             Precisión GNSS: ${p.precision_gnss_m ?? "?"} m`
          )
        )
        .addTo(map);
      marcadores.push(marker);
      bounds.extend([lng, lat]);
    }

    const li = document.createElement("li");
    li.innerHTML = `<b>${p.id_objeto}</b>${p.tipo_objeto} · ${p.municipio_divipola} · ${
      p.nivel_dano_preliminar || "sin evaluar"
    }`;
    li.addEventListener("click", () => {
      if (f.geometry?.type === "Point") {
        map.flyTo({ center: f.geometry.coordinates, zoom: 15 });
      }
    });
    ul.appendChild(li);
  }

  document.getElementById("kpi-total").textContent = features.length;
  document.getElementById("kpi-severos").textContent = severos;
  document.getElementById("kpi-fuera-servicio").textContent = fueraServicio;

  if (!bounds.isEmpty()) {
    map.fitBounds(bounds, { padding: 60, maxZoom: 14 });
  }
}

document.getElementById("btn-recargar").addEventListener("click", () => {
  const fuente = document.getElementById("select-fuente").value;
  cargarDatos(fuente);
});

map.on("load", () => cargarDatos(document.getElementById("select-fuente").value));
