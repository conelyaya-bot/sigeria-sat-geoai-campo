# Despliegue de SIGERIA en Google Cloud (Always Free)

App en vivo (HTTPS real, candado verde): **https://35-196-65-232.sslip.io**
(la IP sola, `http://35.196.65.232`, también responde pero sin certificado)

Este directorio documenta cómo se creó la VM real que corre SIGERIA — para poder
recrearla desde cero si hiciera falta, o para que otro departamento haga lo mismo con
su propia cuenta de Google Cloud.

## Requisitos

- Cuenta de Google Cloud con facturación activada (necesaria incluso para el nivel
  Always Free — no cobra si te quedas dentro de esos límites).
- `gcloud` CLI instalado (`brew install --cask google-cloud-sdk` en Mac) y autenticado
  (`gcloud auth login`).

## Pasos (los que se ejecutaron para la app en vivo actual)

```bash
PROYECTO="tu-project-id"   # el de SIGERIA en vivo es campa2026-7a020

gcloud config set project "$PROYECTO"
gcloud services enable compute.googleapis.com --project="$PROYECTO"

# Always Free solo aplica en us-west1, us-central1 o us-east1 — si una zona no
# tiene cupo disponible (pasó con us-central1-a al desplegar SIGERIA), probar otra.
gcloud compute instances create sigeria-campo \
  --project="$PROYECTO" \
  --zone=us-east1-b \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --boot-disk-size=30GB \
  --boot-disk-type=pd-standard \
  --tags=http-server \
  --metadata-from-file=startup-script=deploy/gcloud_startup.sh

gcloud compute firewall-rules create sigeria-allow-http \
  --project="$PROYECTO" \
  --allow=tcp:80 \
  --target-tags=http-server \
  --direction=INGRESS \
  --source-ranges=0.0.0.0/0

# Fijar la IP para que no cambie con un reinicio (usar la IP real que asignó Google):
gcloud compute addresses create sigeria-campo-ip \
  --project="$PROYECTO" \
  --region=us-east1 \
  --addresses=IP_QUE_TE_DIO_GOOGLE
```

`gcloud_startup.sh` es exactamente el script que Google Cloud ejecuta como `root` al
crear la VM: instala Python/git, clona este mismo repo (público, sin credenciales),
instala las dependencias en un venv, y registra un servicio `systemd` con
`Restart=always` — si el proceso se cae o la VM se reinicia, vuelve a levantarse solo.

## Actualizar el código en la VM ya creada

```bash
gcloud compute ssh sigeria-campo --zone=us-east1-b --project=campa2026-7a020 \
  --command="cd /opt/sigeria && sudo git pull && cd backend && sudo ./.venv/bin/pip install -r requirements.txt && sudo systemctl restart sigeria"
```

## Revisar logs / estado

```bash
gcloud compute ssh sigeria-campo --zone=us-east1-b --project=campa2026-7a020 \
  --command="sudo journalctl -u sigeria -n 50 --no-pager"
```

## HTTPS real con sslip.io + Let's Encrypt (sin comprar dominio)

`sslip.io` da un nombre de host que resuelve directo a la IP embebida en el propio
nombre (`35-196-65-232.sslip.io` → `35.196.65.232`), sin tocar ningún DNS. Con ese
nombre Let's Encrypt sí puede validar y emitir un certificado real (con solo la IP no
puede — el challenge HTTP-01 necesita un hostname).

```bash
# En la VM (por SSH):
sudo apt-get install -y nginx certbot python3-certbot-nginx

# Mover uvicorn a un puerto interno — nginx queda como único expuesto en 80/443
sudo sed -i 's/--port 80/--port 8080/; s/--host 0.0.0.0/--host 127.0.0.1/' \
  /etc/systemd/system/sigeria.service
sudo systemctl daemon-reload && sudo systemctl restart sigeria

# Proxy reverso
sudo tee /etc/nginx/sites-available/sigeria > /dev/null <<'EOF'
server {
    listen 80;
    server_name TU-IP-CON-GUIONES.sslip.io;
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
EOF
sudo rm -f /etc/nginx/sites-enabled/default
sudo ln -sf /etc/nginx/sites-available/sigeria /etc/nginx/sites-enabled/sigeria
sudo nginx -t && sudo systemctl restart nginx

# Certificado real — certbot configura nginx solo (HTTPS + redirect HTTP→HTTPS)
sudo certbot --nginx -d TU-IP-CON-GUIONES.sslip.io --non-interactive --agree-tos \
  -m tu-correo@ejemplo.com --redirect
```

Y abrir el firewall para 443:
```bash
gcloud compute firewall-rules create sigeria-allow-https \
  --project="$PROYECTO" --allow=tcp:443 --target-tags=http-server \
  --direction=INGRESS --source-ranges=0.0.0.0/0
```

El certificado se renueva solo (`certbot.timer`, ya viene activo por defecto).

## Limitaciones honestas

- 1 VM `e2-micro` (2 vCPU compartidas, 1 GB RAM) — alcanza para un piloto, no para carga
  masiva nacional.
- Base de datos SQLite en el disco de la VM — persiste reinicios, se pierde si se borra
  la instancia. Migrar a PostgreSQL/PostGIS (`db/schema_postgis.sql`) sigue pendiente.
- ~~Solo HTTP~~ — ya resuelto, ver sección de HTTPS arriba. `sslip.io` + Let's Encrypt
  dan un candado real gratis sin necesitar un dominio comprado.
