#!/bin/sh

 killall blueman-manager
 killall blueman-applet
 sudo /etc/init.d/bluetooth stop
 sudo /etc/init.d/bluetooth start
 blueman-manager &
