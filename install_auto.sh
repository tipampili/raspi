#!/bin/bash
set -e

echo "🚀 Iniciando instalação híbrida com detecção automática de display..."

# -------------------------------------------------------------------
# 🔧 Atualização e pacotes base
# -------------------------------------------------------------------
echo "🔧 Atualizando sistema..."
sudo apt update -y && sudo apt upgrade -y
sudo apt install -y sqlite3 x11vnc unclutter git libdrm-dev libdtovl-dev cmake python3 python3-pip

# -------------------------------------------------------------------
# 🔍 Detectar modo (gráfico ou headless)
# -------------------------------------------------------------------
if [ -d "/etc/xdg/lxsession/LXDE-pi" ] || pgrep -x "lxsession" >/dev/null; then
  MODE="desktop"
  echo "🖥️ Ambiente gráfico LXDE detectado — instalando no modo Desktop."
else
  MODE="headless"
  echo "💡 Ambiente gráfico não detectado — instalando no modo Headless."
fi

# -------------------------------------------------------------------
# 🧱 Configuração do VNC
# -------------------------------------------------------------------
echo "🧱 Configurando VNC..."
sudo mkdir -p /etc/x11vnc
sudo x11vnc -storepasswd 1234 /etc/x11vnc/pass  # troque 1234 pela senha desejada

cat <<EOF | sudo tee /etc/systemd/system/x11vnc.service > /dev/null
[Unit]
Description=X11VNC Service
After=graphical.target network.target

[Service]
Type=simple
ExecStart=/usr/bin/x11vnc -rfbauth /etc/x11vnc/pass -forever -shared -display :0 -auth guess -noxdamage
Restart=always
User=pi

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable x11vnc.service

# -------------------------------------------------------------------
# ⚙️ Inicialização automática da aplicação
# -------------------------------------------------------------------
echo "⚙️ Configurando inicialização automática..."
if [ "$MODE" = "desktop" ]; then
  mkdir -p /home/pi/.config/autostart
  install -m 644 auto.desktop /home/pi/.config/autostart/auto.desktop
  install -m 644 x11vnc.desktop /home/pi/.config/autostart/x11vnc.desktop

  sudo mkdir -p /etc/lightdm
  sudo install -m 644 lightdm.conf /etc/lightdm/lightdm.conf

  if [ -d "/etc/xdg/lxsession/LXDE-pi" ]; then
    sudo install -m 644 autostart /etc/xdg/lxsession/LXDE-pi/autostart
  fi
  echo "✅ Autostart configurado para Desktop."
else
  cat <<EOF | sudo tee /etc/systemd/system/pythonapp.service > /dev/null
[Unit]
Description=Aplicação Python automática
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /home/pi/seu_script.py
WorkingDirectory=/home/pi
Restart=always
User=pi

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl enable pythonapp.service
  echo "✅ Serviço Python configurado para iniciar automaticamente (modo headless)."
fi

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
# 📺 Detecção automática do display SPI
# -------------------------------------------------------------------
echo "📺 Detectando display SPI conectado..."

# Função auxiliar
detectar_display_spi() {
  local overlay="piscreen"

  # Detectar pelo dmesg
  if dmesg | grep -qi "waveshare"; then
    overlay="waveshare35a"
  elif dmesg | grep -qi "mhs35"; then
    overlay="mhs35"
  elif dmesg | grep -qi "goodtft"; then
    overlay="goodtft35a"
  elif dmesg | grep -qi "fb_ili9486" || dmesg | grep -qi "ili9486"; then
    overlay="piscreen"
  elif ls /sys/class/spi_master/spi0/spi0.0 2>/dev/null | grep -q "spi0.0"; then
    overlay="piscreen"
  fi

  echo "$overlay"
}

DISPLAY_OVERLAY=$(detectar_display_spi)
BOOTCFG="/boot/firmware/config.txt"
[ -f "$BOOTCFG" ] || BOOTCFG="/boot/config.txt"

echo "🧩 Display detectado: $DISPLAY_OVERLAY"
echo "⚙️ Aplicando overlay em $BOOTCFG..."

sudo tee -a "$BOOTCFG" > /dev/null <<EOF

# --- Display SPI configurado automaticamente ---
dtoverlay=vc4-kms-v3d
dtoverlay=${DISPLAY_OVERLAY},speed=16000000,rotate=90
framebuffer_width=480
framebuffer_height=320
EOF

echo "✅ Overlay aplicado com sucesso!"

# -------------------------------------------------------------------
# 🧹 Limpeza
# -------------------------------------------------------------------
echo "🧹 Limpando pacotes desnecessários..."
sudo apt autoremove -y
sudo apt clean

echo ""
echo "✅ Instalação concluída!"
if [ "$MODE" = "desktop" ]; then
  echo "🖥️ Modo: Desktop (LXDE + autostart + VNC + display SPI)"
else
  echo "💡 Modo: Headless (systemd + VNC + display SPI)"
fi
echo "🔁 Reinicie o sistema com: sudo reboot"
