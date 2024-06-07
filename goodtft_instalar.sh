#! /bin/sh
sudo apt update
sudo apt upgrade -y
sudo mkdir /home/pi/.config/autostart
chmod -R 777 /home/pi/.config/autostart
sudo cp auto.desktop /home/pi/.config/autostart/auto.desktop
sudo cp x11vnc.desktop /home/pi/.config/autostart/x11vnc.desktop
sudo cp autostart /etc/xdg/lxsession/LXDE-pi/autostart
sudo cp lightdm.conf /etc/lightdm
sudo apt-get install unclutter
unclutter -idle 0.01 -root
sudo rm -rf LCD-show
git clone https://github.com/goodtft/LCD-show.git
chmod -R 755 LCD-show
cd LCD-show/
sudo ./LCD35-show
