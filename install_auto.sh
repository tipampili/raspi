#!/bin/bash
set -e

echo "🚀 Iniciando instalação/reconfiguração do ponto.py com LCD touchscreen (GoodTFT ou LCDwiki)"
echo "───────────────────────────────────────────────────────────────"

# -------------------------------------------------------------------
# 🔧 Atualização e pacotes base
# -------------------------------------------------------------------
#sudo apt update
#sudo apt upgrade -y
sudo apt install --only-upgrade realvnc-vnc-server -y
sudo apt install -y git sqlite3 unclutter python3 python3-pip python3-tk python3-rpi.gpio fbset fbi x11-xserver-utils

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

check_fb() { [ -e /dev/fb0 ]; }
check_ponto() { pgrep -f "python3 /home/pi/raspi/ponto.py" > /dev/null; }

if ! check_fb; then
  echo "$DATE ⚠️ Framebuffer ausente — reiniciando ponto.service." >> "$LOGFILE"
  sudo systemctl restart ponto.service
  exit 1
fi

if ! check_ponto; then
  echo "$DATE ⚠️ ponto.py parado — reiniciando serviço." >> "$LOGFILE"
  sudo systemctl restart ponto.service
else
  echo "$DATE ✅ ponto.py ativo e LCD funcional." >> "$LOGFILE"
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
# 💡 Manter tela ligada e brilho máximo
# -------------------------------------------------------------------

echo ""
echo "💡 Configurando para manter o LCD sempre ligado e brilho máximo..."

# 1️⃣ Impedir screen blank no console
sudo sed -i 's/$/ consoleblank=0/' /boot/firmware/cmdline.txt 2>/dev/null || \
sudo sed -i 's/$/ consoleblank=0/' /boot/cmdline.txt

# 2️⃣ Impedir blank e DPMS no X11
sudo mkdir -p /etc/xdg/lxsession/LXDE-pi
sudo tee -a /etc/xdg/lxsession/LXDE-pi/autostart > /dev/null <<'EOF'
@xset s off
@xset -dpms
@xset s noblank
EOF

# 3️⃣ Serviço para forçar brilho máximo no boot
sudo tee /etc/systemd/system/backlight-on.service > /dev/null <<'EOF'
[Unit]
Description=Manter brilho máximo e LCD ligado
After=graphical.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'for b in /sys/class/backlight/*/brightness; do echo 255 > "$b" 2>/dev/null || true; done'

[Install]
WantedBy=graphical.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable backlight-on.service

# -------------------------------------------------------------------
echo "🖥️ Ativando o RealVNC Server nativo do Raspberry Pi OS..."
# -------------------------------------------------------------------
# Habilita e inicia o serviço
echo "⚙️ Habilitando e iniciando o serviço VNC..."
sudo systemctl enable vncserver-x11-serviced.service
sudo systemctl start vncserver-x11-serviced.service

# (Opcional) Mostra status e IP
echo "🔍 Verificando status do VNC..."
sudo systemctl status vncserver-x11-serviced.service --no-pager | grep Active

echo "🌐 Endereço IP do Raspberry Pi:"
hostname -I | awk '{print $1}'

echo "✅ RealVNC Server ativado e em execução!"

# -------------------------------------------------------------------
echo "⏰ Configurando reboot diário às 05:00..."
# -------------------------------------------------------------------
# Linha de cron a adicionar
CRON_CMD="5 0 * * * /sbin/shutdown -r now"

# Cria crontab vazio se não existir e adiciona o comando
crontab -l 2>/dev/null > temp_cron || true

# Verifica se a linha já existe
if grep -Fxq "$CRON_CMD" temp_cron; then
    echo "✅ O reboot diário já está configurado."
else
    echo "$CRON_CMD" >> temp_cron
    crontab temp_cron
    echo "✅ Tarefa adicionada com sucesso!"
fi

# Remove arquivo temporário
rm -f temp_cron

# Mostra o crontab atual
echo "📋 Crontab atual:"
crontab -l

# -------------------------------------------------------------------
# 📺 Escolha do driver LCD
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
  # -------------------------------------------------------------------
  # 🧹 Limpeza final
  # -------------------------------------------------------------------
  sudo apt autoremove -y && sudo apt clean
fi

echo "✅ Instalação concluída com sucesso!"
echo "📺 Driver: $DRIVER instalado"
echo "💾 Backup: $BACKUP"
echo "🧠 Monitoramento: ponto-check.timer"
echo "☀️ Brilho máximo e tela sempre ligada configurados"
echo "✅ RealVNC Server ativado e em execução!"
echo "🌐 Endereço IP do Raspberry Pi:"
hostname -I | awk '{print $1}'
echo "📋 Crontab atual:"
crontab -l
echo "🔁 Reinicie o Raspberry Pi: sudo reboot"
