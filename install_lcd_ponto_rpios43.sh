#!/bin/bash
set -e

echo "🚀 Iniciando instalação / reconfiguração do ponto.py com LCD touchscreen (Raspberry Pi 4, kernel 6.0)..."
echo "───────────────────────────────────────────────────────────────"

# -------------------------------------------------------------------
# 🔧 Atualização e pacotes base
# -------------------------------------------------------------------
sudo apt update -y && sudo apt upgrade -y
sudo apt install -y sqlite3 unclutter git cmake python3 python3-pip python3-tk python3-rpi.gpio fbset fbi

# -------------------------------------------------------------------
# 📄 Caminhos padrão
# -------------------------------------------------------------------
BOOTCFG="/boot/firmware/config.txt"
[ -f "$BOOTCFG" ] || BOOTCFG="/boot/config.txt"
APP_PATH="/home/pi/raspi/ponto.py"
SERVICE_PATH="/etc/systemd/system/ponto.service"

# -------------------------------------------------------------------
# 🩺 Detectar se já existe configuração anterior
# -------------------------------------------------------------------
if [ -f "$SERVICE_PATH" ]; then
  echo "⚙️ Detecção: o serviço ponto.service já existe."
  echo "Escolha a ação desejada:"
  echo "1) Reconfigurar display e reinstalar serviço"
  echo "2) Apenas reiniciar serviço ponto"
  echo "3) Cancelar"
  read -p "👉 Escolha [1-3]: " opt
  case $opt in
    1) echo "🔧 Reconfigurando...";;
    2) sudo systemctl restart ponto.service && echo "✅ Serviço reiniciado." && exit 0;;
    3) echo "🚪 Saindo sem alterações." && exit 0;;
  esac
fi

# -------------------------------------------------------------------
# 💾 Backup para rollback
# -------------------------------------------------------------------
BACKUP="${BOOTCFG}.bak.$(date +%Y%m%d%H%M)"
sudo cp "$BOOTCFG" "$BACKUP"
echo "💾 Backup criado: $BACKUP"

# -------------------------------------------------------------------
# 📺 Detectar display SPI automaticamente
# -------------------------------------------------------------------
echo ""
echo "📺 Detectando LCD touchscreen..."
DETECTED="none"

if dmesg | grep -qi "waveshare"; then
  DETECTED="waveshare"
elif dmesg | grep -qi "mhs35"; then
  DETECTED="mhs35"
elif dmesg | grep -qi "goodtft"; then
  DETECTED="goodtft"
elif dmesg | grep -qi "ili9486"; then
  DETECTED="ili9486"
fi

# -------------------------------------------------------------------
# 🖐️ Seleção manual (caso não detectado)
# -------------------------------------------------------------------
if [ "$DETECTED" = "none" ]; then
  echo ""
  echo "⚠️ Nenhum LCD detectado automaticamente."
  echo "Selecione o modelo:"
  echo "1) Waveshare 3.5\""
  echo "2) MHS 3.5\""
  echo "3) GoodTFT 3.5\""
  echo "4) ILI9486 Genérico"
  echo "5) Outro SPI (overlay padrão)"
  read -p "👉 Escolha [1-5]: " opt
  case $opt in
    1) DETECTED="waveshare" ;;
    2) DETECTED="mhs35" ;;
    3) DETECTED="goodtft" ;;
    4) DETECTED="ili9486" ;;
    5|*) DETECTED="default" ;;
  esac
fi

# -------------------------------------------------------------------
# ⚙️ Aplicar overlay correspondente (modo KMS moderno)
# -------------------------------------------------------------------
echo ""
echo "📄 Aplicando configuração para display: $DETECTED"
OVERLAY="vc4-kms-dpi-default"

case $DETECTED in
  waveshare) OVERLAY="vc4-kms-dpi-waveshare35a" ;;
  mhs35) OVERLAY="vc4-kms-dpi-mhs35" ;;
  goodtft) OVERLAY="vc4-kms-dpi-ili9486" ;;  # GoodTFT usa ILI9486
  ili9486) OVERLAY="vc4-kms-dpi-ili9486" ;;
esac

sudo sed -i '/^dtoverlay=/d' "$BOOTCFG"
sudo tee -a "$BOOTCFG" > /dev/null <<EOF

# --- LCD SPI configurado automaticamente (kernel 6.0) ---
dtoverlay=${OVERLAY},rotate=90,speed=48000000
max_framebuffers=2
framebuffer_width=480
framebuffer_height=320
EOF

echo "✅ Overlay aplicado: $OVERLAY"

# -------------------------------------------------------------------
# 🧪 Teste de framebuffer e rollback se falhar
# -------------------------------------------------------------------
echo ""
echo "🔎 Testando framebuffer..."
if ! fbset -s >/dev/null 2>&1; then
  echo "❌ Framebuffer não detectado! Restaurando backup..."
  sudo cp "$BACKUP" "$BOOTCFG"
  echo "🔄 Configuração revertida."
  exit 1
else
  echo "✅ Framebuffer ativo."
fi

# -------------------------------------------------------------------
# ⚙️ Criar serviço systemd para ponto.py (com sudo)
# -------------------------------------------------------------------
echo ""
echo "⚙️ Criando serviço systemd para ponto.py..."
cat <<EOF | sudo tee "$SERVICE_PATH" > /dev/null
[Unit]
Description=Aplicação ponto.py automática (sudo + LCD)
After=graphical.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 $APP_PATH
WorkingDirectory=/home/pi/raspi
Environment=DISPLAY=:0
Environment=XAUTHORITY=/home/pi/.Xauthority
Restart=always
RestartSec=5

[Install]
WantedBy=graphical.target
EOF

sudo chmod 644 "$SERVICE_PATH"
sudo systemctl daemon-reload
sudo systemctl enable ponto.service

echo "✅ Serviço ponto.service criado e habilitado."

# -------------------------------------------------------------------
# 🖱️ Ocultar cursor
# -------------------------------------------------------------------
cat <<EOF | sudo tee /etc/systemd/system/unclutter.service > /dev/null
[Unit]
Description=Ocultar cursor do mouse
After=graphical.target

[Service]
ExecStart=/usr/bin/unclutter -idle 0.1 -root
Restart=always
User=pi

[Install]
WantedBy=graphical.target
EOF

sudo systemctl enable unclutter.service

# -------------------------------------------------------------------
# 🔐 Ajustar sudoers (para permitir execução direta)
# -------------------------------------------------------------------
sudo bash -c 'echo "pi ALL=(ALL) NOPASSWD: /usr/bin/python3" > /etc/sudoers.d/010_pi-nopasswd-python'
sudo chmod 440 /etc/sudoers.d/010_pi-nopasswd-python

# -------------------------------------------------------------------
# 🧹 Limpeza final
# -------------------------------------------------------------------
sudo apt autoremove -y && sudo apt clean
echo ""
echo "✅ Instalação concluída com sucesso!"
echo "📺 Display configurado: $OVERLAY"
echo "💾 Backup salvo em: $BACKUP"
echo "⚙️ Serviço criado: $SERVICE_PATH"
echo "🔁 Reinicie o sistema para aplicar (sudo reboot)"
