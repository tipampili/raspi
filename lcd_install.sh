#!/bin/bash
set -e

echo "🚀 Iniciando instalação automática de driver LCD Touch (GoodTFT / LCDWiki)..."

# -------------------------------------------------------------------
# 🧩 Função para detectar LCD conectado
detectar_lcd() {
    echo "🔍 Detectando LCD conectado..."

    if dmesg | grep -qi "goodtft"; then
        echo "✅ Tela GoodTFT detectada automaticamente!"
        DRIVER="goodtft"
    elif dmesg | grep -qi "fb_ili9486"; then
        echo "✅ Driver ILI9486 detectado — compatível com LCDWiki!"
        DRIVER="lcdwiki"
    elif ls /dev/fb1 >/dev/null 2>&1; then
        echo "⚠️ Framebuffer secundário encontrado (/dev/fb1) — possível LCD SPI!"
        DRIVER="manual"
    else
        echo "⚠️ Nenhum LCD reconhecido automaticamente."
        DRIVER="manual"
    fi
}

# -------------------------------------------------------------------
# 🧰 Função para escolher driver manualmente
escolher_driver() {
    echo ""
    echo "💡 Escolha o driver a instalar:"
    echo "1) GoodTFT"
    echo "2) LCDWiki"
    read -p "Digite o número da opção desejada [1-2]: " escolha

    case "$escolha" in
        1) DRIVER="goodtft" ;;
        2) DRIVER="lcdwiki" ;;
        *) echo "❌ Opção inválida. Abortando."; exit 1 ;;
    esac
}

# -------------------------------------------------------------------
# 📦 Função de instalação do driver GoodTFT
instalar_goodtft() {
    echo "📺 Instalando driver GoodTFT..."
    sudo apt-get update -y
    sudo apt-get install -y git

    cd /home/pi || exit
    git clone https://github.com/goodtft/LCD-show.git || true
    cd LCD-show
    chmod +x *.sh

    echo "⚙️ Aplicando driver padrão de 3.5 polegadas..."
    sudo ./LCD35-show
}

# -------------------------------------------------------------------
# 📦 Função de instalação do driver LCDWiki
instalar_lcdwiki() {
    echo "📺 Instalando driver LCDWiki..."
    sudo apt-get update -y
    sudo apt-get install -y git

    cd /home/pi || exit
    git clone https://github.com/lcdwiki/LCD-show.git || true
    cd LCD-show
    chmod +x *.sh

    echo "⚙️ Aplicando driver padrão de 3.5 polegadas (ILI9486)..."
    sudo ./LCD35-show
}

# -------------------------------------------------------------------
# 🧩 Forçar boot gráfico e auto-login
habilitar_modo_grafico() {
    echo "🖥️ Habilitando modo gráfico com autologin..."
    sudo raspi-config nonint do_boot_behaviour B4
    sudo raspi-config nonint do_boot_splash 0
}

# -------------------------------------------------------------------
# 🚀 Execução principal
detectar_lcd

if [ "$DRIVER" = "manual" ]; then
    escolher_driver
fi

case "$DRIVER" in
    goodtft)
        instalar_goodtft
        ;;
    lcdwiki)
        instalar_lcdwiki
        ;;
    *)
        echo "❌ Nenhum driver selecionado. Abortando."
        exit 1
        ;;
esac

habilitar_modo_grafico

echo ""
echo "✅ Instalação concluída!"
echo "🔁 O Raspberry Pi será reiniciado para aplicar as configurações..."
sleep 5
sudo reboot
