#!/bin/bash
set -e

echo "🚀 Iniciando instalação do ponto.py com LCD touchscreen — Raspberry Pi OS 4.3 (Bookworm 2025)..."

# -------------------------------------------------------------------
# 🔧 Atualização e pacotes base
# -------------------------------------------------------------------
sudo apt update -y && sudo apt full-upgrade -y
sudo apt install -y git cmake python3 python3-pip python3-tk python3-rpi.gpio sqlite3 unclutter fbset fbi dialog

# -------------------------------------------------------------------
# 📄 Caminhos e variáveis
# -------------------------------------------------------------------
BOOTCFG="/boot/firmware/config.txt"
[ -f "$BOOTCFG" ] || BOOTCFG="/boot/config.txt"
APP_PATH="/home/pi/raspi/ponto.py"
BACKUP="${BOOTCFG}.bak.$(date +%Y%m%d%H%M)"
LCD_REPO="/home/pi/LCD-show"

sudo cp "$BOOTCFG" "$BACKUP"
echo "💾 Backup criado: $BACKUP"

# -------------------------------------------------------------------
# 🧠 Detectar HDMI ou SPI
# -------------------------------------------------------------------
echo "🔍 Verificando tipo de display..."
if tvservice -s 2>/dev/null | grep -q "HDMI"; then
  echo "🖥️ Display HDMI detectado — não é necessário driver SPI."
  DISPLAY_MODE="HDMI"
else
  DISPLAY_MODE="SPI"
fi

# -------------------------------------------------------------------
# 📺 Instalação do driver LCD (apenas para SPI)
# -------------------------------------------------------------------
if [ "$DISPLAY_MODE" = "SPI" ]; then
  echo "📺 Modo SPI detectado — preparando instalação interativa do driver LCD..."

  # Clona repositório se não existir
  if [ ! -d "$LCD_REPO" ]; then
    git clone https://github.com/goodtft/LCD-show.git "$LCD_REPO"
  fi
  cd "$LCD_REPO"

  # Menu interativo de seleção
  CHOICE=$(dialog --clear --title "Seleção de LCD" --menu "Escolha o modelo do seu display:" 15 60 6 \
    1 "Waveshare 3.5\"" \
    2 "MHS 3.5\"" \
    3 "GoodTFT 3.5\"" \
    4 "ILI9486 Genérico" \
    5 "Cancelar" \
    3>&1 1>&2 2>&3)

  clear
  case $CHOICE in
    1) LCD_SCRIPT="LCD35-show"; LCD_NAME="waveshare";;
    2) LCD_SCRIPT="MHS35-show"; LCD_NAME="mhs35";;
    3) LCD_SCRIPT="LCD35-show"; LCD_NAME="goodtft";;
    4) LCD_SCRIPT="LCD35-show"; LCD_NAME="ili9486";;
    5|"") echo "❌ Instalação cancelada."; exit 0;;
  esac

  echo "📄 Instalando driver $LCD_NAME usando script $LCD_SCRIPT ..."
  sudo chmod +x "$LCD_SCRIPT"

  if ! sudo ./"$LCD_SCRIPT"; then
    echo "❌ Falha na instalação do driver LCD. Restaurando backup..."
    sudo cp "$BACKUP" "$BOOTCFG"
    exit 1
  fi

  echo "✅ Driver $LCD_NAME instalado com sucesso!"
else
  echo "✅ Nenhum driver LCD necessário (display HDMI detectado)."
fi

# -------------------------------------------------------------------
# 🧪 Teste do framebuffer (SPI ou HDMI)
# -------------------------------------------------------------------
echo ""
echo "🔎 Testando framebuffer..."
if ! fbset -s >/dev/null 2>&1; then
  echo "❌ Framebuffer não detectado! Restaurando backup..."
  sudo cp "$BACKUP" "$BOOTCFG"
  exit 1
else
  echo "✅ Framebuffer ativo."
fi

# -------------------------------------------------------------------
# 🧭 Teste visual do LCD
# -------------------------------------------------------------------
TEST_IMG="/tmp/lcd_test.ppm"
cat > "$TEST_IMG" <<'PPM'
P3
480 320
255
255 0 0   0 255 0   0 0 255
PPM

if command -v fbi >/dev/null 2>&1; then
  sudo fbi -T 1 -d /dev/fb0 -noverbose -a "$TEST_IMG" >/dev/null 2>&1 &
  echo "🖥️ Exibindo imagem de teste por 5 s..."
  sleep 5
  sudo killall fbi >/dev/null 2>&1 || true
fi

# -------------------------------------------------------------------
# 📱 Teste opcional de toque
# -------------------------------------------------------------------
echo ""
read -p "👉 Deseja testar o toque na tela agora? [s/N]: " TOQUE
if [[ "$TOQUE" =~ ^[Ss]$ ]]; then
  sudo python3 - <<'PY'
import tkinter as tk
root = tk.Tk()
root.attributes("-fullscreen", True)
root.configure(bg="black")
msg = tk.Label(root, text="Toque na tela...", fg="white", bg="black", font=("Arial", 22))
msg.pack(expand=True)
def touched(e): msg.config(text=f"✔ Toque detectado ({e.x},{e.y})"); root.after(2000, root.destroy)
root.bind("<Button-1>", touched)
root.after(10000, root.destroy)
root.mainloop()
PY
fi

# -------------------------------------------------------------------
# ⚙️ Serviço systemd ponto.py
# -------------------------------------------------------------------
echo ""
echo "⚙️ Criando serviço systemd para ponto.py..."
cat <<EOF | sudo tee /etc/systemd/system/ponto.service >/dev/null
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

[Install]
WantedBy=graphical.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable ponto.service

# -------------------------------------------------------------------
# 🖱️ Ocultar cursor
# -------------------------------------------------------------------
cat <<EOF | sudo tee /etc/systemd/system/unclutter.service >/dev/null
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
# 🔐 Sudoers
# -------------------------------------------------------------------
sudo bash -c 'echo "pi ALL=(ALL) NOPASSWD: /usr/bin/python3" > /etc/sudoers.d/010_pi-nopasswd-python'
sudo chmod 440 /etc/sudoers.d/010_pi-nopasswd-python

# -------------------------------------------------------------------
# 🧹 Limpeza
# -------------------------------------------------------------------
sudo apt autoremove -y && sudo apt clean
echo ""
echo "✅ Instalação concluída com sucesso!"
echo "📺 Tipo de display: $DISPLAY_MODE"
[ "$DISPLAY_MODE" = "SPI" ] && echo "🧩 Driver SPI aplicado: $LCD_NAME"
echo "💾 Backup salvo em: $BACKUP"
echo "🔁 Reinicie com: sudo reboot"
