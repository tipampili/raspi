#!/bin/bash
set -e

echo "🚀 Iniciando instalação avançada do ponto.py com suporte total ao Raspberry Pi 4 (Bookworm + Kernel 6.0)"

# -------------------------------------------------------------------
# 🔧 Atualização e pacotes base
# -------------------------------------------------------------------
echo "🔧 Atualizando sistema..."
sudo apt update -y && sudo apt full-upgrade -y
sudo apt install -y sqlite3 unclutter git libdrm-dev cmake python3 python3-pip python3-tk python3-rpi.gpio xserver-xorg-input-libinput

# -------------------------------------------------------------------
# 🔍 Detectar modo (gráfico ou headless)
# -------------------------------------------------------------------
if pgrep -x "lxsession" >/dev/null || pgrep -x "wayfire" >/dev/null; then
  MODE="desktop"
  echo "🖥️ Ambiente gráfico detectado — modo Desktop."
else
  MODE="headless"
  echo "💡 Ambiente gráfico não detectado — modo Headless."
fi

# -------------------------------------------------------------------
# 📁 Backup do config.txt para rollback
# -------------------------------------------------------------------
BOOTCFG="/boot/firmware/config.txt"
[ -f "$BOOTCFG" ] || BOOTCFG="/boot/config.txt"
sudo cp "$BOOTCFG" "${BOOTCFG}.bak-$(date +%Y%m%d%H%M%S)"
echo "💾 Backup criado: ${BOOTCFG}.bak-$(date +%Y%m%d%H%M%S)"

# -------------------------------------------------------------------
# 📺 Detectar e configurar display SPI compatível (modo KMS moderno)
# -------------------------------------------------------------------
echo "📺 Detectando LCD touchscreen conectado..."
OVERLAY=""

if dmesg | grep -qi "waveshare"; then
  OVERLAY="vc4-kms-dpi-waveshare35a"
elif dmesg | grep -qi "mhs35"; then
  OVERLAY="vc4-kms-dpi-mhs35"
elif dmesg | grep -qi "ili9486"; then
  OVERLAY="vc4-kms-dpi-ili9486"
elif dmesg | grep -qi "goodtft"; then
  OVERLAY="vc4-kms-dpi-goodtft35"
else
  echo "⚠️ Nenhum LCD reconhecido — aplicando overlay genérico para SPI 3.5\"."
  OVERLAY="vc4-kms-dpi-default"
fi

echo "📄 Aplicando overlay ${OVERLAY} no ${BOOTCFG}..."
sudo sed -i '/^dtoverlay=/d' "$BOOTCFG"

sudo tee -a "$BOOTCFG" > /dev/null <<EOF

# --- Configuração automática de LCD SPI compatível com Kernel 6.0 ---
dtoverlay=${OVERLAY},rotate=90,speed=48000000
max_framebuffers=2
framebuffer_width=480
framebuffer_height=320
EOF

echo "✅ Overlay atualizado com sucesso."

# -------------------------------------------------------------------
# ⚙️ Serviço systemd para ponto.py
# -------------------------------------------------------------------
APP_PATH="/home/pi/raspi/ponto.py"
if [ ! -f "$APP_PATH" ]; then
  echo "⚠️ Arquivo $APP_PATH não encontrado! Verifique o caminho antes de prosseguir."
  exit 1
fi

echo "⚙️ Criando serviço systemd para ponto.py..."
cat <<EOF | sudo tee /etc/systemd/system/ponto.service > /dev/null
[Unit]
Description=Aplicação ponto.py automática (sudo + touchscreen)
After=graphical.target

[Service]
User=root
Environment=DISPLAY=:0
Environment=XAUTHORITY=/home/pi/.Xauthority
WorkingDirectory=/home/pi/raspi
ExecStart=/usr/bin/python3 $APP_PATH
Restart=always
RestartSec=5
# Em caso de travamento, emite pulso no GPIO 18
ExecStartPost=/bin/bash -c 'if command -v gpio >/dev/null; then gpio -g mode 18 out; gpio -g write 18 1; sleep 0.5; gpio -g write 18 0; fi'

[Install]
WantedBy=graphical.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable ponto.service
sudo systemctl start ponto.service
echo "✅ ponto.py configurado e ativo como serviço systemd."

# -------------------------------------------------------------------
# 🖱️ Ocultar cursor
# -------------------------------------------------------------------
echo "🖱️ Configurando ocultação automática do cursor..."
cat <<EOF | sudo tee /etc/systemd/system/unclutter.service > /dev/null
[Unit]
Description=Ocultar cursor automaticamente
After=display-manager.service

[Service]
ExecStart=/usr/bin/unclutter -idle 0.1 -root
Restart=always
User=pi

[Install]
WantedBy=graphical.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable unclutter.service
echo "✅ Cursor será ocultado automaticamente após 0.1s de inatividade."

# -------------------------------------------------------------------
# 🔐 Permitir execução de python3 com sudo sem senha
# -------------------------------------------------------------------
echo "🔐 Configurando sudoers..."
echo "pi ALL=(ALL) NOPASSWD: /usr/bin/python3" | sudo tee /etc/sudoers.d/010_pi-nopasswd-python >/dev/null
sudo chmod 440 /etc/sudoers.d/010_pi-nopasswd-python

# -------------------------------------------------------------------
# 🧹 Limpeza final
# -------------------------------------------------------------------
echo "🧹 Limpando pacotes desnecessários..."
sudo apt autoremove -y
sudo apt clean

echo ""
echo "✅ Instalação completa!"
echo "📺 Display configurado com overlay moderno (KMS/DRM compatível)."
echo "🕒 ponto.py será iniciado automaticamente na tela touchscreen."
echo "💾 Backup salvo em ${BOOTCFG}.bak-*"
echo "🔁 Reinicie o sistema com: sudo reboot"
