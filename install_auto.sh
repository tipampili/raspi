#!/bin/bash
set -e

echo "🚀 Iniciando instalação híbrida com autostart de ponto.py..."

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
# ⚙️ Inicialização automática da aplicação ponto.py
# -------------------------------------------------------------------
APP_PATH="/home/pi/raspi/ponto.py"

if [ "$MODE" = "desktop" ]; then
  echo "⚙️ Configurando autostart do ponto.py no ambiente gráfico..."
  mkdir -p /home/pi/.config/autostart
  cat <<EOF > /home/pi/.config/autostart/ponto.desktop
[Desktop Entry]
Type=Application
Name=PontoApp
Exec=/usr/bin/python3 $APP_PATH
X-GNOME-Autostart-enabled=true
EOF

  # Copiar VNC para autostart
  cat <<EOF > /home/pi/.config/autostart/x11vnc.desktop
[Desktop Entry]
Type=Application
Name=X11VNC
Exec=/usr/bin/systemctl start x11vnc.service
X-GNOME-Autostart-enabled=true
EOF

  sudo mkdir -p /etc/lightdm
  sudo install -m 644 lightdm.conf /etc/lightdm/lightdm.conf

  echo "✅ ponto.py será iniciado automaticamente no ambiente Desktop."
else
  echo "⚙️ Criando serviço systemd para executar ponto.py..."
  cat <<EOF | sudo tee /etc/systemd/system/ponto.service > /dev/null
[Unit]
Description=Aplicação ponto.py automática
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 $APP_PATH
WorkingDirectory=/home/pi/raspi
Restart=always
User=pi

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl enable ponto.service
  echo "✅ ponto.py será iniciado automaticamente no modo Headless."
fi

# -------------------------------------------------------------------
# 🖱️ Ocultar cursor (se houver display)
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
# 📺 Detecção automática de display SPI
# -------------------------------------------------------------------
echo "📺 Detectando display SPI conectado..."

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
  echo "🖥️ Modo: Desktop (autostart ponto.py + VNC + display SPI)"
else
  echo "💡 Modo: Headless (systemd ponto.service + VNC + display SPI)"
fi
echo "🔁 Reinicie o sistema com: sudo reboot"
