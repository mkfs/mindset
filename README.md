                                 M I N D S E T

               Ruby and R code for working with a Neurosky Mindset


Mindset gem
===========

The gem provides the mindset_capture utility:

    bash$ mindset_capture -h
    Usage: mindset_capture.rb [-aehjqrvw] [-sn num] [DEVICE]

    Notes:
     * DEVICE defaults to /dev/rfcomm0
     * Ctrl-C will terminate if both -s and -n are not set
     * JSON output will only be written on exit.

    Options:
        -a, --all                Capture all data types
        -e, --esense             Capture eSense (attention, meditation) data
        -q, --quality            Capture signal quality data
        -r, --raw                Capture raw wave data
        -w, --wave               Capture ASIC brainwave data [default]
        -j, --json               Generate JSON output
        -s, --seconds n          Capture for n seconds
        -n, --num n              Capture up to n data points
        -v, --verbose            Show debug output
        -h, --help               Show help screen
    bash$ mindset_capture -aj -s 300 > eeg_data.json

To run from the repo, set the RUBYLIB to include the lib subdir:

    bash$ RUBYLIB=lib bin/mindset_capture -h

The gem provides the Mindset module, which contains the Connection, Packet,
and PacketStore objects.

    require 'mindset'
    Mindset.connect(options.device, options.verbose) do |conn|
      cont = true
      while cont
        begin
           packets = conn.read_packet
	   packets.each { |pkt| puts pkt.inspect }
	rescue Mindset::Connection::TimeoutError, Interrupt => e
          cont = false
        end
      end
    end

Using a MindSet under Linux
===========================


**GUI Tools**

The MindSet can be connected as a Serial Device (and also an Audio Sink or a
HandsFree device) in Blueman (`blueman-manager`).

_Setup_

    1. Enable pairing on MindSet
    2. Click Search in BlueMan
    3. Select MindSet device in BlueMan
    4. Click on Pair in BlueMan
    5. Enter default PIN (0000)

_Connect_

    1. In BlueMan, right-click on MindSet 
       and select "Connect To: Dev B" (serial connector icon).
       This will connect to the next available rfcomm device,
       usually /dev/rfcomm0.
    2. Run capture utility ONCE
    3. In BlueMan, right-click on MindSet 
       and select "Disconnect: Dev B"
    4. Quit BlueMan
    5. Restart the bluetooth service to release rfcomm0
    bash$ sudo /etc/init.d/bluetooth stop
    bash$ sudo /etc/init.d/bluetooth start

Note that steps 4 and 5 are required due to bugs in either BlueMan or the
Linux Bluetooth daemon. According to bug 495696, it's BlueMan at fault:
  <http://bugs.launchpad.net/blueman/+bug/495696>


**CLI Tools**
Connecting with the command line tools does not appear to work. At first, this
seems to be a problem with

_Pairing with BlueZ_

NOTE: Be sure BlueMan (and the accompany blueman-applet) are not running, as
they will conflict with the command line tools. Before closing BlueMan,
remove the MindSet from the list of recognized devices. Restart the
system Bluetooth daemon.

    1. Run `hcitool scan` to get the bluetooth address of the Mindset
    2. Run  `bluez-simple-agent hci0 ##:##:##:##:##:##` to pair the
       device. If the device is already connected, run
       `bluez-simple-agent hci0 ##:##:##:##:##:## remove` to unpair the
       device, then attempt to pair again. The slower reader may not be
       aware that "##:##:##:##:##:##" should be replaced with the 
       hardware address returned by `hciutil scan`.

_Connecting once Paired_

This is the part that fails. The same behavior occurs when paired with bluez
(no BlueMan software running), and when paired (but not connected) using
BlueMan.

    bash$ sudo rfcomm connect /dev/rfcomm0 ##:##:##:##:##:## 1
    ... waits for Ctrl-C ...
    bash$ ./mindset-capture.rb
    ... reads 11 bytes ("AT+BRSF=24\r"), then hits EOF
    bash$ sudo rfcomm release 0
    bash$ sudo rfcomm bind /dev/rfcomm0 ##:##:##:##:##:## 1
    bash$ ./mindset-capture.rb
    ... immediate EOF ...
    bash$ sudo rfcomm release 0

The bytes "AT+BRSF=24\r" are probably coming from rfcomm and not from the 
MindSet, hence the subsequent EOF -- matching the behavior of connecting via
`rfcomm bind`. This appears to be a problem in the socket opened by rfcomm.


**Neurosky Applications**

The Brainwave Visualizer will install and run under WINE, but it does not
seem able to read from the COM port. This may just need some debugging.

    bash$ cd ~/.wine/dosdevices
    bash$ ln -s /dev/rfcomm0 com1
    bash$ sudo chmod a+rwx /dev/rfcomm0 	# no, this does not help either
