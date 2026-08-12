#!/bin/bash
# Startup script de la VM de SIGERIA — corre solo una vez al crear la instancia
# (Google Cloud lo ejecuta automáticamente como root en cada arranque).
set -e
exec > /var/log/sigeria-startup.log 2>&1
echo "== SIGERIA startup: $(date) =="

apt-get update -y
apt-get install -y python3-venv python3-pip git

# Carpeta de datos persistente (vive en el disco de arranque de la VM, que sí
# sobrevive reinicios y apagados — solo se pierde si se BORRA la instancia).
mkdir -p /opt/sigeria-data/evidencias

# Clona o actualiza el código (repo público, sin credenciales).
if [ -d /opt/sigeria/.git ]; then
  cd /opt/sigeria && git pull
else
  rm -rf /opt/sigeria
  git clone https://github.com/conelyaya-bot/sigeria-sat-geoai-campo.git /opt/sigeria
fi

cd /opt/sigeria/backend
python3 -m venv .venv
./.venv/bin/pip install --upgrade pip
./.venv/bin/pip install -r requirements.txt

cat > /etc/systemd/system/sigeria.service <<'EOF'
[Unit]
Description=SIGERIA API + app (uvicorn)
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/sigeria/backend
Environment=SIGERIA_DB_PATH=/opt/sigeria-data/sigeria_local.db
Environment=SIGERIA_CARPETA_EVIDENCIAS=/opt/sigeria-data/evidencias
ExecStart=/opt/sigeria/backend/.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 80
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable sigeria
systemctl restart sigeria
echo "== SIGERIA startup terminado =="
