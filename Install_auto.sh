#!/bin/bash
set -e

echo "🔧 Atualizando sistema..."
sudo apt update -y && sudo apt upgrade -y
sudo apt install -y sqlite3 x11vnc unclutter git

echo "🧱 Configurando VNC..."
sudo mkdir -p /etc/x11vnc
sudo x11vnc -storepasswd 1234 /etc/x11vnc/pass  # troque 1234 pela senha desejada
sudo cp x11vnc.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable x11vnc.service

echo "📁 Configurando inicialização automática..."
mkdir -p /home/pi/.config/autostart
install -m 644 auto.desktop /home/pi/.config/autostart/auto.desktop
install -m 644 x11vnc.desktop /home/pi/.config/autostart/x11vnc.desktop
sudo install -m 644 autostart /etc/xdg/lxsession/LXDE-pi/autostart
sudo install -m 644 lightdm.conf /etc/lightdm/lightdm.conf

echo "🖱️ Ocultando cursor (unclutter)..."
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

echo "📺 Instalando driver de tela (detecção automática)..."
sudo rm -rf LCD-show || true
if [ ! -d "/home/pi/LCD-show" ]; then
  git clone https://github.com/goodtft/LCD-show.git /home/pi/LCD-show || \
  git clone https://github.com/lcdwiki/LCD-show.git /home/pi/LCD-show
fi
cd /home/pi/LCD-show
chmod +x *.sh
if [ -f "./LCD35-show" ]; then
  sudo ./LCD35-show
elif [ -f "./MHS35-show" ]; then
  sudo ./MHS35-show
else
  echo "⚠️ Nenhum driver LCD reconhecido, pulei esta etapa."
fi

echo "🧹 Limpando pacotes desnecessários..."
sudo apt autoremove -y

echo "✅ Instalação concluída! Reinicie o sistema para aplicar as configurações."
