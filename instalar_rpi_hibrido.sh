#!/bin/bash
set -e

echo "🚀 Iniciando instalação híbrida para Raspberry Pi..."

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
# ⚙️ Configuração de inicialização automática
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

  echo "✅ Autostart configurado para ambiente Desktop."
else
  echo "⚙️ Criando serviço systemd para iniciar aplicação Python..."
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
  echo "✅ Serviço Python configurado para inicializar automaticamente (modo headless)."
fi

# -------------------------------------------------------------------
# 🖱️ Ocultar cursor (somente se houver display)
# -------------------------------------------------------------------
echo "🖱️ Configurando ocultação de cursor..."
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
# 📺 Instalação do driver de tela com fallback moderno
# -------------------------------------------------------------------
echo "📺 Instalando driver de tela (detecção automática)..."
cd /home/pi
sudo rm -rf LCD-show || true

git clone --depth 1 https://github.com/goodtft/LCD-show.git || true

LCD_FAIL=0
if [ -d "/home/pi/LCD-show" ]; then
  cd /home/pi/LCD-show
  chmod +x *.sh || true

  if [ -f "./LCD35-show" ]; then
    echo "🔍 Tentando executar script antigo (LCD35-show)..."
    if ! sudo ./LCD35-show; then
      LCD_FAIL=1
    fi
  else
    LCD_FAIL=1
  fi
else
  LCD_FAIL=1
fi

# -------------------------------------------------------------------
# 🚫 Se o LCD-show falhar, aplicar overlay moderno
# -------------------------------------------------------------------
if [ "${LCD_FAIL}" = "1" ]; then
  echo "⚙️ Aplicando driver de tela via overlay moderno..."
  BOOTCFG="/boot/firmware/config.txt"
  [ -f "$BOOTCFG" ] || BOOTCFG="/boot/config.txt"

  sudo tee -a "$BOOTCFG" > /dev/null <<EOF

# --- Tela SPI 3.5 configurada automaticamente ---
dtoverlay=vc4-kms-v3d
dtoverlay=piscreen,speed=16000000,rotate=90
framebuffer_width=480
framebuffer_height=320
EOF

  echo "✅ Overlay aplicado em $BOOTCFG"
  echo "⚠️ O método antigo (LCD-show) foi desativado por incompatibilidade."
fi

# -------------------------------------------------------------------
# 🧹 Limpeza
# -------------------------------------------------------------------
echo "🧹 Limpando pacotes desnecessários..."
sudo apt autoremove -y
sudo apt clean

echo ""
echo "✅ Instalação concluída!"
if [ "$MODE" = "desktop" ]; then
  echo "🖥️ Modo: Desktop com autostart + VNC + Unclutter"
else
  echo "💡 Modo: Headless com serviço Python + VNC"
fi
echo "🔁 Reinicie o sistema com: sudo reboot"
