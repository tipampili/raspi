#! /bin/sh
#sudo apt update
#sudo apt upgrade -y
sudo apt-get install x11vnc
x11vnc -usepw -forever -display: 0
sudo cp x11vnc.desktop /home/pi/.config/autostart/x11vnc.desktop
sudo x11vnc -storepasswd /etc/x11vnc.pass
sudo cp x11vnc.service /lib/systemd/system/x11vnc.service
sudo systemctl enable x11vnc.service
sudo mkdir /home/pi/.config/autostart
chmod -R 777 /home/pi/.config/autostart
sudo cp auto.desktop /home/pi/.config/autostart/auto.desktop
sudo cp x11vnc.desktop /home/pi/.config/autostart/x11vnc.desktop
sudo cp autostart /etc/xdg/lxsession/LXDE-pi/autostart
sudo cp lightdm.conf /etc/lightdm
sudo apt-get install unclutter
unclutter -idle 0.01 -root
sudo rm -rf LCD-show
git clone https://github.com/Lcdwiki/LCD-show
chmod -R 755 LCD-show
cd LCD-show
sudo ./MHS35-show
