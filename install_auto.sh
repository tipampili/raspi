#!/bin/bash
set -e

echo "🔧 Atualizando sistema..."
sudo apt update -y && sudo apt upgrade -y
sudo apt install -y sqlite3 x11vnc unclutter git libdrm-dev libdtovl-dev cmake

# -------------------------------------------------------------------
# 🧱 Configuração do VNC
# -------------------------------------------------------------------
echo "🧱 Configurando VNC..."
sudo mkdir -p /etc/x11vnc
sudo x11vnc -storepasswd 1234 /etc/x11vnc/pass  # troque 1234 pela senha desejada
sudo install -m 644 x11vnc.service /etc/systemd/system/x11vnc.service
sudo systemctl daemon-reload
sudo systemctl enable x11vnc.service

# -------------------------------------------------------------------
# ⚙️ Configuração de inicialização automática
# -------------------------------------------------------------------
echo "📁 Configurando inicialização automática..."
mkdir -p /home/pi/.config/autostart
install -m 644 auto.desktop /home/pi/.config/autostart/auto.desktop
install -m 644 x11vnc.desktop /home/pi/.config/autostart/x11vnc.desktop

if [ -d "/etc/xdg/lxsession/LXDE-pi" ]; then
  echo "📁 Ambiente LXDE detectado — configurando autostart..."
  sudo install -m 644 autostart /etc/xdg/lxsession/LXDE-pi/autostart
else
  echo "⚠️ Ambiente LXDE não encontrado — pulando autostart gráfico."
fi

sudo mkdir -p /etc/lightdm
sudo install -m 644 lightdm.conf /etc/lightdm/lightdm.conf

# -------------------------------------------------------------------
# 🖱️ Ocultar cursor (serviço unclutter)
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
# 📺 Instalação do driver de tela com fallback
# -------------------------------------------------------------------
echo "📺 Instalando driver de tela (detecção automática)..."
cd /home/pi
sudo rm -rf LCD-show || true

# Tenta clonar de um dos repositórios
git clone https://github.com/goodtft/LCD-show.git || \
git clone https://github.com/lcdwiki/LCD-show.git || true

if [ -d "/home/pi/LCD-show" ]; then
  cd /home/pi/LCD-show
  chmod +x *.sh || true

  echo "🔍 Tentando executar script do LCD-show..."
  if [ -f "./LCD35-show" ]; then
    sudo ./LCD35-show || LCD_FAIL=1
  elif [ -f "./MHS35-show" ]; then
    sudo ./MHS35-show || LCD_FAIL=1
  else
    echo "⚠️ Nenhum script LCD reconhecido — ignorando."
    LCD_FAIL=1
  fi
else
  echo "⚠️ Repositório LCD-show não encontrado — ignorando."
  LCD_FAIL=1
fi

# Se o script falhar, aplica o método moderno via overlay
if [ "${LCD_FAIL}" = "1" ]; then
  echo "🧩 Aplicando método moderno (overlay em config.txt)..."

  BOOTCFG="/boot/firmware/config.txt"
  [ -f "$BOOTCFG" ] || BOOTCFG="/boot/config.txt"

  sudo tee -a "$BOOTCFG" > /dev/null <<EOF

# --- Tela SPI 3.5" configurada automaticamente ---
dtoverlay=vc4-kms-v3d
dtoverlay=piscreen,speed=16000000,rotate=90
framebuffer_width=480
framebuffer_height=320
EOF

  echo "✅ Overlay aplicado em $BOOTCFG"
fi

# -------------------------------------------------------------------
# 🧹 Limpeza
# -------------------------------------------------------------------
echo "🧹 Limpando pacotes desnecessários..."
sudo apt autoremove -y
sudo apt clean

echo "✅ Instalação concluída!"
echo "🔁 Reinicie o sistema com: sudo reboot"
