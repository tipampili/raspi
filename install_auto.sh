#!/bin/bash
set -e

echo "🚀 Iniciando instalação híbrida com autostart root de ponto.py..."

# -------------------------------------------------------------------
# 🔧 Atualização e pacotes base
# -------------------------------------------------------------------
echo "🔧 Atualizando sistema..."
sudo apt update -y && sudo apt upgrade -y
sudo apt install -y sqlite3 unclutter git libdrm-dev libdtovl-dev cmake python3 python3-pip

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
# ⚙️ Inicialização automática da aplicação ponto.py (com sudo)
# -------------------------------------------------------------------
APP_PATH="/home/pi/raspi/ponto.py"

if [ "$MODE" = "desktop" ]; then
  echo "⚙️ Configurando autostart do ponto.py (modo gráfico, root)..."
  mkdir -p /home/pi/.config/autostart
  cat <<EOF > /home/pi/.config/autostart/ponto.desktop
[Desktop Entry]
Type=Application
Name=PontoApp
Exec=sudo /usr/bin/python3 $APP_PATH
X-GNOME-Autostart-enabled=true
EOF

  # Ocultar cursor
  cat <<EOF > /home/pi/.config/autostart/unclutter.desktop
[Desktop Entry]
Type=Application
Name=Unclutter
Exec=/usr/bin/unclutter -idle 0.1 -root
X-GNOME-Autostart-enabled=true
EOF

  echo "✅ ponto.py configurado para iniciar como root (modo Desktop)."
else
  echo "⚙️ Criando serviço systemd para executar ponto.py (root)..."
  cat <<EOF | sudo tee /etc/systemd/system/ponto.service > /dev/null
[Unit]
Description=Aplicação ponto.py automática
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 $APP_PATH
WorkingDirectory=/home/pi/raspi
Restart=always
User=root
Environment=DISPLAY=:0
Environment=XAUTHORITY=/home/pi/.Xauthority

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable ponto.service
  echo "✅ ponto.py configurado para iniciar como root (modo Headless)."
fi

# -------------------------------------------------------------------
# 📺 Instalar driver da tela touchscreen (modo gráfico)
# -------------------------------------------------------------------
echo "📺 Instalando driver da tela touchscreen..."
git clone https://github.com/goodtft/LCD-show.git /tmp/LCD-show
cd /tmp/LCD-show

if [ "$MODE" = "desktop" ]; then
  sudo chmod +x LCD35-show
  sudo ./LCD35-show
else
  echo "💡 Driver touchscreen não será instalado no modo headless."
fi
cd ~
rm -rf /tmp/LCD-show
echo "✅ Driver touchscreen instalado!"

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
echo "✅ Instalação concluída!"
if [ "$MODE" = "desktop" ]; then
  echo "🖥️ Modo: Desktop (autostart root ponto.py + touchscreen)"
else
  echo "💡 Modo: Headless (systemd root ponto.py)"
fi
echo "🔁 Reinicie o sistema com: sudo reboot"
