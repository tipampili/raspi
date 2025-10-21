#!/bin/bash
set -e

echo "🚀 Iniciando instalação/reconfiguração do ponto.py com LCD touchscreen (GoodTFT ou LCDwiki)"
echo "───────────────────────────────────────────────────────────────"

# -------------------------------------------------------------------
# 🔧 Atualização e pacotes base
# -------------------------------------------------------------------
#sudo apt update -y && sudo apt upgrade -y
sudo apt install -y git sqlite3 unclutter python3 python3-pip python3-tk python3-rpi.gpio fbset fbi

# -------------------------------------------------------------------
# 📄 Caminhos padrão
# -------------------------------------------------------------------
BOOTCFG="/boot/firmware/config.txt"
[ -f "$BOOTCFG" ] || BOOTCFG="/boot/config.txt"
APP_PATH="/home/pi/raspi/ponto.py"
SERVICE_PATH="/etc/systemd/system/ponto.service"

# -------------------------------------------------------------------
# 🩺 Modo reconfiguração se já instalado
# -------------------------------------------------------------------
if [ -f "$SERVICE_PATH" ]; then
  echo ""
  echo "⚙️ O serviço ponto.service já existe."
  echo "1) Reinstalar driver e reconfigurar"
  echo "2) Reiniciar ponto.py"
  echo "3) Cancelar"
  read -p "👉 Escolha [1-3]: " opt
  case $opt in
    1) echo "🔧 Reconfigurando ambiente..." ;;
    2) sudo systemctl restart ponto.service && echo "✅ Serviço reiniciado." && exit 0 ;;
    3) echo "🚪 Saindo sem alterações." && exit 0 ;;
  esac
fi

# -------------------------------------------------------------------
# 💾 Backup para rollback
# -------------------------------------------------------------------
BACKUP="${BOOTCFG}.bak.$(date +%Y%m%d%H%M)"
sudo cp "$BOOTCFG" "$BACKUP"
echo "💾 Backup criado: $BACKUP"

# -------------------------------------------------------------------
# ⚙️ Criar serviço systemd do ponto.py (sudo + auto restart)
# -------------------------------------------------------------------
echo ""
echo "⚙️ Criando serviço systemd ponto.service..."

cat <<EOF | sudo tee "$SERVICE_PATH" > /dev/null
[Unit]
Description=Aplicação ponto.py (root + LCD)
After=graphical.target

[Service]
Type=simple
User=root
WorkingDirectory=/home/pi/raspi
ExecStart=/usr/bin/python3 $APP_PATH
Environment=DISPLAY=:0
Environment=XAUTHORITY=/home/pi/.Xauthority
Restart=always
RestartSec=5

[Install]
WantedBy=graphical.target
EOF

sudo chmod 644 "$SERVICE_PATH"
sudo systemctl daemon-reload
sudo systemctl enable ponto.service

echo "✅ Serviço ponto.service criado e habilitado."

# -------------------------------------------------------------------
# 🧠 Criar serviço de monitoramento ponto-check
# -------------------------------------------------------------------
echo ""
echo "🧠 Criando serviço ponto-check (monitoramento automático)..."

cat <<'EOF' | sudo tee /usr/local/bin/ponto-check.sh > /dev/null
#!/bin/bash
LOGFILE="/var/log/ponto-check.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

check_fb() {
  [ -e /dev/fb0 ]
}

check_ponto() {
  pgrep -f "python3 /home/pi/raspi/ponto.py" > /dev/null
}

if ! check_fb; then
  echo "$DATE ⚠️ Framebuffer /dev/fb0 ausente — LCD pode ter falhado." >> "$LOGFILE"
  sudo systemctl restart ponto.service
  exit 1
fi

if ! check_ponto; then
  echo "$DATE ⚠️ ponto.py não está em execução — reiniciando serviço." >> "$LOGFILE"
  sudo systemctl restart ponto.service
else
  echo "$DATE ✅ Verificação ok — ponto.py ativo e LCD funcional." >> "$LOGFILE"
fi
EOF

sudo chmod +x /usr/local/bin/ponto-check.sh

cat <<EOF | sudo tee /etc/systemd/system/ponto-check.service > /dev/null
[Unit]
Description=Verificação automática do LCD e ponto.py
After=ponto.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/ponto-check.sh
EOF

cat <<EOF | sudo tee /etc/systemd/system/ponto-check.timer > /dev/null
[Unit]
Description=Executa ponto-check a cada 2 minutos

[Timer]
OnBootSec=2min
OnUnitActiveSec=2min
Unit=ponto-check.service

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now ponto-check.timer
echo "✅ Monitoramento automático ativado (a cada 2 min)."

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
# 🖥️ Escolha do driver LCD
# -------------------------------------------------------------------
echo ""
echo "📺 Escolha o tipo de LCD conectado:"
echo "1) GoodTFT (LCD35-show)"
echo "2) LCDwiki (MHS35-show)"
read -p "👉 Escolha [1-2]: " opt

DRIVER=""
if [ "$opt" = "1" ]; then
  DRIVER="goodtft"
elif [ "$opt" = "2" ]; then
  DRIVER="lcdwiki"
else
  echo "❌ Opção inválida. Abortando."
  exit 1
fi

# -------------------------------------------------------------------
# 🔄 Instalar driver selecionado
# -------------------------------------------------------------------
echo ""
echo "🧩 Instalando driver para $DRIVER..."
cd /home/pi
sudo rm -rf LCD-show

if [ "$DRIVER" = "goodtft" ]; then
  echo "⬇️ Clonando GoodTFT..."
  git clone https://github.com/goodtft/LCD-show.git
  cd LCD-show
  chmod -R 755 .
  echo "⚙️ Instalando GoodTFT LCD35-show..."
  sudo ./LCD35-show
elif [ "$DRIVER" = "lcdwiki" ]; then
  echo "⬇️ Clonando LCDwiki..."
  git clone https://github.com/Lcdwiki/LCD-show.git
  cd LCD-show
  chmod -R 755 .
  echo "⚙️ Instalando LCDwiki MHS35-show..."
  sudo ./MHS35-show
fi

echo "✅ Driver $DRIVER instalado com sucesso."

# -------------------------------------------------------------------
# 🧹 Limpeza final
# -------------------------------------------------------------------
sudo apt autoremove -y && sudo apt clean

echo ""
echo "✅ Instalação concluída com sucesso!"
echo "📺 Driver: $DRIVER"
echo "💾 Backup: $BACKUP"
echo "🧠 Monitoramento ativo: ponto-check.timer"
echo "⚙️ Serviço: /etc/systemd/system/ponto.service"
echo "🔁 Reinicie com: sudo reboot"
