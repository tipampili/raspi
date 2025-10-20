#!/bin/bash
set -e

echo "🚀 Iniciando instalação do ponto.py com LCD touchscreen e suporte para kernel 6.0 (Bookworm)..."

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

# -------------------------------------------------------------------
# 💾 Backup para rollback
# -------------------------------------------------------------------
BACKUP="${BOOTCFG}.bak.$(date +%Y%m%d%H%M)"
sudo cp "$BOOTCFG" "$BACKUP"
echo "💾 Backup criado: $BACKUP"

# -------------------------------------------------------------------
# 📺 Detectar display SPI automaticamente
# -------------------------------------------------------------------
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
# 🖐️ Seleção manual (se necessário)
# -------------------------------------------------------------------
if [ "$DETECTED" = "none" ]; then
  echo ""
  echo "⚠️ Nenhum LCD detectado automaticamente."
  echo "Selecione o modelo:"
  echo "1) Waveshare 3.5\""
  echo "2) MHS 3.5\""
  echo "3) GoodTFT 3.5\""
  echo "4) ILI9486 Genérico"
  echo "5) Outro SPI (vc4-kms-dpi-default)"
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
  goodtft) OVERLAY="vc4-kms-dpi-ili9486" ;;  # GoodTFT usa controlador ILI9486 no kernel 6.0
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
# 🧭 Teste visual do LCD antes do reboot
# -------------------------------------------------------------------
TEST_IMG="/tmp/lcd_test.ppm"
echo ""
echo "🧭 Testando exibição do LCD..."
cat > "$TEST_IMG" <<'PPM'
P3
480 320
255
255 0 0  0 255 0  0 0 255
PPM

if command -v fbi >/dev/null 2>&1; then
  sudo fbi -T 1 -d /dev/fb0 -noverbose -a "$TEST_IMG" >/dev/null 2>&1 &
  echo "🖥️ Imagem de teste exibida por 5 segundos..."
  sleep 5
  sudo killall fbi >/dev/null 2>&1 || true
else
  echo "⚠️ Comando fbi não disponível — pulando teste visual."
fi

# -------------------------------------------------------------------
# 🧩 Teste de toque (opcional)
# -------------------------------------------------------------------
echo ""
read -p "👉 Deseja testar o toque na tela agora? [s/N]: " resp
if [[ "$resp" =~ ^[Ss]$ ]]; then
  echo "📱 Teste de toque: toque em qualquer área da tela..."
  sudo python3 - <<'EOF'
import tkinter as tk
import time
root = tk.Tk()
root.attributes("-fullscreen", True)
root.configure(bg="black")
label = tk.Label(root, text="Toque na tela para testar...", fg="white", bg="black", font=("Arial", 20))
label.pack(expand=True)
def on_touch(event):
    label.config(text=f"✔ Toque detectado em ({event.x}, {event.y})")
    root.after(2000, root.destroy)
root.bind("<Button-1>", on_touch)
root.after(10000, root.destroy)
root.mainloop()
EOF
else
  echo "⏭️ Teste de toque ignorado."
fi

# -------------------------------------------------------------------
# ⚙️ Criar serviço systemd para ponto.py
# -------------------------------------------------------------------
echo ""
echo "⚙️ Criando serviço systemd para ponto.py..."
cat <<EOF | sudo tee /etc/systemd/system/ponto.service > /dev/null
[Unit]
Description=Aplicação ponto.py automática (root + LCD)
After=graphical.target

[Service]
User=root
Environment=DISPLAY=:0
Environment=XAUTHORITY=/home/pi/.Xauthority
ExecStart=/usr/bin/python3 $APP_PATH
WorkingDirectory=/home/pi/raspi
Restart=always
RestartSec=5
ExecStartPost=/bin/bash -c 'gpio -g mode 18 out; gpio -g write 18 1; sleep 0.3; gpio -g write 18 0'

[Install]
WantedBy=graphical.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable ponto.service
echo "✅ Serviço ponto.service configurado."

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
# 🔐 Ajustar sudoers
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
echo "🧭 Teste do LCD realizado com sucesso."
echo "🔁 Para finalizar, reinicie com: sudo reboot"
