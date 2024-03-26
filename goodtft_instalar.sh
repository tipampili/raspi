#! /bin/sh
sudo apt-get install x11vnc
x11vnc -forever -usepw -httpport 5900 -q -bg
sudo mkdir /home/pi/.config/autostart
chmod -R 777 /home/pi/.config/autostart
sudo cp auto.desktop /home/pi/.config/autostart/auto.desktop
sudo cp x11vnc.desktop /home/pi/.config/autostart/x11vnc.desktop
sudo cp autostart /etc/xdg/lxsession/LXDE-pi/autostart
sudo cp lightdm.conf /etc/lightdm
sudo apt-get install unclutter
unclutter -idle 0.01 -root
rm -rf LCD-show
git clone https://github.com/goodtft/LCD-show
chmod -R 755 LCD-show
cd LCD-show
./LCD35-show
