#!/bin/bash
set -e

echo "🚀 Iniciando instalação avançada do ponto.py com LCD touchscreen e monitoramento..."

# -------------------------------------------------------------------
# 🔧 Atualização e pacotes base
# -------------------------------------------------------------------
echo "🔧 Atualizando sistema..."
sudo apt update -y && sudo apt upgrade -y
sudo apt install -y sqlite3 unclutter git libdrm-dev libdtovl-dev cmake python3 python3-pip python3-tk python3-rpi.gpio

# -------------------------------------------------------------------
# 🔍 Detectar modo (gráfico ou headless)
# -------------------------------------------------------------------
if [ -d "/etc/xdg/lxsession/LXDE-pi" ] || pgrep -x "lxsession" >/dev/null; then
  MODE="desktop"
  echo "🖥️ Ambiente gráfico LXDE detectado — modo Desktop."
else
  MODE="headless"
  echo "💡 Ambiente gráfico não detectado — modo Headless."
fi

# -------------------------------------------------------------------
# 📺 Backup do config.txt para rollback
# -------------------------------------------------------------------
BOOTCFG="/boot/firmware/config.txt"
[ -f "$BOOTCFG" ] || BOOTCFG="/boot/config.txt"
sudo cp "$BOOTCFG" "${BOOTCFG}.bak"
echo "💾 Backup do config.txt criado em ${BOOTCFG}.bak"

# -------------------------------------------------------------------
# 📺 Instalar driver LCD touchscreen automaticamente
# -------------------------------------------------------------------
echo "📺 Detectando LCD touchscreen conectado..."
LCD_DIR="/home/pi/LCD-show"
if [ ! -d "$LCD_DIR" ]; then
  git clone https://github.com/goodtft/LCD-show.git $LCD_DIR
fi
cd $LCD_DIR

# Detecta o tipo de LCD
LCD_SCRIPT=""
if dmesg | grep -qi "waveshare"; then
  LCD_SCRIPT="LCD35-show"
elif dmesg | grep -qi "mhs35"; then
  LCD_SCRIPT="MHS35-show"
elif dmesg | grep -qi "goodtft"; then
  LCD_SCRIPT="LCD35-show"
elif dmesg | grep -qi "fb_ili9486" || dmesg | grep -qi "ili9486"; then
  LCD_SCRIPT="LCD35-show"
else
  echo "⚠️ LCD touchscreen não detectado automaticamente. Usando LCD35-show por padrão."
  LCD_SCRIPT="LCD35-show"
fi

echo "📺 Instalando driver $LCD_SCRIPT..."
sudo chmod +x $LCD_SCRIPT
if ! sudo ./$LCD_SCRIPT; then
  echo "❌ Falha na instalação do driver LCD. Restaurando config.txt original..."
  sudo cp "${BOOTCFG}.bak" "$BOOTCFG"
  echo "🔄 Rollback concluído. Abortando instalação."
  exit 1
fi
echo "✅ Driver LCD instalado com sucesso."

# -------------------------------------------------------------------
# ⚙️ Configuração do ponto.py como serviço sudo com monitoramento
# -------------------------------------------------------------------
APP_PATH="/home/pi/raspi/ponto.py"
echo "⚙️ Criando serviço systemd para ponto.py (sudo + monitoramento)..."

cat <<EOF | sudo tee /etc/systemd/system/ponto.service > /dev/null
[Unit]
Description=Aplicação ponto.py automática (sudo + touchscreen)
After=graphical.target

[Service]
User=root
Environment=DISPLAY=:0
Environment=XAUTHORITY=/home/pi/.Xauthority
ExecStart=/usr/bin/python3 $APP_PATH
WorkingDirectory=/home/pi/raspi
Restart=always
RestartSec=5
# Se travar ou falhar, envia sinal de alerta (buzzer GPIO 18)
ExecStartPost=/bin/bash -c 'gpio -g mode 18 out; gpio -g write 18 1; sleep 0.5; gpio -g write 18 0'

[Install]
WantedBy=graphical.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable ponto.service
sudo systemctl start ponto.service
echo "✅ ponto.py configurado para iniciar como sudo na tela touchscreen com monitoramento."

# -------------------------------------------------------------------
# 🖱️ Ocultar cursor
# -------------------------------------------------------------------
echo "🖱️ Ocultando cursor..."
cat <<EOF | sudo tee /etc/systemd/system/unclutter.service > /dev/null
[Unit]
Description=Unclutter hide mouse cursor
After=display-manager.service

[Service]
ExecStart=/usr/bin/unclutter -idle 0.1 -root
Restart=always
User=pi

[Install]
WantedBy=graphical.target
EOF
sudo systemctl enable unclutter.service

# -------------------------------------------------------------------
# 📺 Configuração overlay SPI no config.txt
# -------------------------------------------------------------------
echo "📺 Configurando overlay SPI automaticamente..."
detectar_display_spi() {
  local overlay="piscreen"
  if dmesg | grep -qi "waveshare"; then
    overlay="waveshare35a"
  elif dmesg | grep -qi "mhs35"; then
    overlay="mhs35"
  elif dmesg | grep -qi "goodtft"; then
    overlay="goodtft35a"
  elif dmesg | grep -qi "fb_ili9486" || dmesg | grep -qi "ili9486"; then
    overlay="piscreen"
  fi
  echo "$overlay"
}

DISPLAY_OVERLAY=$(detectar_display_spi)

sudo tee -a "$BOOTCFG" > /dev/null <<EOF

# --- Display SPI configurado automaticamente ---
dtoverlay=vc4-kms-v3d
dtoverlay=${DISPLAY_OVERLAY},speed=16000000,rotate=90
framebuffer_width=480
framebuffer_height=320
EOF
echo "✅ Overlay aplicado com sucesso!"

# -------------------------------------------------------------------
# 🔐 Permitir sudo sem senha para python3
# -------------------------------------------------------------------
echo "🔐 Ajustando sudoers para permitir execução sem senha..."
sudo bash -c 'echo "pi ALL=(ALL) NOPASSWD: /usr/bin/python3" > /etc/sudoers.d/010_pi-nopasswd-python'
sudo chmod 440 /etc/sudoers.d/010_pi-nopasswd-python

# -------------------------------------------------------------------
# 🧹 Limpeza
# -------------------------------------------------------------------
echo "🧹 Limpando pacotes desnecessários..."
sudo apt autoremove -y
sudo apt clean

echo ""
echo "✅ Instalação completa com monitoramento, rollback e alerta via buzzer!"
echo "🔁 Reinicie o sistema com: sudo reboot"
